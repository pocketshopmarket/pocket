import calendar

from django.contrib import admin
from django.utils.html import format_html

from .models import PlatformSettings, RevenueSnapshot


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


def _zmw(value):
    return f'ZMW {value:,.2f}' if value else '—'


@admin.register(RevenueSnapshot)
class RevenueSnapshotAdmin(admin.ModelAdmin):
    list_display = (
        'period',
        'order_count',
        'col_gmv',
        'col_delivery',
        'col_seller_commission',
        'col_rider_commission',
        'col_buyer_fees',
        'col_total_revenue',
        'col_payouts',
        'col_refunds',
        'col_net',
        'updated_at',
    )
    list_filter = ('year',)
    ordering = ('-year', '-month')
    search_fields = ()

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def changelist_view(self, request, extra_context=None):
        # Refresh numbers every time the list is opened
        try:
            RevenueSnapshot.refresh_all()
        except Exception:
            pass
        return super().changelist_view(request, extra_context=extra_context)

    @admin.display(description='Period', ordering='-year')
    def period(self, obj):
        return f'{calendar.month_name[obj.month]} {obj.year}'

    @admin.display(description='GMV')
    def col_gmv(self, obj):
        return _zmw(obj.gmv)

    @admin.display(description='Delivery collected')
    def col_delivery(self, obj):
        return _zmw(obj.delivery_collected)

    @admin.display(description='Seller commission')
    def col_seller_commission(self, obj):
        return _zmw(obj.seller_commission)

    @admin.display(description='Rider commission')
    def col_rider_commission(self, obj):
        return _zmw(obj.rider_commission)

    @admin.display(description='Buyer fees')
    def col_buyer_fees(self, obj):
        return _zmw(obj.buyer_fees)

    @admin.display(description='Total revenue')
    def col_total_revenue(self, obj):
        return format_html(
            '<strong style="color:#00BCD4">{}</strong>',
            _zmw(obj.total_revenue),
        )

    @admin.display(description='Payouts made')
    def col_payouts(self, obj):
        return _zmw(obj.total_payouts)

    @admin.display(description='Refunds')
    def col_refunds(self, obj):
        return _zmw(obj.total_refunds)

    @admin.display(description='Net revenue')
    def col_net(self, obj):
        color = '#38A169' if obj.net_revenue >= 0 else '#E53E3E'
        return format_html(
            '<strong style="color:{}">{}</strong>',
            color,
            _zmw(obj.net_revenue),
        )
