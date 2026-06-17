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
        'failure_message',
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
    actions = ['mark_as_manually_paid', 'retry_refund']

    @admin.action(description='Retry refund via PawaPay (failed/pending refunds only)')
    def retry_refund(self, request, queryset):
        from .services.pawapay import PawaPayService

        eligible = queryset.filter(
            transaction_type='refund',
            status__in=['pending', 'failed'],
        )
        if not eligible.exists():
            self.message_user(
                request,
                'No eligible refund rows selected (must be type=refund and status=pending or failed).',
                messages.WARNING,
            )
            return

        succeeded, failed = 0, 0
        for tx in eligible.select_related('order', 'recipient'):
            tx.status = 'pending'
            tx.failure_message = ''
            tx.save(update_fields=['status', 'failure_message', 'updated_at'])
            try:
                result = PawaPayService.initiate_refund(tx)
                if result:
                    succeeded += 1
                else:
                    failed += 1
            except Exception as exc:
                tx.status = 'failed'
                tx.failure_message = str(exc)[:200]
                tx.save(update_fields=['status', 'failure_message', 'updated_at'])
                failed += 1

        if succeeded:
            self.message_user(
                request,
                f'{succeeded} refund(s) submitted to PawaPay. '
                f'Status will update when PawaPay webhooks back.',
                messages.SUCCESS,
            )
        if failed:
            self.message_user(
                request,
                f'{failed} refund(s) failed — check failure_message on the transaction.',
                messages.ERROR,
            )

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
