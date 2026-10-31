"""Offer ready orders to riders in turns instead of to everyone at once.

1. The seller marks an order ready: the best few riders get an offer (push + in the app).
2. If nobody accepts before the round ends, the next few riders get it.
3. After a few rounds, or when nobody else is eligible, it opens to every nearby online rider.

Who goes first: online, approved riders with a recent location who are near the shop and
not on a job. Among them, the one who has waited longest since their last job (or since
going online) goes first, minus points per km so far-away riders don't jump the queue.

Lock order everywhere is dispatch row -> order row -> rider profile row, so accepts,
declines and round changes can't deadlock each other.
"""
import logging
from datetime import timedelta

from django.db import transaction
from django.db.models import Max
from django.utils import timezone

from accounts.models import DeliveryProfile

from .coordinates import resolve_pickup_coordinates
from .models import DeliveryAssignment, DeliveryDispatch, DeliveryOffer, DispatchSettings
from .utils import LocationService

logger = logging.getLogger(__name__)

ACTIVE_JOB = ['accepted', 'picked_up', 'in_transit']


# ---------------------------------------------------------------- choosing riders

def ready_riders(ds, now):
    """Online, approved riders with a recent location who aren't on a job."""
    busy = DeliveryAssignment.objects.filter(status__in=ACTIVE_JOB).values('delivery_person_id')
    return (
        DeliveryProfile.objects.filter(
            is_available=True,
            is_approved=True,
            user__is_active=True,
            location_updated_at__gte=now - timedelta(minutes=ds.location_fresh_minutes),
            current_location_lat__isnull=False,
            current_location_lng__isnull=False,
        )
        .exclude(user_id__in=busy)
        .select_related('user')
    )


def rank_riders(pickup, ds, now, exclude_ids=()):
    """Riders within range of the shop, best first, as (score, km, profile)."""
    profiles = [p for p in ready_riders(ds, now) if p.user_id not in exclude_ids]
    if not profiles:
        return []
    last_job = dict(
        DeliveryAssignment.objects.filter(
            delivery_person_id__in=[p.user_id for p in profiles], status='delivered',
        )
        .order_by()
        .values('delivery_person_id')
        .annotate(t=Max('delivered_at'))
        .values_list('delivery_person_id', 't')
    )
    ranked = []
    for p in profiles:
        km = LocationService.calculate_distance(
            p.current_location_lat, p.current_location_lng, pickup['lat'], pickup['lng'],
        )
        if km > ds.max_distance_km:
            continue
        since = max((t for t in (last_job.get(p.user_id), p.online_since) if t), default=None)
        waited = ds.wait_cap_minutes if since is None else (now - since).total_seconds() / 60
        score = min(waited, ds.wait_cap_minutes) - ds.km_penalty * km
        ranked.append((score, km, p))
    ranked.sort(key=lambda r: (-r[0], r[1]))
    return ranked


def _riders_holding_live_offers(now):
    """A rider gets one offer at a time, so two orders never fight over the same rider."""
    return set(
        DeliveryOffer.objects.filter(status='pending', expires_at__gt=now).values_list('rider_id', flat=True)
    )


# ---------------------------------------------------------------- rounds

def _order_needs_rider(order):
    if order.status != 'out_for_delivery' or order.fulfillment_type == 'pickup':
        return False
    # One assignment per order (OneToOne), so any assignment means it's taken.
    return not DeliveryAssignment.objects.filter(order=order).exists()


def start_dispatch(order):
    """The seller marked the order ready: offer it to the first riders."""
    now = timezone.now()
    with transaction.atomic():
        dispatch, _ = DeliveryDispatch.objects.select_for_update().get_or_create(order=order)
        if not _order_needs_rider(order):
            return dispatch
        DeliveryOffer.objects.filter(order=order, status='pending').update(status='expired', responded_at=now)
        dispatch.round = 0
        dispatch.round_ends_at = None
        dispatch.opened_at = None
        dispatch.finished_at = None
        _next_round(dispatch, DispatchSettings.get(), now)
    return dispatch


