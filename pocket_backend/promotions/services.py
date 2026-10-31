"""Discount and partner-earning rules. Views and signals call these; nothing else does the maths."""
from dataclasses import dataclass
from datetime import timedelta
from decimal import ROUND_HALF_UP, Decimal
from typing import Optional

from django.utils import timezone

from .models import FIXED, Partner, PartnerEarning, PromoCode, PromoSettings, Referral

CENT = Decimal('0.01')
# An unpaid order stops "holding" a discount after this long, so an abandoned
# checkout doesn't lock the buyer out of their welcome discount forever.
UNPAID_HOLD = timedelta(hours=2)


class PromoError(Exception):
    """A promo code that can't be used. The message is shown to the buyer."""


@dataclass
class Discount:
    kind: str = ''              # '', 'welcome' or 'promo'
    amount: Decimal = Decimal('0')
    promo: Optional[PromoCode] = None
    label: str = ''

    def as_dict(self):
        return {
            'kind': self.kind,
            'amount': str(self.amount),
            'code': self.promo.code if self.promo else None,
            'label': self.label,
        }


def _money(v) -> Decimal:
    return Decimal(str(v)).quantize(CENT, rounding=ROUND_HALF_UP)


def discount_amount(discount_type, value, cap, subtotal) -> Decimal:
    subtotal = _money(subtotal)
    if discount_type == FIXED:
        amount = Decimal(str(value))
    else:
        amount = subtotal * Decimal(str(value)) / Decimal('100')
    if cap is not None:
        amount = min(amount, Decimal(str(cap)))
    return _money(max(Decimal('0'), min(amount, subtotal)))


def _discount_label(discount_type, value):
    v = Decimal(str(value))
    v = v.quantize(Decimal('1')) if v == v.to_integral() else v
    return f'K{v} off' if discount_type == FIXED else f'{v}% off'


def _holding_orders(user):
    """Orders that count as 'used' for discount limits: paid, or unpaid but recent."""
    from orders.models import Order

    cutoff = timezone.now() - UNPAID_HOLD
    return Order.objects.filter(buyer=user).exclude(status='cancelled').exclude(
        status='payment_pending', created_at__lt=cutoff,
    )


def has_placed_order(user) -> bool:
    return _holding_orders(user).exists()


def welcome_discount(user, subtotal, ps=None) -> Discount:
    ps = ps or PromoSettings.get()
    if not ps.welcome_enabled or getattr(user, 'role', 'buyer') != 'buyer':
        return Discount()
    if user.date_joined < timezone.now() - timedelta(days=ps.welcome_valid_days):
        return Discount()
    if _money(subtotal) < ps.welcome_min_order or has_placed_order(user):
        return Discount()
    amount = discount_amount(ps.welcome_discount_type, ps.welcome_discount_value, ps.welcome_max_discount, subtotal)
    if amount <= 0:
        return Discount()
    return Discount('welcome', amount, None, 'Welcome discount')


def promo_discount(user, code, subtotal) -> Discount:
    code = (code or '').strip().upper()
    promo = PromoCode.objects.filter(code=code).first()
    if promo is None or not promo.is_active:
        raise PromoError("That promo code isn't valid.")
    now = timezone.now()
    if promo.starts_at and now < promo.starts_at:
        raise PromoError("That promo code hasn't started yet.")
    if promo.ends_at and now > promo.ends_at:
        raise PromoError('That promo code has ended.')
    if _money(subtotal) < promo.min_order:
        raise PromoError(f'Add items worth K{promo.min_order} or more to use {promo.code}.')
    if promo.first_order_only and has_placed_order(user):
        raise PromoError(f'{promo.code} is only for your first order.')

    used_by_user = _holding_orders(user).filter(promo_code=promo).count()
    if used_by_user >= promo.max_uses_per_user:
        raise PromoError(f"You've already used {promo.code}.")
    if promo.max_uses is not None:
        from orders.models import Order

        cutoff = now - UNPAID_HOLD
        used_total = Order.objects.filter(promo_code=promo).exclude(status='cancelled').exclude(
            status='payment_pending', created_at__lt=cutoff,
        ).count()
        if used_total >= promo.max_uses:
            raise PromoError(f'{promo.code} has been fully used.')

    amount = discount_amount(promo.discount_type, promo.value, promo.max_discount, subtotal)
    if amount <= 0:
        raise PromoError("That promo code doesn't apply to this order.")
    return Discount('promo', amount, promo, f'{promo.code} ({_discount_label(promo.discount_type, promo.value)})')


