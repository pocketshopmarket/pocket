from django.db import models
from accounts.models import User

# Create your models here.

class Cart(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    def __str__(self):
        return f"Cart for {self.user.phone_number}"
    
    @property
    def total_price(self):
        return sum(item.subtotal for item in self.items.all())
    
    @property
    def total_items(self):
        return sum(item.quantity for item in self.items.all())

class CartItem(models.Model):
    cart = models.ForeignKey(Cart, on_delete=models.CASCADE, related_name='items')
    product = models.ForeignKey('products.Product', on_delete=models.CASCADE)
    variant = models.ForeignKey(
        'products.ProductVariant',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    quantity = models.PositiveIntegerField(default=1)
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        unique_together = ['cart', 'product', 'variant']
    
    @property
    def subtotal(self):
        return self.product.price * self.quantity
    
    def __str__(self):
        return f"{self.quantity} x {self.product.name}"

class Order(models.Model):
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('payment_pending', 'Payment Pending'),
        ('accepted', 'Accepted'),
        ('preparing', 'Preparing'),
        ('out_for_delivery', 'Out for Delivery'),
        ('delivered', 'Delivered'),
        ('cancelled', 'Cancelled'),
    ]
    
    FULFILLMENT_CHOICES = [
        ('delivery', 'Delivery'),
        ('pickup', 'Pickup'),
    ]

    order_number = models.CharField(max_length=20, unique=True)
    buyer = models.ForeignKey(User, on_delete=models.CASCADE, related_name='orders')
    seller = models.ForeignKey(User, on_delete=models.CASCADE, related_name='sales')
    total_price = models.DecimalField(max_digits=10, decimal_places=2)
    delivery_fee = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    service_fee = models.DecimalField(
        max_digits=10, decimal_places=2, default=0,
        help_text='Buyer service fee, snapshotted from PlatformSettings.buyer_service_fee_rate at order creation time.',
    )
    fulfillment_type = models.CharField(
        max_length=10, choices=FULFILLMENT_CHOICES, default='delivery',
    )
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='payment_pending')
    delivery_address = models.TextField()
    delivery_lat = models.FloatField(null=True, blank=True)
    delivery_lng = models.FloatField(null=True, blank=True)
    special_instructions = models.TextField(blank=True)
    payment_method = models.ForeignKey(
        'accounts.BuyerPaymentMethod',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='orders',
    )
    pickup_time_slot = models.CharField(max_length=100, blank=True)
    quoted_distance_km = models.FloatField(null=True, blank=True)
    quoted_eta_minutes = models.PositiveIntegerField(null=True, blank=True)
    payment_provider_snapshot = models.CharField(max_length=64, blank=True)
    payment_account_snapshot = models.CharField(max_length=64, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    @property
    def grand_total(self):
        """Items + delivery fee + service fee — the actual amount the buyer is charged."""
        from decimal import Decimal
        return (
            self.total_price
            + (self.delivery_fee or Decimal('0'))
            + (self.service_fee or Decimal('0'))
        )
    
    class Meta:
        ordering = ['-created_at']
    
    def __str__(self):
        return f"Order {self.order_number} - {self.status}"
    
    def save(self, *args, **kwargs):
        if not self.order_number:
            # Generate unique order number
            import uuid
            self.order_number = f"ORD{uuid.uuid4().hex[:8].upper()}"
        super().save(*args, **kwargs)

class TransportRequest(models.Model):
    """
    A buyer too far for normal rider delivery asking the seller to arrange
    their own transport (e.g. an intercity bus/courier) instead — and the
    seller's reply. Deliberately one-shot: the seller proposes a method and
    a fee once, the buyer accepts or doesn't, no back-and-forth haggling.
    Accepting creates a real Order with that fee as the delivery_fee.

    Doesn't reserve stock while pending — kept simple since this is expected
    to be low-volume; a buyer who accepts a stale request just sees the
    normal "out of stock" error, same as anyone else.
    """
    STATUS_CHOICES = [
        ('pending', 'Waiting for seller'),
        ('proposed', 'Seller proposed'),
        ('accepted', 'Buyer accepted'),
        ('declined', 'Seller declined'),
        ('expired', 'Expired — seller never responded'),
    ]

    buyer = models.ForeignKey(User, on_delete=models.CASCADE, related_name='transport_requests')
    seller = models.ForeignKey(User, on_delete=models.CASCADE, related_name='transport_requests_received')
    product = models.ForeignKey('products.Product', on_delete=models.CASCADE, related_name='transport_requests')
    quantity = models.PositiveIntegerField(default=1)

    delivery_address = models.TextField()
    delivery_lat = models.FloatField(null=True, blank=True)
    delivery_lng = models.FloatField(null=True, blank=True)
    distance_km = models.FloatField(help_text='Straight-line distance from the seller’s shop at request time.')

    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default='pending')

    proposed_method = models.CharField(max_length=200, blank=True, default='')
    proposed_fee = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    decline_reason = models.CharField(max_length=300, blank=True, default='')

    order = models.OneToOneField(
        'orders.Order', null=True, blank=True, on_delete=models.SET_NULL, related_name='transport_request',
    )

    expires_at = models.DateTimeField(help_text='Seller must respond by this time, or the request auto-expires.')
    responded_at = models.DateTimeField(null=True, blank=True, help_text='When the seller proposed or declined.')
    decided_at = models.DateTimeField(null=True, blank=True, help_text='When the buyer accepted (or it expired).')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        constraints = [
            # One live (pending/proposed) request per buyer+product at a time —
            # the "can't ask twice" rule enforced at the database level, not
            # just in the view.
            models.UniqueConstraint(
                fields=['buyer', 'product'],
                condition=models.Q(status__in=['pending', 'proposed']),
                name='one_live_transport_request_per_buyer_product',
            ),
        ]

    def __str__(self):
        return f'{self.product.name} for {self.buyer.full_name} ({self.get_status_display()})'


