from datetime import timedelta
from decimal import Decimal
from unittest import mock

from django.utils import timezone
from rest_framework.test import APITestCase

from accounts.models import SellerProfile, User
from delivery.models import DeliveryPricingConfig
from products.models import Category, Product

from .models import TransportRequest


def _setup():
    """A seller 500km from a buyer, with max delivery distance at 100km."""
    config = DeliveryPricingConfig.get_config()
    config.max_delivery_distance_km = 100
    config.save()

    seller = User.objects.create_user(phone_number='+260911111111', password='x', full_name='Seller', role='seller')
    SellerProfile.objects.create(
        user=seller, shop_name='Far Shop', shop_location='Kasama', is_approved=True,
        shop_lat=-10.2167, shop_lng=31.1800,  # Kasama
    )
    buyer = User.objects.create_user(phone_number='+260922222222', password='x', full_name='Buyer', role='buyer')
    product = Product.objects.create(
        name='Bag of Mealie Meal', description='d', price=Decimal('450.00'),
        seller=seller, stock_quantity=5,
    )
    # Lusaka — genuinely ~600km from Kasama by straight-line distance.
    buyer_lat, buyer_lng = -15.3875, 28.3228
    return seller, buyer, product, buyer_lat, buyer_lng


class TransportRequestCreateTests(APITestCase):
    def setUp(self):
        self.seller, self.buyer, self.product, self.lat, self.lng = _setup()
        self.client.force_authenticate(self.buyer)

    def _create(self, **overrides):
        body = {
            'product_id': self.product.id, 'quantity': 1,
            'delivery_address': 'Lusaka, near the market',
            'delivery_lat': self.lat, 'delivery_lng': self.lng,
            **overrides,
        }
        return self.client.post('/api/orders/transport-requests/', body, format='json')

    def test_creates_a_request_and_notifies_the_seller(self):
        with mock.patch('orders.transport_views._notify') as notify:
            r = self._create()
        self.assertEqual(r.status_code, 201)
        self.assertEqual(r.json()['status'], 'pending')
        self.assertGreater(r.json()['distance_km'], 100)
        tr = TransportRequest.objects.get()
        self.assertEqual((tr.buyer, tr.seller, tr.product), (self.buyer, self.seller, self.product))
        self.assertAlmostEqual((tr.expires_at - tr.created_at).total_seconds(), 24 * 3600, delta=5)
        notify.assert_called_once()
        self.assertEqual(notify.call_args.args[0], self.seller)

    def test_refused_when_within_normal_delivery_range(self):
        # A point ~30km from the shop, well inside the 100km cap.
        r = self._create(delivery_lat=-10.45, delivery_lng=31.40)
        self.assertEqual(r.status_code, 400)
        self.assertIn('within normal delivery range', r.json()['error'])

    def test_only_buyers_can_create_one(self):
        self.client.force_authenticate(self.seller)
        self.assertEqual(self._create().status_code, 403)

    def test_cannot_open_a_second_request_for_the_same_product(self):
        self.assertEqual(self._create().status_code, 201)
        r = self._create()
        self.assertEqual(r.status_code, 400)
        self.assertIn('already have an open', r.json()['error'])

    def test_age_restricted_product_is_blocked_same_as_checkout(self):
        liq = Category.objects.create(name='Liq', slug='liq-transport', is_age_restricted=True)
        self.product.category = liq
        self.product.save()
        r = self._create()
        self.assertEqual(r.status_code, 403)

    def test_seller_without_shop_coordinates_is_refused_cleanly(self):
        self.seller.seller_profile.shop_lat = None
        self.seller.seller_profile.save()
        r = self._create()
        self.assertEqual(r.status_code, 400)


