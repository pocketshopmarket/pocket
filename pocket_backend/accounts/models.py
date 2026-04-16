from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.core.exceptions import ValidationError
from django.db import models
import secrets


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
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='seller_profile')
    shop_name = models.CharField(max_length=200)
    shop_location = models.TextField()
    shop_lat = models.FloatField(null=True, blank=True)
    shop_lng = models.FloatField(null=True, blank=True)
    business_license = models.ImageField(upload_to='licenses/', blank=True, null=True)
    nrc_number = models.CharField(max_length=30, blank=True, null=True)
    is_approved = models.BooleanField(default=False)
    approval_date = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Seller Profile: {self.shop_name}"

    def clean(self):
        if self.is_approved and not self.nrc_number:
            raise ValidationError("NRC number is required before seller verification.")


class DeliveryProfile(models.Model):
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

    @classmethod
    def generate_otp(cls, phone_number):
        otp = f"{secrets.randbelow(10**6):06d}"
        # Delete any existing unverified OTPs for this number
        cls.objects.filter(phone_number=phone_number, is_verified=False).delete()
        return cls.objects.create(phone_number=phone_number, otp_code=otp)

    def is_expired(self):
        from django.utils import timezone
        return timezone.now() - self.created_at > timezone.timedelta(minutes=10)
