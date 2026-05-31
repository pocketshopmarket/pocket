"""
One-shot demo setup:
  - Creates seller account (0763887732 / niza2006) + approved SellerProfile
  - Creates delivery account (0973714666 / kate2006) + approved DeliveryProfile
  - Seeds 10 demo products across 5 categories with images
"""

import urllib.request
from decimal import Decimal
from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand
from django.utils import timezone
from django.utils.text import slugify

from accounts.models import User, SellerProfile, DeliveryProfile
from products.models import Category, Product


DEMO_PRODUCTS = [
    {
        'category': 'Food & Snacks',
        'icon': 'restaurant',
        'products': [
            {
                'name': 'Mixed Nuts Pack',
                'description': 'Roasted mixed nuts — groundnuts, cashews, and almonds.',
                'price': Decimal('15.00'),
                'stock': 100,
                'image_url': 'https://images.unsplash.com/photo-1599599810769-bcde5a160d32?w=400&q=80',
            },
            {
                'name': 'Local Honey 250ml',
                'description': 'Pure natural honey from local beekeepers. No additives.',
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
                'description': 'Warm knitted beanie, perfect for cool evenings.',
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
                'description': 'Adjustable aluminium phone desk stand. Foldable and portable.',
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
                'name': 'Shea Butter 100g',
                'description': 'Pure unrefined shea butter. Moisturises skin and hair.',
                'price': Decimal('15.00'),
                'stock': 55,
                'image_url': 'https://images.unsplash.com/photo-1608248543803-ba4f8c70ae0b?w=400&q=80',
            },
            {
                'name': 'Aloe Vera Gel',
                'description': '99% pure aloe vera gel. Soothes skin naturally.',
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
                'name': 'Cotton Dish Towels 2pk',
                'description': 'Absorbent cotton kitchen towels. Machine washable.',
                'price': Decimal('14.00'),
                'stock': 90,
                'image_url': 'https://images.unsplash.com/photo-1585771724684-38269d6639fd?w=400&q=80',
            },
        ],
    },
]


def _download(url, filename):
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=15) as r:
            return ContentFile(r.read(), name=filename)
    except Exception as e:
        print(f'    Image download failed: {e}')
        return None


def _normalize(phone):
    phone = phone.strip().replace(' ', '')
    if phone.startswith('0'):
        phone = '+260' + phone[1:]
    return phone


class Command(BaseCommand):
    help = 'Create demo seller/rider accounts and seed products'

    def handle(self, *args, **options):
        now = timezone.now()

        # ── Seller ───────────────────────────────────────────────────────────
        self.stdout.write('Creating seller account...')
        seller_phone = _normalize('0763887732')
        seller, created = User.objects.get_or_create(
            phone_number=seller_phone,
            defaults={
                'full_name': 'Niza Store',
                'role': 'seller',
                'is_active': True,
                'is_phone_verified': True,
            },
        )
        seller.set_password('niza2006')
        seller.is_phone_verified = True
        seller.save()

        profile, _ = SellerProfile.objects.get_or_create(
            user=seller,
            defaults={
                'shop_name': 'Niza Store',
                'shop_location': 'Lusaka, Zambia',
                'tier1_status': 'approved',
                'is_approved': True,
                'approval_date': now,
            },
        )
        if not profile.is_approved:
            profile.tier1_status = 'approved'
            profile.is_approved = True
            profile.approval_date = now
            profile.save()

        action = 'Created' if created else 'Updated'
        self.stdout.write(self.style.SUCCESS(f'  {action} seller: {seller_phone}'))

        # ── Rider ────────────────────────────────────────────────────────────
        self.stdout.write('Creating delivery account...')
        rider_phone = _normalize('0973714666')
        rider, created = User.objects.get_or_create(
            phone_number=rider_phone,
            defaults={
                'full_name': 'Kate Rider',
                'role': 'delivery',
                'is_active': True,
                'is_phone_verified': True,
            },
        )
        rider.set_password('kate2006')
        rider.is_phone_verified = True
        rider.save()

        dp, _ = DeliveryProfile.objects.get_or_create(
            user=rider,
            defaults={
                'vehicle_type': 'motorcycle',
                'license_number': 'ZM-DEMO-001',
                'province': 'Lusaka',
                'town': 'Lusaka',
                'area': 'Woodlands',
                'verification_status': 'approved',
                'is_approved': True,
                'is_available': True,
            },
        )
        if not dp.is_approved:
            dp.verification_status = 'approved'
            dp.is_approved = True
            dp.save()

        action = 'Created' if created else 'Updated'
        self.stdout.write(self.style.SUCCESS(f'  {action} rider: {rider_phone}'))

        # ── Products ─────────────────────────────────────────────────────────
        self.stdout.write('Seeding products...')
        count = 0
        for group in DEMO_PRODUCTS:
            cat, _ = Category.objects.get_or_create(
                slug=slugify(group['category']),
                defaults={'name': group['category'], 'icon_name': group['icon']},
            )
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
                img = _download(p['image_url'], slugify(p['name']) + '.jpg')
                if img:
                    product.image.save(slugify(p['name']) + '.jpg', img, save=False)
                product.save()
                count += 1

        self.stdout.write(self.style.SUCCESS(f'Done. {count} products created.'))
