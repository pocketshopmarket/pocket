"""
Transport requests: a buyer too far for normal rider delivery asks the
seller to arrange their own transport (bus/courier), the seller proposes a
method and fee once, and the buyer accepts or lets it expire. See
TransportRequest's docstring in models.py for the full design.
"""
import logging
from datetime import timedelta
from decimal import Decimal

from django.db import transaction as db_transaction
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.permissions import IsBuyer
from delivery.models import DeliveryPricingConfig
from delivery.utils import LocationService
from products.models import Product, product_blocked_for_user

from .models import Order, OrderItem, TransportRequest
from .serializers import (
    CreateTransportRequestSerializer,
    DeclineTransportSerializer,
    OrderSerializer,
    ProposeTransportSerializer,
    TransportRequestSerializer,
)

logger = logging.getLogger(__name__)

RESPONSE_WINDOW = timedelta(hours=24)


class IsSeller(permissions.BasePermission):
    def has_permission(self, request, view):
        return bool(request.user and request.user.is_authenticated and request.user.role == 'seller')


def _notify(user, notification_type, title, message, data_payload):
    try:
        from notifications.signals import _create_notification
        _create_notification(
            recipient=user, notification_type=notification_type,
            title=title, message=message, data_payload=data_payload,
        )
    except Exception:
        logger.exception('Transport request notification failed for user %s', user.id)


class TransportRequestCreateListView(APIView):
    """
    POST — buyer asks the seller to arrange transport for a product that's
    too far for normal delivery.
    GET  — the requesting user's own transport requests (buyer: what they've
    asked for; seller: what's been asked of them), newest first.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        if user.role == 'buyer':
            qs = TransportRequest.objects.filter(buyer=user)
        elif user.role == 'seller':
            qs = TransportRequest.objects.filter(seller=user)
        else:
            return Response({'error': 'Only buyers and sellers use transport requests.'}, status=status.HTTP_403_FORBIDDEN)
        qs = qs.select_related('buyer', 'seller', 'product', 'order')[:200]
        return Response(TransportRequestSerializer(qs, many=True, context={'request': request}).data)

    def post(self, request):
        if request.user.role != 'buyer':
            return Response({'error': 'Only buyers can request transport.'}, status=status.HTTP_403_FORBIDDEN)

        serializer = CreateTransportRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        product = get_object_or_404(Product.objects.select_related('seller__seller_profile'), pk=data['product_id'])
        if not product.is_available:
            return Response({'error': 'This product is not available.'}, status=status.HTTP_400_BAD_REQUEST)
        if product_blocked_for_user(product, request.user):
            return Response({'error': f'{product.name} requires the buyer to be 18+.'}, status=status.HTTP_403_FORBIDDEN)

        shop = getattr(product.seller, 'seller_profile', None)
        if not shop or shop.shop_lat is None or shop.shop_lng is None:
            return Response(
                {'error': "This seller's shop location isn't set, so distance can't be checked."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        distance_km = LocationService.calculate_distance(
            shop.shop_lat, shop.shop_lng, data['delivery_lat'], data['delivery_lng'],
        )
        max_km = float(DeliveryPricingConfig.get_config().max_delivery_distance_km)
        if distance_km <= max_km:
            return Response(
                {'error': 'This seller is within normal delivery range — use regular delivery at checkout instead.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if TransportRequest.objects.filter(
            buyer=request.user, product=product, status__in=['pending', 'proposed'],
        ).exists():
            return Response(
                {'error': 'You already have an open transport request for this product.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        tr = TransportRequest.objects.create(
            buyer=request.user,
            seller=product.seller,
            product=product,
            quantity=data['quantity'],
            delivery_address=data['delivery_address'],
            delivery_lat=data['delivery_lat'],
            delivery_lng=data['delivery_lng'],
            distance_km=distance_km,
            expires_at=timezone.now() + RESPONSE_WINDOW,
        )

        _notify(
            product.seller, 'transport_request', 'New transport request',
            f'A buyer {distance_km:.0f} km away wants {product.name}. Propose how you’d get it to them.',
            {'transport_request_id': tr.id, 'product_id': product.id},
        )
        return Response(TransportRequestSerializer(tr, context={'request': request}).data, status=status.HTTP_201_CREATED)


class TransportRequestProposeView(APIView):
    """POST — the seller proposes a transport method and fee."""
    permission_classes = [permissions.IsAuthenticated, IsSeller]

    def post(self, request, pk):
        tr = get_object_or_404(TransportRequest, pk=pk, seller=request.user)
        if tr.status != 'pending':
            return Response({'error': f'This request is already {tr.get_status_display()}.'}, status=status.HTTP_400_BAD_REQUEST)

        serializer = ProposeTransportSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        tr.proposed_method = serializer.validated_data['method']
        tr.proposed_fee = serializer.validated_data['fee']
        tr.status = 'proposed'
        tr.responded_at = timezone.now()
        tr.save(update_fields=['proposed_method', 'proposed_fee', 'status', 'responded_at', 'updated_at'])

        _notify(
            tr.buyer, 'transport_proposed', 'Transport proposal received',
            f'The seller proposed {tr.proposed_method} for ZMW {tr.proposed_fee}.',
            {'transport_request_id': tr.id},
        )
        return Response(TransportRequestSerializer(tr, context={'request': request}).data)


class TransportRequestDeclineView(APIView):
    """POST — the seller can't fulfil this one."""
    permission_classes = [permissions.IsAuthenticated, IsSeller]

    def post(self, request, pk):
        tr = get_object_or_404(TransportRequest, pk=pk, seller=request.user)
        if tr.status != 'pending':
            return Response({'error': f'This request is already {tr.get_status_display()}.'}, status=status.HTTP_400_BAD_REQUEST)

        serializer = DeclineTransportSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        tr.decline_reason = serializer.validated_data.get('reason', '')
        tr.status = 'declined'
        tr.responded_at = timezone.now()
        tr.save(update_fields=['decline_reason', 'status', 'responded_at', 'updated_at'])

        _notify(
            tr.buyer, 'transport_declined', 'Transport request declined',
            f'The seller can’t fulfil this order.' + (f' {tr.decline_reason}' if tr.decline_reason else ''),
            {'transport_request_id': tr.id},
        )
        return Response(TransportRequestSerializer(tr, context={'request': request}).data)


