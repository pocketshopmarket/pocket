from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from accounts.models import SellerProfile, User
from products.models import Product


class ProductCatalogApiTests(APITestCase):
    def setUp(self):
        self.buyer = User.objects.create_user(
            phone_number='+260900000001',
            password='testpass123',
            full_name='Buyer One',
            role='buyer',
        )
        self.seller = User.objects.create_user(
            phone_number='+260900000002',
            password='testpass123',
            full_name='Seller One',
            role='seller',
        )
        SellerProfile.objects.create(
            user=self.seller,
            shop_name='Tech Hub',
            shop_location='Lusaka',
            is_approved=True,
        )
        Product.objects.create(
            name='Phone X',
            description='Smart phone',
            price=1000,
            category='electronics',
            seller=self.seller,
            stock_quantity=5,
        )
        Product.objects.create(
            name='Book Y',
            description='Novel',
            price=80,
            category='books',
            seller=self.seller,
            stock_quantity=12,
        )

    def test_buyer_can_filter_search_and_paginate(self):
        self.client.force_authenticate(user=self.buyer)
        response = self.client.get(
            '/api/products/',
            {
                'search': 'phone',
                'category': 'electronics',
                'ordering': '-created_at',
                'page_size': 1,
            },
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['count'], 1)
        self.assertEqual(len(response.data['results']), 1)
        self.assertEqual(response.data['results'][0]['name'], 'Phone X')
