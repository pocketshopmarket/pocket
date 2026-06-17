from rest_framework import status, permissions
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework.views import APIView
from django.db import transaction
from django.db.models import Prefetch, Sum, Count, F, DecimalField, ExpressionWrapper
from django.db.models.functions import TruncDate
from django.utils import timezone
from datetime import timedelta
from django.shortcuts import get_object_or_404
from .models import Cart, CartItem, Order, OrderItem, RefundRequest, CancellationRequest
from .serializers import (
    CartSerializer,
    OrderSerializer,
    CreateOrderSerializer,
    AddToCartSerializer,
    OrderRatingSerializer,
    RefundRequestSerializer,
    CreateRefundRequestSerializer,
    SellerRespondRefundSerializer,
    AdminRespondRefundSerializer,
    CancellationRequestSerializer,
    CreateCancellationRequestSerializer,
    SellerRespondCancellationSerializer,
    AdminRespondCancellationSerializer,
)
from products.models import Product, ProductImage, ProductVariant
from delivery.coordinates import resolve_delivery_coordinates
from delivery.utils import create_delivery_offers_for_order
from delivery.models import DeliveryAssignment
from payments.models import Transaction
from payments.services.pawapay import PawaPayService
from .models import OrderRating
from accounts.permissions import IsBuyer
from .services import cancel_order_with_refund


def _cart_for_api(cart):
    return (
        Cart.objects.prefetch_related(
            Prefetch(
                'items',
                queryset=CartItem.objects.select_related('product').prefetch_related(
                    Prefetch(
                        'product__gallery_images',
                        queryset=ProductImage.objects.order_by('sort_order', 'id'),
                    ),
                ),
            ),
        ).get(pk=cart.pk)
    )


class CartView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsBuyer]
    
    def get(self, request):
        cart, created = Cart.objects.get_or_create(user=request.user)
        cart = _cart_for_api(cart)
        serializer = CartSerializer(cart, context={'request': request})
        return Response(serializer.data)
    
    def post(self, request):
        # Add item to cart
        serializer = AddToCartSerializer(data=request.data)
        if serializer.is_valid():
            product_id = serializer.validated_data['product_id']
            variant_id = serializer.validated_data.get('variant_id')
            quantity = serializer.validated_data['quantity']
            
            try:
                product = Product.objects.get(id=product_id, is_available=True)
                cart, created = Cart.objects.get_or_create(user=request.user)
                variant = None
                if variant_id:
                    variant = ProductVariant.objects.filter(
                        id=variant_id,
                        product_id=product_id,
                        is_active=True,
                    ).first()
                    if variant is None:
                        return Response(
                            {'error': 'Variant not found'},
                            status=status.HTTP_404_NOT_FOUND,
                        )
                
                cart_item, created = CartItem.objects.get_or_create(
                    cart=cart,
                    product=product,
                    variant=variant,
                    defaults={'quantity': quantity}
                )
                
                if not created:
                    cart_item.quantity += quantity
                    cart_item.save()
                
                cart = _cart_for_api(cart)
                serializer = CartSerializer(cart, context={'request': request})
                return Response(serializer.data)
                
            except Product.DoesNotExist:
                return Response({'error': 'Product not found'}, status=status.HTTP_404_NOT_FOUND)
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

class CartItemDetailView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsBuyer]
    
    def put(self, request, item_id):
        # Update cart item quantity
        try:
            cart_item = CartItem.objects.get(id=item_id, cart__user=request.user)
            cart = cart_item.cart
            quantity = request.data.get('quantity', 1)
            
            if quantity > 0:
                cart_item.quantity = quantity
                cart_item.save()
            else:
                cart_item.delete()
            
            cart = _cart_for_api(cart)
            serializer = CartSerializer(cart, context={'request': request})
            return Response(serializer.data)
            
        except CartItem.DoesNotExist:
            return Response({'error': 'Cart item not found'}, status=status.HTTP_404_NOT_FOUND)
    
    def delete(self, request, item_id):
        # Remove item from cart
        try:
            cart_item = CartItem.objects.get(id=item_id, cart__user=request.user)
            cart = cart_item.cart
            cart_item.delete()
            
            cart = _cart_for_api(cart)
            serializer = CartSerializer(cart, context={'request': request})
            return Response(serializer.data)
            
        except CartItem.DoesNotExist:
            return Response({'error': 'Cart item not found'}, status=status.HTTP_404_NOT_FOUND)

