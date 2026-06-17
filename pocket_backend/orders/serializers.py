from rest_framework import serializers
from .models import Cart, CartItem, Order, OrderItem, RefundRequest, CancellationRequest
from .models import OrderRating

class CartItemSerializer(serializers.ModelSerializer):
    product_name = serializers.CharField(source='product.name', read_only=True)
    product_price = serializers.DecimalField(source='product.price', max_digits=10, decimal_places=2, read_only=True)
    seller_id = serializers.IntegerField(source='product.seller_id', read_only=True)
    subtotal = serializers.DecimalField(max_digits=10, decimal_places=2, read_only=True)
    product_image_url = serializers.SerializerMethodField()
    variant_id = serializers.IntegerField(read_only=True)
    variant_label = serializers.SerializerMethodField()

    class Meta:
        model = CartItem
        fields = [
            'id',
            'product',
            'product_name',
            'product_price',
            'seller_id',
            'quantity',
            'subtotal',
            'product_image_url',
            'variant_id',
            'variant_label',
        ]

    def get_product_image_url(self, obj):
        from products.serializers import first_image_url_for_product

        return first_image_url_for_product(obj.product, self.context.get('request'))

    def get_variant_label(self, obj):
        if not obj.variant:
            return ''
        return f'{obj.variant.name}: {obj.variant.value}'

class CartSerializer(serializers.ModelSerializer):
    items = CartItemSerializer(many=True, read_only=True)
    total_price = serializers.DecimalField(max_digits=10, decimal_places=2, read_only=True)
    total_items = serializers.IntegerField(read_only=True)
    
    class Meta:
        model = Cart
        fields = ['id', 'items', 'total_price', 'total_items', 'created_at', 'updated_at']

class OrderItemSerializer(serializers.ModelSerializer):
    product_name = serializers.CharField(source='product.name', read_only=True)
    subtotal = serializers.DecimalField(max_digits=10, decimal_places=2, read_only=True)
    
    class Meta:
        model = OrderItem
        fields = [
            'id',
            'product',
            'product_name',
            'variant',
            'variant_label',
            'quantity',
            'price',
            'subtotal',
        ]

class OrderSerializer(serializers.ModelSerializer):
    items = OrderItemSerializer(many=True, read_only=True)
    buyer_name = serializers.CharField(source='buyer.full_name', read_only=True)
    seller_name = serializers.CharField(source='seller.full_name', read_only=True)
    payment_method_id = serializers.IntegerField(source='payment_method.id', read_only=True)
    delivery_assignment_id = serializers.SerializerMethodField()
    ratings = serializers.SerializerMethodField()
    seller_phone = serializers.SerializerMethodField()
    buyer_phone = serializers.SerializerMethodField()
    seller_shop_name = serializers.SerializerMethodField()
    seller_shop_location = serializers.SerializerMethodField()
    seller_shop_lat = serializers.SerializerMethodField()
    seller_shop_lng = serializers.SerializerMethodField()
    # Expose delivery_fee as quoted_delivery_fee — the fee quoted at order creation time.
    quoted_delivery_fee = serializers.DecimalField(
        source='delivery_fee', max_digits=10, decimal_places=2, read_only=True
    )
    refund_request_status = serializers.SerializerMethodField()

    class Meta:
        model = Order
        fields = ['id', 'order_number', 'buyer', 'buyer_name', 'seller', 'seller_name',
                 'total_price', 'fulfillment_type', 'status',
                 'delivery_address', 'delivery_lat', 'delivery_lng',
                 'quoted_delivery_fee',
                 'pickup_time_slot', 'quoted_distance_km', 'quoted_eta_minutes',
                 'special_instructions', 'payment_method_id',
                 'delivery_assignment_id',
                 'payment_provider_snapshot', 'payment_account_snapshot',
                 'seller_phone', 'buyer_phone',
                 'seller_shop_name', 'seller_shop_location', 'seller_shop_lat', 'seller_shop_lng',
                 'refund_request_status',
                 'items', 'ratings', 'created_at', 'updated_at']
        read_only_fields = ['order_number', 'buyer', 'seller', 'total_price', 'delivery_lat', 'delivery_lng']

    def get_ratings(self, obj):
        return OrderRatingSerializer(obj.ratings.all(), many=True).data

    def get_delivery_assignment_id(self, obj):
        assignment = getattr(obj, 'deliveryassignment', None)
        return getattr(assignment, 'id', None)

    def get_seller_phone(self, obj):
        try:
            return obj.seller.phone_number
        except Exception:
            return None

    def get_buyer_phone(self, obj):
        try:
            request = self.context.get('request')
            viewer = getattr(request, 'user', None)
            if viewer and viewer == obj.buyer:
                return obj.buyer.phone_number
            # Only approved sellers may see the buyer's phone number.
            if viewer and viewer == obj.seller:
                try:
                    if viewer.seller_profile.can_sell:
                        return obj.buyer.phone_number
                except Exception:
                    pass
                return None
            # Riders always need the buyer phone for delivery coordination.
            if viewer and getattr(viewer, 'role', None) == 'delivery':
                return obj.buyer.phone_number
            return None
        except Exception:
            return None

    def get_seller_shop_name(self, obj):
        try:
            return obj.seller.sellerprofile.shop_name
        except Exception:
            return None

    def get_seller_shop_location(self, obj):
        try:
            return obj.seller.sellerprofile.shop_location
        except Exception:
            return None

    def get_seller_shop_lat(self, obj):
        try:
            return obj.seller.sellerprofile.shop_lat
        except Exception:
            return None

    def get_seller_shop_lng(self, obj):
        try:
            return obj.seller.sellerprofile.shop_lng
        except Exception:
            return None

    def get_refund_request_status(self, obj):
        try:
            return obj.refund_request.status
        except Exception:
            return None

