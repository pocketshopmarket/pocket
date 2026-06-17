from django.contrib import admin
from .models import PlatformSettings


@admin.register(PlatformSettings)
class PlatformSettingsAdmin(admin.ModelAdmin):
    fieldsets = (
        ('Commission', {
            'fields': ('commission_rate',),
            'description': 'Set the percentage the platform takes from each order.'
        }),
        ('Orders', {
            'fields': ('order_acceptance_timeout_minutes',),
        }),
        ('Delivery Pricing', {
            'fields': (
                'delivery_per_km_rate',
                'delivery_short_distance_threshold_km',
                'delivery_short_distance_flat_rate',
            ),
        }),
        ('Payouts', {
            'fields': ('payout_method',),
        }),
        ('Maintenance', {
            'fields': ('maintenance_mode', 'maintenance_message'),
        }),
    )

    def has_add_permission(self, request):
        return not PlatformSettings.objects.exists()

    def has_delete_permission(self, request, obj=None):
        return False