def _next_round(dispatch, ds, now):
    """Offer to the next riders, or open the order to everyone. Caller holds the dispatch lock."""
    order = dispatch.order
    pickup = resolve_pickup_coordinates(order.seller, allow_fallback=False)
    if pickup is None or dispatch.round >= ds.rounds_before_open:
        _open_to_all(dispatch, ds, now, pickup)
        return
    already_asked = set(DeliveryOffer.objects.filter(order=order).values_list('rider_id', flat=True))
    chosen = rank_riders(pickup, ds, now, already_asked | _riders_holding_live_offers(now))
    chosen = chosen[:ds.riders_per_round]
    if not chosen:
        _open_to_all(dispatch, ds, now, pickup)
        return

    dispatch.round += 1
    dispatch.round_ends_at = now + timedelta(seconds=ds.seconds_per_round)
    dispatch.save()
    offers = [
        DeliveryOffer.objects.create(
            order=order,
            rider=profile.user,
            round=dispatch.round,
            expires_at=dispatch.round_ends_at,
            rider_distance_km=round(km, 2),
        )
        for _score, km, profile in chosen
    ]
    transaction.on_commit(lambda: [_push_offer(o) for o in offers])


def _open_to_all(dispatch, ds, now, pickup):
    dispatch.opened_at = now
    dispatch.round_ends_at = None
    dispatch.save()
    if pickup is None:
        return  # can't tell who is near; riders still see it in their list
    said_no = set(
        DeliveryOffer.objects.filter(order=dispatch.order, status='declined').values_list('rider_id', flat=True)
    )
    riders = [p.user for _s, _km, p in rank_riders(pickup, ds, now, said_no)]
    order = dispatch.order
    transaction.on_commit(lambda: [_push_open(u, order) for u in riders])


def advance_dispatch(now=None):
    """Move on every order whose round has ended. Cheap, and safe to call often from many requests."""
    now = now or timezone.now()
    due = list(
        DeliveryDispatch.objects.filter(
            finished_at__isnull=True, opened_at__isnull=True, round_ends_at__lte=now,
        ).values_list('pk', flat=True)[:50]
    )
    if not due:
        return 0
    ds = DispatchSettings.get()
    moved = 0
    for pk in due:
        missed_riders = []
        with transaction.atomic():
            dispatch = (
                DeliveryDispatch.objects.select_for_update(skip_locked=True, of=('self',))
                .select_related('order', 'order__seller')
                .filter(pk=pk, finished_at__isnull=True, opened_at__isnull=True, round_ends_at__lte=now)
                .first()
            )
            if dispatch is None:
                continue  # another request is already moving it on
            pending = DeliveryOffer.objects.filter(order=dispatch.order, status='pending')
            missed_riders = list(pending.values_list('rider_id', flat=True))
            pending.update(status='expired', responded_at=now)
            if _order_needs_rider(dispatch.order):
                _next_round(dispatch, ds, now)
            else:
                dispatch.finished_at = now
                dispatch.save(update_fields=['finished_at'])
            moved += 1
        # Outside the dispatch lock, so it never waits on a rider row while holding it.
        for rider_id in missed_riders:
            _count_missed_offer(rider_id, ds)
    return moved


def finish_dispatch(order, rider, now=None):
    """A rider took the order. Caller holds the dispatch and order locks."""
    now = now or timezone.now()
    DeliveryDispatch.objects.filter(order=order, finished_at__isnull=True).update(finished_at=now)
    DeliveryOffer.objects.filter(order=order, status='pending').exclude(rider=rider).update(
        status='taken', responded_at=now,
    )


def decline_offer(offer, now=None):
    """The rider pressed "No thanks". Doesn't count as a miss; moves on early if everyone said no."""
    now = now or timezone.now()
    with transaction.atomic():
        dispatch = DeliveryDispatch.objects.select_for_update().filter(order=offer.order_id).first()
        offer.refresh_from_db()
        if offer.status != 'pending':
            return False
        offer.status = 'declined'
        offer.responded_at = now
        offer.save(update_fields=['status', 'responded_at'])
        round_empty = not DeliveryOffer.objects.filter(order=offer.order_id, status='pending').exists()
        if dispatch and round_empty and dispatch.finished_at is None and dispatch.opened_at is None:
            dispatch.round_ends_at = now
            dispatch.save(update_fields=['round_ends_at'])
        DeliveryProfile.objects.filter(user_id=offer.rider_id).update(missed_offers_in_a_row=0)
    advance_dispatch()
    return True


