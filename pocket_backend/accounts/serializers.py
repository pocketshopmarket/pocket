from rest_framework import serializers
from django.contrib.auth import authenticate
from .models import (
    BuyerPaymentMethod,
    BuyerProfile,
    DeliveryProfile,
    SellerProfile,
    User,
)
from .phone_utils import normalize_zambia_phone_to_e164
from .otp_utils import assert_phone_otp_valid


class UserProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = [
            'id', 'phone_number', 'full_name', 'gender', 'date_of_birth', 'email', 'role',
            'is_verified', 'is_phone_verified', 'date_joined',
        ]
        read_only_fields = ['id', 'is_verified', 'is_phone_verified', 'date_joined']


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
        attrs['account_phone'] = phone
        if not phone:
            raise serializers.ValidationError(
                {'account_phone': ['Wallet / mobile money number is required.']}
            )

        provider = attrs.get('provider')
        exists = BuyerPaymentMethod.objects.filter(
            user=user,
            provider=provider,
            account_phone=phone,
        )
        if self.instance is not None:
            exists = exists.exclude(pk=self.instance.pk)
        if exists.exists():
            raise serializers.ValidationError(
                {'account_phone': ['This payment method is already saved.']}
            )
        return attrs


class SellerProfileSerializer(serializers.ModelSerializer):
    user = UserProfileSerializer(read_only=True)
    
    class Meta:
        model = SellerProfile
        fields = ['user', 'shop_name', 'shop_location', 'shop_lat', 'shop_lng', 'business_license',
                  'nrc_number', 'is_approved', 'approval_date', 'created_at', 'updated_at']
        read_only_fields = ['shop_lat', 'shop_lng', 'is_approved', 'approval_date', 'created_at', 'updated_at']


class DeliveryProfileSerializer(serializers.ModelSerializer):
    user = UserProfileSerializer(read_only=True)
    
    class Meta:
        model = DeliveryProfile
        fields = ['user', 'vehicle_type', 'license_number', 'license_front_image', 'license_back_image', 'is_available', 'is_approved',
                 'current_location_lat', 'current_location_lng', 'created_at', 'updated_at']
        read_only_fields = ['is_approved', 'created_at', 'updated_at']


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
    class Meta:
        model = SellerProfile
        fields = ['shop_name', 'shop_location', 'business_license', 'nrc_number']
    
    def create(self, validated_data):
        user = self.context['request'].user
        seller_profile, created = SellerProfile.objects.update_or_create(
            user=user,
            defaults=validated_data
        )
        return seller_profile


class DeliveryApplicationSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeliveryProfile
        fields = ['vehicle_type', 'license_number', 'license_front_image', 'license_back_image']

    def validate(self, attrs):
        front_image = attrs.get('license_front_image')
        back_image = attrs.get('license_back_image')
        if not front_image or not back_image:
            raise serializers.ValidationError(
                "Driver license front and back images are required."
            )
        return attrs
    
    def create(self, validated_data):
        user = self.context['request'].user
        delivery_profile, created = DeliveryProfile.objects.update_or_create(
            user=user,
            defaults=validated_data
        )
        return delivery_profile
