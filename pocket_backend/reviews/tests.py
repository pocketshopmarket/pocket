from rest_framework import status
from rest_framework.test import APITestCase

from accounts.models import SellerProfile, User
from orders.models import Order, OrderItem
from products.models import Product


class ProductReviewTests(APITestCase):
    def setUp(self):
        self.buyer = User.objects.create_user(
            phone_number='+260933333333',
            password='testpass123',
            full_name='Buyer',
            role='buyer',
        )
        self.seller = User.objects.create_user(
            phone_number='+260944444444',
            password='testpass123',
            full_name='Seller',
            role='seller',
        )
        SellerProfile.objects.create(
            user=self.seller,
            shop_name='Store',
            shop_location='Lusaka',
            is_approved=True,
        )
        self.product = Product.objects.create(
            name='Router',
            description='WiFi router',
            price=500,
            seller=self.seller,
            stock_quantity=3,
        )
        self.order = Order.objects.create(
            buyer=self.buyer,
            seller=self.seller,
            total_price=500,
            status='delivered',
            delivery_address='Test',
            payment_provider_snapshot='disabled',
            payment_account_snapshot='disabled',
        )
        OrderItem.objects.create(
            order=self.order,
            product=self.product,
            quantity=1,
            price=500,
        )

    def test_review_create_marks_verified_purchase(self):
        self.client.force_authenticate(user=self.buyer)
        response = self.client.post(
            f'/api/reviews/products/{self.product.id}/',
            {'rating': 5, 'comment': 'Great'},
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(response.data['is_verified_purchase'])
