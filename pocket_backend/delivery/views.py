import logging
import json
from decimal import Decimal

from django.db.models import Avg, Case, Count, IntegerField, Q, Sum, When
from django.db import transaction
from datetime import timedelta
from django.conf import settings
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView
from .models import (
    DeliveryAssignment,
    DeliveryHandoffToken,
    DeliveryOffer,
    DeliverySpeedProfile,
    DeliveryTelemetrySegment,
    DeliveryTracking,
    DeliveryZone,
)
from .serializers import (
    AcceptDeliverySerializer,
    AvailableOrderSerializer,
    DeliveryAssignmentSerializer,
    DeliveryHandoffTokenSerializer,
    DeliveryOfferSerializer,
    DeliveryTrackingSerializer,
    DeliveryZoneSerializer,
    UpdateDeliveryStatusSerializer,
    UpdateLocationSerializer,
)
from accounts.models import SellerProfile
from orders.models import Order
from payments.models import Transaction
from payments.services.pawapay import PawaPayService

from .coordinates import (
    build_pickup_coords_for_orders,
    resolve_delivery_coordinates,
    resolve_pickup_coordinates,
)
from .routing import apply_route_to_assignment
from .utils import LocationService

logger = logging.getLogger(__name__)


def _extract_order_finance_meta(order: Order) -> dict:
    text = order.special_instructions or ''
    start = text.find('[PS_META]')
    end = text.find('[/PS_META]')
    if start == -1 or end == -1 or end <= start:
        return {}
    raw = text[start + len('[PS_META]') : end].strip()
    if not raw:
        return {}
    try:
        data = json.loads(raw)
        return data if isinstance(data, dict) else {}
    except json.JSONDecodeError:
        return {}


def _delivery_fee_for_order(order: Order) -> Decimal:
    meta = _extract_order_finance_meta(order)
    raw_fee = meta.get('quoted_delivery_fee')
    try:
        return Decimal(str(raw_fee))
    except Exception:
        return Decimal('0')