class CreateOrderSerializer(serializers.Serializer):
    delivery_address = serializers.CharField(max_length=500)
    special_instructions = serializers.CharField(max_length=500, required=False, allow_blank=True)
    
    def validate(self, attrs):
        user = self.context['request'].user
        cart, _ = Cart.objects.get_or_create(user=user)

        if not cart.items.exists():
            raise serializers.ValidationError("Cart is empty")
        return attrs

class AddToCartSerializer(serializers.Serializer):
    product_id = serializers.IntegerField()
    variant_id = serializers.IntegerField(required=False, allow_null=True)
    quantity = serializers.IntegerField(min_value=1, default=1)


class OrderRatingSerializer(serializers.ModelSerializer):
    author_name = serializers.CharField(source='author.full_name', read_only=True)

    class Meta:
        model = OrderRating
        fields = [
            'id',
            'order',
            'author',
            'author_name',
            'target_role',
            'score',
            'comment',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'order', 'author', 'created_at', 'updated_at']

    def validate_score(self, value):
        if value < 1 or value > 5:
            raise serializers.ValidationError('Score must be between 1 and 5.')
        return value


class RefundRequestSerializer(serializers.ModelSerializer):
    buyer_name = serializers.CharField(source='requested_by.full_name', read_only=True)
    order_number = serializers.CharField(source='order.order_number', read_only=True)
    order_total = serializers.DecimalField(
        source='order.total_price', max_digits=10, decimal_places=2, read_only=True
    )
    status_display = serializers.CharField(source='get_status_display', read_only=True)

    class Meta:
        model = RefundRequest
        fields = [
            'id', 'order', 'order_number', 'order_total',
            'requested_by', 'buyer_name',
            'reason', 'status', 'status_display',
            'seller_note', 'admin_note',
            'created_at', 'updated_at',
        ]
        read_only_fields = [
            'id', 'order', 'requested_by', 'status',
            'seller_note', 'admin_note', 'created_at', 'updated_at',
        ]


class CreateRefundRequestSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=1000)


class SellerRespondRefundSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=['approve', 'reject', 'escalate'])
    note = serializers.CharField(max_length=500, required=False, allow_blank=True)


class AdminRespondRefundSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=['approve', 'reject'])


class CancellationRequestSerializer(serializers.ModelSerializer):
    buyer_name = serializers.CharField(source='requested_by.full_name', read_only=True)
    order_number = serializers.CharField(source='order.order_number', read_only=True)
    order_total = serializers.DecimalField(
        source='order.total_price', max_digits=10, decimal_places=2, read_only=True
    )
    status_display = serializers.CharField(source='get_status_display', read_only=True)

    class Meta:
        model = CancellationRequest
        fields = [
            'id', 'order', 'order_number', 'order_total',
            'requested_by', 'buyer_name',
            'reason', 'status', 'status_display',
            'seller_note', 'admin_note',
            'created_at', 'updated_at',
        ]
        read_only_fields = [
            'id', 'order', 'requested_by', 'status',
            'seller_note', 'admin_note', 'created_at', 'updated_at',
        ]


class CreateCancellationRequestSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=1000)


class SellerRespondCancellationSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=['approve', 'reject', 'escalate'])
    note = serializers.CharField(max_length=500, required=False, allow_blank=True)


class AdminRespondCancellationSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=['approve', 'reject'])
    note = serializers.CharField(max_length=500, required=False, allow_blank=True)
