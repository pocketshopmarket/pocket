from rest_framework import serializers
from .models import (
    DeliveryAssignment,
    DeliveryHandoffToken,
    DeliveryOffer,
    DeliveryTracking,
    DeliveryZone,
)
from orders.models import Order

class DeliveryTrackingSerializer(serializers.ModelSerializer):
    formatted_time = serializers.SerializerMethodField()
    
    class Meta:
        model = DeliveryTracking
        fields = ['id', 'latitude', 'longitude', 'timestamp', 'speed', 'accuracy', 'formatted_time']
    
    def get_formatted_time(self, obj):
        return obj.timestamp.strftime('%H:%M:%S')

class DeliveryAssignmentSerializer(serializers.ModelSerializer):
    order_number = serializers.CharField(source='order.order_number', read_only=True)
    buyer_name = serializers.CharField(source='order.buyer.full_name', read_only=True)
    delivery_person_name = serializers.CharField(source='delivery_person.full_name', read_only=True)
    buyer_phone = serializers.CharField(source='order.buyer.phone_number', read_only=True)
    delivery_address = serializers.CharField(source='order.delivery_address', read_only=True)
    estimated_time = serializers.SerializerMethodField()
    
    class Meta:
        model = DeliveryAssignment
        fields = ['id', 'order', 'order_number', 'delivery_person', 'delivery_person_name',
                 'status', 'pickup_location', 'delivery_location', 'current_location',
                 'assigned_at', 'accepted_at', 'picked_up_at', 'delivered_at',
                 'location_updated_at',
                 'estimated_distance', 'estimated_duration', 'estimated_time', 'buyer_name',
                 'buyer_phone', 'delivery_address',
                 'route_coordinates', 'route_distance_m', 'route_duration_s',
                 'route_source', 'route_confidence', 'last_eta_recomputed_at',
                 'reroute_count', 'initial_estimated_duration',
                 'final_eta_error_minutes']
        read_only_fields = ['assigned_at']
    
    def get_estimated_time(self, obj):
        if obj.estimated_duration:
            return f"{obj.estimated_duration} minutes"
        return "Calculating..."

class AvailableOrderSerializer(serializers.ModelSerializer):
    distance_from_rider = serializers.SerializerMethodField()
    estimated_time = serializers.SerializerMethodField()
    pickup_location = serializers.SerializerMethodField()
    
    class Meta:
        model = Order
        fields = [
            'id',
            'order_number',
            'status',
            'total_price',
            'delivery_address',
            'pickup_location',
            'distance_from_rider',
            'estimated_time',
            'created_at',
        ]
    
    def get_distance_from_rider(self, obj):
        """Great-circle distance from rider to this order's pickup (seller shop)."""
        rider_lat = self.context.get('rider_lat')
        rider_lng = self.context.get('rider_lng')
        pickup = self.context.get('pickup_coords', {}).get(obj.id)

        if pickup is None:
            return None

        try:
            rlat = float(rider_lat)
            rlng = float(rider_lng)
        except (TypeError, ValueError):
            return None

        if rlat == 0.0 and rlng == 0.0:
            return None

        from .utils import LocationService

        return LocationService.calculate_distance(
            rlat,
            rlng,
            pickup['lat'],
            pickup['lng'],
        )

    def get_estimated_time(self, obj):
        distance = self.get_distance_from_rider(obj)
        if distance is not None:
            from .utils import LocationService

            return LocationService.estimate_eta(distance, phase='accepted')
        return None

    def get_pickup_location(self, obj):
        pickup = self.context.get('pickup_coords', {}).get(obj.id)
        if pickup is None:
            return None
        return {'lat': pickup.get('lat'), 'lng': pickup.get('lng')}

class DeliveryZoneSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeliveryZone
        fields = ['id', 'name', 'description', 'area', 'is_active', 'base_rate', 'per_km_rate']

class AcceptDeliverySerializer(serializers.Serializer):
    order_id = serializers.IntegerField()
    offer_id = serializers.IntegerField(required=False)
    lat = serializers.DecimalField(max_digits=12, decimal_places=8)
    lng = serializers.DecimalField(max_digits=12, decimal_places=8)

class UpdateLocationSerializer(serializers.Serializer):
    assignment_id = serializers.IntegerField()
    lat = serializers.DecimalField(max_digits=12, decimal_places=8)
    lng = serializers.DecimalField(max_digits=12, decimal_places=8)
    speed = serializers.FloatField(required=False, allow_null=True)
    accuracy = serializers.FloatField(required=False, allow_null=True)

class UpdateDeliveryStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=DeliveryAssignment.STATUS_CHOICES)


class DeliveryOfferSerializer(serializers.ModelSerializer):
    order_number = serializers.CharField(source='order.order_number', read_only=True)
    order_status = serializers.CharField(source='order.status', read_only=True)
    delivery_address = serializers.CharField(source='order.delivery_address', read_only=True)

    class Meta:
        model = DeliveryOffer
        fields = [
            'id',
            'order',
            'order_number',
            'order_status',
            'delivery_address',
            'status',
            'rider_distance_km',
            'expires_at',
            'created_at',
            'responded_at',
        ]


class DeliveryHandoffTokenSerializer(serializers.ModelSerializer):
    order_number = serializers.CharField(source='order.order_number', read_only=True)

    class Meta:
        model = DeliveryHandoffToken
        fields = [
            'id',
            'order',
            'order_number',
            'assignment',
            'step',
            'token',
            'status',
            'expires_at',
            'used_at',
            'created_at',
        ]
        read_only_fields = ['id', 'token', 'status', 'used_at', 'created_at']
