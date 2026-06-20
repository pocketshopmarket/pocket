import uuid

from django.db import models


class Transaction(models.Model):
    TRANSACTION_TYPES = [
        ('deposit', 'Deposit (Buyer paying)'),
        ('payout', 'Payout (Paying Seller/Delivery)'),
        ('refund', 'Refund (Returning buyer funds)'),
    ]

    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('accepted', 'Accepted by PawaPay'),
        ('completed', 'Completed/Successful'),
        ('failed', 'Failed'),
        ('duplicate_ignored', 'Duplicate Ignored'),
    ]

    RECIPIENT_ROLE_CHOICES = [
        ('buyer', 'Buyer'),
        ('seller', 'Seller'),
        ('delivery', 'Delivery'),
        ('platform', 'Platform'),
    ]

    PAYOUT_STAGE_CHOICES = [
        ('na', 'Not Applicable'),
        ('pickup_pending_scan', 'Waiting Pickup QR Scan'),
        ('dropoff_pending_scan', 'Waiting Dropoff QR Scan'),
        ('ready_for_payout', 'Ready For Payout'),
        ('payout_sent', 'Payout Sent'),
        ('payout_paid', 'Payout Paid'),
        ('payout_failed', 'Payout Failed'),
    ]

    TRIGGER_EVENT_CHOICES = [
        ('manual', 'Manual'),
        ('pickup_qr', 'Pickup QR'),
        ('dropoff_qr', 'Dropoff QR'),
        ('order_cancelled', 'Order Cancelled'),
    ]

    PAYOUT_METHOD_CHOICES = [
        ('manual', 'Manual (platform sends from own phone)'),
        ('gateway', 'Gateway (PawaPay payout API)'),
    ]

    transaction_id = models.UUIDField(
        primary_key=True, default=uuid.uuid4, editable=False
    )
    order = models.ForeignKey(
        'orders.Order', on_delete=models.CASCADE, related_name='transactions'
    )
    transaction_type = models.CharField(max_length=10, choices=TRANSACTION_TYPES)
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    currency = models.CharField(max_length=3, default='ZMW')
    provider = models.CharField(
        max_length=50,
        help_text='e.g MTN_MOMO_ZMB, AIRTEL_OAPI_ZMB, ZAMTEL_MONEY_ZMB',
    )
    payer_number = models.CharField(
        max_length=15, help_text='Phone number for deposit/payout/refund'
    )
    recipient = models.ForeignKey(
        'accounts.User',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='payment_transactions',
    )
    recipient_role = models.CharField(
        max_length=20,
        choices=RECIPIENT_ROLE_CHOICES,
        blank=True,
        default='',
    )
    payout_stage = models.CharField(
        max_length=30, choices=PAYOUT_STAGE_CHOICES, default='na'
    )
    trigger_event = models.CharField(
        max_length=20, choices=TRIGGER_EVENT_CHOICES, default='manual'
    )
    payout_method = models.CharField(
        max_length=10, choices=PAYOUT_METHOD_CHOICES, default='manual'
    )
    failure_message = models.TextField(blank=True, null=True)
    marked_paid_by = models.ForeignKey(
        'accounts.User',
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name='marked_paid_transactions',
    )
    marked_paid_at = models.DateTimeField(null=True, blank=True)
    payout_notes = models.TextField(blank=True, default='')
    proof_image = models.ImageField(
        upload_to='payout_proofs/', blank=True, null=True,
        help_text='Screenshot of the mobile money transaction uploaded by staff',
    )
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return (
            f'{self.transaction_type.capitalize()} - {self.transaction_id} '
            f'({self.status})'
        )