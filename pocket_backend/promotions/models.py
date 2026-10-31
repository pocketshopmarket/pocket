import secrets
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import MinValueValidator, RegexValidator
from django.db import models
from django.db.models import Sum
from django.utils import timezone

CODE_VALIDATOR = RegexValidator(
    r'^[A-Z0-9]{3,20}$',
    'Use 3–20 capital letters or numbers, no spaces (e.g. YOMAPS or EASTER30).',
)

PERCENT = 'percent'
FIXED = 'fixed'
DISCOUNT_TYPES = [(PERCENT, 'Percent off'), (FIXED, 'Fixed amount off (ZMW)')]


def _token():
    return secrets.token_urlsafe(24)


class PromoSettings(models.Model):
    """One row of settings staff can change any time in the admin."""

    welcome_enabled = models.BooleanField(
        'Welcome discount on', default=True,
        help_text='Every new buyer gets this discount on their first order.',
    )
    welcome_discount_type = models.CharField(max_length=10, choices=DISCOUNT_TYPES, default=PERCENT)
    welcome_discount_value = models.DecimalField(
        max_digits=8, decimal_places=2, default=Decimal('15'),
        validators=[MinValueValidator(0)],
        help_text='Percent off: 15 means 15%. Fixed: the amount in ZMW.',
    )
    welcome_max_discount = models.DecimalField(
        'Welcome discount cap (ZMW)', max_digits=8, decimal_places=2, null=True, blank=True,
        default=Decimal('30'), help_text='The most the welcome discount can take off. Blank = no cap.',
    )
    welcome_min_order = models.DecimalField(
        'Welcome minimum order (ZMW)', max_digits=8, decimal_places=2, default=Decimal('0'),
        help_text='Items total needed before the welcome discount applies.',
    )
    welcome_valid_days = models.PositiveIntegerField(
        'Days to use the welcome discount', default=30,
        help_text='Counted from the day the buyer signs up.',
    )

    partner_commission_rate = models.DecimalField(
        'Partner share of service fee', max_digits=5, decimal_places=4, default=Decimal('0.10'),
        validators=[MinValueValidator(0)],
        help_text='0.10 = partners earn 10% of the service fee. A partner can have their own rate.',
    )
    partner_window_days = models.PositiveIntegerField(
        'Days a partner earns per buyer', default=30,
        help_text='Partners earn on orders a buyer places within this many days of signing up.',
    )
    partner_hold_days = models.PositiveIntegerField(
        'Days before earnings can be requested', default=7,
        help_text='Earnings wait this long after delivery, in case the order is refunded.',
    )
    partner_min_payout = models.DecimalField(
        'Minimum payout request (ZMW)', max_digits=8, decimal_places=2, default=Decimal('50'),
    )
    staff_email = models.EmailField(
        'Staff email', default='pocketshopmarket@gmail.com',
        help_text='Gets new partner applications and payment requests.',
    )

    class Meta:
        verbose_name = 'Promo & partner settings'
        verbose_name_plural = 'Promo & partner settings'

    def __str__(self):
        return 'Promo & partner settings'

    def save(self, *args, **kwargs):
        self.pk = 1
        super().save(*args, **kwargs)

    @classmethod
    def get(cls):
        obj, _ = cls.objects.get_or_create(pk=1)
        return obj


