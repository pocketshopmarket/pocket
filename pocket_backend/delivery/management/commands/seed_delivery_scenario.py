"""
Management command: seed_delivery_scenario

Sets up a complete, ready-to-test delivery scenario:
  1. Approves the rider account (+260973714666)
  2. Ensures the seller shop has Lusaka GPS coordinates
  3. Cancels any stale active assignment for the rider
  4. Creates a fresh order in out_for_delivery status
  5. Creates a DeliveryOffer for the rider

Usage:
    python manage.py seed_delivery_scenario
    python manage.py seed_delivery_scenario --reset   (also cancels any existing active assignment)
"""

from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from accounts.models import DeliveryProfile, SellerProfile, User
from delivery.models import DeliveryAssignment, DeliveryOffer
from orders.models import Order, OrderItem
from products.models import Product


# Lusaka test coordinates
LUSAKA_MARKET_LAT = -15.4167
LUSAKA_MARKET_LNG = 28.2833
BUYER_DROP_LAT = -15.4250
BUYER_DROP_LNG = 28.2900

RIDER_PHONE = '+260973714666'
SELLER_PHONE = '+260974086484'
BUYER_PHONE = '+260763887732'


class Command(BaseCommand):
    help = 'Seed a ready-to-accept delivery scenario for the test rider'

    def add_arguments(self, parser):
        parser.add_argument(
            '--reset',
            action='store_true',
            help='Cancel any existing active assignment for the rider before creating new order',
        )

    def handle(self, *args, **options):
        reset = options['reset']
        lines = []
        with transaction.atomic():
            lines = self._run(reset=reset)
        for line in lines:
            self.stdout.write(line)

    def _run(self, reset=False):
        lines = []

        # ── 1. Get users ────────────────────────────────────────────────────
        try:
            rider = User.objects.get(phone_number=RIDER_PHONE)
        except User.DoesNotExist:
            # Fall back to any delivery-role user
            rider = User.objects.filter(role='delivery').first()
            if not rider:
                return [self.style.ERROR('No delivery rider found. Run seed_test_data first.')]

        try:
            seller = User.objects.get(phone_number=SELLER_PHONE)
        except User.DoesNotExist:
            seller = User.objects.filter(role='seller').first()
            if not seller:
                return [self.style.ERROR('No seller found. Run seed_test_data first.')]

        try:
            buyer = User.objects.get(phone_number=BUYER_PHONE)
        except User.DoesNotExist:
            buyer = User.objects.filter(role='buyer').first()
            if not buyer:
                return [self.style.ERROR('No buyer found. Run seed_test_data first.')]

        lines.append(f'Rider:  {rider.full_name} ({rider.phone_number})')
        lines.append(f'Seller: {seller.full_name} ({seller.phone_number})')
        lines.append(f'Buyer:  {buyer.full_name} ({buyer.phone_number})')

        # ── 2. Approve rider ─────────────────────────────────────────────────
        profile, created = DeliveryProfile.objects.get_or_create(
            user=rider,
            defaults={
                'vehicle_type': 'motorcycle',
                'license_number': 'ZM-TEST-001',
                'province': 'Copperbelt',
                'town': 'Kitwe',
                'area': 'Parklands',
                'is_approved': True,
                'verification_status': 'approved',
                'is_available': True,
            },
        )
        if not created and not profile.is_approved:
            # Use update to bypass image validation in clean()
            DeliveryProfile.objects.filter(pk=profile.pk).update(
                is_approved=True,
                verification_status='approved',
                is_available=True,
            )
            lines.append('Rider profile: approved (updated)')
        else:
            lines.append(f'Rider profile: {"created" if created else "already approved"}')

        # ── 3. Ensure seller has shop GPS coordinates ─────────────────────────
        seller_profile, sp_created = SellerProfile.objects.get_or_create(
            user=seller,
            defaults={
                'shop_name': 'Test Shop Lusaka',
                'shop_location': 'Cairo Road, Lusaka',
                'shop_lat': LUSAKA_MARKET_LAT,
                'shop_lng': LUSAKA_MARKET_LNG,
            },
        )
        if not sp_created and (seller_profile.shop_lat is None or seller_profile.shop_lng is None):
            SellerProfile.objects.filter(pk=seller_profile.pk).update(
                shop_lat=LUSAKA_MARKET_LAT,
                shop_lng=LUSAKA_MARKET_LNG,
                shop_location='Cairo Road, Lusaka',
            )
            lines.append('Seller shop coords: set (updated)')
        else:
            lines.append(f'Seller shop coords: {"created" if sp_created else "OK"} ({seller_profile.shop_lat}, {seller_profile.shop_lng})')

        # ── 4. Cancel stale active assignment for rider ───────────────────────
        active_qs = DeliveryAssignment.objects.filter(
            delivery_person=rider,
            status__in=['assigned', 'accepted', 'picked_up', 'in_transit'],
        )
        if active_qs.exists():
            if reset:
                count = active_qs.update(status='cancelled')
                lines.append(f'Cancelled {count} existing active assignment(s) for rider')
            else:
                a = active_qs.first()
                lines.append(
                    self.style.WARNING(
                        f'Rider already has an active assignment: {a.order.order_number} '
                        f'(status={a.status}). Run with --reset to cancel it first.'
                    )
                )
                lines.append(self.style.SUCCESS('Seed complete (no new order created).'))
                return lines

        # ── 5. Find a product to use ──────────────────────────────────────────
        product = Product.objects.filter(seller=seller, is_available=True).first()
        if product is None:
            product = Product.objects.filter(is_available=True).first()
        if product is None:
            return [self.style.ERROR('No available products found. Run seed_test_data first.')]

        # ── 6. Create a fresh out_for_delivery order ──────────────────────────
        order = Order.objects.create(
            buyer=buyer,
            seller=seller,
            total_price=product.price,
            delivery_fee=Decimal('30.00'),
            fulfillment_type='delivery',
            status='out_for_delivery',
            delivery_address='Plot 15, Independence Avenue, Lusaka',
            delivery_lat=BUYER_DROP_LAT,
            delivery_lng=BUYER_DROP_LNG,
            special_instructions='Ready for delivery - test scenario',
        )
        OrderItem.objects.create(
            order=order,
            product=product,
            quantity=1,
            price=product.price,
        )
        lines.append(f'Order created: {order.order_number}  (status=out_for_delivery)')
        lines.append(f'  Product: {product.name}  ZMW {product.price}')
        lines.append(f'  Delivery to: {order.delivery_address}')
        lines.append(f'  Delivery fee: ZMW {order.delivery_fee}')

        # ── 7. Create a DeliveryOffer for the rider ───────────────────────────
        offer, offer_created = DeliveryOffer.objects.get_or_create(
            order=order,
            rider=rider,
            defaults={
                'status': 'pending',
                'rider_distance_km': 1.5,
                'expires_at': timezone.now() + timezone.timedelta(minutes=10),
            },
        )
        lines.append(
            f'Delivery offer: {"created" if offer_created else "already exists"} '
            f'(expires {offer.expires_at.strftime("%H:%M:%S")})'
        )

        lines.append('')
        lines.append(self.style.SUCCESS('Seed complete. Delivery scenario is ready.'))
        lines.append('  Log in as the rider and tap "Accept" on the order board.')
        lines.append(f'  Rider login: {rider.phone_number}')
        lines.append(f'  Order:       {order.order_number}')
        lines.append(f'  Pickup:      Cairo Road, Lusaka ({LUSAKA_MARKET_LAT}, {LUSAKA_MARKET_LNG})')
        lines.append(f'  Drop-off:    Independence Avenue, Lusaka ({BUYER_DROP_LAT}, {BUYER_DROP_LNG})')

        return lines
