from django.db import models
from django.utils import timezone
import secrets
from accounts.models import User
from orders.models import Order

# Create your models here.


class DeliveryPricingConfig(models.Model):
    """
    Singleton model — only one row should ever exist.
    Operators edit this from Django Admin to control delivery fees platform-wide.

    Pricing logic:
      if distance_km <= short_distance_threshold_km:
          fee = short_distance_flat_rate          (e.g. ZMW 30 flat)
      else:
          fee = distance_km * per_km_rate         (e.g. 12 km × ZMW 5 = ZMW 60)
    """
    per_km_rate = models.DecimalField(
        max_digits=6,
        decimal_places=2,
        default=5.00,
        help_text='Charge per kilometre for long-distance trips (ZMW)',
    )
    short_distance_threshold_km = models.FloatField(
        default=3.0,
        help_text='Trips at or below this distance (km) get the flat rate',
    )
    short_distance_flat_rate = models.DecimalField(
        max_digits=6,
        decimal_places=2,
        default=30.00,
        help_text='Flat delivery fee for short-distance trips (ZMW)',
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Delivery Pricing Config'
        verbose_name_plural = 'Delivery Pricing Config'

    def __str__(self):
        return (
            f'Short ≤{self.short_distance_threshold_km} km → ZMW {self.short_distance_flat_rate} flat | '
            f'Long → ZMW {self.per_km_rate}/km'
        )

    @classmethod
    def get_config(cls):
        """Always returns the single config row, creating it with defaults if absent."""
        obj, _ = cls.objects.get_or_create(pk=1)
        return obj


class DeliveryAssignment(models.Model):
    STATUS_CHOICES = [
        ('assigned', 'Assigned'),
        ('accepted', 'Accepted'),
        ('picked_up', 'Picked Up'),
        ('in_transit', 'In Transit'),
        ('delivered', 'Delivered'),
        ('cancelled', 'Cancelled'),
    ]
    
    order = models.OneToOneField(Order, on_delete=models.CASCADE)
    delivery_person = models.ForeignKey(User, on_delete=models.CASCADE, related_name='deliveries')
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='assigned')
    
    # Location tracking
    pickup_location = models.JSONField(default=dict)  # {"lat": -15.3875, "lng": 28.3228}
    delivery_location = models.JSONField(default=dict)
    current_location = models.JSONField(default=dict)
    
    # Timing
    assigned_at = models.DateTimeField(auto_now_add=True)
    accepted_at = models.DateTimeField(null=True, blank=True)
    location_updated_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text='When current_location was last set (rider GPS)',
    )
    picked_up_at = models.DateTimeField(null=True, blank=True)
    delivered_at = models.DateTimeField(null=True, blank=True)
    
    # Distance and time (straight-line or routing-based; see route_* when OSRM succeeds)
    estimated_distance = models.FloatField(help_text="Distance in km")
    estimated_duration = models.IntegerField(help_text="Duration in minutes")
    actual_distance = models.FloatField(null=True, blank=True)

    # Driving route (OSRM GeoJSON coordinates: list of [lng, lat])
    route_coordinates = models.JSONField(null=True, blank=True)
    route_distance_m = models.FloatField(null=True, blank=True)
    route_duration_s = models.FloatField(null=True, blank=True)
    route_source = models.CharField(max_length=32, default='haversine_fallback')
    route_confidence = models.FloatField(null=True, blank=True)
    last_eta_recomputed_at = models.DateTimeField(null=True, blank=True)
    reroute_count = models.PositiveIntegerField(default=0)

    # ETA quality tracking KPIs
    initial_estimated_duration = models.IntegerField(null=True, blank=True)
    final_eta_error_minutes = models.IntegerField(null=True, blank=True)
    
    class Meta:
        ordering = ['-assigned_at']
    
    def __str__(self):
        return f"Delivery {self.order.order_number} - {self.status}"
    
    @property
    def is_active(self):
        return self.status in ['assigned', 'accepted', 'picked_up', 'in_transit']

class DeliveryZone(models.Model):
    name = models.CharField(max_length=100)
    description = models.TextField(blank=True)
    area = models.JSONField()  # GeoJSON polygon coordinates
    is_active = models.BooleanField(default=True)
    base_rate = models.DecimalField(max_digits=6, decimal_places=2, help_text="Base delivery rate in ZMW")
    per_km_rate = models.DecimalField(max_digits=6, decimal_places=2, help_text="Rate per km in ZMW")
    
    def __str__(self):
        return f"{self.name} - ZMW {self.base_rate}"
    
    def contains_point(self, lat, lng):
        """Check if point is within delivery zone"""
        try:
            from shapely.geometry import Point, Polygon
            import json
            
            if not self.area or not isinstance(self.area, dict):
                return False
                
            ring = self.area.get('coordinates', [[]])[0]
            # GeoJSON: each position is [longitude, latitude]
            polygon = Polygon([(c[0], c[1]) for c in ring])
            point = Point(float(lng), float(lat))
            
            return polygon.contains(point)
        except ImportError:
            # Fallback if shapely not available
            return False
        except Exception:
            return False

