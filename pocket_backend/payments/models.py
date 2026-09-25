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
        ('refund_request', 'Refund Request Approved'),
    ]

    PAYOUT_METHOD_CHOICES = [
        ('manual', 'Manual (platform sends from own phone)'),
        ('gateway', 'Gateway (PawaPay payout API)'),
    ]

    GATEWAY_CHOICES = [
        ('pawapay', 'PawaPay (mobile money)'),
        ('lenco', 'Lenco (card / bank)'),
    ]

    PAYMENT_METHOD_CHOICES = [
        ('mobile_money', 'Mobile money'),
        ('card', 'Card'),
        ('bank', 'Bank account'),
    ]

    transaction_id = models.UUIDField(
        primary_key=True, default=uuid.uuid4, editable=False
    )
    # Which provider moved the money, and over which rail. Everything that
    # predates Lenco is PawaPay mobile money, hence the defaults.
    gateway = models.CharField(max_length=10, choices=GATEWAY_CHOICES, default='pawapay')
    payment_method = models.CharField(
        max_length=15, choices=PAYMENT_METHOD_CHOICES, default='mobile_money'
    )
    gateway_reference = models.CharField(
        max_length=64, blank=True, default='',
        help_text="The provider's own reference for this transaction (e.g. Lenco's lencoReference).",
    )
    gateway_fee = models.DecimalField(
        max_digits=10, decimal_places=2, null=True, blank=True,
        help_text='Processing fee the provider reported, when it reports one.',
    )
    fee_deducted = models.DecimalField(
        max_digits=10, decimal_places=2, default=0,
        help_text=(
            'Fee taken out of a payout before it is sent (e.g. the bank transfer fee). '
            '`amount` is what the recipient receives; amount + fee_deducted is what left their earnings.'
        ),
    )
    due_at = models.DateTimeField(
        null=True, blank=True,
        help_text='When a refund was promised to the buyer by (card refunds).',
    )
    bank_account = models.ForeignKey(
        'payments.PayoutBankAccount', on_delete=models.SET_NULL,
        null=True, blank=True, related_name='transactions',
        help_text='Destination account for a bank payout.',
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


class PayoutBankAccount(models.Model):
    """
    A bank account a seller or rider can be paid into. Only saved after
    Lenco has resolved it to an account-holder name, so `account_name` is
    what the bank says, not what the user typed.
    """
    user = models.ForeignKey(
        'accounts.User', on_delete=models.CASCADE, related_name='payout_bank_accounts'
    )
    bank_id = models.CharField(max_length=20)
    bank_name = models.CharField(max_length=100)
    account_number = models.CharField(max_length=34)
    account_name = models.CharField(max_length=150)
    country = models.CharField(max_length=2, default='zm')
    name_matches = models.BooleanField(
        default=False,
        help_text=(
            "The bank's account holder name matches the owner's registered name. "
            "Accounts that don't match are never paid automatically — staff review first."
        ),
    )
    is_default = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-is_default', '-created_at']
        constraints = [
            models.UniqueConstraint(
                fields=['user', 'bank_id', 'account_number'],
                name='unique_payout_bank_account_per_user',
            ),
        ]

    def __str__(self):
        return f'{self.bank_name} ••••{self.account_number[-4:]} ({self.account_name})'

    @property
    def masked_number(self):
        return f'••••{self.account_number[-4:]}'