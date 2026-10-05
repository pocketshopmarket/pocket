from rest_framework.test import APITestCase

from accounts.models import PhoneOTP, User
from products.models import Category, Product


class SignupAlcoholPreferenceTests(APITestCase):
    """
    An 18+ buyer is asked at signup whether they want alcohol products in
    their listings. Defaults to True (shown) so leaving the question
    unanswered never surprises an existing/legacy buyer who gets no field
    at all — see accounts.models.User.show_alcohol_products.
    """

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

    def test_signup_stores_an_explicit_opt_out(self):
        resp = self._verify_otp(
            '+260970000070',
            date_of_birth='1990-01-01',
            show_alcohol_products=False,
        )
        self.assertEqual(resp.status_code, 201, resp.content)
        user = User.objects.get(phone_number='+260970000070')
        self.assertFalse(user.show_alcohol_products)

    def test_signup_stores_an_explicit_opt_in(self):
        resp = self._verify_otp(
            '+260970000071',
            date_of_birth='1990-01-01',
            show_alcohol_products=True,
        )
        self.assertEqual(resp.status_code, 201, resp.content)
        user = User.objects.get(phone_number='+260970000071')
        self.assertTrue(user.show_alcohol_products)

    def test_signup_without_the_field_defaults_to_true(self):
        resp = self._verify_otp('+260970000072', date_of_birth='1990-01-01')
        self.assertEqual(resp.status_code, 201, resp.content)
        user = User.objects.get(phone_number='+260970000072')
        self.assertTrue(user.show_alcohol_products)

    def test_under_18_signup_ignores_the_field(self):
        # Flutter never shows the question under 18, but even if a client
        # sends it anyway, is_adult=False already excludes alcohol
        # regardless of this preference.
        import datetime
        sixteen_years_ago = (
            datetime.date.today().replace(year=datetime.date.today().year - 16)
        )
        resp = self._verify_otp(
            '+260970000073',
            date_of_birth=sixteen_years_ago.isoformat(),
            show_alcohol_products=True,
        )
        self.assertEqual(resp.status_code, 201, resp.content)
        user = User.objects.get(phone_number='+260970000073')
        self.assertFalse(user.is_adult)


class AlcoholPreferenceFilteringTests(APITestCase):
    def setUp(self):
        self.liq = Category.objects.create(
            name='Liquor', slug='liquor-pref-test', is_age_restricted=True)
        seller = User.objects.create_user(
            phone_number='+260970000080', password='x', full_name='Seller', role='seller')
        Product.objects.create(
            name='Beer', description='d', price=5, seller=seller, stock_quantity=3, category=self.liq)
        self.buyer = User.objects.create_user(
            phone_number='+260970000081', password='x', full_name='Buyer', role='buyer',
            date_of_birth='1990-01-01',
        )
        # date_of_birth assigned on a freshly-constructed instance stays a raw
        # string until reloaded — is_adult would silently read as False
        # (getattr's default swallows the AttributeError from str.year).
        self.buyer.refresh_from_db()

    def _names(self, response):
        return [p['name'] for p in response.json()['results']]

    def test_adult_buyer_sees_alcohol_by_default(self):
        self.client.force_authenticate(self.buyer)
        resp = self.client.get('/api/products/?category=liquor-pref-test')
        self.assertEqual(self._names(resp), ['Beer'])

    def test_adult_buyer_who_opts_out_does_not_see_alcohol(self):
        self.buyer.show_alcohol_products = False
        self.buyer.save()
        self.client.force_authenticate(self.buyer)
        resp = self.client.get('/api/products/?category=liquor-pref-test')
        self.assertEqual(self._names(resp), [])

    def test_opting_back_in_restores_visibility(self):
        self.buyer.show_alcohol_products = False
        self.buyer.save()
        self.client.force_authenticate(self.buyer)
        self.client.put('/api/auth/profile/', {'show_alcohol_products': True}, format='json')
        self.buyer.refresh_from_db()
        self.assertTrue(self.buyer.show_alcohol_products)
        self.client.force_authenticate(self.buyer)
        resp = self.client.get('/api/products/?category=liquor-pref-test')
        self.assertEqual(self._names(resp), ['Beer'])

    def test_opt_out_preference_cannot_unblock_an_underage_buyer(self):
        underage = User.objects.create_user(
            phone_number='+260970000082', password='x', full_name='Teen', role='buyer',
            show_alcohol_products=True,
        )
        self.client.force_authenticate(underage)
        resp = self.client.get('/api/products/?category=liquor-pref-test')
        self.assertEqual(self._names(resp), [])
