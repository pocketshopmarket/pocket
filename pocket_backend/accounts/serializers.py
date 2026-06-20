from rest_framework import serializers
from django.contrib.auth import authenticate
from django.utils import timezone
from .models import (
    BuyerPaymentMethod,
    BuyerProfile,
    DeliveryProfile,
    SellerProfile,
    User,
    VerificationRequest,
)
from .phone_utils import normalize_zambia_phone_to_e164
from .otp_utils import assert_phone_otp_valid

PROVIDER_PREFIX_RULES = {
    'mtn_momo': {'096', '076'},
    'airtel_money': {'097', '077', '057'},
    'zamtel': {'095', '075', '055'},
}


class UserProfileSerializer(serializers.ModelSerializer):
    profile_photo = serializers.SerializerMethodField()

    def get_profile_photo(self, obj):
        if not obj.profile_photo:
            return None
        url = obj.profile_photo.url
        if url.startswith(('http://', 'https://')):
            return url
        from django.conf import settings as _s
        base = getattr(_s, 'PUBLIC_BACKEND_URL', '').rstrip('/')
        if base:
            return f"{base}{url}"
        request = self.context.get('request')
        if request:
            return request.build_absolute_uri(url)
        return url

    class Meta:
        model = User
        fields = [
            'id', 'phone_number', 'full_name', 'gender', 'date_of_birth', 'email', 'role',
            'is_verified', 'is_phone_verified', 'date_joined', 'profile_photo',
        ]
        read_only_fields = ['id', 'is_verified', 'is_phone_verified', 'date_joined', 'profile_photo']


class BuyerProfileSerializer(serializers.ModelSerializer):
    user = UserProfileSerializer(read_only=True)
    
    class Meta:
        model = BuyerProfile
        fields = ['user', 'default_address', 'preferred_payment_method', 'created_at', 'updated_at']
        read_only_fields = ['created_at', 'updated_at']


class BuyerPaymentMethodSerializer(serializers.ModelSerializer):
    provider_label = serializers.CharField(source='get_provider_display', read_only=True)

    class Meta:
        model = BuyerPaymentMethod
        fields = [
            'id',
            'provider',
            'provider_label',
            'account_phone',
            'is_verified',
            'is_default',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'is_verified', 'created_at', 'updated_at']

    def validate(self, attrs):
        user = self.context['request'].user
        phone = (attrs.get('account_phone') or '').strip()
        if not phone:
            raise serializers.ValidationError(
                {'account_phone': ['Wallet / mobile money number is required.']}
            )
        normalized = normalize_zambia_phone_to_e164(phone)
        attrs['account_phone'] = normalized

        provider = attrs.get('provider')
        local_prefix = '0' + normalized[4:6]
        allowed = PROVIDER_PREFIX_RULES.get(provider, set())
        if local_prefix not in allowed:
            raise serializers.ValidationError(
                {
                    'account_phone': [
                        'Phone number does not match selected network/provider.'
                    ]
                }
            )
        exists = BuyerPaymentMethod.objects.filter(
            user=user,
            provider=provider,
        )
        if self.instance is not None:
            exists = exists.exclude(pk=self.instance.pk)
        if exists.exists():
            raise serializers.ValidationError(
                {'provider': [f'You already have an active {provider} payment method. Please delete it first.']}
            )
        return attrs


class VerificationRequestSerializer(serializers.ModelSerializer):
    reviewed_by_name = serializers.CharField(
        source='reviewed_by.full_name',
        read_only=True,
    )

    class Meta:
        model = VerificationRequest
        fields = [
            'id',
            'verification_type',
            'status',
            'rejection_reason',
            'submitted_at',
            'reviewed_at',
            'reviewed_by',
            'reviewed_by_name',
            'created_at',
            'updated_at',
        ]
        read_only_fields = fields


class SellerProfileSerializer(serializers.ModelSerializer):
    user = UserProfileSerializer(read_only=True)
    verification_requests = VerificationRequestSerializer(many=True, read_only=True)
    
    class Meta:
        model = SellerProfile
        fields = ['user', 'shop_name', 'shop_location', 'shop_lat', 'shop_lng', 'business_license',
                  'business_name', 'business_registration_number', 'nrc_number', 'nrc_front_image',
                  'nrc_back_image', 'live_verification_photo', 'tier1_status', 'tier2_status',
                  'verification_rejection_reason', 'submitted_at', 'reviewed_at',
                  'is_approved', 'approval_date', 'verification_requests',
                  'created_at', 'updated_at']
        read_only_fields = [
            'shop_lat', 'shop_lng', 'tier1_status', 'tier2_status',
            'verification_rejection_reason', 'submitted_at', 'reviewed_at',
            'is_approved', 'approval_date', 'verification_requests',
            'created_at', 'updated_at',
        ]


