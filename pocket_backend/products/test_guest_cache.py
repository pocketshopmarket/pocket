from rest_framework.test import APITestCase

from accounts.models import User

from .models import Category, Product


class ProductListGuestCacheTests(APITestCase):
    """
    Regression coverage for a real bug: the product list used to cache by
    Authorization header, but a buyer's token doesn't change when their
    profile does, so after using the date-of-birth nudge they'd keep seeing
    a stale, restricted-content-hidden response for up to 30 seconds. The
    fix only caches for guests, who can never trigger that (no account to
    update) and must never see a logged-in buyer's unlocked content either.
    """

    def setUp(self):
        self.liq = Category.objects.create(name='Liq', slug='liq-cache-test', is_age_restricted=True)
        seller = User.objects.create_user(
            phone_number='+260900000060', password='x', full_name='Seller', role='seller')
        Product.objects.create(
            name='Beer', description='d', price=5, seller=seller, stock_quantity=3, category=self.liq)
        self.buyer = User.objects.create_user(
            phone_number='+260900000061', password='x', full_name='Buyer', role='buyer')

    def _names(self, response):
        return [p['name'] for p in response.json()['results']]

    def test_a_buyer_sees_the_result_of_their_own_profile_update_immediately(self):
        self.client.force_authenticate(self.buyer)
        before = self.client.get('/api/products/?category=liq-cache-test')
        self.assertEqual(self._names(before), [])

        self.client.put('/api/auth/profile/', {'date_of_birth': '1990-01-01'}, format='json')
        self.buyer.refresh_from_db()
        self.client.force_authenticate(self.buyer)  # a real request re-reads the user fresh too

        after = self.client.get('/api/products/?category=liq-cache-test')
        self.assertEqual(self._names(after), ['Beer'])

    def test_a_buyers_unlocked_view_never_leaks_into_the_guest_cache(self):
        guest_before = self.client.get('/api/products/?category=liq-cache-test')
        self.assertEqual(self._names(guest_before), [])

        self.client.force_authenticate(self.buyer)
        self.client.put('/api/auth/profile/', {'date_of_birth': '1990-01-01'}, format='json')
        self.buyer.refresh_from_db()
        self.client.force_authenticate(self.buyer)
        self.client.get('/api/products/?category=liq-cache-test')  # buyer now sees it

        self.client.force_authenticate(user=None)
        guest_after = self.client.get('/api/products/?category=liq-cache-test')
        self.assertEqual(self._names(guest_after), [])

    def test_guest_results_are_still_cached(self):
        from django.core.cache import cache
        cache.clear()
        first = self.client.get('/api/products/?category=liq-cache-test')
        key = f'guest_product_cache:{first.wsgi_request.get_full_path()}'
        self.assertIsNotNone(cache.get(key))
