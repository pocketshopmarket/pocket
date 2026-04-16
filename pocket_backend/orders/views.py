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
from .models import Cart, CartItem, Order, OrderItem
from .serializers import (
    CartSerializer,
    OrderSerializer,
    CreateOrderSerializer,
    AddToCartSerializer,
    OrderRatingSerializer,
)
from products.models import Product, ProductImage, ProductVariant
from delivery.coordinates import resolve_delivery_coordinates
from delivery.utils import create_delivery_offers_for_order
from delivery.models import DeliveryAssignment
from .models import OrderRating
from accounts.permissions import IsBuyer


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
                    if cart_item.variant and cart_item.variant.stock_quantity < cart_item.quantity:
                        return Response(
                            {
                                'error': (
                                    f'Insufficient stock for variant '
                                    f'{cart_item.variant.name}: {cart_item.variant.value}. '
                                    f'Only {cart_item.variant.stock_quantity} left.'
                                )
                            },
                            status=status.HTTP_400_BAD_REQUEST,
                        )
                    line_total += product.price * cart_item.quantity

                # Create order after stock validation passes.
                order = Order.objects.create(
                    buyer=request.user,
                    seller=cart_items[0].product.seller,
                    total_price=line_total,
                    delivery_address=delivery_address,
                    special_instructions=special_instructions,
                    payment_method=None,
                    payment_provider_snapshot='payment_disabled',
                    payment_account_snapshot='payment_disabled',
                )

                for cart_item in cart_items:
                    product = locked_products[cart_item.product_id]
                    OrderItem.objects.create(
                        order=order,
                        product=product,
                        variant=cart_item.variant,
                        variant_label=(
                            f'{cart_item.variant.name}: {cart_item.variant.value}'
                            if cart_item.variant
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
                    if cart_item.variant:
                        cart_item.variant.stock_quantity = max(
                            cart_item.variant.stock_quantity - cart_item.quantity,
                            0,
                        )
                        if cart_item.variant.stock_quantity <= 0:
                            cart_item.variant.is_active = False
                        cart_item.variant.save(
                            update_fields=['stock_quantity', 'is_active', 'updated_at']
                        )

                # Clear cart only after successful order creation.
                cart.items.all().delete()

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
            orders = request.user.sales.all()
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
        if not seller_profile or not seller_profile.is_approved:
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
                'pending': ['accepted', 'cancelled'],
                'accepted': ['preparing', 'cancelled'],
                'preparing': ['out_for_delivery'],
                # Rider marks delivered via delivery assignment flow.
                'out_for_delivery': [],
                'delivered': [],
                'cancelled': []
            }
            
            if new_status not in valid_transitions.get(current_status, []):
                return Response({'error': f'Cannot transition from {current_status} to {new_status}'}, status=status.HTTP_400_BAD_REQUEST)
            
            order.status = new_status
            order.save()
            if new_status == 'out_for_delivery':
                create_delivery_offers_for_order(order)
            
            serializer = OrderSerializer(order)
            return Response(serializer.data)
            
        except Order.DoesNotExist:
            return Response({'error': 'Order not found'}, status=status.HTTP_404_NOT_FOUND)


class SellerDashboardStatsView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        if request.user.role != 'seller':
            return Response(
                {'error': 'Only sellers can access dashboard stats'},
                status=status.HTTP_403_FORBIDDEN,
            )
        seller_profile = getattr(request.user, 'seller_profile', None)
        if not seller_profile or not seller_profile.is_approved:
            return Response(
                {'error': 'Seller approval is required'},
                status=status.HTTP_403_FORBIDDEN,
            )

        orders = Order.objects.filter(seller=request.user)
        orders_count = orders.count()
        delivered_count = orders.filter(status='delivered').count()
        pending_count = orders.filter(status='pending').count()
        revenue = orders.filter(status='delivered').aggregate(
            total=Sum('total_price')
        )['total'] or 0
        low_stock_products = Product.objects.filter(
            seller=request.user,
            stock_quantity__lte=5
        ).count()

        recent_orders = orders.select_related('buyer').order_by('-created_at')[:5]
        seven_days_ago = timezone.now() - timedelta(days=6)
        trend_rows = (
            orders.filter(created_at__gte=seven_days_ago)
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

        return Response(
            {
                'metrics': {
                    'orders_count': orders_count,
                    'delivered_count': delivered_count,
                    'pending_count': pending_count,
                    'revenue': str(revenue),
                    'low_stock_products': low_stock_products,
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
