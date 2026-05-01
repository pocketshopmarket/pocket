from django.contrib import admin
from django.urls import reverse
from django.http import HttpResponseRedirect
from .models import (
    DeliveryAssignment,
    DeliveryPricingConfig,
    DeliverySpeedProfile,
    DeliveryTelemetrySegment,
    DeliveryTracking,
    DeliveryZone,
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
