from rest_framework import serializers
from .models import Cart, CartItem, Order, OrderItem
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
    ratings = serializers.SerializerMethodField()
    
    class Meta:
        model = Order
        fields = ['id', 'order_number', 'buyer', 'buyer_name', 'seller', 'seller_name',
                 'total_price', 'status', 'delivery_address', 'delivery_lat', 'delivery_lng',
                 'special_instructions', 'payment_method_id',
                 'payment_provider_snapshot', 'payment_account_snapshot',
                 'items', 'ratings', 'created_at', 'updated_at']
        read_only_fields = ['order_number', 'buyer', 'seller', 'total_price', 'delivery_lat', 'delivery_lng']

    def get_ratings(self, obj):
        return OrderRatingSerializer(obj.ratings.all(), many=True).data

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
