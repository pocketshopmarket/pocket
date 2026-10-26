from rest_framework.test import APITestCase

from accounts.models import SellerProfile, ShopType, User
from products.models import Category, Product


def _seller(phone, shop_name, shop_type=None):
    user = User.objects.create_user(phone_number=phone, password='x', full_name=shop_name, role='seller')
    SellerProfile.objects.create(
        user=user, shop_name=shop_name, shop_location='Lusaka', is_approved=True, shop_type=shop_type,
    )
    return user


class ShopTypeListViewTests(APITestCase):
    def test_only_active_types_are_returned(self):
        ShopType.objects.create(name='Pharmacy Test', is_active=True)
        ShopType.objects.create(name='Retired Type Test', is_active=False)
        r = self.client.get('/api/auth/shop-types/')
        self.assertEqual(r.status_code, 200)
        names = [t['name'] for t in r.json()]
        self.assertIn('Pharmacy Test', names)
        self.assertNotIn('Retired Type Test', names)

    def test_guest_can_list_shop_types_no_auth_required(self):
        ShopType.objects.create(name='Supermarket Test')
        r = self.client.get('/api/auth/shop-types/')
        self.assertEqual(r.status_code, 200)


class ShopListShopTypeFilterTests(APITestCase):
    def setUp(self):
        self.pharmacy = ShopType.objects.create(name='Pharmacy Test')
        self.electronics = ShopType.objects.create(name='Electronics Store Test')
        self.grocer = _seller('+260970000300', 'Fresh Mart', shop_type=self.pharmacy)
        self.techie = _seller('+260970000301', 'Gadget World', shop_type=self.electronics)
        self.untyped = _seller('+260970000302', 'No Type Yet', shop_type=None)
        # Enough filler shops that the cold-start "show everything" fallback
        # doesn't mask the filter.
        for i in range(5):
            _seller(f'+2609700013{i:02d}', f'Filler Shop {i}')

    def _names(self, response):
        return [s['shop_name'] for s in response.json()['results']]

    def test_shop_type_filter_matches_only_that_type(self):
        resp = self.client.get(f'/api/auth/shops/?shop_type={self.pharmacy.id}')
        names = self._names(resp)
        self.assertIn('Fresh Mart', names)
        self.assertNotIn('Gadget World', names)
        self.assertNotIn('No Type Yet', names)

    def test_no_shop_type_param_returns_everything(self):
        resp = self.client.get('/api/auth/shops/')
        names = self._names(resp)
        self.assertIn('Fresh Mart', names)
        self.assertIn('Gadget World', names)
        self.assertIn('No Type Yet', names)

    def test_shop_type_name_is_exposed_on_the_shop(self):
        resp = self.client.get(f'/api/auth/shops/?shop_type={self.pharmacy.id}')
        shop = resp.json()['results'][0]
        self.assertEqual(shop['shop_type'], 'Pharmacy Test')

    def test_untyped_shop_exposes_null_shop_type(self):
        resp = self.client.get('/api/auth/shops/')
        by_name = {s['shop_name']: s for s in resp.json()['results']}
        self.assertIsNone(by_name['No Type Yet']['shop_type'])


class TopCategoryFallbackTests(APITestCase):
    """
    top_category is the fallback badge for a shop with no staff-assigned
    ShopType yet. A shop with only a couple of products commonly has a tied
    count across categories — this must resolve the same way every time,
    not flip depending on insertion order (the original bug report: the
    badge appeared to change to match whichever product was added last).
    """

    def setUp(self):
        self.category_a = Category.objects.create(name='Electronics', slug='electronics-topcat-test')
        self.category_b = Category.objects.create(name='Groceries', slug='groceries-topcat-test')
        self.seller = _seller('+260970000310', 'Tied Shop')
        Product.objects.create(
            name='Phone', description='d', price=10, seller=self.seller,
            stock_quantity=5, category=self.category_b, is_available=True,
        )
        Product.objects.create(
            name='Milk', description='d', price=10, seller=self.seller,
            stock_quantity=5, category=self.category_a, is_available=True,
        )

    def test_a_tie_resolves_the_same_way_every_time(self):
        first = self.client.get('/api/auth/shops/').json()['results'][0]['top_category']
        for _ in range(5):
            again = self.client.get('/api/auth/shops/').json()['results'][0]['top_category']
            self.assertEqual(again, first)

    def test_a_tie_is_broken_by_category_id_not_insertion_order(self):
        # category_a has the lower id, so it should win the tie even though
        # category_b's product was added to the shop first.
        resp = self.client.get('/api/auth/shops/')
        self.assertEqual(resp.json()['results'][0]['top_category'], self.category_a.name)
