from rest_framework.test import APITestCase

from accounts.models import SellerProfile, ShopType, User


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
