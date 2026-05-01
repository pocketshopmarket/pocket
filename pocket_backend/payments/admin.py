from django.contrib import admin
from .models import Transaction


@admin.register(Transaction)
class TransactionAdmin(admin.ModelAdmin):
    list_display = [
        'transaction_id',
        'transaction_type',
        'amount',
        'currency',
        'provider',
        'status',
        'payout_stage',
        'recipient_role',
        'trigger_event',
        'created_at',
    ]
    list_filter = [
        'transaction_type',
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
