from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from .models import User, BuyerProfile, SellerProfile, DeliveryProfile, PhoneOTP


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    list_display = ['full_name', 'phone_number', 'email', 'role', 'gender', 'is_verified', 'is_phone_verified', 'date_joined', 'is_active']
    list_filter = ['role', 'gender', 'is_verified', 'is_phone_verified', 'is_active', 'date_joined']
    search_fields = ['full_name', 'phone_number', 'email']
    ordering = ['-date_joined']
    
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


@admin.register(BuyerProfile)
class BuyerProfileAdmin(admin.ModelAdmin):
    list_display = ['user', 'preferred_payment_method', 'created_at']
    list_filter = ['preferred_payment_method', 'created_at']
    search_fields = ['user__phone_number']
    readonly_fields = ['created_at', 'updated_at']


@admin.register(SellerProfile)
class SellerProfileAdmin(admin.ModelAdmin):
    list_display = ['user', 'shop_name', 'is_approved', 'approval_date', 'created_at']
    list_filter = ['is_approved', 'created_at']
    search_fields = ['user__phone_number', 'shop_name']
    readonly_fields = ['created_at', 'updated_at']
    
    actions = ['approve_sellers']
    
    def approve_sellers(self, request, queryset):
        approved = 0
        for profile in queryset:
            if not profile.nrc_number:
                continue
            profile.is_approved = True
            profile.full_clean()
            profile.save()
            approved += 1
        skipped = queryset.count() - approved
        self.message_user(
            request,
            f"Approved {approved} sellers. Skipped {skipped} without NRC."
        )
    approve_sellers.short_description = "Approve selected sellers"


@admin.register(DeliveryProfile)
class DeliveryProfileAdmin(admin.ModelAdmin):
    list_display = ['user', 'vehicle_type', 'license_number', 'is_approved', 'is_available', 'created_at']
    list_filter = ['vehicle_type', 'is_approved', 'is_available', 'created_at']
    search_fields = ['user__phone_number', 'license_number']
    readonly_fields = ['created_at', 'updated_at']
    
    actions = ['approve_delivery_personnel']
    
    def approve_delivery_personnel(self, request, queryset):
        approved = 0
        for profile in queryset:
            if not profile.license_front_image or not profile.license_back_image:
                continue
            profile.is_approved = True
            profile.full_clean()
            profile.save()
            approved += 1
        skipped = queryset.count() - approved
        self.message_user(
            request,
            f"Approved {approved} delivery personnel. Skipped {skipped} with missing license images."
        )
    approve_delivery_personnel.short_description = "Approve selected delivery personnel"


@admin.register(PhoneOTP)
class PhoneOTPAdmin(admin.ModelAdmin):
    list_display = ['phone_number', 'otp_code', 'is_verified', 'attempts', 'created_at']
    list_filter = ['is_verified', 'created_at']
    search_fields = ['phone_number']
    readonly_fields = ['created_at']
    
    def has_add_permission(self, request):
        return False  # Don't allow manual creation through admin
