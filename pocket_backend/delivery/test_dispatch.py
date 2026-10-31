from datetime import timedelta
from decimal import Decimal
from unittest import mock

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APITestCase

from accounts.models import DeliveryProfile, SellerProfile, User
from notifications.models import Notification
from orders.models import Order

from .dispatch import advance_dispatch, rank_riders, start_dispatch
from .models import DeliveryAssignment, DeliveryDispatch, DeliveryOffer, DispatchSettings

SHOP = (-15.4000, 28.3000)
KM = 0.009  # about 1 km of latitude


def make_rider(phone, km=1.0, online_min=30, online=True, fresh=True):
    user = User.objects.create_user(phone_number=phone, password='x', full_name=f'Rider {phone[-2:]}', role='delivery')
    now = timezone.now()
    DeliveryProfile.objects.create(
        user=user, vehicle_type='motorcycle', license_number='L1', is_approved=True, is_available=online,
        current_location_lat=SHOP[0] + km * KM, current_location_lng=SHOP[1],
        location_updated_at=now if fresh else now - timedelta(minutes=30),
        online_since=now - timedelta(minutes=online_min) if online else None,
    )
    return user


class DispatchBase(APITestCase):
    def setUp(self):
        self.seller = User.objects.create_user(phone_number='+260922000000', password='x', full_name='Shop', role='seller')
        SellerProfile.objects.create(
            user=self.seller, shop_name='Mama Shop', shop_location='Lusaka', is_approved=True,
            shop_lat=SHOP[0], shop_lng=SHOP[1],
        )
        self.buyer = User.objects.create_user(phone_number='+260911000000', password='x', full_name='Buyer', role='buyer')
        route = mock.patch('delivery.views.apply_route_to_assignment')
        route.start()
        self.addCleanup(route.stop)

    def ready_order(self, **extra):
        fields = dict(
            buyer=self.buyer, seller=self.seller, total_price=Decimal('100'), delivery_fee=Decimal('35'),
            status='out_for_delivery', delivery_address='Kabulonga', delivery_lat=-15.42, delivery_lng=28.32,
        )
        fields.update(extra)
        return Order.objects.create(**fields)

    def offered(self, order, round_=None):
        qs = DeliveryOffer.objects.filter(order=order, status='pending')
        if round_ is not None:
            qs = qs.filter(round=round_)
        return set(qs.values_list('rider_id', flat=True))

    def end_round(self, order):
        DeliveryDispatch.objects.filter(order=order).update(round_ends_at=timezone.now() - timedelta(seconds=1))
        advance_dispatch()

    def accept(self, rider, order):
        self.client.force_authenticate(rider)
        return self.client.post('/api/delivery/orders/accept/', {'order_id': order.id, 'lat': -15.4, 'lng': 28.3}, format='json')

    def available(self, rider):
        self.client.force_authenticate(rider)
        return self.client.get('/api/delivery/orders/available/', {'lat': -15.4, 'lng': 28.3})


class WhoGetsOffersTests(DispatchBase):
    def setUp(self):
        super().setUp()
        self.a = make_rider('+260970000001', km=3, online_min=40)    # 40 - 15 = 25
        self.b = make_rider('+260970000002', km=1, online_min=120)   # just finished a job: 5 - 5 = 0
        self.c = make_rider('+260970000003', km=0.5, online_min=20)  # 20 - 2.5 = 17.5
        make_rider('+260970000004', km=8)                  # too far
        make_rider('+260970000005', km=0.2, online=False)  # offline
        make_rider('+260970000006', km=0.2, fresh=False)   # location too old
        old = self.ready_order(status='delivered')
        DeliveryAssignment.objects.create(
            order=old, delivery_person=self.b, status='delivered', delivered_at=timezone.now() - timedelta(minutes=5),
            pickup_location={}, delivery_location={}, estimated_distance=1, estimated_duration=5,
        )

    def test_fair_order_and_who_is_left_out(self):
        ranked = [p.user for _s, _km, p in rank_riders({'lat': SHOP[0], 'lng': SHOP[1]}, DispatchSettings.get(), timezone.now())]
        self.assertEqual(ranked, [self.a, self.c, self.b])

    def test_rounds_then_open_to_all(self):
        order = self.ready_order()
        start_dispatch(order)
        self.assertEqual(self.offered(order, 1), {self.a.id, self.c.id})

        self.end_round(order)
        self.assertEqual(self.offered(order, 2), {self.b.id})
        self.assertEqual(DeliveryOffer.objects.filter(order=order, status='expired').count(), 2)

        self.end_round(order)  # nobody new left -> everyone nearby
        self.assertIsNotNone(DeliveryDispatch.objects.get(order=order).opened_at)
        r = self.available(self.a)
        self.assertEqual([row['id'] for row in r.data], [order.id])
        self.assertFalse(r.data[0]['is_offer'])

    def test_pickup_orders_are_never_sent_to_riders(self):
        order = self.ready_order(fulfillment_type='pickup')
        start_dispatch(order)
        self.assertEqual(self.offered(order), set())
        self.assertEqual(self.available(self.a).data, [])


