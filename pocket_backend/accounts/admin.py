import random
import string

from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import (
    BuyerProfile,
    DeliveryProfile,
    ErrorLog,
    PhoneOTP,
    SellerProfile,
    User,
    VerificationRequest,
)


def _generate_staff_password(length=6):
    chars = string.ascii_letters + string.digits
    return ''.join(random.choices(chars, k=length))


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    list_display = ['full_name', 'phone_number', 'email', 'role', 'gender', 'is_verified', 'is_phone_verified', 'date_joined', 'is_active']
    list_filter = ['role', 'gender', 'is_verified', 'is_phone_verified', 'is_active', 'date_joined']
    search_fields = ['full_name', 'phone_number', 'email']
    ordering = ['-date_joined']
    readonly_fields = ['date_joined', 'last_login']

    fieldsets = (
        (None, {'fields': ('phone_number', 'password')}),
        ('Personal info', {'fields': ('full_name', 'gender', 'date_of_birth', 'email')}),
        ('Permissions', {'fields': ('role', 'is_verified', 'is_phone_verified', 'is_active', 'is_staff', 'is_superuser')}),
        ('Important dates', {'fields': ('date_joined', 'last_login')}),
    )

    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': ('phone_number', 'full_name', 'gender', 'role'),
        }),
    )

    def save_model(self, request, obj, form, change):
        if not change and obj.role == 'staff':
            raw = _generate_staff_password()
            obj.set_password(raw)
            request._staff_generated_password = raw
        super().save_model(request, obj, form, change)

    def response_add(self, request, obj, post_url_continue=None):
        response = super().response_add(request, obj, post_url_continue)
        pwd = getattr(request, '_staff_generated_password', None)
        if pwd:
            self.message_user(
                request,
                f'Staff account created. Generated password: {pwd} — copy this now, it cannot be recovered.',
                level='warning',
            )
        return response


@admin.register(BuyerProfile)
class BuyerProfileAdmin(admin.ModelAdmin):
    list_display = ['user', 'preferred_payment_method', 'created_at']
    list_filter = ['preferred_payment_method', 'created_at']
    search_fields = ['user__phone_number']
    readonly_fields = ['created_at', 'updated_at']


@admin.register(SellerProfile)
class SellerProfileAdmin(admin.ModelAdmin):
    list_display = [
        'user', 'shop_name', 'tier1_status', 'tier2_status',
        'is_approved', 'approval_date', 'created_at',
    ]
    list_filter = ['tier1_status', 'tier2_status', 'is_approved', 'created_at']
    search_fields = ['user__phone_number', 'shop_name', 'nrc_number']
    readonly_fields = ['created_at', 'updated_at']
    
    actions = ['approve_tier1_sellers', 'approve_tier2_sellers', 'reject_sellers']
    
    def approve_tier1_sellers(self, request, queryset):
        approved = 0
        for profile in queryset:
            if (
                not profile.nrc_number
                or not profile.nrc_front_image
                or not profile.nrc_back_image
                or not profile.live_verification_photo
            ):
                continue
            verification, _ = VerificationRequest.objects.get_or_create(
                user=profile.user,
                verification_type='seller_tier1',
                defaults={
                    'seller_profile': profile,
                    'submitted_at': profile.submitted_at or profile.created_at,
                },
            )
            if verification.seller_profile_id != profile.id:
                verification.seller_profile = profile
                verification.save(update_fields=['seller_profile', 'updated_at'])
            verification.approve(reviewer=request.user)
            approved += 1
        skipped = queryset.count() - approved
        self.message_user(
            request,
            f"Approved {approved} Tier 1 sellers. Skipped {skipped} missing NRC data or live photo."
        )
    approve_tier1_sellers.short_description = "Approve selected sellers for Tier 1"

    def approve_tier2_sellers(self, request, queryset):
        approved = 0
        for profile in queryset:
            if profile.tier1_status != 'approved' or not profile.business_license:
                continue
            verification, _ = VerificationRequest.objects.get_or_create(
                user=profile.user,
                verification_type='seller_tier2',
                defaults={
                    'seller_profile': profile,
                    'submitted_at': profile.submitted_at or profile.created_at,
                },
            )
            if verification.seller_profile_id != profile.id:
                verification.seller_profile = profile
                verification.save(update_fields=['seller_profile', 'updated_at'])
            verification.approve(reviewer=request.user)
            approved += 1
        skipped = queryset.count() - approved
        self.message_user(
            request,
            f"Approved {approved} Tier 2 sellers. Skipped {skipped} missing Tier 1 approval or business license."
        )
    approve_tier2_sellers.short_description = "Approve selected sellers for Tier 2"

    def reject_sellers(self, request, queryset):
        updated = 0
        for profile in queryset:
            verification_type = 'seller_tier2' if profile.tier2_status == 'submitted' else 'seller_tier1'
            verification, _ = VerificationRequest.objects.get_or_create(
                user=profile.user,
                verification_type=verification_type,
                defaults={
                    'seller_profile': profile,
                    'submitted_at': profile.submitted_at or profile.created_at,
                },
            )
            if verification.seller_profile_id != profile.id:
                verification.seller_profile = profile
                verification.save(update_fields=['seller_profile', 'updated_at'])
            verification.reject(reviewer=request.user)
            updated += 1
        self.message_user(request, f"Rejected {updated} seller profile(s).")
    reject_sellers.short_description = "Reject selected seller verification"