class DeliveryTracking(models.Model):
    delivery_assignment = models.ForeignKey(DeliveryAssignment, on_delete=models.CASCADE, related_name='tracking_points')
    latitude = models.DecimalField(max_digits=12, decimal_places=8)
    longitude = models.DecimalField(max_digits=12, decimal_places=8)
    timestamp = models.DateTimeField(auto_now_add=True)
    speed = models.FloatField(null=True, blank=True, help_text="Speed in km/h")
    accuracy = models.FloatField(null=True, blank=True, help_text="GPS accuracy in meters")
    
    class Meta:
        ordering = ['-timestamp']
        indexes = [
            models.Index(fields=['delivery_assignment', 'timestamp'])
        ]
    
    def __str__(self):
        return f"Location for {self.delivery_assignment.order.order_number} at {self.timestamp}"


class DeliveryTelemetrySegment(models.Model):
    """
    Derived trip telemetry between two rider pings.
    Used for learning real-world delivery speeds by time/area.
    """

    delivery_assignment = models.ForeignKey(
        DeliveryAssignment,
        on_delete=models.CASCADE,
        related_name='telemetry_segments',
    )
    from_tracking = models.ForeignKey(
        DeliveryTracking,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='telemetry_from_segments',
    )
    to_tracking = models.ForeignKey(
        DeliveryTracking,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='telemetry_to_segments',
    )
    phase = models.CharField(max_length=20, default='accepted')
    started_at = models.DateTimeField()
    ended_at = models.DateTimeField()
    duration_s = models.PositiveIntegerField()
    distance_m = models.FloatField()
    derived_speed_kmh = models.FloatField(null=True, blank=True)
    reported_speed_kmh = models.FloatField(null=True, blank=True)
    route_source = models.CharField(max_length=32, blank=True, default='')
    route_confidence = models.FloatField(null=True, blank=True)
    route_distance_m = models.FloatField(null=True, blank=True)
    route_duration_s = models.FloatField(null=True, blank=True)
    weekday = models.PositiveSmallIntegerField(help_text='0=Mon, 6=Sun')
    hour_of_day = models.PositiveSmallIntegerField(help_text='0..23')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-ended_at']
        indexes = [
            models.Index(fields=['delivery_assignment', 'ended_at']),
            models.Index(fields=['phase', 'weekday', 'hour_of_day']),
        ]

    def __str__(self):
        return (
            f"Telemetry {self.delivery_assignment.order.order_number} "
            f"{self.distance_m:.0f}m/{self.duration_s}s"
        )


class DeliverySpeedProfile(models.Model):
    """
    Learned average speed profile by delivery phase and local hour bucket.
    Updated continuously from telemetry segments.
    """

    phase = models.CharField(max_length=20, default='in_transit')
    weekday = models.PositiveSmallIntegerField(help_text='0=Mon, 6=Sun')
    hour_of_day = models.PositiveSmallIntegerField(help_text='0..23')
    samples = models.PositiveIntegerField(default=0)
    total_distance_m = models.FloatField(default=0)
    total_duration_s = models.FloatField(default=0)
    avg_speed_kmh = models.FloatField(default=0)
    last_updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['phase', 'weekday', 'hour_of_day']
        constraints = [
            models.UniqueConstraint(
                fields=['phase', 'weekday', 'hour_of_day'],
                name='uniq_speed_profile_phase_weekday_hour',
            )
        ]

    def __str__(self):
        if self.weekday == 7:
            day = 'weekday'
        elif self.weekday == 8:
            day = 'weekend'
        else:
            day = f'd{self.weekday}'
        return (
            f"{self.phase} {day} h{self.hour_of_day} "
            f"{self.avg_speed_kmh:.1f}km/h ({self.samples})"
        )


class DeliveryOffer(models.Model):
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('accepted', 'Accepted'),
        ('expired', 'Expired'),
        ('taken', 'Taken by another rider'),
        ('declined', 'Declined'),
    ]

    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name='delivery_offers')
    rider = models.ForeignKey(User, on_delete=models.CASCADE, related_name='delivery_offers')
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    rider_distance_km = models.FloatField(null=True, blank=True)
    expires_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)
    responded_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['rider', 'status', 'expires_at']),
            models.Index(fields=['order', 'status']),
        ]

    @property
    def is_expired(self):
        return timezone.now() > self.expires_at


class DeliveryHandoffToken(models.Model):
    STEP_CHOICES = [
        ('pickup', 'Seller to Rider Pickup'),
        ('dropoff', 'Rider to Buyer Dropoff'),
    ]
    STATUS_CHOICES = [
        ('active', 'Active'),
        ('used', 'Used'),
        ('expired', 'Expired'),
    ]

    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name='handoff_tokens')
    assignment = models.ForeignKey(
        DeliveryAssignment, on_delete=models.CASCADE, related_name='handoff_tokens'
    )
    step = models.CharField(max_length=20, choices=STEP_CHOICES)
    token = models.CharField(max_length=16, unique=True, db_index=True)
    expires_at = models.DateTimeField()
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='active')
    used_at = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True, related_name='generated_handoff_tokens'
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['assignment', 'step', 'status']),
        ]

    @classmethod
    def generate_token(cls):
        return secrets.token_hex(3).upper()

    @property
    def is_expired(self):
        return timezone.now() > self.expires_at
