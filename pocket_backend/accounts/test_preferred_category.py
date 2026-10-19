from rest_framework.test import APITestCase

from accounts.models import BuyerProfile, PhoneOTP, User
from products.models import Category, Product


class SignupPreferredCategoryTests(APITestCase):
    def _verify_otp(self, phone, **extra):
        PhoneOTP.objects.create(phone_number=phone, otp_code='123456', is_verified=False)
        data = {
            'phone_number': phone,
            'otp_code': '123456',
            'role': 'buyer',
            'password': 'testpass123',
            'full_name': 'Test Buyer',
        }
        data.update(extra)
        return self.client.post('/api/auth/verify-otp/', data, format='json')

    def setUp(self):
        self.groceries = Category.objects.create(name='Groceries', slug='groceries-pref-test')

    def test_signup_sets_the_chosen_preferred_category(self):
        resp = self._verify_otp('+260970000090', preferred_category=self.groceries.id)
        self.assertEqual(resp.status_code, 201, resp.content)
        profile = BuyerProfile.objects.get(user__phone_number='+260970000090')
        self.assertEqual(profile.preferred_category_id, self.groceries.id)

    def test_signup_without_a_choice_leaves_it_unset(self):
        resp = self._verify_otp('+260970000091')
        self.assertEqual(resp.status_code, 201, resp.content)
        profile = BuyerProfile.objects.get(user__phone_number='+260970000091')
        self.assertIsNone(profile.preferred_category_id)


class ProfilePreferredCategoryTests(APITestCase):
    def setUp(self):
        self.groceries = Category.objects.create(name='Groceries', slug='groceries-profile-test')
        self.electronics = Category.objects.create(name='Electronics', slug='electronics-profile-test')
        self.buyer = User.objects.create_user(
            phone_number='+260970000092', password='x', full_name='Buyer', role='buyer')
        BuyerProfile.objects.create(user=self.buyer, preferred_category=self.groceries)
        self.client.force_authenticate(self.buyer)

    def test_buyer_can_change_their_preferred_category(self):
        r = self.client.put('/api/auth/profile/', {'preferred_category': self.electronics.id}, format='json')
        self.assertEqual(r.status_code, 200, r.content)
        self.buyer.buyer_profile.refresh_from_db()
        self.assertEqual(self.buyer.buyer_profile.preferred_category_id, self.electronics.id)

    def test_buyer_can_clear_their_preferred_category(self):
        r = self.client.put('/api/auth/profile/', {'preferred_category': None}, format='json')
        self.assertEqual(r.status_code, 200, r.content)
        self.buyer.buyer_profile.refresh_from_db()
        self.assertIsNone(self.buyer.buyer_profile.preferred_category_id)

    def test_profile_response_includes_the_category_name(self):
        r = self.client.get('/api/auth/profile/')
        self.assertEqual(r.json()['data']['profile']['preferred_category_name'], 'Groceries')


class ShopListCategoryFilterTests(APITestCase):
    def setUp(self):
        self.groceries = Category.objects.create(name='Groceries', slug='groceries-shop-test')
        self.liquor = Category.objects.create(
            name='Liquor', slug='liquor-shop-test', parent=self.groceries)
        self.electronics = Category.objects.create(name='Electronics', slug='electronics-shop-test')

        self.grocer = User.objects.create_user(
            phone_number='+260970000093', password='x', full_name='Grocer', role='seller')
        from accounts.models import SellerProfile
        SellerProfile.objects.create(
            user=self.grocer, shop_name='Fresh Mart', shop_location='Lusaka', is_approved=True)
        Product.objects.create(
            name='Milk', description='d', price=20, seller=self.grocer,
            stock_quantity=5, category=self.liquor, is_available=True,
        )

        self.techie = User.objects.create_user(
            phone_number='+260970000094', password='x', full_name='Techie', role='seller')
        SellerProfile.objects.create(
            user=self.techie, shop_name='Gadget World', shop_location='Lusaka', is_approved=True)
        Product.objects.create(
            name='Phone', description='d', price=2000, seller=self.techie,
            stock_quantity=5, category=self.electronics, is_available=True,
        )

        # Enough other "real" shops that the cold-start fallback (which shows
        # everything while supply is thin) doesn't mask the category filter.
        for i in range(5):
            seller = User.objects.create_user(
                phone_number=f'+2609700001{i:02d}', password='x', full_name=f'Filler {i}', role='seller')
            SellerProfile.objects.create(
                user=seller, shop_name=f'Filler Shop {i}', shop_location='Lusaka', is_approved=True)
            Product.objects.create(
                name=f'Thing {i}', description='d', price=10, seller=seller,
                stock_quantity=5, category=self.electronics, is_available=True,
            )

    def _names(self, response):
        return [s['shop_name'] for s in response.json()['results']]

    def test_category_filter_matches_via_a_subcategory(self):
        # Fresh Mart's only product is filed under Liquor, a child of Groceries.
        resp = self.client.get(f'/api/auth/shops/?category={self.groceries.id}')
        self.assertIn('Fresh Mart', self._names(resp))
        self.assertNotIn('Gadget World', self._names(resp))

    def test_category_filter_excludes_shops_without_a_matching_product(self):
        resp = self.client.get(f'/api/auth/shops/?category={self.groceries.id}')
        names = self._names(resp)
        for i in range(5):
            self.assertNotIn(f'Filler Shop {i}', names)

    def test_unavailable_products_do_not_count_toward_the_match(self):
        Product.objects.create(
            name='Old stock', description='d', price=5, seller=self.techie,
            stock_quantity=0, category=self.groceries, is_available=False,
        )
        resp = self.client.get(f'/api/auth/shops/?category={self.groceries.id}')
        self.assertNotIn('Gadget World', self._names(resp))

    def test_no_category_param_returns_everything(self):
        resp = self.client.get('/api/auth/shops/')
        names = self._names(resp)
        self.assertIn('Fresh Mart', names)
        self.assertIn('Gadget World', names)
