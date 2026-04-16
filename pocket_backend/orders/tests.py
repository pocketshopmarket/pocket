from rest_framework import status
from rest_framework.test import APITestCase

from accounts.models import SellerProfile, User
from products.models import Product


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