class TransportRequestProposeDeclineTests(APITestCase):
    def setUp(self):
        self.seller, self.buyer, self.product, self.lat, self.lng = _setup()
        self.client.force_authenticate(self.buyer)
        r = self.client.post('/api/orders/transport-requests/', {
            'product_id': self.product.id, 'quantity': 1, 'delivery_address': 'Lusaka',
            'delivery_lat': self.lat, 'delivery_lng': self.lng,
        }, format='json')
        self.tr_id = r.json()['id']

    def test_seller_proposes_and_buyer_is_notified(self):
        self.client.force_authenticate(self.seller)
        with mock.patch('orders.transport_views._notify') as notify:
            r = self.client.post(f'/api/orders/transport-requests/{self.tr_id}/propose/', {
                'method': 'Power Tools Bus, Lusaka branch', 'fee': '150.00',
            }, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertEqual((r.json()['status'], r.json()['proposed_fee']), ('proposed', '150.00'))
        notify.assert_called_once()
        self.assertEqual(notify.call_args.args[0], self.buyer)

    def test_seller_declines_with_an_optional_reason(self):
        self.client.force_authenticate(self.seller)
        r = self.client.post(f'/api/orders/transport-requests/{self.tr_id}/decline/', {
            'reason': 'Too fragile to bus.',
        }, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()['status'], 'declined')
        self.assertEqual(TransportRequest.objects.get(pk=self.tr_id).decline_reason, 'Too fragile to bus.')

    def test_decline_reason_is_optional(self):
        self.client.force_authenticate(self.seller)
        r = self.client.post(f'/api/orders/transport-requests/{self.tr_id}/decline/', {}, format='json')
        self.assertEqual(r.status_code, 200)

    def test_only_the_assigned_seller_can_respond(self):
        other_seller = User.objects.create_user(
            phone_number='+260933333333', password='x', full_name='Other', role='seller')
        self.client.force_authenticate(other_seller)
        r = self.client.post(f'/api/orders/transport-requests/{self.tr_id}/propose/', {
            'method': 'x', 'fee': '10',
        }, format='json')
        self.assertEqual(r.status_code, 404)

    def test_cannot_respond_twice(self):
        self.client.force_authenticate(self.seller)
        self.client.post(f'/api/orders/transport-requests/{self.tr_id}/decline/', {}, format='json')
        r = self.client.post(f'/api/orders/transport-requests/{self.tr_id}/propose/', {
            'method': 'x', 'fee': '10',
        }, format='json')
        self.assertEqual(r.status_code, 400)

    def test_buyer_cannot_propose_or_decline(self):
        r = self.client.post(f'/api/orders/transport-requests/{self.tr_id}/propose/', {
            'method': 'x', 'fee': '10',
        }, format='json')
        self.assertEqual(r.status_code, 403)


class TransportRequestAcceptTests(APITestCase):
    def setUp(self):
        self.seller, self.buyer, self.product, self.lat, self.lng = _setup()
        self.client.force_authenticate(self.buyer)
        r = self.client.post('/api/orders/transport-requests/', {
            'product_id': self.product.id, 'quantity': 2, 'delivery_address': 'Lusaka, near the market',
            'delivery_lat': self.lat, 'delivery_lng': self.lng,
        }, format='json')
        self.tr_id = r.json()['id']
        self.client.force_authenticate(self.seller)
        self.client.post(f'/api/orders/transport-requests/{self.tr_id}/propose/', {
            'method': 'Power Tools Bus', 'fee': '150.00',
        }, format='json')
        self.client.force_authenticate(self.buyer)

    def test_accepting_creates_an_order_with_the_agreed_fee_not_a_recalculated_one(self):
        r = self.client.post(f'/api/orders/transport-requests/{self.tr_id}/accept/')
        self.assertEqual(r.status_code, 201)
        order = r.json()
        self.assertEqual(order['quoted_delivery_fee'], '150.00')  # the agreed fee...
        self.assertEqual(order['total_price'], '900.00')  # ...not a distance-based one (2 x 450)
        self.assertEqual(order['fulfillment_type'], 'delivery')
        self.assertEqual(order['status'], 'payment_pending')

        tr = TransportRequest.objects.get(pk=self.tr_id)
        self.assertEqual(tr.status, 'accepted')
        self.assertIsNotNone(tr.order)
        self.assertEqual(tr.order.order_number, order['order_number'])

    def test_stock_is_deducted_same_as_a_normal_order(self):
        self.client.post(f'/api/orders/transport-requests/{self.tr_id}/accept/')
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 3)  # 5 - 2

    def test_out_of_stock_at_accept_time_is_refused_cleanly(self):
        self.product.stock_quantity = 1
        self.product.save()
        r = self.client.post(f'/api/orders/transport-requests/{self.tr_id}/accept/')
        self.assertEqual(r.status_code, 400)
        self.assertIn('Insufficient stock', r.json()['error'])
        self.assertEqual(TransportRequest.objects.get(pk=self.tr_id).status, 'proposed')  # unchanged, can't double-spend

    def test_cannot_accept_a_request_still_pending(self):
        # A different product, so this doesn't collide with the setUp request
        # (still open, 'proposed') under the one-live-request-per-product rule.
        other_product = Product.objects.create(
            name='Other', description='d', price=Decimal('10'), seller=self.seller, stock_quantity=5)
        r2 = self.client.post('/api/orders/transport-requests/', {
            'product_id': other_product.id, 'quantity': 1, 'delivery_address': 'Lusaka',
            'delivery_lat': self.lat, 'delivery_lng': self.lng,
        }, format='json')
        pending_id = r2.json()['id']
        r = self.client.post(f'/api/orders/transport-requests/{pending_id}/accept/')
        self.assertEqual(r.status_code, 400)

    def test_only_the_requesting_buyer_can_accept(self):
        other_buyer = User.objects.create_user(
            phone_number='+260944444444', password='x', full_name='Other Buyer', role='buyer')
        self.client.force_authenticate(other_buyer)
        r = self.client.post(f'/api/orders/transport-requests/{self.tr_id}/accept/')
        self.assertEqual(r.status_code, 404)

    def test_cannot_accept_the_same_request_twice(self):
        self.assertEqual(self.client.post(f'/api/orders/transport-requests/{self.tr_id}/accept/').status_code, 201)
        r = self.client.post(f'/api/orders/transport-requests/{self.tr_id}/accept/')
        self.assertEqual(r.status_code, 400)