class AvailableOrdersView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    def get(self, request):
        if request.user.role != 'delivery':
            return Response({'error': 'Only delivery personnel can view available orders'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        # Get rider's current location
        rider_lat = float(request.GET.get('lat', 0))
        rider_lng = float(request.GET.get('lng', 0))
        
        # Pipeline: seller still preparing, or ready for rider pickup — but not if any
        # rider already has an active assignment on this order (OneToOne).
        busy_order_ids = DeliveryAssignment.objects.exclude(
            status__in=['delivered', 'cancelled'],
        ).values_list('order_id', flat=True)

        orders = list(
            Order.objects.filter(
                status='out_for_delivery',
            )
            .exclude(id__in=busy_order_ids)
            .select_related('seller')
            .order_by('-created_at')
        )

        pickup_coords = build_pickup_coords_for_orders(
            orders, allow_fallback=False
        )

        serializer = AvailableOrderSerializer(
            orders,
            many=True,
            context={
                'rider_lat': rider_lat,
                'rider_lng': rider_lng,
                'pickup_coords': pickup_coords,
            },
        )
        payload = list(serializer.data)
        # Fairness: sort by status priority, then rider distance to pickup.
        payload.sort(
            key=lambda row: (
                {'out_for_delivery': 0, 'preparing': 1, 'accepted': 2, 'pending': 3}.get(
                    row.get('status'), 4
                ),
                row.get('distance_from_rider')
                if row.get('distance_from_rider') is not None
                else 10**9,
                row.get('created_at', ''),
            )
        )
        return Response(payload)

class AcceptDeliveryView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def _reconcile_stale_active_assignments(self, rider):
        stale_qs = DeliveryAssignment.objects.select_for_update().filter(
            delivery_person=rider,
            status__in=['accepted', 'picked_up', 'in_transit'],
            order__status='delivered',
        )
        for a in stale_qs:
            a.status = 'delivered'
            if a.delivered_at is None:
                a.delivered_at = timezone.now()
            a.save(update_fields=['status', 'delivered_at'])
    
    def post(self, request):
        if request.user.role != 'delivery':
            return Response({'error': 'Only delivery personnel can accept deliveries'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        serializer = AcceptDeliverySerializer(data=request.data)
        if serializer.is_valid():
            order_id = serializer.validated_data['order_id']
            offer_id = serializer.validated_data.get('offer_id')
            rider_lat = serializer.validated_data['lat']
            rider_lng = serializer.validated_data['lng']

            try:
                with transaction.atomic():
                    self._reconcile_stale_active_assignments(request.user)
                    has_active_job = DeliveryAssignment.objects.select_for_update().filter(
                        delivery_person=request.user,
                        status__in=['accepted', 'picked_up', 'in_transit'],
                    ).exists()
                    if has_active_job:
                        current = (
                            DeliveryAssignment.objects.filter(
                                delivery_person=request.user,
                                status__in=['accepted', 'picked_up', 'in_transit'],
                            )
                            .select_related('order')
                            .order_by('-assigned_at')
                            .first()
                        )
                        order_ref = (
                            current.order.order_number if current and current.order else ''
                        )
                        st = current.status if current else 'active'
                        return Response(
                            {
                                'error': (
                                    'You already have an active delivery. '
                                    'Complete it before accepting another one.'
                                ),
                                'active_assignment': {
                                    'order_number': order_ref,
                                    'status': st,
                                },
                            },
                            status=status.HTTP_400_BAD_REQUEST,
                        )

                    order = Order.objects.select_for_update().get(
                        id=order_id, status='out_for_delivery'
                    )

                    if DeliveryAssignment.objects.filter(order=order).exists():
                        return Response(
                            {'error': 'Order already assigned'},
                            status=status.HTTP_400_BAD_REQUEST,
                        )

                    offer = None
                    if offer_id is not None:
                        offer = DeliveryOffer.objects.filter(
                            id=offer_id, order=order, rider=request.user
                        ).first()
                        if offer is None:
                            return Response(
                                {'error': 'Offer not found for this rider/order'},
                                status=status.HTTP_400_BAD_REQUEST,
                            )
                        if offer.status != 'pending' or offer.is_expired:
                            return Response(
                                {'error': 'Offer is no longer valid'},
                                status=status.HTTP_400_BAD_REQUEST,
                            )

                    profile = SellerProfile.objects.filter(user=order.seller).first()
                    if profile is None:
                        return Response(
                            {'error': 'Seller shop profile is missing'},
                            status=status.HTTP_400_BAD_REQUEST,
                        )
                    pickup_ok = (
                        profile.shop_lat is not None
                        and profile.shop_lng is not None
                    ) or bool((profile.shop_location or '').strip())
                    if not pickup_ok:
                        return Response(
                            {
                                'error': (
                                    'Seller must set shop coordinates or a shop address '
                                    'before deliveries can be accepted'
                                )
                            },
                            status=status.HTTP_400_BAD_REQUEST,
                        )
                    delivery_ok = (
                        order.delivery_lat is not None
                        and order.delivery_lng is not None
                    ) or bool((order.delivery_address or '').strip())
                    if not delivery_ok:
                        return Response(
                            {
                                'error': (
                                    'Order needs a delivery address or coordinates '
                                    'before a rider can accept'
                                )
                            },
                            status=status.HTTP_400_BAD_REQUEST,
                        )

                    pickup = resolve_pickup_coordinates(
                        order.seller, allow_fallback=False
                    )
                    delivery_pt = resolve_delivery_coordinates(
                        order, allow_fallback=False
                    )
                    if pickup is None or delivery_pt is None:
                        missing = []
                        if pickup is None:
                            missing.append('pickup/shop location')
                        if delivery_pt is None:
                            missing.append('customer drop-off location')
                        return Response(
                            {
                                'error': (
                                    'Precise coordinates could not be resolved for: '
                                    f"{', '.join(missing)}. "
                                    'Please make the address more specific and try again.'
                                )
                            },
                            status=status.HTTP_400_BAD_REQUEST,
                        )
                    distance_km = LocationService.calculate_distance(
                        pickup['lat'],
                        pickup['lng'],
                        delivery_pt['lat'],
                        delivery_pt['lng'],
                    )
                    duration_min = LocationService.estimate_eta(
                        distance_km, phase='in_transit'
                    )

                    now = timezone.now()
                    assignment = DeliveryAssignment.objects.create(
                        order=order,
                        delivery_person=request.user,
                        status='accepted',
                        accepted_at=now,
                        location_updated_at=now,
                        current_location={
                            'lat': float(rider_lat),
                            'lng': float(rider_lng),
                        },
                        pickup_location=pickup,
                        delivery_location=delivery_pt,
                        estimated_distance=round(distance_km, 2),
                        estimated_duration=duration_min,
                        initial_estimated_duration=duration_min,
                    )

                    # Seed first tracking point so future pings produce telemetry segments.
                    DeliveryTracking.objects.create(
                        delivery_assignment=assignment,
                        latitude=float(rider_lat),
                        longitude=float(rider_lng),
                    )

                    apply_route_to_assignment(assignment, pickup, delivery_pt)
                    assignment.initial_estimated_duration = (
                        assignment.estimated_duration
                    )
                    assignment.save(
                        update_fields=[
                            'route_coordinates',
                            'route_distance_m',
                            'route_duration_s',
                            'route_source',
                            'route_confidence',
                            'last_eta_recomputed_at',
                            'estimated_distance',
                            'estimated_duration',
                            'initial_estimated_duration',
                        ]
                    )

                    if offer is not None:
                        offer.status = 'accepted'
                        offer.responded_at = timezone.now()
                        offer.save(update_fields=['status', 'responded_at'])
                    DeliveryOffer.objects.filter(order=order, status='pending').exclude(
                        rider=request.user
                    ).update(status='taken', responded_at=timezone.now())

                response_serializer = DeliveryAssignmentSerializer(assignment)
                return Response(response_serializer.data, status=status.HTTP_201_CREATED)
                
            except Order.DoesNotExist:
                return Response({'error': 'Order not found'}, 
                              status=status.HTTP_404_NOT_FOUND)
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

class UpdateLocationView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    WEEKDAY_AGG_BUCKET = 7
    WEEKEND_AGG_BUCKET = 8


    def _destination_for_assignment(self, assignment):
        if assignment.status == 'accepted':
            return assignment.pickup_location or {}
        return assignment.delivery_location or {}

    def _recompute_live_eta(self, assignment, latitude: float, longitude: float) -> None:
        destination = self._destination_for_assignment(assignment)
        if not destination:
            return
        start = {'lat': latitude, 'lng': longitude}
        try:
            prev_distance = assignment.route_distance_m
            prev_duration = assignment.route_duration_s
            prev_source = assignment.route_source
            apply_route_to_assignment(assignment, start, destination)
            changed = (
                prev_distance != assignment.route_distance_m
                or prev_duration != assignment.route_duration_s
                or prev_source != assignment.route_source
            )
            if changed:
                assignment.reroute_count = (assignment.reroute_count or 0) + 1
        except Exception as exc:
            logger.warning(
                'Live ETA recalculation failed for assignment=%s: %s',
                assignment.id,
                exc,
            )

    def _capture_segment_telemetry(
        self,
        assignment,
        previous_point: DeliveryTracking | None,
        current_point: DeliveryTracking,
        reported_speed,
    ) -> None:
        if previous_point is None:
            return

        started_at = previous_point.timestamp
        ended_at = current_point.timestamp
        delta = ended_at - started_at
        duration_s = int(delta.total_seconds())
        if duration_s <= 0:
            return

        distance_km = LocationService.calculate_distance(
            float(previous_point.latitude),
            float(previous_point.longitude),
            float(current_point.latitude),
            float(current_point.longitude),
        )
        distance_m = distance_km * 1000.0
        if distance_m < 0:
            return

        derived_speed_kmh = (distance_km / max(duration_s / 3600.0, 0.001))
        ended_local = timezone.localtime(ended_at)
        DeliveryTelemetrySegment.objects.create(
            delivery_assignment=assignment,
            from_tracking=previous_point,
            to_tracking=current_point,
            phase=assignment.status,
            started_at=started_at,
            ended_at=ended_at,
            duration_s=duration_s,
            distance_m=distance_m,
            derived_speed_kmh=round(derived_speed_kmh, 2),
            reported_speed_kmh=float(reported_speed)
            if reported_speed is not None
            else None,
            route_source=assignment.route_source or '',
            route_confidence=assignment.route_confidence,
            route_distance_m=assignment.route_distance_m,
            route_duration_s=assignment.route_duration_s,
            weekday=ended_local.weekday(),
            hour_of_day=ended_local.hour,
        )
        self._update_speed_profile(
            phase=assignment.status,
            weekday=ended_local.weekday(),
            hour_of_day=ended_local.hour,
            distance_m=distance_m,
            duration_s=duration_s,
        )

    def _upsert_speed_profile_bucket(
        self,
        *,
        phase: str,
        weekday_bucket: int,
        hour_of_day: int,
        distance_m: float,
        duration_s: int,
    ) -> None:
        alpha = float(getattr(settings, 'DELIVERY_SPEED_SMOOTHING_ALPHA', 0.35))
        alpha = min(max(alpha, 0.05), 1.0)
        sample_speed_kmh = (distance_m / 1000.0) / max(duration_s / 3600.0, 0.001)
        profile, _ = DeliverySpeedProfile.objects.get_or_create(
            phase=phase,
            weekday=weekday_bucket,
            hour_of_day=hour_of_day,
            defaults={
                'samples': 0,
                'total_distance_m': 0,
                'total_duration_s': 0,
                'avg_speed_kmh': sample_speed_kmh,
            },
        )
        profile.samples += 1
        profile.total_distance_m += float(distance_m)
        profile.total_duration_s += float(duration_s)
        # EMA smoothing so recent conditions affect ETA quickly.
        if profile.samples <= 1:
            profile.avg_speed_kmh = sample_speed_kmh
        else:
            profile.avg_speed_kmh = (
                alpha * sample_speed_kmh
                + (1.0 - alpha) * float(profile.avg_speed_kmh or sample_speed_kmh)
            )
        profile.save(
            update_fields=[
                'samples',
                'total_distance_m',
                'total_duration_s',
                'avg_speed_kmh',
                'last_updated_at',
            ]
        )

    def _update_speed_profile(
        self,
        *,
        phase: str,
        weekday: int,
        hour_of_day: int,
        distance_m: float,
        duration_s: int,
    ) -> None:
        # Ignore low-signal micro hops from GPS jitter.
        if duration_s < 10 or distance_m < 25:
            return
        self._upsert_speed_profile_bucket(
            phase=phase,
            weekday_bucket=weekday,
            hour_of_day=hour_of_day,
            distance_m=distance_m,
            duration_s=duration_s,
        )
        daytype_bucket = (
            self.WEEKEND_AGG_BUCKET if weekday >= 5 else self.WEEKDAY_AGG_BUCKET
        )
        self._upsert_speed_profile_bucket(
            phase=phase,
            weekday_bucket=daytype_bucket,
            hour_of_day=hour_of_day,
            distance_m=distance_m,
            duration_s=duration_s,
        )
    
    def post(self, request):
        if request.user.role != 'delivery':
            return Response({'error': 'Only delivery personnel can update location'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        serializer = UpdateLocationSerializer(data=request.data)
        if serializer.is_valid():
            assignment_id = serializer.validated_data['assignment_id']
            latitude = float(serializer.validated_data['lat'])
            longitude = float(serializer.validated_data['lng'])
            speed = serializer.validated_data.get('speed')
            accuracy = serializer.validated_data.get('accuracy')
            
            try:
                assignment = DeliveryAssignment.objects.get(
                    id=assignment_id, 
                    delivery_person=request.user,
                    status__in=['accepted', 'picked_up', 'in_transit']
                )
                previous_point = (
                    DeliveryTracking.objects.filter(delivery_assignment=assignment)
                    .order_by('-timestamp')
                    .first()
                )
                
                # Update current location
                assignment.current_location = {'lat': latitude, 'lng': longitude}
                assignment.location_updated_at = timezone.now()
                self._recompute_live_eta(assignment, latitude, longitude)
                assignment.save(
                    update_fields=[
                        'current_location',
                        'location_updated_at',
                        'route_coordinates',
                        'route_distance_m',
                        'route_duration_s',
                        'route_source',
                        'route_confidence',
                        'last_eta_recomputed_at',
                        'estimated_distance',
                        'estimated_duration',
                        'reroute_count',
                    ]
                )
                
                # Create tracking point
                current_point = DeliveryTracking.objects.create(
                    delivery_assignment=assignment,
                    latitude=latitude,
                    longitude=longitude,
                    speed=speed,
                    accuracy=accuracy
                )
                self._capture_segment_telemetry(
                    assignment=assignment,
                    previous_point=previous_point,
                    current_point=current_point,
                    reported_speed=speed,
                )
                
                return Response({'message': 'Location updated successfully'})
                
            except DeliveryAssignment.DoesNotExist:
                return Response({'error': 'Delivery assignment not found'}, 
                              status=status.HTTP_404_NOT_FOUND)
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

class UpdateDeliveryStatusView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    def put(self, request, assignment_id):
        if request.user.role != 'delivery':
            return Response({'error': 'Only delivery personnel can update delivery status'}, 
                          status=status.HTTP_403_FORBIDDEN)
        
        try:
            assignment = DeliveryAssignment.objects.get(
                id=assignment_id, 
                delivery_person=request.user
            )
            
            serializer = UpdateDeliveryStatusSerializer(data=request.data)
            if serializer.is_valid():
                new_status = serializer.validated_data['status']
                simulate_qr = request.data.get('simulate_qr') in [
                    True,
                    'true',
                    'True',
                    1,
                    '1',
                ]
                
                # Validate status transitions
                current_status = assignment.status
                valid_transitions = {
                    'accepted': ['picked_up'],
                    'picked_up': ['in_transit'],
                    'in_transit': ['delivered'],
                    'delivered': [],
                    'cancelled': []
                }
                
                if new_status not in valid_transitions.get(current_status, []):
                    return Response({'error': f'Cannot transition from {current_status} to {new_status}'}, 
                                  status=status.HTTP_400_BAD_REQUEST)

                if new_status == 'picked_up':
                    pickup_verified = DeliveryHandoffToken.objects.filter(
                        assignment=assignment,
                        step='pickup',
                        status='used',
                    ).exists()
                    if not pickup_verified:
                        if simulate_qr and settings.DEBUG:
                            DeliveryHandoffToken.objects.filter(
                                assignment=assignment,
                                step='pickup',
                                status='active',
                            ).update(status='expired')
                            DeliveryHandoffToken.objects.create(
                                order=assignment.order,
                                assignment=assignment,
                                step='pickup',
                                token=DeliveryHandoffToken.generate_token(),
                                expires_at=timezone.now() + timedelta(minutes=5),
                                status='used',
                                used_at=timezone.now(),
                                created_by=request.user,
                            )
                            pickup_verified = True
                        else:
                            return Response(
                                {
                                    'error': (
                                        'Pickup QR must be verified before marking picked up'
                                    )
                                },
                                status=status.HTTP_400_BAD_REQUEST,
                            )
                    if not pickup_verified:
                        return Response(
                            {'error': 'Pickup QR must be verified before marking picked up'},
                            status=status.HTTP_400_BAD_REQUEST,
                        )

                if new_status == 'delivered':
                    dropoff_verified = DeliveryHandoffToken.objects.filter(
                        assignment=assignment,
                        step='dropoff',
                        status='used',
                    ).exists()
                    if not dropoff_verified:
                        if simulate_qr and settings.DEBUG:
                            DeliveryHandoffToken.objects.filter(
                                assignment=assignment,
                                step='dropoff',
                                status='active',
                            ).update(status='expired')
                            DeliveryHandoffToken.objects.create(
                                order=assignment.order,
                                assignment=assignment,
                                step='dropoff',
                                token=DeliveryHandoffToken.generate_token(),
                                expires_at=timezone.now() + timedelta(minutes=5),
                                status='used',
                                used_at=timezone.now(),
                                created_by=request.user,
                            )
                            dropoff_verified = True
                        else:
                            return Response(
                                {
                                    'error': (
                                        'Dropoff QR must be verified before marking delivered'
                                    )
                                },
                                status=status.HTTP_400_BAD_REQUEST,
                            )
                    if not dropoff_verified:
                        return Response(
                            {'error': 'Dropoff QR must be verified before marking delivered'},
                            status=status.HTTP_400_BAD_REQUEST,
                        )

                # Update status and timestamps
                assignment.status = new_status
                
                if new_status == 'picked_up':
                    assignment.picked_up_at = timezone.now()
                    assignment.order.status = 'out_for_delivery'
                    assignment.order.save(update_fields=['status', 'updated_at'])
                elif new_status == 'in_transit':
                    assignment.order.status = 'out_for_delivery'
                    assignment.order.save(update_fields=['status', 'updated_at'])
                elif new_status == 'delivered':
                    assignment.delivered_at = timezone.now()
                    # Update order status
                    assignment.order.status = 'delivered'
                    assignment.order.save(update_fields=['status', 'updated_at'])
                    if assignment.accepted_at is not None:
                        elapsed = assignment.delivered_at - assignment.accepted_at
                        actual_minutes = max(1, int(elapsed.total_seconds() / 60))
                        if assignment.initial_estimated_duration is not None:
                            assignment.final_eta_error_minutes = (
                                actual_minutes - assignment.initial_estimated_duration
                            )
                        logger.info(
                            (
                                'Delivery KPI order=%s assignment=%s '
                                'initial_eta_min=%s actual_min=%s eta_error_min=%s '
                                'reroutes=%s route_source=%s route_confidence=%s'
                            ),
                            assignment.order.order_number,
                            assignment.id,
                            assignment.initial_estimated_duration,
                            actual_minutes,
                            assignment.final_eta_error_minutes,
                            assignment.reroute_count,
                            assignment.route_source,
                            assignment.route_confidence,
                        )
                
                assignment.save()
                
                # Notify customer (later)
                
                response_serializer = DeliveryAssignmentSerializer(assignment)
                return Response(response_serializer.data)
            
        except DeliveryAssignment.DoesNotExist:
            return Response({'error': 'Delivery assignment not found'}, 
                          status=status.HTTP_404_NOT_FOUND)

class TrackDeliveryView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    def get(self, request, order_number):
        user = request.user
        try:
            if user.role == 'buyer':
                order = request.user.orders.get(order_number=order_number)
            elif user.role == 'seller':
                order = Order.objects.get(order_number=order_number, seller=user)
            elif user.role == 'delivery':
                order = Order.objects.get(order_number=order_number)
            else:
                return Response(
                    {'error': 'Unauthorized'},
                    status=status.HTTP_403_FORBIDDEN,
                )
        except Order.DoesNotExist:
            return Response(
                {'error': 'Order not found'},
                status=status.HTTP_404_NOT_FOUND,
            )

        try:
            assignment = order.deliveryassignment
        except DeliveryAssignment.DoesNotExist:
            return Response(
                {'error': 'Delivery not started yet'},
                status=status.HTTP_404_NOT_FOUND,
            )

        if user.role == 'delivery' and assignment.delivery_person_id != user.id:
            return Response(
                {'error': 'You are not assigned to this delivery'},
                status=status.HTTP_403_FORBIDDEN,
            )

        tracking_points = DeliveryTracking.objects.filter(
            delivery_assignment=assignment
        ).order_by('-timestamp')[:50]

        return Response(
            {
                'order': {
                    'id': order.id,
                    'order_number': order.order_number,
                    'status': order.status,
                    'total_price': str(order.total_price),
                },
                'assignment': DeliveryAssignmentSerializer(assignment).data,
                'tracking_points': DeliveryTrackingSerializer(
                    tracking_points, many=True
                ).data,
                'osm_tiles': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            }
        )


class ActiveAssignmentView(APIView):
    """Current in-progress job for the logged-in rider."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        if request.user.role != 'delivery':
            return Response(
                {'error': 'Only delivery personnel'},
                status=status.HTTP_403_FORBIDDEN,
            )

        assignment = (
            DeliveryAssignment.objects.filter(
                delivery_person=request.user,
                status__in=['accepted', 'picked_up', 'in_transit'],
            )
            .select_related('order', 'order__buyer')
            .order_by('-assigned_at')
            .first()
        )

        if not assignment:
            return Response({'assignment': None})

        return Response(
            {'assignment': DeliveryAssignmentSerializer(assignment).data}
        )


class DeliveryOffersView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        if request.user.role != 'delivery':
            return Response(
                {'error': 'Only delivery personnel'},
                status=status.HTTP_403_FORBIDDEN,
            )
        now = timezone.now()
        DeliveryOffer.objects.filter(
            rider=request.user, status='pending', expires_at__lt=now
        ).update(status='expired')
        offers = DeliveryOffer.objects.filter(rider=request.user).select_related('order')[:20]
        return Response(DeliveryOfferSerializer(offers, many=True).data)


class GenerateHandoffTokenView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, assignment_id):
        step = str(request.data.get('step', '')).strip()
        if step not in ['pickup', 'dropoff']:
            return Response(
                {'error': 'step must be pickup or dropoff'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        assignment = DeliveryAssignment.objects.filter(id=assignment_id).select_related(
            'order', 'order__seller'
        ).first()
        if assignment is None:
            return Response({'error': 'Assignment not found'}, status=404)

        user = request.user
        is_seller = user.role == 'seller' and assignment.order.seller_id == user.id
        is_buyer = user.role == 'buyer' and assignment.order.buyer_id == user.id
        if step == 'pickup' and not is_seller:
            return Response(
                {'error': 'Only the seller can generate pickup QR token'},
                status=status.HTTP_403_FORBIDDEN,
            )
        if step == 'dropoff' and not is_buyer:
            return Response(
                {'error': 'Only the buyer can generate dropoff QR token'},
                status=status.HTTP_403_FORBIDDEN,
            )

        DeliveryHandoffToken.objects.filter(
            assignment=assignment, step=step, status='active'
        ).update(status='expired')
        token = DeliveryHandoffToken.objects.create(
            order=assignment.order,
            assignment=assignment,
            step=step,
            token=DeliveryHandoffToken.generate_token(),
            expires_at=timezone.now() + timedelta(minutes=5),
            created_by=user,
        )
        return Response(DeliveryHandoffTokenSerializer(token).data, status=201)


class VerifyHandoffTokenView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, assignment_id):
        step = str(request.data.get('step', '')).strip()
        token_raw = str(request.data.get('token', '')).strip().upper()
        if step not in ['pickup', 'dropoff'] or not token_raw:
            return Response(
                {'error': 'step and token are required'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        assignment = DeliveryAssignment.objects.filter(id=assignment_id).select_related(
            'order', 'order__buyer'
        ).first()
        if assignment is None:
            return Response({'error': 'Assignment not found'}, status=404)

        user = request.user
        is_rider = user.role == 'delivery' and assignment.delivery_person_id == user.id
        if step == 'pickup' and not is_rider:
            return Response(
                {'error': 'Only assigned rider can verify pickup token'},
                status=status.HTTP_403_FORBIDDEN,
            )
        if step == 'dropoff' and not is_rider:
            return Response(
                {'error': 'Only assigned rider can verify dropoff token'},
                status=status.HTTP_403_FORBIDDEN,
            )

        token = DeliveryHandoffToken.objects.filter(
            assignment=assignment,
            step=step,
            token=token_raw,
            status='active',
        ).first()
        if token is None or token.is_expired:
            return Response(
                {'error': 'Token is invalid or expired'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        token.status = 'used'
        token.used_at = timezone.now()
        token.save(update_fields=['status', 'used_at'])

        deposit_tx = (
            Transaction.objects.filter(
                order=assignment.order,
                transaction_type='deposit',
                status='completed',
            )
            .order_by('-created_at')
            .first()
        )
        if deposit_tx is not None:
            delivery_fee = _delivery_fee_for_order(assignment.order)
            order_total = Decimal(str(assignment.order.total_price))
            seller_share = max(order_total - delivery_fee, Decimal('0'))

            if step == 'pickup':
                seller_tx = Transaction.objects.filter(
                    order=assignment.order,
                    transaction_type='payout',
                    recipient=assignment.order.seller,
                    recipient_role='seller',
                    trigger_event='pickup_qr',
                ).order_by('-created_at').first()
                if seller_tx is None and seller_share > 0:
                    seller_tx = Transaction.objects.create(
                        order=assignment.order,
                        transaction_type='payout',
                        amount=seller_share,
                        currency=deposit_tx.currency,
                        provider=deposit_tx.provider,
                        payer_number=assignment.order.seller.phone_number,
                        recipient=assignment.order.seller,
                        recipient_role='seller',
                        trigger_event='pickup_qr',
                        payout_stage='pickup_pending_scan',
                        status='pending',
                    )
                if seller_tx is not None and seller_tx.payout_stage in [
                    'pickup_pending_scan',
                    'ready_for_payout',
                ]:
                    seller_tx.payout_stage = 'ready_for_payout'
                    seller_tx.save(update_fields=['payout_stage', 'updated_at'])
                    payout_resp = PawaPayService.initiate_payout(seller_tx)
                    if payout_resp:
                        seller_tx.payout_stage = (
                            'payout_paid'
                            if seller_tx.status == 'completed'
                            else 'payout_sent'
                        )
                    else:
                        seller_tx.payout_stage = 'payout_failed'
                    seller_tx.save(update_fields=['payout_stage', 'updated_at'])

                rider_tx = Transaction.objects.filter(
                    order=assignment.order,
                    transaction_type='payout',
                    recipient=assignment.delivery_person,
                    recipient_role='delivery',
                    trigger_event='dropoff_qr',
                ).order_by('-created_at').first()
                if rider_tx is None and delivery_fee > 0:
                    Transaction.objects.create(
                        order=assignment.order,
                        transaction_type='payout',
                        amount=delivery_fee,
                        currency=deposit_tx.currency,
                        provider=deposit_tx.provider,
                        payer_number=assignment.delivery_person.phone_number,
                        recipient=assignment.delivery_person,
                        recipient_role='delivery',
                        trigger_event='dropoff_qr',
                        payout_stage='dropoff_pending_scan',
                        status='pending',
                    )

            if step == 'dropoff':
                rider_tx = Transaction.objects.filter(
                    order=assignment.order,
                    transaction_type='payout',
                    recipient=assignment.delivery_person,
                    recipient_role='delivery',
                    trigger_event='dropoff_qr',
                ).order_by('-created_at').first()
                if rider_tx is None and delivery_fee > 0:
                    rider_tx = Transaction.objects.create(
                        order=assignment.order,
                        transaction_type='payout',
                        amount=delivery_fee,
                        currency=deposit_tx.currency,
                        provider=deposit_tx.provider,
                        payer_number=assignment.delivery_person.phone_number,
                        recipient=assignment.delivery_person,
                        recipient_role='delivery',
                        trigger_event='dropoff_qr',
                        payout_stage='dropoff_pending_scan',
                        status='pending',
                    )
                if rider_tx is not None and rider_tx.payout_stage in [
                    'dropoff_pending_scan',
                    'ready_for_payout',
                ]:
                    rider_tx.payout_stage = 'ready_for_payout'
                    rider_tx.save(update_fields=['payout_stage', 'updated_at'])
                    payout_resp = PawaPayService.initiate_payout(rider_tx)
                    if payout_resp:
                        rider_tx.payout_stage = (
                            'payout_paid'
                            if rider_tx.status == 'completed'
                            else 'payout_sent'
                        )
                    else:
                        rider_tx.payout_stage = 'payout_failed'
                    rider_tx.save(update_fields=['payout_stage', 'updated_at'])

        return Response(
            {
                'message': 'Handoff verified',
                'token': DeliveryHandoffTokenSerializer(token).data,
            }
        )


class DeliveryZonesListView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        zones = DeliveryZone.objects.filter(is_active=True).order_by('name')
        return Response(DeliveryZoneSerializer(zones, many=True).data)


class DeliveryPricingConfigView(APIView):
    """
    Public endpoint returning the current delivery pricing variables.
    Used by the app to display 'Delivery from ZMW X' on product pages.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        from .models import DeliveryPricingConfig
        config = DeliveryPricingConfig.get_config()
        return Response({
            'short_distance_threshold_km': float(config.short_distance_threshold_km),
            'short_distance_flat_rate': float(config.short_distance_flat_rate),
            'per_km_rate': float(config.per_km_rate),
        })


class DeliveryQuoteView(APIView):
    """
    Calculate a delivery fee quote using the platform's live pricing config.

    POST body:
        delivery_lat / delivery_lng  — buyer's drop-off coordinates (required)
        pickup_lat   / pickup_lng    — seller's shop coordinates    (optional)
        seller_id                    — if given, auto-resolves pickup from seller profile

    Returns:
        distance_km            — straight-line distance between shop and buyer
        estimated_fee_zmw      — calculated fee in ZMW
        pricing_mode           — 'flat' (short trip) or 'per_km' (long trip)
        short_distance_threshold_km
        short_distance_flat_rate
        per_km_rate
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        from .models import DeliveryPricingConfig
        from .coordinates import resolve_pickup_coordinates

        # --- Resolve delivery (buyer) coordinates ---
        try:
            dlat = float(
                request.data.get('delivery_lat') or request.data.get('lat')
            )
            dlng = float(
                request.data.get('delivery_lng') or request.data.get('lng')
            )
        except (TypeError, ValueError):
            return Response(
                {'error': 'delivery_lat and delivery_lng (or lat/lng) are required'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # --- Resolve pickup (seller) coordinates ---
        plat = request.data.get('pickup_lat')
        plng = request.data.get('pickup_lng')

        # Auto-resolve from seller_id if not provided directly
        if (plat is None or plng is None):
            seller_id = request.data.get('seller_id')
            if seller_id:
                try:
                    from accounts.models import User
                    seller = User.objects.get(pk=seller_id, role='seller')
                    pickup = resolve_pickup_coordinates(seller, allow_fallback=True)
                    if pickup:
                        plat = pickup.get('lat')
                        plng = pickup.get('lng')
                except Exception:
                    pass

        # --- Calculate distance and fee ---
        distance_km = None
        fee = None
        pricing_mode = None
        config = DeliveryPricingConfig.get_config()

        if plat is not None and plng is not None:
            try:
                distance_km = LocationService.calculate_distance(
                    float(plat), float(plng), dlat, dlng
                )
                fee = LocationService.calculate_delivery_fee(distance_km)
                pricing_mode = (
                    'flat'
                    if distance_km <= float(config.short_distance_threshold_km)
                    else 'per_km'
                )
            except (TypeError, ValueError):
                pass

        return Response(
            {
                'distance_km': round(distance_km, 2) if distance_km is not None else None,
                'estimated_fee_zmw': fee,
                'pricing_mode': pricing_mode,
                'short_distance_threshold_km': float(config.short_distance_threshold_km),
                'short_distance_flat_rate': float(config.short_distance_flat_rate),
                'per_km_rate': float(config.per_km_rate),
            }
        )



class DeliveryStatsView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        if request.user.role != 'delivery':
            return Response(
                {'error': 'Only delivery personnel'},
                status=status.HTTP_403_FORBIDDEN,
            )

        agg = DeliveryAssignment.objects.filter(
            delivery_person=request.user, status='delivered'
        ).aggregate(
            n=Count('id'),
            km=Sum('estimated_distance'),
            avg_eta_error=Avg('final_eta_error_minutes'),
            low_conf_routes=Count(
                'id',
                filter=Q(route_confidence__lt=0.55),
            ),
            reroutes=Sum('reroute_count'),
        )
        rider_payouts = Transaction.objects.filter(
            transaction_type='payout',
            recipient=request.user,
            recipient_role='delivery',
        ).order_by('-created_at')[:30]
        payout_rows = [
            {
                'transaction_id': str(tx.transaction_id),
                'order_number': tx.order.order_number,
                'amount': str(tx.amount),
                'currency': tx.currency,
                'status': tx.status,
                'payout_stage': tx.payout_stage,
                'trigger_event': tx.trigger_event,
                'amount_color': (
                    'green'
                    if tx.status == 'completed' and tx.payout_stage == 'payout_paid'
                    else 'orange'
                ),
                'created_at': tx.created_at,
            }
            for tx in rider_payouts
        ]
        payout_total = (
            Transaction.objects.filter(
                transaction_type='payout',
                recipient=request.user,
                recipient_role='delivery',
                status='completed',
            ).aggregate(total=Sum('amount'))['total']
            or 0
        )
        pending_total = (
            Transaction.objects.filter(
                transaction_type='payout',
                recipient=request.user,
                recipient_role='delivery',
            )
            .exclude(status='completed')
            .aggregate(total=Sum('amount'))['total']
            or 0
        )

        return Response(
            {
                'completed_deliveries': agg['n'] or 0,
                'total_estimated_km': float(agg['km'] or 0),
                'avg_eta_error_minutes': float(agg['avg_eta_error'] or 0),
                'low_confidence_routes': agg['low_conf_routes'] or 0,
                'total_reroutes': agg['reroutes'] or 0,
                'delivery_payout_total': str(payout_total),
                'delivery_pending_payouts': str(pending_total),
                'payouts': payout_rows,
            }
        )


class ReverseGeocodeView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        try:
            lat = float(request.GET.get('lat'))
            lng = float(request.GET.get('lng'))
        except (TypeError, ValueError):
            return Response(
                {'error': 'lat and lng are required'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        result = LocationService.reverse_geocode(lat, lng)
        if result is None:
            return Response(
                {'error': 'Could not resolve location name'},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response(result)


class AddressAutocompleteView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        query = request.GET.get('q', '')
        limit = request.GET.get('limit', 5)
        try:
            n = int(limit)
        except (TypeError, ValueError):
            n = 5
        suggestions = LocationService.search_address_suggestions(query, limit=n)
        return Response({'results': suggestions})