class DeliveryProfileSerializer(serializers.ModelSerializer):
    user = UserProfileSerializer(read_only=True)
    verification_requests = VerificationRequestSerializer(many=True, read_only=True)
    
    class Meta:
        model = DeliveryProfile
        fields = [
            'user', 'vehicle_type', 'vehicle_make', 'vehicle_model',
            'license_number', 'license_front_image',
            'license_back_image', 'province', 'town', 'area',
            'live_verification_photo', 'profile_photo', 'verification_status',
            'verification_rejection_reason', 'submitted_at', 'reviewed_at',
            'is_available', 'is_approved', 'current_location_lat',
            'current_location_lng', 'verification_requests',
            'created_at', 'updated_at',
        ]
        read_only_fields = [
            'verification_status', 'verification_rejection_reason',
            'submitted_at', 'reviewed_at', 'is_approved', 'created_at',
            'verification_requests', 'updated_at',
        ]


class SendOTPSerializer(serializers.Serializer):
    phone_number = serializers.CharField(max_length=20)

    def validate_phone_number(self, value):
        return normalize_zambia_phone_to_e164(value)


class VerifyOTPSerializer(serializers.Serializer):
    phone_number = serializers.CharField(max_length=20)
    otp_code = serializers.CharField(max_length=6)
    role = serializers.ChoiceField(choices=User.ROLE_CHOICES, required=False)
    password = serializers.CharField(write_only=True, required=False, allow_blank=True)
    full_name = serializers.CharField(max_length=200, required=False, allow_blank=True)
    gender = serializers.ChoiceField(choices=User.GENDER_CHOICES, required=False, allow_blank=True)
    date_of_birth = serializers.DateField(required=False, allow_null=True)

    def validate_phone_number(self, value):
        return normalize_zambia_phone_to_e164(value)

    def validate(self, attrs):
        phone_number = attrs.get('phone_number')
        otp_code = attrs.get('otp_code')

        otp_instance = assert_phone_otp_valid(phone_number, otp_code)
        attrs['_otp_instance'] = otp_instance

        if not User.objects.filter(phone_number=phone_number).exists():
            password = (attrs.get('password') or '').strip()
            if not password:
                raise serializers.ValidationError(
                    {'password': ['Password is required for new registration.']}
                )
            if len(password) < 6:
                raise serializers.ValidationError(
                    {'password': ['Password must be at least 6 characters.']}
                )
            attrs['password'] = password

        return attrs


class LoginSerializer(serializers.Serializer):
    phone_number = serializers.CharField(max_length=20)
    password = serializers.CharField()

    def validate_phone_number(self, value):
        return normalize_zambia_phone_to_e164(value)

    def validate(self, attrs):
        phone_number = attrs.get('phone_number')
        password = attrs.get('password')

        user = authenticate(username=phone_number, password=password)

        if not user:
            raise serializers.ValidationError('Invalid credentials')

        if not user.is_active:
            raise serializers.ValidationError('This account has been disabled.')

        attrs['user'] = user
        return attrs


class PasswordResetSendSerializer(serializers.Serializer):
    phone_number = serializers.CharField(max_length=20)

    def validate_phone_number(self, value):
        return normalize_zambia_phone_to_e164(value)


class PasswordResetConfirmSerializer(serializers.Serializer):
    phone_number = serializers.CharField(max_length=20)
    otp_code = serializers.CharField(max_length=6)
    new_password = serializers.CharField(write_only=True, min_length=6)

    def validate_phone_number(self, value):
        return normalize_zambia_phone_to_e164(value)

    def validate_new_password(self, value):
        if len(value) < 6:
            raise serializers.ValidationError('Password must be at least 6 characters.')
        return value

    def validate(self, attrs):
        phone_number = attrs['phone_number']
        otp_code = attrs['otp_code']

        if not User.objects.filter(phone_number=phone_number).exists():
            raise serializers.ValidationError(
                {'phone_number': ['No account found for this number.']}
            )

        otp_instance = assert_phone_otp_valid(phone_number, otp_code)
        attrs['_otp_instance'] = otp_instance
        return attrs


class ChangePasswordSerializer(serializers.Serializer):
    old_password = serializers.CharField(write_only=True)
    new_password = serializers.CharField(write_only=True, min_length=6)

    def validate_new_password(self, value):
        if len(value) < 6:
            raise serializers.ValidationError('Password must be at least 6 characters.')
        return value

    def validate(self, attrs):
        user = self.context['request'].user
        if not user.check_password(attrs['old_password']):
            raise serializers.ValidationError(
                {'old_password': ['Current password is incorrect.']}
            )
        return attrs


