from django.contrib import admin
from .models import PlatformSettings


@admin.register(PlatformSettings)
class PlatformSettingsAdmin(admin.ModelAdmin):
    fieldsets = (
        ('Charges', {
            'fields': (
                'buyer_service_fee_rate',
                'seller_commission_rate',
                'rider_commission_rate',
                'payout_fee_rate',
            ),
            'description': (
                'All rates are decimals: 0.05 = 5%, 0.10 = 10%, 0 = no charge. '
                'Changes take effect immediately.'
            ),
        }),
        ('Orders', {
            'fields': ('order_acceptance_timeout_minutes',),
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