class TransportRequestExpiryTests(APITestCase):
    def test_expire_command_only_touches_overdue_pending_requests(self):
        from django.core.management import call_command

        seller, buyer, product, lat, lng = _setup()
        # Different products so these don't collide with the one-live-request-
        # per-buyer-product constraint — each row here stands for a different
        # buyer/request in reality, this just keeps the test setup light.
        product2 = Product.objects.create(name='P2', description='d', price=Decimal('10'), seller=seller, stock_quantity=5)
        product3 = Product.objects.create(name='P3', description='d', price=Decimal('10'), seller=seller, stock_quantity=5)
        fresh = TransportRequest.objects.create(
            buyer=buyer, seller=seller, product=product, distance_km=500,
            delivery_address='x', expires_at=timezone.now() + timedelta(hours=1),
        )
        overdue = TransportRequest.objects.create(
            buyer=buyer, seller=seller, product=product2, distance_km=500,
            delivery_address='x', expires_at=timezone.now() - timedelta(minutes=1),
        )
        # Already decided — must not be touched even though its window has long passed.
        decided = TransportRequest.objects.create(
            buyer=buyer, seller=seller, product=product3, distance_km=500, status='declined',
            delivery_address='x', expires_at=timezone.now() - timedelta(days=5),
        )

        call_command('expire_transport_requests')

        fresh.refresh_from_db(); overdue.refresh_from_db(); decided.refresh_from_db()
        self.assertEqual(fresh.status, 'pending')
        self.assertEqual(overdue.status, 'expired')
        self.assertIsNotNone(overdue.decided_at)
        self.assertEqual(decided.status, 'declined')

    def test_an_expired_request_frees_the_buyer_to_ask_again(self):
        from django.core.management import call_command
        seller, buyer, product, lat, lng = _setup()
        TransportRequest.objects.create(
            buyer=buyer, seller=seller, product=product, distance_km=500,
            delivery_address='x', expires_at=timezone.now() - timedelta(minutes=1),
        )
        call_command('expire_transport_requests')

        self.client.force_authenticate(buyer)
        r = self.client.post('/api/orders/transport-requests/', {
            'product_id': product.id, 'quantity': 1, 'delivery_address': 'Lusaka',
            'delivery_lat': lat, 'delivery_lng': lng,
        }, format='json')
        self.assertEqual(r.status_code, 201)


class DeliveryQuoteDistanceCapTests(APITestCase):
    def test_quote_reports_within_range_for_a_nearby_point(self):
        seller, buyer, product, lat, lng = _setup()
        self.client.force_authenticate(buyer)
        r = self.client.post('/api/delivery/quote/', {
            'delivery_lat': -10.45, 'delivery_lng': 31.40,  # ~30km from the shop
            'seller_id': seller.id,
        }, format='json')
        body = r.json()
        self.assertTrue(body['within_range'])
        self.assertIsNotNone(body['estimated_fee_zmw'])

    def test_quote_reports_out_of_range_and_no_fee_for_a_distant_point(self):
        seller, buyer, product, lat, lng = _setup()
        self.client.force_authenticate(buyer)
        r = self.client.post('/api/delivery/quote/', {
            'delivery_lat': lat, 'delivery_lng': lng, 'seller_id': seller.id,
        }, format='json')
        body = r.json()
        self.assertFalse(body['within_range'])
        self.assertIsNone(body['estimated_fee_zmw'])
        self.assertGreater(body['distance_km'], 100)


class CreateOrderDistanceCapTests(APITestCase):
    """Server-side enforcement in normal checkout, not just the quote step."""

    def test_normal_checkout_refuses_delivery_beyond_the_cap(self):
        import json as _json
        seller, buyer, product, lat, lng = _setup()
        self.client.force_authenticate(buyer)
        self.client.post('/api/orders/cart/', {'product_id': product.id, 'quantity': 1}, format='json')

        meta = _json.dumps({'fulfillment_type': 'delivery', 'delivery_lat': lat, 'delivery_lng': lng})
        r = self.client.post('/api/orders/orders/create/', {
            'delivery_address': 'Lusaka',
            'special_instructions': f'[PS_META]{meta}[/PS_META]',
        }, format='json')
        self.assertEqual(r.status_code, 400)
        self.assertIn('too far for', r.json()['error'])
