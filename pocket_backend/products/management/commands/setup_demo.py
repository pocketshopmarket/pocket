"""
One-shot demo setup:
  - Creates seller account (0763887732 / niza2006) + approved SellerProfile
  - Creates delivery account (0973714666 / kate2006) + approved DeliveryProfile
  - Seeds 10 demo products across 5 categories with images
"""

from decimal import Decimal
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
                'image_url': 'https://picsum.photos/seed/nuts/400/400',
            },
            {
                'name': 'Local Honey 250ml',
                'description': 'Pure natural honey from local beekeepers. No additives.',
                'price': Decimal('25.00'),
                'stock': 40,
                'image_url': 'https://picsum.photos/seed/honey/400/400',
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
                'image_url': 'https://picsum.photos/seed/tshirt/400/400',
            },
            {
                'name': 'Beanie Hat',
                'description': 'Warm knitted beanie, perfect for cool evenings.',
                'price': Decimal('18.00'),
                'stock': 35,
                'image_url': 'https://picsum.photos/seed/beanie/400/400',
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
                'image_url': 'https://picsum.photos/seed/cable/400/400',
            },
            {
                'name': 'Phone Stand',
                'description': 'Adjustable aluminium phone desk stand. Foldable and portable.',
                'price': Decimal('22.00'),
                'stock': 45,
                'image_url': 'https://picsum.photos/seed/phonestand/400/400',
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
                'image_url': 'https://picsum.photos/seed/sheabutter/400/400',
            },
            {
                'name': 'Aloe Vera Gel',
                'description': '99% pure aloe vera gel. Soothes skin naturally.',
                'price': Decimal('18.00'),
                'stock': 50,
                'image_url': 'https://picsum.photos/seed/aloevera/400/400',
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
                'image_url': 'https://picsum.photos/seed/spoon/400/400',
            },
            {
                'name': 'Cotton Dish Towels 2pk',
                'description': 'Absorbent cotton kitchen towels. Machine washable.',
                'price': Decimal('14.00'),
                'stock': 90,
                'image_url': 'https://picsum.photos/seed/towels/400/400',
            },
        ],
    },
]


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
                existing = Product.objects.filter(name=p['name'], seller=seller).first()
                if existing:
                    # Always update the image_url in case it changed.
                    existing.image_url = p['image_url']
                    existing.save(update_fields=['image_url', 'updated_at'])
                    self.stdout.write(f"  Updated image: {p['name']}")
                    continue
                self.stdout.write(f"  Creating: {p['name']}")
                Product.objects.create(
                    seller=seller,
                    category=cat,
                    name=p['name'],
                    description=p['description'],
                    price=p['price'],
                    stock_quantity=p['stock'],
                    image_url=p['image_url'],
                    is_available=True,
                )
                count += 1

        self.stdout.write(self.style.SUCCESS(f'Done. {count} products created/updated.'))