class CreateOrderView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsBuyer]
    
    def post(self, request):
        serializer = CreateOrderSerializer(data=request.data, context={'request': request})
        if serializer.is_valid():
            cart, _ = Cart.objects.get_or_create(user=request.user)
            delivery_address = serializer.validated_data['delivery_address']
            special_instructions = serializer.validated_data.get('special_instructions', '')

            cart_items = list(cart.items.select_related('product').all())
            if not cart_items:
                return Response({'error': 'Cart is empty'}, status=status.HTTP_400_BAD_REQUEST)

            seller_ids = {item.product.seller_id for item in cart_items}
            if len(seller_ids) > 1:
                return Response(
                    {
                        'error': 'Your cart contains products from multiple sellers. '
                        'Remove items so all products are from one shop, then checkout again.'
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

            with transaction.atomic():
                # Lock products to prevent concurrent overselling.
                locked_products = {
                    p.id: p
                    for p in Product.objects.select_for_update().filter(
                        id__in=[item.product_id for item in cart_items]
                    )
                }
                # Lock variants to prevent concurrent overselling of the same variant.
                variant_ids = [item.variant_id for item in cart_items if item.variant_id]
                locked_variants = {
                    v.id: v
                    for v in ProductVariant.objects.select_for_update().filter(
                        id__in=variant_ids
                    )
                } if variant_ids else {}

                line_total = 0
                for cart_item in cart_items:
                    product = locked_products.get(cart_item.product_id)
                    if not product or not product.is_available:
                        return Response(
                            {'error': f'Product {cart_item.product_id} is not available'},
                            status=status.HTTP_400_BAD_REQUEST,
                        )
                    if product.stock_quantity < cart_item.quantity:
                        return Response(
                            {
                                'error': (
                                    f'Insufficient stock for {product.name}. '
                                    f'Only {product.stock_quantity} left.'
                                )
                            },
                            status=status.HTTP_400_BAD_REQUEST,
                        )
                    variant = locked_variants.get(cart_item.variant_id) if cart_item.variant_id else None
                    if variant and variant.stock_quantity < cart_item.quantity:
                        return Response(
                            {
                                'error': (
                                    f'Insufficient stock for variant '
                                    f'{variant.name}: {variant.value}. '
                                    f'Only {variant.stock_quantity} left.'
                                )
                            },
                            status=status.HTTP_400_BAD_REQUEST,
                        )
                    line_total += product.price * cart_item.quantity

                # ---------- Delivery fee (server-side validated) ----------
                import json as _json
                fulfillment_type = 'delivery'
                server_delivery_fee = 0
                raw_instructions = special_instructions
                # Parse PS_META from special_instructions if present.
                meta_start = raw_instructions.find('[PS_META]')
                meta_end = raw_instructions.find('[/PS_META]')
                ps_meta = {}
                if meta_start != -1 and meta_end != -1 and meta_end > meta_start:
                    try:
                        ps_meta = _json.loads(
                            raw_instructions[meta_start + len('[PS_META]'):meta_end].strip()
                        )
                    except _json.JSONDecodeError:
                        pass
                    fulfillment_type = ps_meta.get('fulfillment_type', 'delivery')

                if fulfillment_type == 'delivery':
                    dlat = ps_meta.get('delivery_lat')
                    dlng = ps_meta.get('delivery_lng')
                    if dlat is not None and dlng is not None:
                        from delivery.utils import LocationService
                        from accounts.models import SellerProfile
                        try:
                            # Resolve seller shop coordinates.
                            seller_id = cart_items[0].product.seller_id
                            sp = SellerProfile.objects.filter(user_id=seller_id).first()
                            if sp and sp.shop_lat and sp.shop_lng:
                                distance_km = LocationService.calculate_distance(
                                    sp.shop_lat, sp.shop_lng,
                                    float(dlat), float(dlng),
                                )
                                server_delivery_fee = LocationService.calculate_delivery_fee(distance_km)
                            else:
                                # No seller coords — trust client as fallback.
                                server_delivery_fee = ps_meta.get('quoted_delivery_fee', 0)
                        except Exception:
                            server_delivery_fee = ps_meta.get('quoted_delivery_fee', 0)
                    else:
                        server_delivery_fee = ps_meta.get('quoted_delivery_fee', 0)

                from decimal import Decimal as _Decimal
                delivery_fee_val = _Decimal(str(server_delivery_fee or 0))

                # Create order after stock validation passes.
                order = Order.objects.create(
                    buyer=request.user,
                    seller=cart_items[0].product.seller,
                    total_price=line_total,
                    delivery_fee=delivery_fee_val,
                    fulfillment_type=fulfillment_type,
                    delivery_address=delivery_address,
                    special_instructions=special_instructions,
                    payment_method=None,
                    payment_provider_snapshot='payment_disabled',
                    payment_account_snapshot='payment_disabled',
                )

                for cart_item in cart_items:
                    product = locked_products[cart_item.product_id]
                    variant = locked_variants.get(cart_item.variant_id) if cart_item.variant_id else None
                    OrderItem.objects.create(
                        order=order,
                        product=product,
                        variant=variant,
                        variant_label=(
                            f'{variant.name}: {variant.value}'
                            if variant
                            else ''
                        ),
                        quantity=cart_item.quantity,
                        price=product.price
                    )
                    product.stock_quantity -= cart_item.quantity
                    product.purchases_count += cart_item.quantity
                    if product.stock_quantity <= 0:
                        product.stock_quantity = 0
                        product.is_available = False
                    product.save(
                        update_fields=[
                            'stock_quantity',
                            'is_available',
                            'purchases_count',
                            'updated_at',
                        ]
                    )
                    if variant:
                        variant.stock_quantity = max(
                            variant.stock_quantity - cart_item.quantity,
                            0,
                        )
                        if variant.stock_quantity <= 0:
                            variant.is_active = False
                        variant.save(
                            update_fields=['stock_quantity', 'is_active', 'updated_at']
                        )

                # Clear cart only after successful order creation.
                cart.items.all().delete()

            if order.fulfillment_type != 'pickup':
                resolve_delivery_coordinates(order)

            serializer = OrderSerializer(order)
            return Response(serializer.data, status=status.HTTP_201_CREATED)
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

class OrderListView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    def get(self, request):
        # Get orders based on user role
        if request.user.role == 'buyer':
            orders = request.user.orders.all()
        elif request.user.role == 'seller':
            # Only show orders where payment has been confirmed.
            orders = request.user.sales.exclude(status='payment_pending')
        else:
            return Response({'error': 'Unauthorized'}, status=status.HTTP_403_FORBIDDEN)
        
        serializer = OrderSerializer(orders, many=True)
        return Response(serializer.data)

class OrderDetailView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    def get(self, request, order_id):
        try:
            if request.user.role == 'buyer':
                order = request.user.orders.get(id=order_id)
            elif request.user.role == 'seller':
                order = request.user.sales.get(id=order_id)
            else:
                return Response({'error': 'Unauthorized'}, status=status.HTTP_403_FORBIDDEN)
            
            serializer = OrderSerializer(order)
            return Response(serializer.data)
            
        except Order.DoesNotExist:
            return Response({'error': 'Order not found'}, status=status.HTTP_404_NOT_FOUND)

class UpdateOrderStatusView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    
    def put(self, request, order_id):
        # Only sellers can update order status
        if request.user.role != 'seller':
            return Response({'error': 'Only sellers can update order status'}, status=status.HTTP_403_FORBIDDEN)
        seller_profile = getattr(request.user, 'seller_profile', None)
        if not seller_profile or not seller_profile.can_sell:
            return Response(
                {'error': 'Seller approval is required'},
                status=status.HTTP_403_FORBIDDEN,
            )
        
        try:
            order = request.user.sales.get(id=order_id)
            new_status = request.data.get('status')
            
            if new_status not in dict(Order.STATUS_CHOICES):
                return Response({'error': 'Invalid status'}, status=status.HTTP_400_BAD_REQUEST)
            
            # Validate status flow
            current_status = order.status
            valid_transitions = {
                'pending': ['accepted', 'payment_pending', 'cancelled'],
                'payment_pending': ['accepted', 'cancelled'],
                'accepted': ['preparing', 'cancelled'],
                'preparing': ['out_for_delivery'],
                # Rider marks delivered via delivery assignment flow for 'delivery'.
                # Seller marks delivered for 'pickup'.
                'out_for_delivery': ['delivered'] if order.fulfillment_type == 'pickup' else [],
                'delivered': [],
                'cancelled': []
            }
            
            if new_status not in valid_transitions.get(current_status, []):
                return Response({'error': f'Cannot transition from {current_status} to {new_status}'}, status=status.HTTP_400_BAD_REQUEST)
            
            order.status = new_status
            order.save()
            if new_status == 'out_for_delivery' and order.fulfillment_type == 'delivery':
                create_delivery_offers_for_order(order)
            elif new_status == 'cancelled':
                # Use the shared cancel service (handles refund + stock restore).
                cancel_order_with_refund(
                    order, reason='Seller cancelled order'
                )
            
            serializer = OrderSerializer(order)
            return Response(serializer.data)
            
        except Order.DoesNotExist:
            return Response({'error': 'Order not found'}, status=status.HTTP_404_NOT_FOUND)


class BuyerCancelOrderView(APIView):
    """
    Allow buyers to cancel their own orders while the seller hasn't
    started preparing yet (status in 'pending' or 'accepted').
    Automatically refunds the buyer if they already paid.
    """
    permission_classes = [permissions.IsAuthenticated, IsBuyer]

    def post(self, request, order_id):
        try:
            order = request.user.orders.get(id=order_id)
        except Order.DoesNotExist:
            return Response(
                {'error': 'Order not found'},
                status=status.HTTP_404_NOT_FOUND,
            )

        # Buyers can only cancel before the seller starts preparing.
        if order.status not in ('pending', 'payment_pending', 'accepted'):
            return Response(
                {
                    'error': (
                        f'Cannot cancel — order is already "{order.get_status_display()}". '
                        'Contact support if you need help.'
                    )
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        ok = cancel_order_with_refund(
            order, reason='Buyer cancelled order'
        )
        if not ok:
            return Response(
                {'error': 'Order could not be cancelled. Please try again.'},
                status=status.HTTP_409_CONFLICT,
            )

        order.refresh_from_db()
        serializer = OrderSerializer(order)
        return Response(serializer.data)


class SellerDashboardStatsView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        if request.user.role != 'seller':
            return Response(
                {'error': 'Only sellers can access dashboard stats'},
                status=status.HTTP_403_FORBIDDEN,
            )
        seller_profile = getattr(request.user, 'seller_profile', None)
        if not seller_profile or not seller_profile.can_sell:
            return Response(
                {'error': 'Seller approval is required'},
                status=status.HTTP_403_FORBIDDEN,
            )

        try:
            days = max(1, min(365, int(request.query_params.get('days', 7))))
        except (ValueError, TypeError):
            days = 7

        orders = Order.objects.filter(seller=request.user)
        cutoff = timezone.now() - timedelta(days=days - 1)
        orders_in_range = orders.filter(created_at__gte=cutoff)
        orders_count = orders_in_range.count()
        delivered_count = orders_in_range.filter(status='delivered').count()
        pending_count = orders_in_range.filter(status='pending').count()
        revenue = orders_in_range.filter(status='delivered').aggregate(
            total=Sum('total_price')
        )['total'] or 0
        low_stock_products = Product.objects.filter(
            seller=request.user,
            stock_quantity__lte=5
        ).count()

        recent_orders = orders.select_related('buyer').order_by('-created_at')[:5]
        trend_rows = (
            orders_in_range
            .annotate(day=TruncDate('created_at'))
            .values('day')
            .annotate(
                orders_count=Count('id'),
                revenue=Sum('total_price'),
            )
            .order_by('day')
        )
        trends = [
            {
                'day': row['day'].isoformat(),
                'orders_count': row['orders_count'],
                'revenue': str(row['revenue'] or 0),
            }
            for row in trend_rows
        ]
        top_products = (
            Product.objects.filter(orderitem__order__seller=request.user)
            .values('id', 'name')
            .annotate(
                units_sold=Sum('orderitem__quantity'),
                revenue=Sum(
                    ExpressionWrapper(
                        F('orderitem__quantity') * F('orderitem__price'),
                        output_field=DecimalField(max_digits=12, decimal_places=2),
                    )
                ),
            )
            .order_by('-units_sold')[:5]
        )
        seller_payouts = Transaction.objects.filter(
            transaction_type='payout',
            recipient=request.user,
            recipient_role='seller',
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
            for tx in seller_payouts
        ]
        payout_total = (
            Transaction.objects.filter(
                transaction_type='payout',
                recipient=request.user,
                recipient_role='seller',
                status='completed',
            ).aggregate(total=Sum('amount'))['total']
            or 0
        )
        payout_pending = (
            Transaction.objects.filter(
                transaction_type='payout',
                recipient=request.user,
                recipient_role='seller',
            )
            .exclude(status='completed')
            .aggregate(total=Sum('amount'))['total']
            or 0
        )

        return Response(
            {
                'days': days,
                'metrics': {
                    'orders_count': orders_count,
                    'delivered_count': delivered_count,
                    'pending_count': pending_count,
                    'revenue': str(revenue),
                    'low_stock_products': low_stock_products,
                    'seller_payout_total': str(payout_total),
                    'seller_pending_payouts': str(payout_pending),
                },
                'recent_orders': OrderSerializer(recent_orders, many=True).data,
                'trends': trends,
                'top_products': [
                    {
                        'id': row['id'],
                        'name': row['name'],
                        'units_sold': row['units_sold'] or 0,
                        'revenue': str(row['revenue'] or 0),
                    }
                    for row in top_products
                ],
                'payouts': payout_rows,
            }
        )


class OrderRatingListCreateView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, order_id):
        order = get_object_or_404(Order, id=order_id)
        if request.user.id not in [order.buyer_id, order.seller_id] and request.user.role != 'delivery':
            return Response({'error': 'Unauthorized'}, status=status.HTTP_403_FORBIDDEN)
        ratings = OrderRating.objects.filter(order=order)
        return Response(OrderRatingSerializer(ratings, many=True).data)

    def post(self, request, order_id):
        order = get_object_or_404(Order, id=order_id)
        if order.status != 'delivered':
            return Response(
                {'error': 'Ratings are allowed only after delivery'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        serializer = OrderRatingSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        target_role = serializer.validated_data['target_role']
        user = request.user
        allowed = (
            (target_role in ['buyer_to_rider', 'buyer_to_order'] and user.id == order.buyer_id)
            or (
                target_role == 'rider_to_seller'
                and user.role == 'delivery'
                and DeliveryAssignment.objects.filter(
                    order=order, delivery_person=user
                ).exists()
            )
        )
        if not allowed:
            return Response(
                {'error': 'You cannot submit this rating type for this order'},
                status=status.HTTP_403_FORBIDDEN,
            )

        rating, created = OrderRating.objects.update_or_create(
            order=order,
            author=user,
            target_role=target_role,
            defaults={
                'score': serializer.validated_data['score'],
                'comment': serializer.validated_data.get('comment', ''),
            },
        )
        code = status.HTTP_201_CREATED if created else status.HTTP_200_OK
        return Response(OrderRatingSerializer(rating).data, status=code)


class RefundRequestCreateView(APIView):
    """Buyer creates a refund request for a delivered order."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, order_id):
        order = get_object_or_404(Order, id=order_id, buyer=request.user)
        if order.status != 'delivered':
            return Response(
                {'error': 'Refund requests can only be made for delivered orders.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if hasattr(order, 'refund_request'):
            return Response(
                {'error': 'A refund request already exists for this order.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = CreateRefundRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        refund = RefundRequest.objects.create(
            order=order,
            requested_by=request.user,
            reason=serializer.validated_data['reason'],
        )
        return Response(
            RefundRequestSerializer(refund).data,
            status=status.HTTP_201_CREATED,
        )

    def get(self, request, order_id):
        order = get_object_or_404(Order, id=order_id)
        user = request.user
        if user != order.buyer and user != order.seller and user.role != 'admin':
            return Response(status=status.HTTP_403_FORBIDDEN)
        try:
            refund = order.refund_request
        except RefundRequest.DoesNotExist:
            return Response({'detail': 'No refund request.'}, status=status.HTTP_404_NOT_FOUND)
        return Response(RefundRequestSerializer(refund).data)


class RefundRequestListView(APIView):
    """List refund requests filtered by the caller's role."""
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        if user.role == 'buyer':
            qs = RefundRequest.objects.filter(requested_by=user)
        elif user.role == 'seller':
            qs = RefundRequest.objects.filter(order__seller=user)
        elif user.role == 'admin' or user.is_staff:
            qs = RefundRequest.objects.all()
        else:
            return Response(status=status.HTTP_403_FORBIDDEN)
        return Response(RefundRequestSerializer(qs, many=True).data)


class RefundRequestRespondView(APIView):
    """Seller approves / rejects / escalates. Admin approves / rejects."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        refund = get_object_or_404(RefundRequest, pk=pk)
        user = request.user

        if user.role == 'seller' and refund.order.seller == user:
            if refund.status != 'pending_seller':
                return Response(
                    {'error': 'Already responded.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            serializer = SellerRespondRefundSerializer(data=request.data)
            serializer.is_valid(raise_exception=True)
            action = serializer.validated_data['action']
            note = serializer.validated_data.get('note', '')
            mapping = {
                'approve': 'approved_by_seller',
                'reject': 'rejected_by_seller',
                'escalate': 'escalated',
            }
            refund.status = mapping[action]
            refund.seller_note = note
            refund.save(update_fields=['status', 'seller_note', 'updated_at'])
            if action == 'approve':
                cancel_order_with_refund(refund.order, reason='Seller approved refund request')

        elif user.role == 'admin' or user.is_staff:
            if refund.status not in ('escalated', 'rejected_by_seller'):
                return Response(
                    {'error': 'Not available for admin action at this stage.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            serializer = AdminRespondRefundSerializer(data=request.data)
            serializer.is_valid(raise_exception=True)
            action = serializer.validated_data['action']
            note = serializer.validated_data.get('note', '')
            mapping = {'approve': 'approved_by_admin', 'reject': 'rejected_by_admin'}
            refund.status = mapping[action]
            refund.admin_note = note
            refund.save(update_fields=['status', 'admin_note', 'updated_at'])
            if action == 'approve':
                cancel_order_with_refund(refund.order, reason='Admin approved refund request')
        else:
            return Response(status=status.HTTP_403_FORBIDDEN)

        return Response(RefundRequestSerializer(refund).data)


class CancellationRequestCreateView(APIView):
    """Buyer requests cancellation of an accepted order — seller must review."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, order_id):
        order = get_object_or_404(Order, id=order_id, buyer=request.user)
        if order.status != 'accepted':
            return Response(
                {'error': 'Cancellation requests can only be made for accepted orders.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if hasattr(order, 'cancellation_request'):
            return Response(
                {'error': 'A cancellation request already exists for this order.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = CreateCancellationRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        req = CancellationRequest.objects.create(
            order=order,
            requested_by=request.user,
            reason=serializer.validated_data['reason'],
        )
        return Response(CancellationRequestSerializer(req).data, status=status.HTTP_201_CREATED)

    def get(self, request, order_id):
        order = get_object_or_404(Order, id=order_id)
        user = request.user
        if user != order.buyer and user != order.seller and user.role != 'admin':
            return Response(status=status.HTTP_403_FORBIDDEN)
        try:
            req = order.cancellation_request
        except CancellationRequest.DoesNotExist:
            return Response({'detail': 'No cancellation request.'}, status=status.HTTP_404_NOT_FOUND)
        return Response(CancellationRequestSerializer(req).data)


class CancellationRequestListView(APIView):
    """List cancellation requests filtered by the caller's role."""
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        if user.role == 'buyer':
            qs = CancellationRequest.objects.filter(requested_by=user)
        elif user.role == 'seller':
            qs = CancellationRequest.objects.filter(order__seller=user)
        elif user.role == 'admin' or user.is_staff:
            qs = CancellationRequest.objects.all()
        else:
            return Response(status=status.HTTP_403_FORBIDDEN)
        return Response(CancellationRequestSerializer(qs, many=True).data)


class CancellationRequestRespondView(APIView):
    """Seller approves / rejects / escalates. Admin approves / rejects."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        req = get_object_or_404(CancellationRequest, pk=pk)
        user = request.user

        if user.role == 'seller' and req.order.seller == user:
            if req.status != 'pending_seller':
                return Response(
                    {'error': 'Already responded.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            serializer = SellerRespondCancellationSerializer(data=request.data)
            serializer.is_valid(raise_exception=True)
            action = serializer.validated_data['action']
            note = serializer.validated_data.get('note', '')
            mapping = {
                'approve': 'approved_by_seller',
                'reject': 'rejected_by_seller',
                'escalate': 'escalated',
            }
            req.status = mapping[action]
            req.seller_note = note
            req.save(update_fields=['status', 'seller_note', 'updated_at'])
            if action == 'approve':
                cancel_order_with_refund(req.order, reason='Seller approved cancellation request')

        elif user.role == 'admin' or user.is_staff:
            if req.status not in ('escalated', 'rejected_by_seller'):
                return Response(
                    {'error': 'Not available for admin action at this stage.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            serializer = AdminRespondCancellationSerializer(data=request.data)
            serializer.is_valid(raise_exception=True)
            action = serializer.validated_data['action']
            note = serializer.validated_data.get('note', '')
            mapping = {'approve': 'approved_by_admin', 'reject': 'rejected_by_admin'}
            req.status = mapping[action]
            req.admin_note = note
            req.save(update_fields=['status', 'admin_note', 'updated_at'])
            if action == 'approve':
                cancel_order_with_refund(req.order, reason='Admin approved cancellation request')
        else:
            return Response(status=status.HTTP_403_FORBIDDEN)

        return Response(CancellationRequestSerializer(req).data)
