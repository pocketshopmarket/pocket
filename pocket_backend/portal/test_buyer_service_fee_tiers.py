from decimal import Decimal

from rest_framework.test import APITestCase

from accounts.models import User
from products.models import Product

from .models import BuyerServiceFeeTier, PlatformSettings, get_buyer_service_fee_rate


class GetBuyerServiceFeeRateTests(APITestCase):
    """Unit coverage for the pure lookup function — no HTTP involved."""

    def test_no_tiers_configured_falls_back_to_the_flat_rate(self):
        ps = PlatformSettings.get()
        ps.buyer_service_fee_rate = Decimal('0.10')
        ps.save()
        self.assertEqual(get_buyer_service_fee_rate(250), Decimal('0.10'))

    def test_amount_inside_a_tier_uses_that_tiers_rate(self):
        BuyerServiceFeeTier.objects.create(min_order_value=0, max_order_value=100, fee_rate=Decimal('0.10'))
        BuyerServiceFeeTier.objects.create(min_order_value=100.01, max_order_value=500, fee_rate=Decimal('0.07'))
        BuyerServiceFeeTier.objects.create(min_order_value=500.01, max_order_value=None, fee_rate=Decimal('0.05'))

        self.assertEqual(get_buyer_service_fee_rate(50), Decimal('0.10'))
        self.assertEqual(get_buyer_service_fee_rate(250), Decimal('0.07'))
        self.assertEqual(get_buyer_service_fee_rate(10000), Decimal('0.05'))

    def test_boundaries_are_inclusive(self):
        BuyerServiceFeeTier.objects.create(min_order_value=0, max_order_value=100, fee_rate=Decimal('0.10'))
        BuyerServiceFeeTier.objects.create(min_order_value=100.01, max_order_value=None, fee_rate=Decimal('0.05'))

        self.assertEqual(get_buyer_service_fee_rate(100), Decimal('0.10'))      # exact top of tier 1
        self.assertEqual(get_buyer_service_fee_rate(100.01), Decimal('0.05'))  # exact bottom of tier 2

    def test_a_gap_between_tiers_falls_back_to_the_flat_rate(self):
        ps = PlatformSettings.get()
        ps.buyer_service_fee_rate = Decimal('0.09')
        ps.save()
        BuyerServiceFeeTier.objects.create(min_order_value=0, max_order_value=100, fee_rate=Decimal('0.10'))
        BuyerServiceFeeTier.objects.create(min_order_value=500, max_order_value=None, fee_rate=Decimal('0.05'))

        # 250 falls in the gap between the two tiers.
        self.assertEqual(get_buyer_service_fee_rate(250), Decimal('0.09'))

    def test_an_inactive_tier_is_ignored(self):
        ps = PlatformSettings.get()
        ps.buyer_service_fee_rate = Decimal('0.08')
        ps.save()
        BuyerServiceFeeTier.objects.create(
            min_order_value=0, max_order_value=None, fee_rate=Decimal('0.10'), is_active=False,
        )
        self.assertEqual(get_buyer_service_fee_rate(250), Decimal('0.08'))


class CreateOrderUsesTieredFeeTests(APITestCase):
    """Integration coverage: the real checkout endpoint charges the correct tier."""

    def setUp(self):
        self.seller = User.objects.create_user(
            phone_number='+260977000001', password='x', full_name='Seller', role='seller')
        self.buyer = User.objects.create_user(
            phone_number='+260977000002', password='x', full_name='Buyer', role='buyer')
        self.product = Product.objects.create(
            name='Shoes', description='d', price=Decimal('300.00'),
            seller=self.seller, stock_quantity=5,
        )
        BuyerServiceFeeTier.objects.create(min_order_value=0, max_order_value=100, fee_rate=Decimal('0.10'))
        BuyerServiceFeeTier.objects.create(min_order_value=100.01, max_order_value=None, fee_rate=Decimal('0.04'))
        self.client.force_authenticate(self.buyer)

    def test_checkout_charges_the_tier_matching_the_cart_subtotal(self):
        self.client.post('/api/orders/cart/', {'product_id': self.product.id, 'quantity': 1}, format='json')
        meta = '{"fulfillment_type": "pickup"}'
        r = self.client.post('/api/orders/orders/create/', {
            'delivery_address': 'Pickup at store',
            'special_instructions': f'[PS_META]{meta}[/PS_META]',
        }, format='json')
        self.assertEqual(r.status_code, 201, r.content)
        order = r.json()
        # 300.00 total -> the 100.01+ tier (4%), not the flat PlatformSettings rate.
        self.assertEqual(order['service_fee'], '12.00')
