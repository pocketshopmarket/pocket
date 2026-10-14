from decimal import Decimal

from django.utils import timezone
from rest_framework.test import APITestCase

from accounts.models import SellerProfile, User
from delivery.models import DeliveryAssignment
from orders.models import Order, OrderItem
from products.models import Product

from .models import Transaction


class StaffAnalyticsTests(APITestCase):
    def setUp(self):
        self.staff = User.objects.create_user(
            phone_number='+260900000010', password='x', full_name='Staff', role='staff')
        self.admin = User.objects.create_user(
            phone_number='+260900000011', password='x', full_name='Admin', role='admin')
        self.buyer = User.objects.create_user(
            phone_number='+260900000012', password='x', full_name='Buyer', role='buyer')

        self.seller_a = User.objects.create_user(
            phone_number='+260900000013', password='x', full_name='Seller A', role='seller')
        SellerProfile.objects.create(user=self.seller_a, shop_name='Shop A', shop_location='Lusaka')
        self.seller_b = User.objects.create_user(
            phone_number='+260900000014', password='x', full_name='Seller B', role='seller')
        SellerProfile.objects.create(user=self.seller_b, shop_name='Shop B', shop_location='Lusaka')

        self.product_a = Product.objects.create(
            name='Widget A', description='d', price=Decimal('100.00'),
            seller=self.seller_a, stock_quantity=50,
        )
        self.product_b = Product.objects.create(
            name='Widget B', description='d', price=Decimal('30.00'),
            seller=self.seller_b, stock_quantity=50,
        )

        self.rider_a = User.objects.create_user(
            phone_number='+260900000015', password='x', full_name='Rider A', role='delivery')
        self.rider_b = User.objects.create_user(
            phone_number='+260900000016', password='x', full_name='Rider B', role='delivery')

    def _delivered_order(self, seller, product, quantity, price, created_at=None):
        order = Order.objects.create(
            buyer=self.buyer, seller=seller, total_price=Decimal(price) * quantity,
            status='delivered', delivery_address='Test',
            payment_provider_snapshot='x', payment_account_snapshot='x',
        )
        if created_at is not None:
            Order.objects.filter(pk=order.pk).update(created_at=created_at)
            order.refresh_from_db()
        OrderItem.objects.create(order=order, product=product, quantity=quantity, price=Decimal(price))
        return order

    def _delivered_assignment(self, rider, order, delivered_at=None):
        assignment = DeliveryAssignment.objects.create(
            order=order, delivery_person=rider, status='delivered',
            estimated_distance=5.0, estimated_duration=15,
        )
        DeliveryAssignment.objects.filter(pk=assignment.pk).update(
            delivered_at=delivered_at or timezone.now(),
        )
        return assignment

    def test_staff_can_access_analytics(self):
        self.client.force_authenticate(self.staff)
        r = self.client.get('/api/staff/analytics/')
        self.assertEqual(r.status_code, 200)

    def test_admin_can_access_analytics_too(self):
        self.client.force_authenticate(self.admin)
        r = self.client.get('/api/staff/analytics/')
        self.assertEqual(r.status_code, 200)

    def test_buyer_cannot_access_analytics(self):
        self.client.force_authenticate(self.buyer)
        r = self.client.get('/api/staff/analytics/')
        self.assertEqual(r.status_code, 403)

    def test_user_breakdown_counts_by_role(self):
        self.client.force_authenticate(self.staff)
        data = self.client.get('/api/staff/analytics/').json()['user_breakdown']
        self.assertEqual(data['buyer_count'], 1)
        self.assertEqual(data['seller_count'], 2)
        self.assertEqual(data['staff_count'], 1)

    def test_top_stores_ranks_by_revenue_highest_first(self):
        # Shop A: one order worth 500. Shop B: one order worth 90.
        self._delivered_order(self.seller_a, self.product_a, 5, '100.00')
        self._delivered_order(self.seller_b, self.product_b, 3, '30.00')
        self.client.force_authenticate(self.staff)
        stores = self.client.get('/api/staff/analytics/').json()['top_stores']
        self.assertEqual(stores[0]['shop_name'], 'Shop A')
        self.assertEqual(stores[0]['revenue'], '500.00')
        self.assertEqual(stores[1]['shop_name'], 'Shop B')
        self.assertEqual(stores[1]['revenue'], '90.00')

    def test_pending_and_cancelled_orders_are_excluded_from_store_revenue(self):
        self._delivered_order(self.seller_a, self.product_a, 1, '100.00')
        cancelled = Order.objects.create(
            buyer=self.buyer, seller=self.seller_a, total_price=Decimal('900.00'),
            status='cancelled', delivery_address='Test',
            payment_provider_snapshot='x', payment_account_snapshot='x',
        )
        OrderItem.objects.create(order=cancelled, product=self.product_a, quantity=9, price=Decimal('100.00'))
        self.client.force_authenticate(self.staff)
        stores = self.client.get('/api/staff/analytics/').json()['top_stores']
        self.assertEqual(len(stores), 1)
        self.assertEqual(stores[0]['revenue'], '100.00')

    def test_top_products_ranks_platform_wide_by_revenue(self):
        self._delivered_order(self.seller_a, self.product_a, 2, '100.00')  # 200
        self._delivered_order(self.seller_b, self.product_b, 10, '30.00')  # 300
        self.client.force_authenticate(self.staff)
        products = self.client.get('/api/staff/analytics/').json()['top_products']
        self.assertEqual(products[0]['name'], 'Widget B')
        self.assertEqual(products[0]['units_sold'], 10)
        self.assertEqual(products[0]['revenue'], '300.00')
        self.assertEqual(products[1]['name'], 'Widget A')

    def test_days_filter_excludes_orders_outside_the_window(self):
        old = timezone.now() - timezone.timedelta(days=60)
        self._delivered_order(self.seller_a, self.product_a, 1, '100.00', created_at=old)
        self.client.force_authenticate(self.staff)
        data = self.client.get('/api/staff/analytics/?days=30').json()
        self.assertEqual(data['top_stores'], [])
        self.assertEqual(data['top_products'], [])
        data_all = self.client.get('/api/staff/analytics/?days=365').json()
        self.assertEqual(len(data_all['top_stores']), 1)

    def test_top_riders_ranks_by_deliveries_count_highest_first(self):
        order1 = self._delivered_order(self.seller_a, self.product_a, 1, '100.00')
        order2 = self._delivered_order(self.seller_a, self.product_a, 1, '100.00')
        order3 = self._delivered_order(self.seller_a, self.product_a, 1, '100.00')
        self._delivered_assignment(self.rider_a, order1)
        self._delivered_assignment(self.rider_a, order2)
        self._delivered_assignment(self.rider_b, order3)
        self.client.force_authenticate(self.staff)
        riders = self.client.get('/api/staff/analytics/').json()['top_riders']
        self.assertEqual(riders[0]['name'], 'Rider A')
        self.assertEqual(riders[0]['deliveries_count'], 2)
        self.assertEqual(riders[1]['name'], 'Rider B')
        self.assertEqual(riders[1]['deliveries_count'], 1)

    def test_top_riders_includes_completed_payout_earnings(self):
        order = self._delivered_order(self.seller_a, self.product_a, 1, '100.00')
        assignment = self._delivered_assignment(self.rider_a, order)
        Transaction.objects.create(
            order=order, transaction_type='payout', amount=Decimal('45.00'),
            provider='MTN_MOMO_ZMB', payer_number='+260970000000',
            recipient=self.rider_a, recipient_role='delivery', status='completed',
        )
        # A pending payout to the same rider must not count yet.
        Transaction.objects.create(
            order=order, transaction_type='payout', amount=Decimal('999.00'),
            provider='MTN_MOMO_ZMB', payer_number='+260970000000',
            recipient=self.rider_a, recipient_role='delivery', status='pending',
        )
        self.client.force_authenticate(self.staff)
        riders = self.client.get('/api/staff/analytics/').json()['top_riders']
        self.assertEqual(riders[0]['rider_id'], self.rider_a.id)
        self.assertEqual(riders[0]['earnings'], '45.00')

    def test_cancelled_deliveries_do_not_count_for_riders(self):
        order = self._delivered_order(self.seller_a, self.product_a, 1, '100.00')
        DeliveryAssignment.objects.create(
            order=order, delivery_person=self.rider_a, status='cancelled',
            estimated_distance=5.0, estimated_duration=15,
        )
        self.client.force_authenticate(self.staff)
        riders = self.client.get('/api/staff/analytics/').json()['top_riders']
        self.assertEqual(riders, [])

    def test_rider_days_filter_excludes_deliveries_outside_the_window(self):
        old = timezone.now() - timezone.timedelta(days=60)
        order = self._delivered_order(self.seller_a, self.product_a, 1, '100.00')
        self._delivered_assignment(self.rider_a, order, delivered_at=old)
        self.client.force_authenticate(self.staff)
        data = self.client.get('/api/staff/analytics/?days=30').json()
        self.assertEqual(data['top_riders'], [])
        data_all = self.client.get('/api/staff/analytics/?days=365').json()
        self.assertEqual(len(data_all['top_riders']), 1)
