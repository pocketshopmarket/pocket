from django.contrib import admin, messages
from django.db.models import Count, Q
from django.utils import timezone
from django.utils.html import format_html

from . import emails
from .models import Partner, PartnerEarning, PayoutRequest, PromoCode, PromoSettings, Referral


@admin.register(PromoSettings)
class PromoSettingsAdmin(admin.ModelAdmin):
    fieldsets = [
        ('Welcome discount (every new buyer, first order)', {'fields': [
            'welcome_enabled', 'welcome_discount_type', 'welcome_discount_value',
            'welcome_max_discount', 'welcome_min_order', 'welcome_valid_days',
        ]}),
        ('Partners', {'fields': [
            'partner_commission_rate', 'partner_window_days', 'partner_hold_days',
            'partner_min_payout', 'staff_email',
        ]}),
    ]

    def has_add_permission(self, request):
        return not PromoSettings.objects.exists()

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(PromoCode)
class PromoCodeAdmin(admin.ModelAdmin):
    list_display = ['code', 'deal', 'min_order', 'used', 'max_uses', 'starts_at', 'ends_at', 'is_active']
    list_filter = ['is_active', 'discount_type', 'first_order_only']
    search_fields = ['code', 'description']
    fields = [
        'code', 'description', 'discount_type', 'value', 'max_discount', 'min_order',
        'starts_at', 'ends_at', 'max_uses', 'max_uses_per_user', 'first_order_only', 'is_active',
    ]

    def get_queryset(self, request):
        return super().get_queryset(request).annotate(
            _used=Count('orders', filter=~Q(orders__status__in=['cancelled', 'payment_pending'])),
        )

    @admin.display(description='Deal')
    def deal(self, obj):
        cap = f' (up to K{obj.max_discount})' if obj.max_discount is not None else ''
        if obj.discount_type == 'fixed':
            return f'K{obj.value} off'
        return f'{obj.value.normalize()}% off{cap}'

    @admin.display(description='Paid orders', ordering='_used')
    def used(self, obj):
        return obj._used


class EarningInline(admin.TabularInline):
    model = PartnerEarning
    extra = 0
    can_delete = False
    fields = ['created_at', 'order', 'service_fee', 'rate', 'amount', 'status', 'available_at']
    readonly_fields = fields
    ordering = ['-created_at']

    def has_add_permission(self, request, obj=None):
        return False


