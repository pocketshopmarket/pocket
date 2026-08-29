import datetime

from rest_framework import status
from rest_framework.test import APITestCase

from accounts.models import SellerProfile, User
from products.models import Category, Product
from .models import Cart, CartItem, Order


class BuyerRoleCheckoutTests(APITestCase):
    def setUp(self):
        self.buyer = User.objects.create_user(
            phone_number='+260911111111',
            password='testpass123',
            full_name='Buyer',
            role='buyer',
        )
        self.seller_user = User.objects.create_user(
            phone_number='+260922222222',
            password='testpass123',
            full_name='Seller',
            role='seller',
        )
        SellerProfile.objects.create(
            user=self.seller_user,
            shop_name='Approved Shop',
            shop_location='Lusaka',
            is_approved=True,
        )
        self.product = Product.objects.create(
            name='Headphones',
            description='Noise cancelling',
            price=350,
            category='electronics',
            seller=self.seller_user,
            stock_quantity=8,
        )

    def test_seller_cannot_access_cart_endpoints(self):
        self.client.force_authenticate(user=self.seller_user)
        response = self.client.get('/api/orders/cart/')
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_buyer_can_checkout(self):
        self.client.force_authenticate(user=self.buyer)
        add_response = self.client.post(
            '/api/orders/cart/',
            {'product_id': self.product.id, 'quantity': 1},
        )
        self.assertEqual(add_response.status_code, status.HTTP_200_OK)

        checkout_response = self.client.post(
            '/api/orders/orders/create/',
            {'delivery_address': 'Town Centre'},
        )
        self.assertEqual(checkout_response.status_code, status.HTTP_201_CREATED)


class AgeRestrictedProductCheckoutTests(APITestCase):
    def setUp(self):
        self.seller_user = User.objects.create_user(
            phone_number='+260933333333',
            password='testpass123',
            full_name='Liquor Seller',
            role='seller',
        )
        SellerProfile.objects.create(
            user=self.seller_user,
            shop_name='Bottle Store',
            shop_location='Lusaka',
            is_approved=True,
        )
        self.restricted_category = Category.objects.create(
            name='Alcohol & Spirits', slug='alcohol-spirits', is_age_restricted=True,
        )
        self.restricted_product = Product.objects.create(
            name='Whisky',
            description='750ml',
            price=250,
            category=self.restricted_category,
            seller=self.seller_user,
            stock_quantity=10,
        )

        today = datetime.date.today()
        self.minor = User.objects.create_user(
            phone_number='+260944444444', password='testpass123',
            full_name='Minor', role='buyer',
            date_of_birth=today.replace(year=today.year - 17),
        )
        self.adult = User.objects.create_user(
            phone_number='+260955555555', password='testpass123',
            full_name='Adult', role='buyer',
            date_of_birth=today.replace(year=today.year - 25),
        )
        self.no_dob = User.objects.create_user(
            phone_number='+260966666666', password='testpass123',
            full_name='No DOB', role='buyer',
        )

    def _authenticate(self, user):
        # force_authenticate() bypasses header-based auth entirely, so it
        # never sets a real Authorization header — meaning every
        # force_authenticate'd request looks identical to the
        # ProductViewSet's vary_on_headers('Authorization') cache
        # partitioning (see products/views.py). Real mobile-app traffic
        # always carries a distinct JWT per user, so this only matters
        # here in tests: set a distinguishing header explicitly so the
        # cache-safety fix is actually exercised, not accidentally
        # bypassed by the test client's shortcut.
        self.client.force_authenticate(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer test-token-{user.id}')

    def test_restricted_product_hidden_from_minor_and_no_dob(self):
        for user in (self.minor, self.no_dob):
            self._authenticate(user)
            response = self.client.get('/api/products/')
            ids = [p['id'] for p in response.data['results']]
            self.assertNotIn(self.restricted_product.id, ids)

    def test_restricted_product_hidden_from_guest(self):
        self.client.credentials()  # no Authorization header at all
        response = self.client.get('/api/products/')
        ids = [p['id'] for p in response.data['results']]
        self.assertNotIn(self.restricted_product.id, ids)

    def test_restricted_product_visible_to_adult(self):
        self._authenticate(self.adult)
        response = self.client.get('/api/products/')
        ids = [p['id'] for p in response.data['results']]
        self.assertIn(self.restricted_product.id, ids)

    def test_add_to_cart_blocked_for_minor_with_known_product_id(self):
        self.client.force_authenticate(user=self.minor)
        response = self.client.post(
            '/api/orders/cart/',
            {'product_id': self.restricted_product.id, 'quantity': 1},
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data['error'], 'You must be 18+ to purchase this item.')
        self.assertFalse(CartItem.objects.filter(product=self.restricted_product).exists())

    def test_checkout_blocked_for_stale_cart_item(self):
        # Simulate a cart item that existed before this feature shipped —
        # bypasses CartView.post() entirely, exercising CreateOrderView's
        # own defense-in-depth check.
        cart, _ = Cart.objects.get_or_create(user=self.minor)
        CartItem.objects.create(cart=cart, product=self.restricted_product, quantity=1)

        self.client.force_authenticate(user=self.minor)
        response = self.client.post(
            '/api/orders/orders/create/',
            {'delivery_address': 'Town Centre'},
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertIn('18+', response.data['error'])
        self.assertFalse(Order.objects.filter(buyer=self.minor).exists())

    def test_adult_can_add_to_cart_and_checkout(self):
        self.client.force_authenticate(user=self.adult)
        add_response = self.client.post(
            '/api/orders/cart/',
            {'product_id': self.restricted_product.id, 'quantity': 1},
        )
        self.assertEqual(add_response.status_code, status.HTTP_200_OK)

        checkout_response = self.client.post(
            '/api/orders/orders/create/',
            {'delivery_address': 'Town Centre'},
        )
        self.assertEqual(checkout_response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(Order.objects.filter(buyer=self.adult).exists())

    def test_no_dob_buyer_unlocked_after_setting_dob(self):
        self.client.force_authenticate(user=self.no_dob)
        blocked = self.client.post(
            '/api/orders/cart/',
            {'product_id': self.restricted_product.id, 'quantity': 1},
        )
        self.assertEqual(blocked.status_code, status.HTTP_403_FORBIDDEN)

        today = datetime.date.today()
        self.no_dob.date_of_birth = today.replace(year=today.year - 20)
        self.no_dob.save(update_fields=['date_of_birth'])

        allowed = self.client.post(
            '/api/orders/cart/',
            {'product_id': self.restricted_product.id, 'quantity': 1},
        )
        self.assertEqual(allowed.status_code, status.HTTP_200_OK)
