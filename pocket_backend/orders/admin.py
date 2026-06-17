from django.contrib import admin
from .models import Cart, CartItem, Order, OrderItem, OrderRating, CancellationRequest

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


@admin.register(CancellationRequest)
class CancellationRequestAdmin(admin.ModelAdmin):
    list_display = ['id', 'order', 'requested_by', 'status', 'created_at']
    list_filter = ['status', 'created_at']
    search_fields = ['order__order_number', 'requested_by__phone_number', 'requested_by__full_name']
    readonly_fields = ['order', 'requested_by', 'reason', 'created_at', 'updated_at']
    actions = ['admin_approve', 'admin_reject']

    @admin.action(description='Approve selected cancellation requests (cancel order + refund)')
    def admin_approve(self, request, queryset):
        from orders.services import cancel_order_with_refund
        eligible = queryset.filter(status__in=['escalated', 'rejected_by_seller'])
        for req in eligible:
            req.status = 'approved_by_admin'
            req.admin_note = 'Approved by admin'
            req.save(update_fields=['status', 'admin_note', 'updated_at'])
            cancel_order_with_refund(req.order, reason='Admin approved cancellation request')
        self.message_user(request, f'{eligible.count()} cancellation(s) approved and orders refunded.')

    @admin.action(description='Reject selected cancellation requests')
    def admin_reject(self, request, queryset):
        eligible = queryset.filter(status__in=['escalated', 'rejected_by_seller'])
        eligible.update(status='rejected_by_admin', admin_note='Rejected by admin')
        self.message_user(request, f'{eligible.count()} cancellation(s) rejected.')
