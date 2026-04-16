from django.contrib import admin
from .models import Cart, CartItem, Order, OrderItem, OrderRating

@admin.register(Cart)
class CartAdmin(admin.ModelAdmin):
    list_display = ['user', 'total_items', 'created_at']
    search_fields = ['user__phone_number', 'user__full_name']
    readonly_fields = ['created_at', 'updated_at']

@admin.register(CartItem)
class CartItemAdmin(admin.ModelAdmin):
    list_display = ['cart', 'product', 'variant', 'quantity', 'subtotal']
    list_filter = ['created_at']
    search_fields = ['product__name', 'cart__user__phone_number']

@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    list_display = ['order_number', 'buyer', 'seller', 'total_price', 'status', 'created_at']
    list_filter = ['status', 'created_at']
    search_fields = ['order_number', 'buyer__phone_number', 'seller__phone_number']
    readonly_fields = ['order_number', 'created_at', 'updated_at']
    
    def get_readonly_fields(self, request, obj=None):
        if obj:  # editing an existing object
            return self.readonly_fields + ['total_price', 'buyer', 'seller']
        return self.readonly_fields

@admin.register(OrderItem)
class OrderItemAdmin(admin.ModelAdmin):
    list_display = ['order', 'product', 'variant_label', 'quantity', 'price', 'subtotal']
    search_fields = ['order__order_number', 'product__name']
    readonly_fields = ['order', 'product', 'quantity', 'price']


@admin.register(OrderRating)
class OrderRatingAdmin(admin.ModelAdmin):
    list_display = ['id', 'order', 'author', 'target_role', 'score', 'created_at']
    list_filter = ['target_role', 'score', 'created_at']
    search_fields = ['order__order_number', 'author__phone_number', 'author__full_name']