class PromoCode(models.Model):
    code = models.CharField(max_length=20, unique=True, validators=[CODE_VALIDATOR])
    description = models.CharField(max_length=200, blank=True, help_text='For staff only, e.g. "Easter 2027 campaign".')
    discount_type = models.CharField(max_length=10, choices=DISCOUNT_TYPES, default=PERCENT)
    value = models.DecimalField(
        max_digits=8, decimal_places=2, validators=[MinValueValidator(0)],
        help_text='Percent off: 25 means 25%. Fixed: the amount in ZMW.',
    )
    max_discount = models.DecimalField(
        'Cap (ZMW)', max_digits=8, decimal_places=2, null=True, blank=True,
        help_text='The most this code can take off. Blank = no cap.',
    )
    min_order = models.DecimalField('Minimum order (ZMW)', max_digits=8, decimal_places=2, default=Decimal('0'))
    starts_at = models.DateTimeField(null=True, blank=True, help_text='Blank = works now.')
    ends_at = models.DateTimeField(null=True, blank=True, help_text='Blank = never ends.')
    max_uses = models.PositiveIntegerField('Total uses allowed', null=True, blank=True, help_text='Blank = no limit.')
    max_uses_per_user = models.PositiveIntegerField('Uses per buyer', default=1)
    first_order_only = models.BooleanField(default=False)
    is_active = models.BooleanField('On', default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return self.code

    def clean_fields(self, exclude=None):
        # Uppercase before the format check so staff can type "easter30".
        self.code = (self.code or '').strip().upper()
        super().clean_fields(exclude)

    def clean(self):
        if Partner.objects.filter(code=self.code).exists():
            raise ValidationError({'code': 'A partner already uses this code. Pick another.'})

    def save(self, *args, **kwargs):
        self.code = (self.code or '').strip().upper()
        super().save(*args, **kwargs)


class Partner(models.Model):
    INVITED, APPLIED, APPROVED, REJECTED, PAUSED = 'invited', 'applied', 'approved', 'rejected', 'paused'
    STATUS_CHOICES = [
        (INVITED, 'Invited (waiting to accept)'),
        (APPLIED, 'Applied (waiting for approval)'),
        (APPROVED, 'Approved'),
        (REJECTED, 'Rejected'),
        (PAUSED, 'Paused'),
    ]
    SOURCE_CHOICES = [('website', 'Applied on website'), ('admin', 'Added by staff')]
    PAYOUT_CHOICES = [('mobile_money', 'Mobile money'), ('bank', 'Bank account')]

    name = models.CharField(max_length=120)
    email = models.EmailField(unique=True)
    phone = models.CharField(max_length=20, blank=True)
    code = models.CharField(max_length=20, unique=True, validators=[CODE_VALIDATOR])
    promotes_on = models.CharField(
        'Where they share it', max_length=300, blank=True,
        help_text='e.g. TikTok @yomaps, Facebook page, WhatsApp groups.',
    )
    payout_method = models.CharField(max_length=20, choices=PAYOUT_CHOICES, blank=True)
    payout_details = models.CharField(
        'Where to pay them', max_length=300, blank=True,
        help_text='Mobile money number and network, or bank name and account number.',
    )
    commission_rate = models.DecimalField(
        'Own share of service fee', max_digits=5, decimal_places=4, null=True, blank=True,
        help_text='Blank = use the default from settings. 0.15 = 15%.',
    )
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default=INVITED)
    source = models.CharField(max_length=10, choices=SOURCE_CHOICES, default='admin')
    staff_notes = models.TextField(blank=True)

    access_token = models.CharField(max_length=64, unique=True, default=_token, editable=False)
    invite_token = models.CharField(max_length=64, unique=True, null=True, blank=True, editable=False)
    invite_expires_at = models.DateTimeField(null=True, blank=True, editable=False)
    agreed_terms_at = models.DateTimeField(null=True, blank=True, editable=False)
    approved_at = models.DateTimeField(null=True, blank=True, editable=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.name} ({self.code})'

    def clean_fields(self, exclude=None):
        # Normalise before validation so "Yomaps" / "A@B.com" pass the format and unique checks.
        self.code = (self.code or '').strip().upper()
        self.email = (self.email or '').strip().lower()
        super().clean_fields(exclude)

    def clean(self):
        if PromoCode.objects.filter(code=self.code).exists():
            raise ValidationError({'code': 'A promo code already uses this. Pick another.'})

    def save(self, *args, **kwargs):
        self.code = (self.code or '').strip().upper()
        self.email = (self.email or '').strip().lower()
        super().save(*args, **kwargs)

    @property
    def is_earning(self):
        return self.status == self.APPROVED

    def effective_rate(self, ps=None):
        if self.commission_rate is not None:
            return self.commission_rate
        return (ps or PromoSettings.get()).partner_commission_rate

    def new_invite(self, days=7):
        self.invite_token = _token()
        self.invite_expires_at = timezone.now() + timedelta(days=days)

    # ---- money ----
    def balances(self, now=None):
        now = now or timezone.now()
        active = self.earnings.filter(status=PartnerEarning.ACTIVE)
        earned = active.aggregate(t=Sum('amount'))['t'] or Decimal('0')
        on_hold = active.filter(available_at__gt=now).aggregate(t=Sum('amount'))['t'] or Decimal('0')
        paid = self.payout_requests.filter(status=PayoutRequest.PAID).aggregate(t=Sum('paid_amount'))['t'] or Decimal('0')
        requested = self.payout_requests.filter(status=PayoutRequest.REQUESTED).aggregate(
            t=Sum('amount_requested'))['t'] or Decimal('0')
        available = earned - on_hold
        return {
            'earned': earned,
            'on_hold': on_hold,
            'paid': paid,
            'requested': requested,
            'owed': earned - paid,
            'requestable': max(Decimal('0'), available - paid - requested),
        }


class Referral(models.Model):
    """Which partner brought a buyer. Set once at sign-up, never changed."""

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='referral')
    partner = models.ForeignKey(Partner, on_delete=models.CASCADE, related_name='referrals')
    code_used = models.CharField(max_length=20)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f'{self.user_id} via {self.code_used}'


class PartnerEarning(models.Model):
    ACTIVE, REVERSED = 'active', 'reversed'
    STATUS_CHOICES = [(ACTIVE, 'Counts'), (REVERSED, 'Reversed (order refunded)')]

    partner = models.ForeignKey(Partner, on_delete=models.CASCADE, related_name='earnings')
    order = models.OneToOneField('orders.Order', on_delete=models.CASCADE, related_name='partner_earning')
    referred_user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='+')
    service_fee = models.DecimalField(max_digits=10, decimal_places=2)
    rate = models.DecimalField(max_digits=5, decimal_places=4)
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default=ACTIVE)
    available_at = models.DateTimeField(help_text='When it can be requested (after the hold period).')
    reversed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.partner.code} K{self.amount} on order {self.order_id}'


class PayoutRequest(models.Model):
    REQUESTED, PAID, CANCELLED = 'requested', 'paid', 'cancelled'
    STATUS_CHOICES = [(REQUESTED, 'Requested'), (PAID, 'Paid'), (CANCELLED, 'Cancelled')]

    partner = models.ForeignKey(Partner, on_delete=models.CASCADE, related_name='payout_requests')
    amount_requested = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default=REQUESTED)
    paid_amount = models.DecimalField(
        max_digits=10, decimal_places=2, null=True, blank=True,
        help_text='Fill in when you have paid them outside the app.',
    )
    reference = models.CharField(
        'Payment reference', max_length=120, blank=True,
        help_text='Mobile money or bank transaction reference.',
    )
    staff_note = models.CharField(max_length=300, blank=True)
    requested_at = models.DateTimeField(auto_now_add=True)
    paid_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-requested_at']

    def __str__(self):
        return f'{self.partner.code} K{self.amount_requested} ({self.get_status_display()})'
