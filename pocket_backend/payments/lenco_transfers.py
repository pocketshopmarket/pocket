"""
Sending money out through Lenco: card refunds (to the buyer's mobile money
number) and seller bank payouts. Everything Lenco reports back is applied
here, once, under a row lock — the webhook, the staff screen and the
background sync can all call it without double-settling anything.
"""
import logging
from decimal import Decimal, InvalidOperation

from django.db import transaction as db_transaction
from django.utils import timezone

from .mobile_money import InvalidMobileNumber, parse_mobile_money_number
from .models import Transaction
from .services.lenco import LencoError, LencoService

logger = logging.getLogger(__name__)


class CannotSend(Exception):
    """This transaction can't be sent through Lenco; the message is safe to show staff."""


def is_lenco_transfer(tx):
    """Refunds of card payments and bank payouts move through Lenco; everything else does not."""
    if tx.gateway != 'lenco':
        return False
    return tx.transaction_type == 'refund' or (
        tx.transaction_type == 'payout' and tx.payment_method == 'bank'
    )


def _initiate(tx):
    if tx.transaction_type == 'refund':
        try:
            phone, operator = parse_mobile_money_number(tx.payer_number)
        except InvalidMobileNumber as exc:
            raise CannotSend('No valid mobile money number is on file for this refund.') from exc
        return LencoService.initiate_mobile_money_transfer(
            reference=tx.transaction_id, amount=tx.amount,
            phone='0' + phone[4:], operator=operator,
            narration=f'Pocket Shop refund {tx.order.order_number}',
        )
    account = tx.bank_account
    if account is None:
        raise CannotSend('No bank account is attached to this payout.')
    return LencoService.initiate_bank_transfer(
        reference=tx.transaction_id, amount=tx.amount,
        account_number=account.account_number, bank_id=account.bank_id,
        narration=f'Pocket Shop payout {tx.order.order_number}', country=account.country,
    )


def send_via_lenco(tx_id, *, allow_name_mismatch=False):
    """
    Start the Lenco transfer for a pending refund/bank payout. Returns the
    updated Transaction. Raises CannotSend (nothing was sent) or LencoError
    (Lenco refused/unreachable; the transaction stays pending so staff can retry).
    """
    with db_transaction.atomic():
        tx = (
            Transaction.objects.select_for_update(of=('self',))
            .select_related('order', 'bank_account', 'recipient')
            .get(pk=tx_id)
        )
        if not is_lenco_transfer(tx):
            raise CannotSend('This transaction is not paid through Lenco.')
        if tx.status != 'pending':
            raise CannotSend(f'This transaction is already {tx.status}.')
        if tx.transaction_type == 'payout' and tx.payout_stage != 'ready_for_payout':
            raise CannotSend('This payout is not ready to be sent yet.')
        if (tx.transaction_type == 'payout' and tx.bank_account
                and not tx.bank_account.name_matches and not allow_name_mismatch):
            raise CannotSend(
                "The bank account's holder name does not match the seller's registered name. "
                'Check it, then confirm to send anyway.'
            )

        try:
            data = _initiate(tx)
        except LencoError as exc:
            refusal = exc  # recorded below, outside this block: raising here would roll the note back
        else:
            refusal = None
            tx.status = 'accepted'  # in flight; the outcome arrives from Lenco
            tx.payout_method = 'gateway'
            tx.failure_message = ''
            if tx.transaction_type == 'payout':
                tx.payout_stage = 'payout_sent'
            tx.save()

    if refusal is not None:
        Transaction.objects.filter(pk=tx_id).update(failure_message=str(refusal)[:500])
        raise refusal

    # Lenco sometimes finishes instantly; otherwise the webhook/sync settles it.
    if data and data.get('status') in ('successful', 'failed'):
        return apply_lenco_transfer(tx.pk, data)
    return tx


def _money(value):
    try:
        return Decimal(str(value))
    except (InvalidOperation, TypeError):
        return None


def apply_lenco_transfer(tx_id, data):
    """Apply a Lenco transfer (`data` of GET /transfers/status/{reference}) to our record."""
    notify = None
    with db_transaction.atomic():
        tx = (
            Transaction.objects.select_for_update(of=('self',))
            .select_related('order', 'recipient')
            .get(pk=tx_id)
        )
        if tx.status in ('completed', 'failed') or not is_lenco_transfer(tx):
            return tx
        if str(data.get('reference')) != str(tx.transaction_id):
            logger.error('Lenco transfer reference mismatch on %s: %s', tx.transaction_id, data.get('reference'))
            return tx

        outcome = data.get('status')
        tx.gateway_reference = str(data.get('lencoReference') or tx.gateway_reference)[:64]
        fee = _money(data.get('fee'))
        if fee is not None:
            tx.gateway_fee = fee

        if outcome == 'successful':
            tx.status = 'completed'
            tx.marked_paid_at = timezone.now()
            if tx.transaction_type == 'payout':
                tx.payout_stage = 'payout_paid'
                notify = 'payout_paid'
            else:
                notify = 'refund_paid'
        elif outcome == 'failed':
            reason = data.get('reasonForFailure') or 'Transfer failed'
            tx.failure_message = reason
            if tx.transaction_type == 'payout':
                # Nothing left the platform, so the earnings come back
                # automatically (failed payouts don't count as paid).
                tx.status = 'failed'
                tx.payout_stage = 'payout_failed'
                notify = 'payout_failed'
            else:
                # The buyer is still owed the money — back to staff.
                tx.status = 'pending'
                tx.payout_method = 'manual'
                notify = 'refund_failed'
        tx.save()

    try:
        if notify == 'payout_paid':
            from notifications.signals import create_payout_completed_notification
            create_payout_completed_notification(tx)
        elif notify == 'refund_paid':
            from notifications.signals import notify_buyer_refund_completed
            from orders.services import sync_refund_request_status
            sync_refund_request_status(tx)
            notify_buyer_refund_completed(tx)
        elif notify == 'payout_failed':
            from .staff_views import notify_staff_payout_failed
            notify_staff_payout_failed(tx)
        elif notify == 'refund_failed':
            from .staff_views import notify_staff_new_refund
            notify_staff_new_refund(tx)
    except Exception:
        logger.exception('Post-transfer notification failed for %s', tx.transaction_id)
    return tx


def sync_lenco_transfer(tx):
    """Ask Lenco how an in-flight transfer ended and apply it. Safe to call often."""
    if not is_lenco_transfer(tx) or tx.status != 'accepted':
        return tx
    try:
        data = LencoService.get_transfer_status(str(tx.transaction_id))
    except LencoError:
        return tx
    if not data:
        return tx
    return apply_lenco_transfer(tx.pk, data)
