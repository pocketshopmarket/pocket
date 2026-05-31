from django.contrib import admin, messages

from notifications.signals import create_payout_completed_notification
from .models import Transaction


@admin.register(Transaction)
class TransactionAdmin(admin.ModelAdmin):
    list_display = [
        'transaction_id',
        'transaction_type',
        'amount',
        'currency',
        'provider',
        'payout_method',
        'status',
        'payout_stage',
        'recipient_role',
        'trigger_event',
        'created_at',
    ]
    list_filter = [
        'transaction_type',
        'payout_method',
        'status',
        'payout_stage',
        'recipient_role',
        'provider',
    ]
    search_fields = [
        'transaction_id',
        'payer_number',
        'order__order_number',
    ]
    readonly_fields = ['transaction_id', 'created_at', 'updated_at']
    raw_id_fields = ['order', 'recipient']
    ordering = ['-created_at']
    actions = ['mark_as_manually_paid']

    @admin.action(description='Mark selected as manually paid (manual payouts only)')
    def mark_as_manually_paid(self, request, queryset):
        eligible = queryset.filter(
            transaction_type='payout',
            payout_method='manual',
            status__in=['pending', 'accepted'],
        )
        count = eligible.count()
        if count == 0:
            self.message_user(
                request,
                'No eligible manual payout rows selected (must be payout + manual + pending/accepted).',
                messages.WARNING,
            )
            return

        for tx in eligible.select_related('recipient'):
            tx.status = 'completed'
            tx.payout_stage = 'payout_paid'
            tx.save(update_fields=['status', 'payout_stage', 'updated_at'])
            try:
                create_payout_completed_notification(tx)
            except Exception:
                pass

        self.message_user(request, f'{count} payout(s) marked as paid and recipients notified.')
