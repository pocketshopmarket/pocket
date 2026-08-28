from unittest.mock import patch

from rest_framework import status
from rest_framework.test import APITestCase

from accounts.models import SellerApiKey, SellerProfile, User
from partner_api.throttles import PartnerAPIThrottle
from products.models import Category, Product


class PartnerProductUpsertApiTests(APITestCase):
    def setUp(self):
        self.category = Category.objects.create(name='Electronics', slug='electronics')

        self.seller = User.objects.create_user(
            phone_number='+260900000010',
            password='testpass123',
            full_name='Approved Seller',
            role='seller',
        )
        SellerProfile.objects.create(
            user=self.seller,
            shop_name='Partner Shop',
            shop_location='Lusaka',
            tier1_status='approved',
            is_approved=True,
        )
        self.raw_key = SellerApiKey.generate_key()
        self.api_key = SellerApiKey.objects.create(
            seller=self.seller,
            label='Test key',
            prefix=self.raw_key[:12],
            hashed_key=SellerApiKey.hash_key(self.raw_key),
        )

    def _auth(self, raw_key=None):
        self.client.credentials(HTTP_AUTHORIZATION=f'Api-Key {raw_key or self.raw_key}')

    def test_create_then_idempotent_update(self):
        self._auth()
        payload = {
            'external_id': 'SKU-001',
            'name': 'Wireless Mouse',
            'price': '149.99',
            'category_slug': 'electronics',
            'stock_quantity': 25,
        }
        response = self.client.post('/api/partner/v1/products/', payload, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(response.data['created'])
        product_id = response.data['id']

        # Second sync for the same external_id updates, does not duplicate.
        payload['stock_quantity'] = 10
        response = self.client.post('/api/partner/v1/products/', payload, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data['created'])
        self.assertEqual(response.data['id'], product_id)
        self.assertEqual(
            Product.objects.filter(seller=self.seller, external_id='SKU-001').count(), 1,
        )
        self.assertEqual(
            Product.objects.get(external_id='SKU-001').stock_quantity, 10,
        )

    def test_unknown_category_slug_rejected(self):
        self._auth()
        payload = {
            'external_id': 'SKU-002',
            'name': 'Gadget',
            'price': '10.00',
            'category_slug': 'not-a-real-category',
        }
        response = self.client.post('/api/partner/v1/products/', payload, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        # The project's global exception handler (accounts.error_logging)
        # wraps DRF's default {field: [...]} validation body into its own
        # envelope, so the field error lives under 'errors', not top-level.
        self.assertIn('category_slug', response.data['errors'])

    def test_revoked_key_rejected(self):
        self.api_key.is_active = False
        self.api_key.save()
        self._auth()
        response = self.client.post(
            '/api/partner/v1/products/',
            {'external_id': 'SKU-003', 'name': 'X', 'price': '1.00'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertFalse(Product.objects.filter(external_id='SKU-003').exists())

    def test_non_approved_seller_rejected_even_with_valid_key(self):
        unapproved_seller = User.objects.create_user(
            phone_number='+260900000011',
            password='testpass123',
            full_name='Unapproved Seller',
            role='seller',
        )
        SellerProfile.objects.create(
            user=unapproved_seller,
            shop_name='Pending Shop',
            shop_location='Lusaka',
        )
        raw = SellerApiKey.generate_key()
        SellerApiKey.objects.create(
            seller=unapproved_seller,
            label='Pending key',
            prefix=raw[:12],
            hashed_key=SellerApiKey.hash_key(raw),
        )
        self._auth(raw_key=raw)
        response = self.client.post(
            '/api/partner/v1/products/',
            {'external_id': 'SKU-004', 'name': 'X', 'price': '1.00'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_invalid_key_rejected(self):
        self._auth(raw_key='psk_not-a-real-key')
        response = self.client.post(
            '/api/partner/v1/products/',
            {'external_id': 'SKU-005', 'name': 'X', 'price': '1.00'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_throttling(self):
        # SimpleRateThrottle.THROTTLE_RATES is bound from api_settings at
        # class-definition (import) time, not re-read per-request, so
        # override_settings on REST_FRAMEWORK doesn't reach it. Patching
        # the throttle class's `rate` directly is DRF's own documented way
        # to test throttle scopes — SimpleRateThrottle.__init__ uses it
        # as-is instead of resolving THROTTLE_RATES[scope] when it's set.
        with patch.object(PartnerAPIThrottle, 'rate', '2/min', create=True):
            self._auth()
            for i in range(2):
                response = self.client.post(
                    '/api/partner/v1/products/',
                    {'external_id': f'SKU-thr-{i}', 'name': 'X', 'price': '1.00'},
                    format='json',
                )
                self.assertEqual(response.status_code, status.HTTP_201_CREATED)
            response = self.client.post(
                '/api/partner/v1/products/',
                {'external_id': 'SKU-thr-over', 'name': 'X', 'price': '1.00'},
                format='json',
            )
            self.assertEqual(response.status_code, status.HTTP_429_TOO_MANY_REQUESTS)
