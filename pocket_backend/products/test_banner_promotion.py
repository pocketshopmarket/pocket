from decimal import Decimal

from django.core.exceptions import ValidationError
from django.test import override_settings
from rest_framework.test import APITestCase

from accounts.models import SellerProfile, User
from portal.models import PlatformSettings

from .models import Category, PromoBanner, Product


def _approved_seller(phone='+260970000200'):
    seller = User.objects.create_user(phone_number=phone, password='x', full_name='Seller', role='seller')
    SellerProfile.objects.create(user=seller, shop_name='Shop', shop_location='Lusaka', is_approved=True)
    return seller


class SellerBannerRequestTests(APITestCase):
    def setUp(self):
        ps = PlatformSettings.get()
        ps.banner_slot_enabled = True
        ps.banner_slot_price_per_day = Decimal('50.00')
        ps.save()
        self.seller = _approved_seller()
        self.client.force_authenticate(self.seller)

    def test_approved_seller_can_request_a_banner(self):
        r = self.client.post('/api/products/banners/request/', {
            'title': 'Big Sale', 'duration_days': 7,
        }, format='json')
        self.assertEqual(r.status_code, 201, r.content)
        data = r.json()
        self.assertEqual(data['status'], 'pending_payment')
        self.assertEqual(data['price_paid'], '350.00')  # 50 * 7

        banner = PromoBanner.objects.get(id=data['id'])
        self.assertEqual(banner.seller_id, self.seller.id)
        self.assertEqual(banner.action_type, 'shop')
        self.assertEqual(banner.action_value, str(self.seller.id))
        self.assertFalse(banner.is_active)

    def test_unapproved_seller_cannot_request_a_banner(self):
        unapproved = User.objects.create_user(
            phone_number='+260970000201', password='x', full_name='New Seller', role='seller')
        SellerProfile.objects.create(user=unapproved, shop_name='New Shop', shop_location='Lusaka')
        self.client.force_authenticate(unapproved)
        r = self.client.post('/api/products/banners/request/', {
            'title': 'Big Sale', 'duration_days': 7,
        }, format='json')
        self.assertEqual(r.status_code, 403)

    def test_buyer_cannot_request_a_banner(self):
        buyer = User.objects.create_user(phone_number='+260970000202', password='x', full_name='Buyer', role='buyer')
        self.client.force_authenticate(buyer)
        r = self.client.post('/api/products/banners/request/', {
            'title': 'Big Sale', 'duration_days': 7,
        }, format='json')
        self.assertEqual(r.status_code, 403)

    def test_disabled_feature_blocks_requests(self):
        ps = PlatformSettings.get()
        ps.banner_slot_enabled = False
        ps.save()
        r = self.client.post('/api/products/banners/request/', {
            'title': 'Big Sale', 'duration_days': 7,
        }, format='json')
        self.assertEqual(r.status_code, 503)

    def test_seller_can_see_their_own_banner_history(self):
        self.client.post('/api/products/banners/request/', {'title': 'A', 'duration_days': 1}, format='json')
        self.client.post('/api/products/banners/request/', {'title': 'B', 'duration_days': 2}, format='json')
        r = self.client.get('/api/products/banners/mine/')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(r.json()), 2)

    def test_a_sellers_banner_history_never_shows_another_sellers(self):
        self.client.post('/api/products/banners/request/', {'title': 'Mine', 'duration_days': 1}, format='json')
        other = _approved_seller('+260970000203')
        self.client.force_authenticate(other)
        r = self.client.get('/api/products/banners/mine/')
        self.assertEqual(r.json(), [])


class PromoBannerModelValidationTests(APITestCase):
    def setUp(self):
        self.category = Category.objects.create(name='Groceries', slug='groceries-banner-test')
        self.seller = _approved_seller('+260970000204')
        self.product = Product.objects.create(
            name='Milk', description='d', price=20, seller=self.seller,
            stock_quantity=5, category=self.category,
        )

    def test_shop_action_requires_a_real_seller_id(self):
        banner = PromoBanner(title='x', action_type='shop', action_value='999999')
        with self.assertRaises(ValidationError):
            banner.full_clean()

    def test_shop_action_accepts_a_real_seller_id(self):
        banner = PromoBanner(title='x', action_type='shop', action_value=str(self.seller.id))
        banner.full_clean()  # should not raise

    def test_category_action_rejects_a_nonexistent_category(self):
        banner = PromoBanner(title='x', action_type='category', action_value='999999')
        with self.assertRaises(ValidationError):
            banner.full_clean()

    def test_product_action_rejects_a_nonexistent_product(self):
        banner = PromoBanner(title='x', action_type='product', action_value='999999')
        with self.assertRaises(ValidationError):
            banner.full_clean()

    def test_product_action_accepts_a_real_product_id(self):
        banner = PromoBanner(title='x', action_type='product', action_value=str(self.product.id))
        banner.full_clean()

    def test_non_numeric_action_value_is_rejected(self):
        banner = PromoBanner(title='x', action_type='shop', action_value='not-a-number')
        with self.assertRaises(ValidationError):
            banner.full_clean()


class PublicBannerFeedTests(APITestCase):
    def setUp(self):
        # PromoBannerListView caches its response for 60s keyed by path —
        # every test here hits the exact same URL, so without clearing,
        # whichever test runs first "wins" the cache for the rest.
        from django.core.cache import cache
        cache.clear()

    def test_only_active_banners_are_returned(self):
        PromoBanner.objects.create(title='Active', is_active=True, priority=1)
        PromoBanner.objects.create(title='Inactive', is_active=False, priority=5)
        r = self.client.get('/api/products/banners/')
        titles = [b['title'] for b in r.json()]
        self.assertIn('Active', titles)
        self.assertNotIn('Inactive', titles)

    def test_higher_priority_shows_first(self):
        PromoBanner.objects.create(title='Low', is_active=True, priority=1)
        PromoBanner.objects.create(title='High', is_active=True, priority=10)
        r = self.client.get('/api/products/banners/')
        titles = [b['title'] for b in r.json()]
        self.assertEqual(titles.index('High') < titles.index('Low'), True)

    def test_seller_paid_banner_is_flagged_sponsored_admin_banner_is_not(self):
        seller = _approved_seller('+260970000205')
        PromoBanner.objects.create(title='Organic', is_active=True)
        PromoBanner.objects.create(title='Paid', is_active=True, seller=seller, status='active')
        r = self.client.get('/api/products/banners/')
        by_title = {b['title']: b for b in r.json()}
        self.assertFalse(by_title['Organic']['is_sponsored'])
        self.assertTrue(by_title['Paid']['is_sponsored'])