class TransportRequestAcceptView(APIView):
    """
    POST — the buyer accepts the seller's proposal. Creates a real Order
    (payment_pending, same as any other checkout) using the agreed fee as
    the delivery fee — never recalculated by distance. The buyer then pays
    through the normal payment endpoints, same as any other order.
    """
    permission_classes = [permissions.IsAuthenticated, IsBuyer]

    def post(self, request, pk):
        tr = get_object_or_404(TransportRequest.objects.select_related('product', 'seller'), pk=pk, buyer=request.user)
        if tr.status != 'proposed':
            return Response({'error': f'This request is {tr.get_status_display()}, not awaiting your decision.'}, status=status.HTTP_400_BAD_REQUEST)

        with db_transaction.atomic():
            tr_locked = TransportRequest.objects.select_for_update(of=('self',)).get(pk=tr.pk)
            if tr_locked.status != 'proposed':
                return Response({'error': f'This request is {tr_locked.get_status_display()}, not awaiting your decision.'}, status=status.HTTP_400_BAD_REQUEST)

            product = Product.objects.select_for_update(of=('self',)).select_related('category').get(pk=tr.product_id)
            if not product.is_available:
                return Response({'error': f'{product.name} is no longer available.'}, status=status.HTTP_400_BAD_REQUEST)
            if product_blocked_for_user(product, request.user):
                return Response({'error': f'{product.name} requires the buyer to be 18+.'}, status=status.HTTP_403_FORBIDDEN)
            if product.stock_quantity < tr.quantity:
                return Response(
                    {'error': f'Insufficient stock for {product.name}. Only {product.stock_quantity} left.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            from portal.models import get_buyer_service_fee_rate
            line_total = product.price * tr.quantity
            service_fee_rate = get_buyer_service_fee_rate(line_total)
            service_fee_val = (Decimal(str(line_total)) * service_fee_rate).quantize(Decimal('0.01'))

            order = Order.objects.create(
                buyer=request.user,
                seller=tr.seller,
                total_price=line_total,
                delivery_fee=tr.proposed_fee,
                service_fee=service_fee_val,
                fulfillment_type='delivery',
                delivery_address=tr.delivery_address,
                delivery_lat=tr.delivery_lat,
                delivery_lng=tr.delivery_lng,
                special_instructions=f'Transport arranged via seller proposal: {tr.proposed_method}',
                quoted_distance_km=tr.distance_km,
                payment_method=None,
                payment_provider_snapshot='payment_disabled',
                payment_account_snapshot='payment_disabled',
            )
            OrderItem.objects.create(order=order, product=product, quantity=tr.quantity, price=product.price)

            product.stock_quantity -= tr.quantity
            product.purchases_count += tr.quantity
            if product.stock_quantity <= 0:
                product.stock_quantity = 0
                product.is_available = False
            product.save(update_fields=['stock_quantity', 'is_available', 'purchases_count', 'updated_at'])

            tr_locked.status = 'accepted'
            tr_locked.decided_at = timezone.now()
            tr_locked.order = order
            tr_locked.save(update_fields=['status', 'decided_at', 'order', 'updated_at'])

        return Response(OrderSerializer(order).data, status=status.HTTP_201_CREATED)
