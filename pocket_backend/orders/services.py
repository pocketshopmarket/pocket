"""
Shared order-lifecycle helpers used by views, management commands, and webhooks.

Centralises cancel → refund → restock logic so every cancellation path
(seller-initiated, buyer-initiated, auto-timeout) behaves identically.
"""

import logging

from django.db import transaction as db_transaction

from orders.models import Order, OrderItem
from payments.models import Transaction
from payments.services.pawapay import PawaPayService
from products.models import Product, ProductVariant

logger = logging.getLogger(__name__)


def _notify_staff_refund(refund_tx):
    """Alert staff that a refund needs to be sent manually."""
    try:
        from payments.staff_views import notify_staff_new_refund
        notify_staff_new_refund(refund_tx)
    except Exception as exc:
        logger.warning('Staff refund notification failed: %s', exc)


def _create_and_attempt_refund(locked_order, *, trigger_event: str, force_auto_refund: bool = False):
    """
    Create a refund Transaction for locked_order and attempt it via the
    PawaPay gateway when applicable, falling back to the manual staff queue
    on failure. Shared by both pre-delivery cancellation and post-delivery
    refund-request approval so they can never diverge in how a refund is
    actually paid out.

    Returns the created Transaction, or None if there's nothing to refund
    (no completed deposit) or a refund already exists for this order. Must
    be called from inside a transaction with locked_order already locked
    via select_for_update() to avoid a duplicate refund race.
    """
    deposit_tx = (
        Transaction.objects.filter(
            order=locked_order,
            transaction_type='deposit',
            status='completed',
        )
        .order_by('-created_at')
        .first()
    )
    has_refund = Transaction.objects.filter(
        order=locked_order,
        transaction_type='refund',
    ).exists()

    if not deposit_tx or has_refund:
        return None

    from portal.models import PlatformSettings
    payout_method = PlatformSettings.get().payout_method
    auto_refund = payout_method == 'gateway' or force_auto_refund

    refund_tx = Transaction.objects.create(
        order=locked_order,
        transaction_type='refund',
        amount=locked_order.grand_total,
        currency=deposit_tx.currency,
        provider=deposit_tx.provider,
        payer_number=deposit_tx.payer_number,
        recipient=locked_order.buyer,
        recipient_role='buyer',
        trigger_event=trigger_event,
        payout_method='gateway' if auto_refund else 'manual',
        status='pending',
    )

    if auto_refund:
        try:
            PawaPayService.initiate_refund(refund_tx)
        except Exception as exc:
            logger.error(
                'Refund initiation failed for order %s: %s',
                locked_order.order_number,
                exc,
            )
        if refund_tx.status not in ('accepted', 'completed'):
            # Gateway attempt failed — hand over to staff so the buyer
            # still gets refunded manually.
            refund_tx.status = 'pending'
            refund_tx.payout_method = 'manual'
            refund_tx.save(update_fields=['status', 'payout_method', 'updated_at'])
            _notify_staff_refund(refund_tx)
    else:
        # Manual mode — staff sends the money from the platform phone and
        # marks it refunded in the staff app.
        _notify_staff_refund(refund_tx)

    return refund_tx


def issue_refund_for_delivered_order(order: Order, *, reason: str = '') -> bool:
    """
    Refund a buyer for an order that already reached 'delivered' — used
    when a seller/admin approves a post-delivery RefundRequest. Unlike
    cancel_order_with_refund, this never touches Order.status or restocks
    products: the goods were actually delivered, so the order stays
    'delivered', only the money moves back.

    Returns True if a refund was created, False if the order isn't
    'delivered' or a refund already exists for it.
    """
    with db_transaction.atomic():
        locked_order = Order.objects.select_for_update().get(pk=order.pk)
        if locked_order.status != 'delivered':
            return False

        refund_tx = _create_and_attempt_refund(
            locked_order, trigger_event='refund_request',
        )
        if refund_tx is None:
            return False

    logger.info(
        'Refund issued for delivered order %s. Reason: %s',
        locked_order.order_number,
        reason or 'unspecified',
    )
    return True