class PayoutInline(admin.TabularInline):
    model = PayoutRequest
    extra = 0
    can_delete = False
    fields = ['requested_at', 'amount_requested', 'status', 'paid_amount', 'reference', 'paid_at']
    readonly_fields = fields
    show_change_link = True

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(Partner)
class PartnerAdmin(admin.ModelAdmin):
    list_display = ['name', 'code', 'status', 'source', 'signups', 'owed', 'created_at']
    list_filter = ['status', 'source']
    search_fields = ['name', 'email', 'code', 'phone']
    actions = ['approve', 'reject', 'pause', 'resend_invite']
    inlines = [PayoutInline, EarningInline]
    readonly_fields = ['links', 'money', 'source', 'agreed_terms_at', 'approved_at', 'invite_expires_at', 'created_at']
    fieldsets = [
        (None, {'fields': ['name', 'email', 'phone', 'code', 'status', 'promotes_on']}),
        ('Payment details', {'fields': ['payout_method', 'payout_details', 'commission_rate']}),
        ('Links & money', {'fields': ['links', 'money']}),
        ('History', {'fields': ['source', 'agreed_terms_at', 'approved_at', 'invite_expires_at', 'created_at', 'staff_notes']}),
    ]

    def get_queryset(self, request):
        return super().get_queryset(request).annotate(_signups=Count('referrals'))

    @admin.display(description='Sign-ups', ordering='_signups')
    def signups(self, obj):
        return obj._signups

    @admin.display(description='Owed (K)')
    def owed(self, obj):
        return obj.balances()['owed']

    @admin.display(description='Links')
    def links(self, obj):
        if not obj.pk:
            return 'Save first.'
        return format_html(
            'Partner page: <a href="{0}" target="_blank">{0}</a><br>Share link: <a href="{1}" target="_blank">{1}</a>',
            emails.partner_page_url(obj), emails.share_url(obj),
        )

    @admin.display(description='Money')
    def money(self, obj):
        if not obj.pk:
            return '—'
        b = obj.balances()
        return format_html(
            'Earned K{} · Waiting (hold) K{} · Paid K{} · <b>Owed K{}</b> · Can request K{}',
            b['earned'], b['on_hold'], b['paid'], b['owed'], b['requestable'],
        )

    def get_changeform_initial_data(self, request):
        return {'status': Partner.INVITED}

    def save_model(self, request, obj, form, change):
        if not change:
            obj.source = 'admin'
            if obj.status == Partner.INVITED:
                obj.new_invite()
            elif obj.status == Partner.APPROVED:
                obj.approved_at = timezone.now()
        super().save_model(request, obj, form, change)
        if not change and obj.status == Partner.INVITED:
            self._notify(request, emails.send_invite(obj), f'Invite sent to {obj.email}.')
        elif not change and obj.status == Partner.APPROVED:
            self._notify(request, emails.send_approved(obj), f'Welcome email sent to {obj.email}.')

    def _notify(self, request, ok, success_text):
        if ok:
            self.message_user(request, success_text)
        else:
            self.message_user(request, 'Saved, but the email could not be sent. Check the email settings.', messages.WARNING)

    @admin.action(description='Approve (sends their code and partner page)')
    def approve(self, request, queryset):
        count = 0
        for p in queryset.exclude(status=Partner.APPROVED):
            was_paused = p.status == Partner.PAUSED
            p.status = Partner.APPROVED
            p.approved_at = p.approved_at or timezone.now()
            p.save(update_fields=['status', 'approved_at'])
            if not was_paused:
                emails.send_approved(p)
            count += 1
        self.message_user(request, f'{count} partner(s) approved.')

    @admin.action(description='Reject (sends a polite "not this time" email)')
    def reject(self, request, queryset):
        count = 0
        for p in queryset.filter(status=Partner.APPLIED):
            p.status = Partner.REJECTED
            p.save(update_fields=['status'])
            emails.send_rejected(p)
            count += 1
        self.message_user(request, f'{count} application(s) rejected.')

    @admin.action(description='Pause (their code stops earning)')
    def pause(self, request, queryset):
        n = queryset.filter(status=Partner.APPROVED).update(status=Partner.PAUSED)
        self.message_user(request, f'{n} partner(s) paused.')

    @admin.action(description='Resend invite')
    def resend_invite(self, request, queryset):
        count = 0
        for p in queryset.filter(status=Partner.INVITED):
            p.new_invite()
            p.save(update_fields=['invite_token', 'invite_expires_at'])
            emails.send_invite(p)
            count += 1
        self.message_user(request, f'{count} invite(s) sent again.')


@admin.register(PayoutRequest)
class PayoutRequestAdmin(admin.ModelAdmin):
    list_display = ['partner', 'amount_requested', 'status', 'pay_to', 'requested_at', 'paid_amount', 'paid_at']
    list_filter = ['status']
    search_fields = ['partner__name', 'partner__code', 'reference']
    readonly_fields = ['partner', 'amount_requested', 'pay_to', 'requested_at', 'paid_at']
    fields = ['partner', 'amount_requested', 'pay_to', 'requested_at', 'status', 'paid_amount', 'reference', 'staff_note', 'paid_at']

    @admin.display(description='Pay to')
    def pay_to(self, obj):
        p = obj.partner
        return f'{p.get_payout_method_display() or "—"}: {p.payout_details or "—"}'

    def has_add_permission(self, request):
        return False

    def save_model(self, request, obj, form, change):
        becoming_paid = change and 'status' in form.changed_data and obj.status == PayoutRequest.PAID
        if becoming_paid:
            obj.paid_at = timezone.now()
            if obj.paid_amount is None:
                obj.paid_amount = obj.amount_requested
        super().save_model(request, obj, form, change)
        if becoming_paid:
            if emails.send_payout_sent(obj):
                self.message_user(request, f'Marked paid. {obj.partner.name} was emailed.')
            else:
                self.message_user(request, 'Marked paid, but the email could not be sent.', messages.WARNING)


@admin.register(PartnerEarning)
class PartnerEarningAdmin(admin.ModelAdmin):
    list_display = ['created_at', 'partner', 'order', 'service_fee', 'rate', 'amount', 'status', 'available_at']
    list_filter = ['status', 'partner']
    readonly_fields = [f.name for f in PartnerEarning._meta.fields]

    def has_add_permission(self, request):
        return False


@admin.register(Referral)
class ReferralAdmin(admin.ModelAdmin):
    list_display = ['created_at', 'user', 'partner', 'code_used']
    list_filter = ['partner']
    search_fields = ['user__phone_number', 'code_used']
    readonly_fields = ['user', 'partner', 'code_used', 'created_at']

    def has_add_permission(self, request):
        return False