class AcceptTests(DispatchBase):
    def setUp(self):
        super().setUp()
        self.near = make_rider('+260970000011', km=0.5, online_min=50)
        self.next = make_rider('+260970000012', km=0.6, online_min=45)
        self.other = make_rider('+260970000013', km=0.7, online_min=10)
        self.order = self.ready_order()
        start_dispatch(self.order)

    def test_only_offered_riders_see_and_take_it_during_rounds(self):
        self.assertEqual(self.offered(self.order), {self.near.id, self.next.id})
        self.assertEqual(self.available(self.other).data, [])
        r = self.accept(self.other, self.order)
        self.assertEqual(r.status_code, 400)
        self.assertIn('offered to other riders first', r.data['error'])

        row = self.available(self.near).data[0]
        self.assertTrue(row['is_offer'])
        self.assertIsNotNone(row['offer_expires_at'])

    def test_first_accept_wins_and_the_other_offer_is_closed(self):
        self.assertEqual(self.accept(self.near, self.order).status_code, 201)
        r = self.accept(self.next, self.order)
        self.assertEqual(r.status_code, 400)
        self.assertIn('already took', r.data['error'])
        self.assertEqual(DeliveryOffer.objects.get(order=self.order, rider=self.next).status, 'taken')
        self.assertIsNotNone(DeliveryDispatch.objects.get(order=self.order).finished_at)

    def test_one_rider_cannot_take_two_orders(self):
        self.assertEqual(self.accept(self.near, self.order).status_code, 201)
        second = self.ready_order()
        DeliveryDispatch.objects.create(order=second, opened_at=timezone.now())
        r = self.accept(self.near, second)
        self.assertEqual(r.status_code, 400)
        self.assertIn('active delivery', r.data['error'])

    def test_a_rider_holds_one_offer_at_a_time(self):
        second = self.ready_order()
        start_dispatch(second)
        self.assertEqual(self.offered(second), {self.other.id})

    def test_offline_rider_cannot_accept(self):
        DeliveryProfile.objects.filter(user=self.near).update(is_available=False)
        r = self.accept(self.near, self.order)
        self.assertEqual(r.status_code, 400)
        self.assertIn('Go online', r.data['error'])


class DeclineAndMissTests(DispatchBase):
    def setUp(self):
        super().setUp()
        self.r1 = make_rider('+260970000021', km=0.5, online_min=50)
        self.r2 = make_rider('+260970000022', km=0.6, online_min=45)
        self.r3 = make_rider('+260970000023', km=0.7, online_min=10)

    def test_when_everyone_says_no_it_moves_on_straight_away(self):
        order = self.ready_order()
        start_dispatch(order)
        for rider in (self.r1, self.r2):
            offer = DeliveryOffer.objects.get(order=order, rider=rider)
            self.client.force_authenticate(rider)
            self.assertEqual(self.client.post(f'/api/delivery/offers/{offer.id}/decline/').status_code, 200)
        self.assertEqual(self.offered(order, 2), {self.r3.id})
        self.assertEqual(DeliveryProfile.objects.get(user=self.r1).missed_offers_in_a_row, 0)

    def test_three_missed_offers_in_a_row_sets_rider_offline(self):
        for _ in range(3):
            order = self.ready_order()
            start_dispatch(order)
            self.assertIn(self.r1.id, self.offered(order, 1))
            self.end_round(order)
            Order.objects.filter(pk=order.pk).update(status='cancelled')
            advance_dispatch()
            DeliveryOffer.objects.filter(status='pending').update(status='expired')
        profile = DeliveryProfile.objects.get(user=self.r1)
        self.assertFalse(profile.is_available)
        self.assertTrue(Notification.objects.filter(recipient=self.r1, notification_type='rider_offline').exists())


class RiderStatusTests(DispatchBase):
    def setUp(self):
        super().setUp()
        self.rider = make_rider('+260970000031', km=0.5, online=False)
        self.client.force_authenticate(self.rider)

    def test_going_online_needs_location(self):
        r = self.client.post('/api/delivery/rider/status/', {'online': True}, format='json')
        self.assertEqual(r.status_code, 400)
        self.assertIn('location', r.data['error'])
        r = self.client.post('/api/delivery/rider/status/', {'online': True, 'lat': -15.4, 'lng': 28.3}, format='json')
        self.assertTrue(r.data['online'])
        self.assertIsNotNone(DeliveryProfile.objects.get(user=self.rider).online_since)

    def test_offline_rider_sees_nothing(self):
        self.ready_order()
        self.assertEqual(self.available(self.rider).data, [])

    def test_going_offline_passes_live_offers_on(self):
        self.client.post('/api/delivery/rider/status/', {'online': True, 'lat': -15.4, 'lng': 28.3}, format='json')
        backup = make_rider('+260970000032', km=1, online_min=5)
        DispatchSettings.objects.update_or_create(pk=1, defaults={'riders_per_round': 1})
        order = self.ready_order()
        start_dispatch(order)
        self.assertEqual(self.offered(order), {self.rider.id})
        self.client.force_authenticate(self.rider)
        self.client.post('/api/delivery/rider/status/', {'online': False}, format='json')
        self.assertEqual(self.offered(order), {backup.id})


class SellerMarksReadyTests(DispatchBase):
    def test_seller_marking_ready_starts_offers(self):
        rider = make_rider('+260970000041', km=0.5)
        order = self.ready_order(status='preparing')
        self.client.force_authenticate(self.seller)
        r = self.client.put(f'/api/orders/orders/{order.id}/status/', {'status': 'out_for_delivery'}, format='json')
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(self.offered(order), {rider.id})
