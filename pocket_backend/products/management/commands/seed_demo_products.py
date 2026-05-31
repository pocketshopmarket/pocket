"""
Management command: seed_demo_products
Creates demo categories and products with images downloaded from the web.
All prices are below ZMW 30. Assigns products to the first approved seller.

Usage:
    python manage.py seed_demo_products
    python manage.py seed_demo_products --seller-id 5
"""

import os
import urllib.request
from decimal import Decimal
from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand
from django.utils.text import slugify

from accounts.models import User, SellerProfile
from products.models import Category, Product


DEMO_DATA = [
    {
        'category': 'Food & Snacks',
        'icon': 'restaurant',
        'products': [
            {
                'name': 'Mixed Nuts Pack',
                'description': 'Roasted mixed nuts — groundnuts, cashews, and almonds. Great snack for any time of day.',
                'price': Decimal('15.00'),
                'stock': 100,
                'image_url': 'https://images.unsplash.com/photo-1599599810769-bcde5a160d32?w=400&q=80',
            },
            {
                'name': 'Local Honey (250ml)',
                'description': 'Pure natural honey sourced from local beekeepers. No additives.',
                'price': Decimal('25.00'),
                'stock': 40,
                'image_url': 'https://images.unsplash.com/photo-1587049352846-4a222e784d38?w=400&q=80',
            },
        ],
    },
    {
        'category': 'Clothing',
        'icon': 'checkroom',
        'products': [
            {
                'name': 'Cotton T-Shirt',
                'description': 'Comfortable plain cotton t-shirt. Available in multiple colours.',
                'price': Decimal('20.00'),
                'stock': 60,
                'image_url': 'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=400&q=80',
            },
            {
                'name': 'Beanie Hat',
                'description': 'Warm knitted beanie hat, perfect for cool evenings.',
                'price': Decimal('18.00'),
                'stock': 35,
                'image_url': 'https://images.unsplash.com/photo-1576871337632-b9aef4c17ab9?w=400&q=80',
            },
        ],
    },
    {
        'category': 'Electronics',
        'icon': 'devices',
        'products': [
            {
                'name': 'USB-C Charging Cable',
                'description': '1.5m braided USB-C cable. Fast charging compatible.',
                'price': Decimal('12.00'),
                'stock': 80,
                'image_url': 'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=400&q=80',
            },
            {
                'name': 'Phone Stand',
                'description': 'Adjustable aluminium phone/tablet desk stand. Foldable and portable.',
                'price': Decimal('22.00'),
                'stock': 45,
                'image_url': 'https://images.unsplash.com/photo-1586953208448-b95a79798f07?w=400&q=80',
            },
        ],
    },
    {
        'category': 'Beauty & Health',
        'icon': 'spa',
        'products': [
            {
                'name': 'Shea Butter (100g)',
                'description': 'Pure unrefined shea butter. Moisturises skin and hair naturally.',
                'price': Decimal('15.00'),
                'stock': 55,
                'image_url': 'https://images.unsplash.com/photo-1608248543803-ba4f8c70ae0b?w=400&q=80',
            },
            {
                'name': 'Aloe Vera Gel',
                'description': '99% pure aloe vera gel. Soothes skin and promotes healing.',
                'price': Decimal('18.00'),
                'stock': 50,
                'image_url': 'https://images.unsplash.com/photo-1596178060810-72c633c3c921?w=400&q=80',
            },
        ],
    },
    {
        'category': 'Home & Kitchen',
        'icon': 'home',
        'products': [
            {
                'name': 'Wooden Serving Spoon',
                'description': 'Handcrafted wooden spoon set. Safe for non-stick cookware.',
                'price': Decimal('10.00'),
                'stock': 70,
                'image_url': 'https://images.unsplash.com/photo-1584990347449-a2d4c2c044b0?w=400&q=80',
            },
            {
                'name': 'Cotton Dish Towels (2 pack)',
                'description': 'Absorbent cotton kitchen towels. Machine washable.',
                'price': Decimal('14.00'),
                'stock': 90,
                'image_url': 'https://images.unsplash.com/photo-1585771724684-38269d6639fd?w=400&q=80',
            },
        ],
    },
]


def _download_image(url, filename):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=15) as resp:
            return ContentFile(resp.read(), name=filename)
    except Exception as e:
        print(f'    Warning: could not download {url}: {e}')
        return None


class Command(BaseCommand):
    help = 'Seed demo categories and products with images'

    def add_arguments(self, parser):
        parser.add_argument('--seller-id', type=int, default=None)

    def handle(self, *args, **options):
        seller_id = options.get('seller_id')

        if seller_id:
            seller = User.objects.get(id=seller_id)
        else:
            profile = SellerProfile.objects.filter(is_approved=True).select_related('user').first()
            if not profile:
                profile = SellerProfile.objects.select_related('user').first()
            if not profile:
                self.stderr.write('No seller found. Create a seller account first.')
                return
            seller = profile.user

        self.stdout.write(f'Seeding products for seller: {seller.full_name} (id={seller.id})')

        created_count = 0
        for group in DEMO_DATA:
            cat_name = group['category']
            cat, _ = Category.objects.get_or_create(
                slug=slugify(cat_name),
                defaults={'name': cat_name, 'icon_name': group['icon']},
            )
            self.stdout.write(f'Category: {cat_name}')

            for p in group['products']:
                if Product.objects.filter(name=p['name'], seller=seller).exists():
                    self.stdout.write(f"  Skipping (exists): {p['name']}")
                    continue

                self.stdout.write(f"  Creating: {p['name']}")
                product = Product(
                    seller=seller,
                    category=cat,
                    name=p['name'],
                    description=p['description'],
                    price=p['price'],
                    stock_quantity=p['stock'],
                    is_available=True,
                )

                img = _download_image(
                    p['image_url'],
                    slugify(p['name']) + '.jpg',
                )
                if img:
                    product.image.save(slugify(p['name']) + '.jpg', img, save=False)

                product.save()
                created_count += 1

        self.stdout.write(self.style.SUCCESS(f'Done. Created {created_count} products.'))
