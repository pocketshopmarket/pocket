from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone
import secrets
import uuid


class CustomUserManager(BaseUserManager):
    def create_user(self, phone_number, password=None, **extra_fields):
        if not phone_number:
            raise ValueError('Phone number is required')

        user = self.model(phone_number=phone_number, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, phone_number, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('is_active', True)

        if extra_fields.get('is_staff') is not True:
            raise ValueError('Superuser must have is_staff=True.')
        if extra_fields.get('is_superuser') is not True:
            raise ValueError('Superuser must have is_superuser=True.')

        return self.create_user(phone_number, password, **extra_fields)


class User(AbstractUser):
    ROLE_CHOICES = [
        ('buyer', 'Buyer'),
        ('seller', 'Seller'),
        ('delivery', 'Delivery'),
        ('admin', 'Admin'),
        ('staff', 'Staff'),
    ]

    GENDER_CHOICES = [
        ('male', 'Male'),
        ('female', 'Female'),
    ]

    username = None  # Disable username
    phone_number = models.CharField(max_length=20, unique=True)
    full_name = models.CharField(max_length=200)
    gender = models.CharField(max_length=20, choices=GENDER_CHOICES, blank=True, null=True)
    email = models.EmailField(blank=True, null=True)
    role = models.CharField(max_length=10, choices=ROLE_CHOICES, default='buyer')
    is_verified = models.BooleanField(default=False)
    is_phone_verified = models.BooleanField(default=False)
    date_of_birth = models.DateField(blank=True, null=True)
    profile_photo = models.ImageField(upload_to='profile_photos/', blank=True, null=True)
    fcm_token = models.CharField(max_length=255, blank=True, default='')
    qr_secret = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    date_joined = models.DateTimeField(auto_now_add=True)

    objects = CustomUserManager()

    USERNAME_FIELD = 'phone_number'
    REQUIRED_FIELDS = ['full_name']

    def __str__(self):
        return f"{self.full_name} ({self.phone_number}) - {self.role}"


class BuyerProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='buyer_profile')
    default_address = models.TextField(blank=True)
    preferred_payment_method = models.CharField(max_length=20, default='cash')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Buyer Profile: {self.user.phone_number}"


class BuyerPaymentMethod(models.Model):
    """Simulated saved wallet / mobile money (Phase 3). Checkout requires a verified row."""

    PROVIDER_CHOICES = [
        ('mtn_momo', 'MTN MoMo'),
        ('airtel_money', 'Airtel Money'),
        ('zamtel', 'Zamtel Kwacha'),
    ]

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='buyer_payment_methods',
    )
    provider = models.CharField(max_length=20, choices=PROVIDER_CHOICES)
    account_phone = models.CharField(max_length=32, help_text='Wallet / mobile money number')
    is_verified = models.BooleanField(default=False)
    is_default = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-is_default', '-created_at']
        constraints = [
            models.UniqueConstraint(
                fields=['user', 'provider', 'account_phone'],
                name='uniq_buyer_payment_user_provider_phone',
            ),
        ]

    def __str__(self):
        return f"{self.user_id} {self.provider} {self.account_phone}"


