"""Single source of truth for seller/rider earnings and available balance.

Used by the seller/rider payout screen (payments.views.RequestPayoutView)
and the staff withdrawals list (payments.staff_views.StaffWithdrawalsView)
so both always show the same numbers.
"""
from decimal import Decimal

from django.db.models import Sum

from .models import Transaction

# A payout row only counts as "earned" once the goods have actually moved —
# i.e. the QR scan advanced it past the *_pending_scan stages. Rows created
# when the buyer paid (but before pickup) are not earnings yet, because the
# order can still be cancelled and the buyer refunded.
EARNED_STAGES = ('ready_for_payout', 'payout_sent', 'payout_paid')

_CENTS = Decimal('0.01')


def earnings_breakdown(user, role_key):
    """Return quantized Decimal totals for one seller or rider."""
    base = Transaction.objects.filter(
        transaction_type='payout',
        recipient=user,
        recipient_role=role_key,
    )

    # Earned from completed handovers (per-order rows, post QR scan).
    total_earned = (
        base.filter(
            trigger_event__in=['pickup_qr', 'dropoff_qr'],
            payout_stage__in=EARNED_STAGES,
        )
        .exclude(status='failed')
        .aggregate(total=Sum('amount'))['total']
        or Decimal('0.00')
    )

    # Paid directly from the staff payout queue (per-order, not via claim).
    queue_already_paid = (
        base.filter(
            trigger_event__in=['pickup_qr', 'dropoff_qr'],
            status='completed',
            payout_stage='payout_paid',
        ).aggregate(total=Sum('amount'))['total']
        or Decimal('0.00')
    )

    # All completed payouts, any method — queue payments and manual claims.
    total_paid_out = (
        base.filter(
            status='completed',
            payout_stage='payout_paid',
        ).aggregate(total=Sum('amount'))['total']
        or Decimal('0.00')
    )

    # Manual withdrawal claims submitted but not yet paid.
    pending_withdrawals = (
        base.filter(
            trigger_event='manual',
            status__in=['pending', 'accepted'],
        ).aggregate(total=Sum('amount'))['total']
        or Decimal('0.00')
    )

    available = total_earned - total_paid_out - pending_withdrawals

    return {
        'total_earned': total_earned.quantize(_CENTS),
        'queue_already_paid': queue_already_paid.quantize(_CENTS),
        'total_paid_out': total_paid_out.quantize(_CENTS),
        'pending_withdrawals': pending_withdrawals.quantize(_CENTS),
        'available': available.quantize(_CENTS),
    }
