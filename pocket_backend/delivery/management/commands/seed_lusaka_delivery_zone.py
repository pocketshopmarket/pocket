from decimal import Decimal

from django.core.management.base import BaseCommand

from delivery.models import DeliveryZone


class Command(BaseCommand):
    help = 'Create a sample Lusaka delivery zone (GeoJSON lng,lat ring).'

    def handle(self, *args, **options):
        area = {
            'type': 'Polygon',
            'coordinates': [
                [
                    [28.20, -15.25],
                    [28.55, -15.25],
                    [28.55, -15.55],
                    [28.20, -15.55],
                    [28.20, -15.25],
                ]
            ],
        }
        z, created = DeliveryZone.objects.update_or_create(
            name='Lusaka metro',
            defaults={
                'description': 'Sample zone for dev (Phase 3)',
                'area': area,
                'is_active': True,
                'base_rate': Decimal('15.00'),
                'per_km_rate': Decimal('3.50'),
            },
        )
        action = 'Created' if created else 'Updated'
        self.stdout.write(self.style.SUCCESS(f'{action} zone: {z.name} (id={z.id})'))