class SellerProfile(models.Model):
    VERIFICATION_STATUS_CHOICES = [
        ('not_started', 'Not Started'),
        ('submitted', 'Submitted'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
    ]

    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='seller_profile')
    shop_name = models.CharField(max_length=200)
    shop_location = models.TextField()
    shop_lat = models.FloatField(null=True, blank=True)
    shop_lng = models.FloatField(null=True, blank=True)
    business_license = models.ImageField(upload_to='licenses/', blank=True, null=True)
    business_name = models.CharField(max_length=200, blank=True)
    business_registration_number = models.CharField(max_length=80, blank=True)
    nrc_number = models.CharField(max_length=30, blank=True, null=True)
    nrc_front_image = models.ImageField(upload_to='seller_nrc/', blank=True, null=True)
    nrc_back_image = models.ImageField(upload_to='seller_nrc/', blank=True, null=True)
    live_verification_photo = models.ImageField(
        upload_to='seller_verification/',
        blank=True,
        null=True,
    )
    tier1_status = models.CharField(
        max_length=20,
        choices=VERIFICATION_STATUS_CHOICES,
        default='not_started',
    )
    tier2_status = models.CharField(
        max_length=20,
        choices=VERIFICATION_STATUS_CHOICES,
        default='not_started',
    )
    verification_rejection_reason = models.TextField(blank=True)
    submitted_at = models.DateTimeField(null=True, blank=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    is_approved = models.BooleanField(default=False)
    approval_date = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Seller Profile: {self.shop_name}"

    def clean(self):
        if self.is_approved and not self.nrc_number:
            raise ValidationError("NRC number is required before seller verification.")
        if self.is_approved and (not self.nrc_front_image or not self.nrc_back_image):
            raise ValidationError("Front and back NRC images are required before seller verification.")
        if self.is_approved and not self.live_verification_photo:
            raise ValidationError("A live verification photo is required before seller verification.")

    @property
    def can_sell(self):
        return self.is_approved or self.tier1_status == 'approved'


class DeliveryProfile(models.Model):
    VERIFICATION_STATUS_CHOICES = [
        ('not_started', 'Not Started'),
        ('submitted', 'Submitted'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
    ]

    VEHICLE_CHOICES = [
        ('bicycle', 'Bicycle'),
        ('motorcycle', 'Motorcycle'),
        ('car', 'Car'),
        ('van', 'Van'),
    ]

    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='delivery_profile')
    vehicle_type = models.CharField(max_length=20, choices=VEHICLE_CHOICES)
    license_number = models.CharField(max_length=50)
    license_front_image = models.ImageField(upload_to='delivery_licenses/', blank=True, null=True)
    license_back_image = models.ImageField(upload_to='delivery_licenses/', blank=True, null=True)
    province = models.CharField(max_length=80, blank=True)
    town = models.CharField(max_length=80, blank=True)
    area = models.CharField(max_length=120, blank=True)
    live_verification_photo = models.ImageField(
        upload_to='delivery_verification/',
        blank=True,
        null=True,
    )
    profile_photo = models.ImageField(upload_to='profile_photos/', blank=True, null=True)
    verification_status = models.CharField(
        max_length=20,
        choices=VERIFICATION_STATUS_CHOICES,
        default='not_started',
    )
    verification_rejection_reason = models.TextField(blank=True)
    submitted_at = models.DateTimeField(null=True, blank=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    is_available = models.BooleanField(default=True)
    is_approved = models.BooleanField(default=False)
    current_location_lat = models.FloatField(null=True, blank=True)
    current_location_lng = models.FloatField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Delivery Profile: {self.user.phone_number} ({self.vehicle_type})"

    def clean(self):
        if self.is_approved and (not self.license_front_image or not self.license_back_image):
            raise ValidationError("Front and back driver license images are required before approval.")
        if self.is_approved and not self.live_verification_photo:
            raise ValidationError("A live verification photo is required before approval.")


class VerificationRequest(models.Model):
    STATUS_CHOICES = [
        ('submitted', 'Submitted'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
    ]

    VERIFICATION_TYPE_CHOICES = [
        ('seller_tier1', 'Seller Tier 1'),
        ('seller_tier2', 'Seller Tier 2'),
        ('delivery', 'Delivery'),
    ]

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='verification_requests',
    )
    seller_profile = models.ForeignKey(
        SellerProfile,
        on_delete=models.CASCADE,
        related_name='verification_requests',
        null=True,
        blank=True,
    )
    delivery_profile = models.ForeignKey(
        DeliveryProfile,
        on_delete=models.CASCADE,
        related_name='verification_requests',
        null=True,
        blank=True,
    )
    verification_type = models.CharField(
        max_length=20,
        choices=VERIFICATION_TYPE_CHOICES,
    )
    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default='submitted',
    )
    rejection_reason = models.TextField(blank=True)
    submitted_at = models.DateTimeField(default=timezone.now)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='reviewed_verification_requests',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-submitted_at', '-created_at']
        constraints = [
            models.UniqueConstraint(
                fields=['user', 'verification_type'],
                name='uniq_user_verification_type',
            ),
        ]

    def __str__(self):
        return f"{self.user.phone_number} - {self.verification_type} ({self.status})"

    def clean(self):
        is_seller_request = self.verification_type in ['seller_tier1', 'seller_tier2']
        if is_seller_request:
            if not self.seller_profile or self.delivery_profile_id is not None:
                raise ValidationError(
                    "Seller verification requests must link to a seller profile only."
                )
            if self.seller_profile.user_id != self.user_id:
                raise ValidationError("Seller verification request user mismatch.")
        elif self.verification_type == 'delivery':
            if not self.delivery_profile or self.seller_profile_id is not None:
                raise ValidationError(
                    "Delivery verification requests must link to a delivery profile only."
                )
            if self.delivery_profile.user_id != self.user_id:
                raise ValidationError("Delivery verification request user mismatch.")

    def approve(self, reviewer=None):
        now = timezone.now()
        self.status = 'approved'
        self.rejection_reason = ''
        self.reviewed_at = now
        self.reviewed_by = reviewer
        self.save(
            update_fields=[
                'status',
                'rejection_reason',
                'reviewed_at',
                'reviewed_by',
                'updated_at',
            ]
        )

        if self.verification_type == 'seller_tier1' and self.seller_profile:
            profile = self.seller_profile
            profile.tier1_status = 'approved'
            profile.is_approved = True
            profile.reviewed_at = now
            profile.approval_date = now
            profile.verification_rejection_reason = ''
            profile.full_clean()
            profile.save()
        elif self.verification_type == 'seller_tier2' and self.seller_profile:
            profile = self.seller_profile
            profile.tier2_status = 'approved'
            profile.reviewed_at = now
            profile.verification_rejection_reason = ''
            profile.save(
                update_fields=[
                    'tier2_status',
                    'reviewed_at',
                    'verification_rejection_reason',
                    'updated_at',
                ]
            )
        elif self.verification_type == 'delivery' and self.delivery_profile:
            profile = self.delivery_profile
            profile.verification_status = 'approved'
            profile.is_approved = True
            profile.reviewed_at = now
            profile.verification_rejection_reason = ''
            profile.full_clean()
            profile.save()

    def reject(self, reviewer=None, reason='Rejected by admin. Please review your submitted details.'):
        now = timezone.now()
        self.status = 'rejected'
        self.rejection_reason = reason
        self.reviewed_at = now
        self.reviewed_by = reviewer
        self.save(
            update_fields=[
                'status',
                'rejection_reason',
                'reviewed_at',
                'reviewed_by',
                'updated_at',
            ]
        )

        if self.verification_type == 'seller_tier1' and self.seller_profile:
            profile = self.seller_profile
            profile.tier1_status = 'rejected'
            profile.tier2_status = 'rejected'
            profile.is_approved = False
            profile.reviewed_at = now
            profile.verification_rejection_reason = reason
            profile.save(
                update_fields=[
                    'tier1_status',
                    'tier2_status',
                    'is_approved',
                    'reviewed_at',
                    'verification_rejection_reason',
                    'updated_at',
                ]
            )
        elif self.verification_type == 'seller_tier2' and self.seller_profile:
            profile = self.seller_profile
            profile.tier2_status = 'rejected'
            profile.reviewed_at = now
            profile.verification_rejection_reason = reason
            profile.save(
                update_fields=[
                    'tier2_status',
                    'reviewed_at',
                    'verification_rejection_reason',
                    'updated_at',
                ]
            )
        elif self.verification_type == 'delivery' and self.delivery_profile:
            profile = self.delivery_profile
            profile.verification_status = 'rejected'
            profile.is_approved = False
            profile.reviewed_at = now
            profile.verification_rejection_reason = reason
            profile.save(
                update_fields=[
                    'verification_status',
                    'is_approved',
                    'reviewed_at',
                    'verification_rejection_reason',
                    'updated_at',
                ]
            )


class PhoneOTP(models.Model):
    phone_number = models.CharField(max_length=20)
    otp_code = models.CharField(max_length=6)
    is_verified = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    attempts = models.IntegerField(default=0)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"OTP for {self.phone_number}: {self.otp_code}"

    def is_expired(self):
        from django.utils import timezone
        return timezone.now() - self.created_at > timezone.timedelta(minutes=10)

    @classmethod
    def generate_otp(cls, phone_number):
        from django.utils import timezone

        # --- Rate limit: max 5 OTP requests per phone per hour ---
        one_hour_ago = timezone.now() - timezone.timedelta(hours=1)
        recent_count = cls.objects.filter(
            phone_number=phone_number,
            created_at__gte=one_hour_ago,
        ).count()
        if recent_count >= 5:
            raise ValueError(
                'Too many OTP requests. Please wait before requesting a new code.'
            )

        otp = f"{secrets.randbelow(10**6):06d}"
        # Delete any existing unverified OTPs for this number
        cls.objects.filter(phone_number=phone_number, is_verified=False).delete()
        return cls.objects.create(phone_number=phone_number, otp_code=otp)


def generate_error_reference():
    return uuid.uuid4().hex[:12].upper()


class ErrorLog(models.Model):
    ERROR_TYPE_CHOICES = [
        ('validation', 'Validation'),
        ('authentication', 'Authentication'),
        ('permission', 'Permission'),
        ('not_found', 'Not Found'),
        ('throttled', 'Throttled'),
        ('external_service', 'External Service'),
        ('server', 'Server'),
        ('unknown', 'Unknown'),
    ]

    user = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='error_logs',
    )
    reference_id = models.CharField(
        max_length=12,
        unique=True,
        default=generate_error_reference,
        editable=False,
    )
    error_type = models.CharField(
        max_length=32,
        choices=ERROR_TYPE_CHOICES,
        default='unknown',
    )
    error_code = models.CharField(max_length=100, blank=True)
    error_class = models.CharField(max_length=200, blank=True)
    message = models.TextField()
    user_message = models.TextField(blank=True)
    status_code = models.PositiveIntegerField(null=True, blank=True)
    method = models.CharField(max_length=10, blank=True)
    path = models.CharField(max_length=255, blank=True)
    request_data = models.JSONField(default=dict, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    traceback = models.TextField(blank=True)
    resolved = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.reference_id} {self.error_type} {self.status_code or '-'}"

    def is_expired(self):
        from django.utils import timezone
        return timezone.now() - self.created_at > timezone.timedelta(minutes=10)
