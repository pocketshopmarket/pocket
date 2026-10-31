from django.contrib import admin
from django.utils import timezone
from django.utils.html import format_html, format_html_join
from django.urls import reverse
from django.http import HttpResponseRedirect
from .models import (
    DeliveryAssignment,
    DeliveryDispatch,
    DeliveryOffer,
    DeliveryPricingConfig,
    DeliverySpeedProfile,
    DeliveryTelemetrySegment,
    DeliveryTracking,
    DeliveryZone,
    DispatchSettings,
)


@admin.register(DeliveryPricingConfig)
class DeliveryPricingConfigAdmin(admin.ModelAdmin):
    """
    Singleton admin — always edits the one pricing config row.
    You can change per_km_rate, short_distance_threshold_km, and short_distance_flat_rate
    here and those values will immediately be used for all new delivery quotes.
    """
    list_display = [
        'short_distance_threshold_km',
        'short_distance_flat_rate',
        'per_km_rate',
        'max_delivery_distance_km',
        'updated_at',
    ]
    fieldsets = (
        ('Short-distance pricing', {
            'description': (
                'Trips at or below the threshold get a flat fee regardless of exact distance.'
            ),
            'fields': ('short_distance_threshold_km', 'short_distance_flat_rate'),
        }),
        ('Long-distance pricing', {
            'description': 'Applied to every trip longer than the short-distance threshold.',
            'fields': ('per_km_rate',),
        }),
        ('Maximum delivery distance', {
            'description': (
                'Beyond this, rider delivery isn’t offered at all — only Pickup and '
                'requesting the seller arrange transport (bus/courier).'
            ),
            'fields': ('max_delivery_distance_km',),
        }),
    )
    readonly_fields = ['updated_at']

    def has_add_permission(self, request):
        # Only allow creating the row if none exists yet.
        return not DeliveryPricingConfig.objects.exists()

    def has_delete_permission(self, request, obj=None):
        # Never allow deleting the config row.
        return False

    def changelist_view(self, request, extra_context=None):
        # Skip the list view and redirect straight to the edit form.
        config = DeliveryPricingConfig.get_config()
        return HttpResponseRedirect(
            reverse('admin:delivery_deliverypricingconfig_change', args=[config.pk])
        )



@admin.register(DeliveryAssignment)
class DeliveryAssignmentAdmin(admin.ModelAdmin):
    list_display = ['order_number', 'delivery_person', 'status', 'estimated_distance', 'assigned_at']
    list_filter = ['status', 'assigned_at']
    search_fields = ['order__order_number', 'delivery_person__phone_number', 'delivery_person__full_name']
    readonly_fields = ['assigned_at', 'location_updated_at']
    
    def order_number(self, obj):
        return obj.order.order_number

@admin.register(DeliveryZone)
class DeliveryZoneAdmin(admin.ModelAdmin):
    list_display = ['name', 'base_rate', 'per_km_rate', 'is_active']
    list_filter = ['is_active']
    search_fields = ['name', 'description']

@admin.register(DeliveryTracking)
class DeliveryTrackingAdmin(admin.ModelAdmin):
    list_display = ['delivery_assignment', 'latitude', 'longitude', 'timestamp', 'speed']
    list_filter = ['timestamp']
    search_fields = ['delivery_assignment__order__order_number']
    readonly_fields = ['delivery_assignment', 'latitude', 'longitude', 'timestamp', 'speed', 'accuracy']
    
    def has_add_permission(self, request):
        # Don't allow manual creation of tracking points
        return False
    
    def has_change_permission(self, request, obj=None):
        # Don't allow editing of tracking points
        return False


@admin.register(DeliveryTelemetrySegment)
class DeliveryTelemetrySegmentAdmin(admin.ModelAdmin):
    list_display = [
        'delivery_assignment',
        'phase',
        'distance_m',
        'duration_s',
        'derived_speed_kmh',
        'ended_at',
    ]
    list_filter = ['phase', 'weekday', 'hour_of_day', 'ended_at']
    search_fields = ['delivery_assignment__order__order_number']
    readonly_fields = [
        'delivery_assignment',
        'from_tracking',
        'to_tracking',
        'phase',
        'started_at',
        'ended_at',
        'duration_s',
        'distance_m',
        'derived_speed_kmh',
        'reported_speed_kmh',
        'route_source',
        'route_confidence',
        'route_distance_m',
        'route_duration_s',
        'weekday',
        'hour_of_day',
        'created_at',
    ]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False


@admin.register(DeliverySpeedProfile)
class DeliverySpeedProfileAdmin(admin.ModelAdmin):
    list_display = [
        'phase',
        'weekday',
        'hour_of_day',
        'avg_speed_kmh',
        'samples',
        'last_updated_at',
    ]
    list_filter = ['phase', 'weekday', 'hour_of_day']
    search_fields = ['phase']
    readonly_fields = [
        'phase',
        'weekday',
        'hour_of_day',
        'samples',
        'total_distance_m',
        'total_duration_s',
        'avg_speed_kmh',
        'last_updated_at',
    ]

    def has_add_permission(self, request):
        return False


@admin.register(DispatchSettings)
class DispatchSettingsAdmin(admin.ModelAdmin):
    """How ready orders are offered to riders: a few at a time, then everyone nearby."""
    fieldsets = (
        ('Offer rounds', {
            'description': (
                'When a shop marks an order ready, the best riders get it first. If nobody '
                'accepts in time, the next riders get it. After the last round, every online '
                'rider nearby can accept it.'
            ),
            'fields': ('riders_per_round', 'seconds_per_round', 'rounds_before_open'),
        }),
        ('Who can get offers', {
            'fields': ('max_distance_km', 'location_fresh_minutes', 'missed_offers_limit'),
        }),
        ('Fairness', {
            'description': (
                'Score = minutes waiting since their last job (up to the cap) minus points per km '
                'from the shop. Highest score goes first.'
            ),
            'fields': ('wait_cap_minutes', 'km_penalty'),
        }),
    )

    def has_add_permission(self, request):
        return not DispatchSettings.objects.exists()

    def has_delete_permission(self, request, obj=None):
        return False

    def changelist_view(self, request, extra_context=None):
        return HttpResponseRedirect(
            reverse('admin:delivery_dispatchsettings_change', args=[DispatchSettings.get().pk])
        )


@admin.register(DeliveryDispatch)
class DeliveryDispatchAdmin(admin.ModelAdmin):
    """Read-only history: who each order was offered to, in which round, and what they did."""
    list_display = ['order', 'round', 'created_at', 'opened_at', 'finished_at']
    list_filter = ['opened_at', 'finished_at']
    search_fields = ['order__order_number']
    readonly_fields = ['order', 'round', 'round_ends_at', 'opened_at', 'finished_at', 'created_at', 'offers']

    @admin.display(description='Offers')
    def offers(self, obj):
        rows = DeliveryOffer.objects.filter(order=obj.order).select_related('rider').order_by('round', 'created_at')
        if not rows:
            return 'No riders were offered this order (it opened to everyone straight away).'
        return format_html(
            '<table><tr><th>Round</th><th>Rider</th><th>Km</th><th>Result</th><th>Sent</th></tr>{}</table>',
            format_html_join('', '<tr><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td></tr>', (
                (o.round, o.rider.full_name or o.rider.phone_number, o.rider_distance_km if o.rider_distance_km is not None else '-',
                 o.get_status_display(), timezone.localtime(o.created_at).strftime('%H:%M:%S'))
                for o in rows
            )),
        )

    def has_add_permission(self, request):
        return False