class SellerApplicationSerializer(serializers.ModelSerializer):
    tier = serializers.ChoiceField(choices=['tier1', 'tier2'], required=False, default='tier1')

    class Meta:
        model = SellerProfile
        fields = [
            'tier', 'shop_name', 'shop_location', 'business_license',
            'business_name', 'business_registration_number', 'nrc_number',
            'nrc_front_image', 'nrc_back_image', 'live_verification_photo',
        ]

    def validate(self, attrs):
        tier = attrs.get('tier', 'tier1')
        required = ['shop_name', 'shop_location', 'nrc_number']
        missing = [field for field in required if not attrs.get(field)]
        if missing:
            raise serializers.ValidationError(
                {field: ['This field is required.'] for field in missing}
            )

        user = self.context['request'].user
        existing = getattr(user, 'seller_profile', None)
        front = attrs.get('nrc_front_image') or getattr(existing, 'nrc_front_image', None)
        back = attrs.get('nrc_back_image') or getattr(existing, 'nrc_back_image', None)
        live_photo = attrs.get('live_verification_photo') or getattr(
            existing, 'live_verification_photo', None
        )
        if not front or not back:
            raise serializers.ValidationError(
                {'nrc_images': ['Front and back NRC images are required for Tier 1.']}
            )
        if not live_photo:
            raise serializers.ValidationError(
                {'live_verification_photo': ['A live verification photo is required for seller verification.']}
            )

        if tier == 'tier2':
            has_business_license = attrs.get('business_license') or getattr(
                existing, 'business_license', None
            )
            if not has_business_license:
                raise serializers.ValidationError(
                    {'business_license': ['Business license is required for Tier 2.']}
                )
        return attrs
    
    def create(self, validated_data):
        tier = validated_data.pop('tier', 'tier1')
        user = self.context['request'].user
        defaults = dict(validated_data)
        submitted_at = timezone.now()
        defaults['submitted_at'] = submitted_at
        defaults['verification_rejection_reason'] = ''
        if tier == 'tier2':
            defaults['tier2_status'] = 'submitted'
        else:
            defaults['tier1_status'] = 'submitted'
            defaults['is_approved'] = False
        seller_profile, created = SellerProfile.objects.update_or_create(
            user=user,
            defaults=defaults,
        )
        VerificationRequest.objects.update_or_create(
            user=user,
            verification_type='seller_tier2' if tier == 'tier2' else 'seller_tier1',
            defaults={
                'seller_profile': seller_profile,
                'delivery_profile': None,
                'status': 'submitted',
                'rejection_reason': '',
                'submitted_at': submitted_at,
                'reviewed_at': None,
                'reviewed_by': None,
            },
        )
        return seller_profile


class DeliveryApplicationSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeliveryProfile
        fields = [
            'vehicle_type', 'vehicle_make', 'vehicle_model',
            'license_number', 'license_front_image',
            'license_back_image', 'province', 'town', 'area',
            'live_verification_photo', 'profile_photo',
        ]

    def validate(self, attrs):
        required = ['vehicle_type', 'license_number', 'province', 'town', 'area']
        missing = [field for field in required if not attrs.get(field)]
        if missing:
            raise serializers.ValidationError(
                {field: ['This field is required.'] for field in missing}
            )

        user = self.context['request'].user
        existing = getattr(user, 'delivery_profile', None)
        front_image = attrs.get('license_front_image') or getattr(existing, 'license_front_image', None)
        back_image = attrs.get('license_back_image') or getattr(existing, 'license_back_image', None)
        live_photo = attrs.get('live_verification_photo') or getattr(
            existing, 'live_verification_photo', None
        )
        if not front_image or not back_image:
            raise serializers.ValidationError(
                "Driver license front and back images are required."
            )
        if not live_photo:
            raise serializers.ValidationError(
                "A live verification photo is required."
            )
        return attrs
    
    def create(self, validated_data):
        user = self.context['request'].user
        submitted_at = timezone.now()
        validated_data['verification_status'] = 'submitted'
        validated_data['verification_rejection_reason'] = ''
        validated_data['submitted_at'] = submitted_at
        validated_data['is_approved'] = False
        delivery_profile, created = DeliveryProfile.objects.update_or_create(
            user=user,
            defaults=validated_data
        )
        VerificationRequest.objects.update_or_create(
            user=user,
            verification_type='delivery',
            defaults={
                'seller_profile': None,
                'delivery_profile': delivery_profile,
                'status': 'submitted',
                'rejection_reason': '',
                'submitted_at': submitted_at,
                'reviewed_at': None,
                'reviewed_by': None,
            },
        )
        return delivery_profile