def sync_refund_request_status(transaction):
    """
    If a completed refund Transaction belongs to an order with a
    RefundRequest (buyer complaint on an already-delivered order), mark
    that request 'refunded' now that money has actually moved. No-op for
    cancellation-triggered refunds, which have no RefundRequest.

    Called from every place a refund Transaction can reach status
    'completed' (PawaPay webhook, staff mark-refunded, admin action) so
    RefundRequest.status always reflects real money movement instead of
    just the approval decision.
    """
    if transaction.transaction_type != 'refund' or transaction.status != 'completed':
        return
    from .models import RefundRequest
    RefundRequest.objects.filter(order=transaction.order).exclude(
        status='refunded'
    ).update(status='refunded')


def cancel_order_with_refund(order: Order, *, reason: str = '') -> bool:
    """
    Atomically cancel an order, restore stock, and initiate a PawaPay refund
    if the buyer already paid.

    Returns True if the order was successfully cancelled, False if it was in a
    non-cancellable state.

    Parameters
    ----------
    order : Order
        The order to cancel.  Must be in a cancellable status
        (``pending``, ``accepted``, or ``preparing``).
    reason : str, optional
        Human-readable reason stored on the refund transaction.
    """
    NON_CANCELLABLE = {'out_for_delivery', 'delivered', 'cancelled'}

    if order.status in NON_CANCELLABLE:
        return False

    with db_transaction.atomic():
        # Re-fetch with a row lock to prevent concurrent mutations.
        locked_order = Order.objects.select_for_update().get(pk=order.pk)
        if locked_order.status in NON_CANCELLABLE:
            return False

        # Status at the moment of cancellation decides the refund path:
        # before the seller accepted, the buyer's money bounces back
        # automatically via the gateway.
        pre_cancel_status = locked_order.status

        # ── 1. Restore product stock ──────────────────────────────────
        items = list(
            OrderItem.objects.filter(order=locked_order)
            .select_related('product', 'variant')
        )
        product_ids = [item.product_id for item in items]
        variant_ids = [item.variant_id for item in items if item.variant_id]

        locked_products = {
            p.id: p
            for p in Product.objects.select_for_update().filter(id__in=product_ids)
        }
        locked_variants = {
            v.id: v
            for v in ProductVariant.objects.select_for_update().filter(id__in=variant_ids)
        } if variant_ids else {}

        for item in items:
            product = locked_products.get(item.product_id)
            if product is None:
                continue
            product.stock_quantity += item.quantity
            product.is_available = True
            product.save(
                update_fields=['stock_quantity', 'is_available', 'updated_at']
            )

            variant = locked_variants.get(item.variant_id) if item.variant_id else None
            if variant is not None:
                variant.stock_quantity += item.quantity
                variant.is_active = True
                variant.save(
                    update_fields=['stock_quantity', 'is_active', 'updated_at']
                )

        # ── 2. Cancel the order ───────────────────────────────────────
        locked_order.status = 'cancelled'
        locked_order.save(update_fields=['status', 'updated_at'])

        # ── 3. Refund buyer if they paid ──────────────────────────────
        # Orders cancelled before the seller accepted always try the
        # automatic gateway refund, even when payouts run in manual mode —
        # no goods moved, so the deposit simply bounces back.
        _create_and_attempt_refund(
            locked_order,
            trigger_event='order_cancelled',
            force_auto_refund=pre_cancel_status in ('payment_pending', 'pending'),
        )

        # ── 4. Cancel any pending payout rows ─────────────────────────
        Transaction.objects.filter(
            order=locked_order,
            transaction_type='payout',
            status__in=['pending', 'accepted'],
        ).update(status='failed', failure_message=reason or 'Order cancelled')

    logger.info(
        'Order %s cancelled and refunded. Reason: %s',
        locked_order.order_number,
        reason or 'unspecified',
    )
    return True