@admin.register(DeliveryProfile)
class DeliveryProfileAdmin(admin.ModelAdmin):
    list_display = [
        'user', 'vehicle_type', 'license_number', 'province', 'town',
        'verification_status', 'is_approved', 'is_available', 'created_at',
    ]
    list_filter = [
        'vehicle_type', 'verification_status', 'is_approved',
        'is_available', 'province', 'created_at',
    ]
    search_fields = ['user__phone_number', 'license_number', 'province', 'town', 'area']
    readonly_fields = ['created_at', 'updated_at']
    
    actions = ['approve_delivery_personnel', 'reject_delivery_personnel']
    
    def approve_delivery_personnel(self, request, queryset):
        approved = 0
        for profile in queryset:
            if (
                not profile.license_front_image
                or not profile.license_back_image
                or not profile.live_verification_photo
            ):
                continue
            verification, _ = VerificationRequest.objects.get_or_create(
                user=profile.user,
                verification_type='delivery',
                defaults={
                    'delivery_profile': profile,
                    'submitted_at': profile.submitted_at or profile.created_at,
                },
            )
            if verification.delivery_profile_id != profile.id:
                verification.delivery_profile = profile
                verification.save(update_fields=['delivery_profile', 'updated_at'])
            verification.approve(reviewer=request.user)
            approved += 1
        skipped = queryset.count() - approved
        self.message_user(
            request,
            f"Approved {approved} delivery personnel. Skipped {skipped} with missing license/live photo."
        )
    approve_delivery_personnel.short_description = "Approve selected delivery personnel"

    def reject_delivery_personnel(self, request, queryset):
        updated = 0
        for profile in queryset:
            verification, _ = VerificationRequest.objects.get_or_create(
                user=profile.user,
                verification_type='delivery',
                defaults={
                    'delivery_profile': profile,
                    'submitted_at': profile.submitted_at or profile.created_at,
                },
            )
            if verification.delivery_profile_id != profile.id:
                verification.delivery_profile = profile
                verification.save(update_fields=['delivery_profile', 'updated_at'])
            verification.reject(reviewer=request.user)
            updated += 1
        self.message_user(request, f"Rejected {updated} delivery profile(s).")
    reject_delivery_personnel.short_description = "Reject selected delivery verification"


@admin.register(VerificationRequest)
class VerificationRequestAdmin(admin.ModelAdmin):
    list_display = [
        'user',
        'verification_type',
        'status',
        'submitted_at',
        'reviewed_at',
        'reviewed_by',
    ]
    list_filter = ['verification_type', 'status', 'submitted_at', 'reviewed_at']
    search_fields = ['user__phone_number', 'user__full_name']
    readonly_fields = ['created_at', 'updated_at']
    actions = ['approve_requests', 'reject_requests']

    def approve_requests(self, request, queryset):
        approved = 0
        for verification in queryset:
            verification.approve(reviewer=request.user)
            approved += 1
        self.message_user(request, f"Approved {approved} verification request(s).")
    approve_requests.short_description = "Approve selected verification requests"

    def reject_requests(self, request, queryset):
        rejected = 0
        for verification in queryset:
            verification.reject(reviewer=request.user)
            rejected += 1
        self.message_user(request, f"Rejected {rejected} verification request(s).")
    reject_requests.short_description = "Reject selected verification requests"


@admin.register(PhoneOTP)
class PhoneOTPAdmin(admin.ModelAdmin):
    list_display = ['phone_number', 'otp_code', 'is_verified', 'attempts', 'created_at']
    list_filter = ['is_verified', 'created_at']
    search_fields = ['phone_number']
    readonly_fields = ['created_at']
    
    def has_add_permission(self, request):
        return False  # Don't allow manual creation through admin


@admin.register(ErrorLog)
class ErrorLogAdmin(admin.ModelAdmin):
    list_display = [
        'reference_id',
        'error_type',
        'status_code',
        'error_class',
        'user',
        'method',
        'path',
        'resolved',
        'created_at',
    ]
    list_filter = ['error_type', 'status_code', 'resolved', 'created_at']
    search_fields = [
        'reference_id',
        'error_code',
        'error_class',
        'message',
        'path',
        'user__phone_number',
        'user__full_name',
    ]
    readonly_fields = [
        'reference_id',
        'user',
        'error_type',
        'error_code',
        'error_class',
        'message',
        'user_message',
        'status_code',
        'method',
        'path',
        'request_data',
        'metadata',
        'traceback',
        'created_at',
        'updated_at',
    ]
    list_per_page = 50
