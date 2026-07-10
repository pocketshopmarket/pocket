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

        if deposit_tx and not has_refund:
            from portal.models import PlatformSettings
            payout_method = PlatformSettings.get().payout_method

            refund_tx = Transaction.objects.create(
                order=locked_order,
                transaction_type='refund',
                amount=locked_order.grand_total,
                currency=deposit_tx.currency,
                provider=deposit_tx.provider,
                payer_number=deposit_tx.payer_number,
                recipient=locked_order.buyer,
                recipient_role='buyer',
                trigger_event='order_cancelled',
                payout_method=payout_method,
                status='pending',
            )
            if payout_method == 'gateway':
                try:
                    PawaPayService.initiate_refund(refund_tx)
                except Exception as exc:
                    logger.error(
                        'Refund initiation failed for order %s: %s',
                        locked_order.order_number,
                        exc,
                    )
            else:
                # Manual mode — staff sends the money from the platform phone
                # and marks it refunded in the staff app.
                try:
                    from payments.staff_views import notify_staff_new_refund
                    notify_staff_new_refund(refund_tx)
                except Exception as exc:
                    logger.warning('Staff refund notification failed: %s', exc)

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
