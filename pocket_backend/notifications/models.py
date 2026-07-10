from django.db import models
from accounts.models import User


class Notification(models.Model):
    """In-app notification stored per-user."""

    TYPE_CHOICES = [
        ('order_placed', 'New Order Placed'),
        ('order_accepted', 'Order Accepted'),
        ('order_preparing', 'Order Being Prepared'),
        ('order_ready', 'Order Ready for Pickup'),
        ('order_out_for_delivery', 'Order Out for Delivery'),
        ('order_delivered', 'Order Delivered'),
        ('order_cancelled', 'Order Cancelled'),
        ('payment_pending', 'Payment Pending'),
        ('payment_completed', 'Payment Completed'),
        ('payment_failed', 'Payment Failed'),
        ('payout_completed', 'Payout Completed'),
        ('payout_processing', 'Payout Processing'),
        ('refund_completed', 'Refund Completed'),
        ('staff_alert', 'Staff Alert'),
        ('delivery_assigned', 'Delivery Assigned'),
        ('verification_approved', 'Verification Approved'),
        ('verification_rejected', 'Verification Rejected'),
        ('welcome', 'Welcome'),
        ('announcement', 'Announcement'),
        ('general', 'General'),
    ]

    recipient = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='notifications',
    )
    notification_type = models.CharField(max_length=32, choices=TYPE_CHOICES, default='general')
    title = models.CharField(max_length=200)
    message = models.TextField()
    data = models.JSONField(default=dict, blank=True)
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['recipient', '-created_at']),
            models.Index(fields=['recipient', 'is_read']),
        ]

    def __str__(self):
        return f"[{self.notification_type}] {self.title} → {self.recipient}"


class Announcement(models.Model):
    """Broadcast notification created by admin and sent to a target audience."""

    AUDIENCE_CHOICES = [
        ('all', 'All Users'),
        ('buyers', 'Buyers Only'),
        ('sellers', 'Sellers Only'),
        ('delivery', 'Delivery Agents Only'),
    ]

    title = models.CharField(max_length=200)
    message = models.TextField()
    target_audience = models.CharField(
        max_length=20, choices=AUDIENCE_CHOICES, default='all'
    )
    created_by = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        related_name='announcements_created',
        limit_choices_to={'role': 'admin'},
    )
    created_at = models.DateTimeField(auto_now_add=True)
    is_sent = models.BooleanField(default=False)
    sent_count = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"[{self.target_audience}] {self.title}"