class OrderItem(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name='items')
    product = models.ForeignKey('products.Product', on_delete=models.CASCADE)
    variant = models.ForeignKey(
        'products.ProductVariant',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    variant_label = models.CharField(max_length=140, blank=True)
    quantity = models.PositiveIntegerField()
    price = models.DecimalField(max_digits=10, decimal_places=2)  # Price at time of order
    
    @property
    def subtotal(self):
        return self.price * self.quantity
    
    def __str__(self):
        return f"{self.quantity} x {self.product.name} in Order {self.order.order_number}"


class RefundRequest(models.Model):
    STATUS_CHOICES = [
        ('pending_seller', 'Pending Seller Review'),
        ('approved_by_seller', 'Approved by Seller'),
        ('rejected_by_seller', 'Rejected by Seller'),
        ('escalated', 'Escalated to Admin'),
        ('approved_by_admin', 'Approved by Admin'),
        ('rejected_by_admin', 'Rejected by Admin'),
        ('refunded', 'Refunded'),
    ]

    order = models.OneToOneField(
        Order, on_delete=models.CASCADE, related_name='refund_request'
    )
    requested_by = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name='refund_requests'
    )
    reason = models.TextField()
    status = models.CharField(
        max_length=30, choices=STATUS_CHOICES, default='pending_seller'
    )
    seller_note = models.TextField(blank=True)
    admin_note = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'RefundRequest {self.order.order_number} [{self.status}]'


class CancellationRequest(models.Model):
    STATUS_CHOICES = [
        ('pending_seller', 'Pending Seller Review'),
        ('approved_by_seller', 'Approved by Seller'),
        ('rejected_by_seller', 'Rejected by Seller'),
        ('escalated', 'Escalated to Admin'),
        ('approved_by_admin', 'Approved by Admin'),
        ('rejected_by_admin', 'Rejected by Admin'),
    ]

    order = models.OneToOneField(
        Order, on_delete=models.CASCADE, related_name='cancellation_request'
    )
    requested_by = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name='cancellation_requests'
    )
    reason = models.TextField()
    status = models.CharField(
        max_length=30, choices=STATUS_CHOICES, default='pending_seller'
    )
    seller_note = models.TextField(blank=True)
    admin_note = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'CancellationRequest {self.order.order_number} [{self.status}]'


class OrderRating(models.Model):
    ROLE_CHOICES = [
        ('buyer_to_rider', 'Buyer to Rider'),
        ('buyer_to_order', 'Buyer to Order Experience'),
        ('rider_to_seller', 'Rider to Seller Pickup'),
    ]

    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name='ratings')
    author = models.ForeignKey(User, on_delete=models.CASCADE, related_name='authored_ratings')
    target_role = models.CharField(max_length=32, choices=ROLE_CHOICES)
    score = models.PositiveSmallIntegerField()
    comment = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        constraints = [
            models.UniqueConstraint(
                fields=['order', 'author', 'target_role'],
                name='uniq_order_author_target_role',
            ),
        ]

    def __str__(self):
        return f"Rating {self.score}/5 for {self.order.order_number}"