# ---------------------------------------------------------------- riders

def set_rider_location(user, lat, lng, now=None):
    if lat is None or lng is None or (float(lat) == 0 and float(lng) == 0):
        return
    DeliveryProfile.objects.filter(user=user).update(
        current_location_lat=float(lat),
        current_location_lng=float(lng),
        location_updated_at=now or timezone.now(),
    )


def set_rider_online(user, online, lat=None, lng=None):
    """Going online needs a location; it also starts the fairness clock."""
    now = timezone.now()
    profile = DeliveryProfile.objects.get(user=user)
    if online:
        if not profile.is_available or profile.online_since is None:
            profile.online_since = now
        profile.is_available = True
        profile.missed_offers_in_a_row = 0
        if lat is not None and lng is not None:
            profile.current_location_lat = float(lat)
            profile.current_location_lng = float(lng)
            profile.location_updated_at = now
    else:
        profile.is_available = False
        profile.online_since = None
    profile.save(update_fields=[
        'is_available', 'online_since', 'missed_offers_in_a_row',
        'current_location_lat', 'current_location_lng', 'location_updated_at',
    ])
    if not online:
        _release_live_offers(user, now)
    return profile


def _release_live_offers(user, now):
    """A rider going offline hands their live offers straight to the next riders."""
    offers = list(DeliveryOffer.objects.filter(rider=user, status='pending', expires_at__gt=now))
    for offer in offers:
        decline_offer(offer, now)


def _count_missed_offer(rider_id, ds):
    if not ds.missed_offers_limit:
        return
    with transaction.atomic():
        profile = DeliveryProfile.objects.select_for_update().filter(user_id=rider_id).select_related('user').first()
        if profile is None:
            return
        profile.missed_offers_in_a_row += 1
        set_offline = profile.is_available and profile.missed_offers_in_a_row >= ds.missed_offers_limit
        if set_offline:
            profile.is_available = False
            profile.online_since = None
            profile.missed_offers_in_a_row = 0
        profile.save(update_fields=['missed_offers_in_a_row', 'is_available', 'online_since'])
    if set_offline:
        _notify_set_offline(profile.user, ds.missed_offers_limit)


# ---------------------------------------------------------------- notifications

def _offer_text(order):
    fee = order.delivery_fee or 0
    shop = getattr(getattr(order.seller, 'seller_profile', None), 'shop_name', '') or 'a shop'
    return f'K{fee:.0f}' if fee == int(fee) else f'K{fee:.2f}', shop


def _push_offer(offer):
    from notifications.signals import _send_push

    fee, shop = _offer_text(offer.order)
    km = f' · {offer.rider_distance_km:.1f} km away' if offer.rider_distance_km is not None else ''
    _send_push(
        offer.rider,
        'New delivery for you',
        f'{fee} · pick up at {shop}{km}. Open the app to accept.',
        {
            'type': 'delivery_offer',
            'offer_id': offer.id,
            'order_id': offer.order_id,
            'expires_at': offer.expires_at.isoformat(),
        },
    )


def _push_open(rider, order):
    from notifications.signals import _send_push

    fee, shop = _offer_text(order)
    _send_push(
        rider,
        'Delivery near you',
        f'{fee} · pick up at {shop}. First rider to accept gets it.',
        {'type': 'delivery_open', 'order_id': order.id},
    )


def _notify_set_offline(user, limit):
    from notifications.signals import _create_notification

    _create_notification(
        recipient=user,
        notification_type='rider_offline',
        title="You're offline",
        message=f'You missed {limit} delivery offers in a row, so we set you offline. '
                "Go online again when you're ready.",
        data_payload={'type': 'rider_offline'},
    )