def best_discount(user, subtotal, code=None) -> Discount:
    """One discount per order: the promo code or the welcome discount, whichever is bigger.

    Raises PromoError only when a code was typed and can't be used, so the buyer
    can fix it; with no code this never raises.
    """
    welcome = welcome_discount(user, subtotal)
    if not (code or '').strip():
        return welcome
    promo = promo_discount(user, code, subtotal)
    return promo if promo.amount >= welcome.amount else welcome


# ---------------------------------------------------------------- partners

def find_partner_code(code) -> Optional[Partner]:
    code = str(code or '').strip().upper()
    if not code:
        return None
    return Partner.objects.filter(code=code, status=Partner.APPROVED).first()


def attach_referral(user, code) -> Optional[Referral]:
    """Record who brought a new buyer. Silently ignores bad codes and own codes."""
    partner = find_partner_code(code)
    if partner is None or getattr(user, 'role', 'buyer') != 'buyer':
        return None
    if Referral.objects.filter(user=user).exists():
        return None
    if partner.phone and user.phone_number and _same_phone(partner.phone, user.phone_number):
        return None  # a partner can't refer themselves
    return Referral.objects.create(user=user, partner=partner, code_used=partner.code)


def _same_phone(a, b):
    da = ''.join(ch for ch in a if ch.isdigit())[-9:]
    db = ''.join(ch for ch in b if ch.isdigit())[-9:]
    return len(da) == 9 and da == db


def record_earning_for_delivered_order(order) -> Optional[PartnerEarning]:
    if order.status != 'delivered' or PartnerEarning.objects.filter(order=order).exists():
        return None
    referral = Referral.objects.select_related('partner').filter(user_id=order.buyer_id).first()
    if referral is None or not referral.partner.is_earning:
        return None
    ps = PromoSettings.get()
    if order.created_at > referral.created_at + timedelta(days=ps.partner_window_days):
        return None
    service_fee = Decimal(str(order.service_fee or 0))
    if service_fee <= 0:
        return None
    rate = referral.partner.effective_rate(ps)
    amount = _money(service_fee * rate)
    if amount <= 0:
        return None
    return PartnerEarning.objects.create(
        partner=referral.partner,
        order=order,
        referred_user_id=order.buyer_id,
        service_fee=service_fee,
        rate=rate,
        amount=amount,
        available_at=timezone.now() + timedelta(days=ps.partner_hold_days),
    )


def reverse_earning_for_refunded_order(order_id):
    PartnerEarning.objects.filter(order_id=order_id, status=PartnerEarning.ACTIVE).update(
        status=PartnerEarning.REVERSED, reversed_at=timezone.now(),
    )


def code_taken(code, exclude_partner_id=None) -> bool:
    """Partner codes and promo codes share one namespace so buyers never mix them up."""
    code = (code or '').strip().upper()
    partners = Partner.objects.filter(code=code)
    if exclude_partner_id:
        partners = partners.exclude(pk=exclude_partner_id)
    return partners.exists() or PromoCode.objects.filter(code=code).exists()


def suggest_code(name) -> str:
    """A free code from the partner's name, e.g. 'Yoma Phiri' -> YOMAPHIRI or YOMAPHIRI2."""
    base = ''.join(ch for ch in (name or '').upper() if 'A' <= ch <= 'Z' or ch.isdigit())[:12]
    if len(base) < 3:
        base = 'POCKET'
    if not code_taken(base):
        return base
    n = 2
    while code_taken(f'{base}{n}'):
        n += 1
    return f'{base}{n}'


def partner_stats(partner, since=None, until=None):
    """Numbers for the partner page and the email update."""
    referrals = partner.referrals.all()
    earnings = partner.earnings.filter(status=PartnerEarning.ACTIVE)
    if since is not None:
        referrals = referrals.filter(created_at__gte=since)
        earnings = earnings.filter(created_at__gte=since)
    if until is not None:
        referrals = referrals.filter(created_at__lt=until)
        earnings = earnings.filter(created_at__lt=until)
    total = sum((e.amount for e in earnings), Decimal('0'))
    return {
        'signups': referrals.count(),
        'orders': earnings.count(),
        'earned': total,
    }

