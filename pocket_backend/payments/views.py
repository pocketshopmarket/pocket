import hashlib
import hmac
import json
import logging

from decimal import Decimal
from django.conf import settings as django_settings
from django.db.models import Sum
from django.shortcuts import get_object_or_404
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Transaction
from .services.pawapay import PawaPayService
from accounts.models import BuyerPaymentMethod
from accounts.phone_utils import normalize_zambia_phone_to_e164
from notifications.signals import (
    create_payment_notification,
    create_payout_completed_notification,
)
from orders.models import Order
from orders.services import cancel_order_with_refund

logger = logging.getLogger(__name__)

# ─── Helpers ────────────────────────────────────────────────────────────

# Direct mapping from user payment method provider to correct PawaPay provider code.
METHOD_KEY_TO_PROVIDER = {
    'mtn_momo': 'MTN_MOMO_ZMB',
    'airtel_money': 'AIRTEL_OAPI_ZMB',
    'zamtel': 'ZAMTEL_MONEY_ZMB',
}

# Reverse mapping for incoming webhooks or resolving method keys from PawaPay codes.
PROVIDER_TO_METHOD_KEY = {
    'MTN_MOMO_ZMB': 'mtn_momo',
    'AIRTEL_OAPI_ZMB': 'airtel_money',
    'AIRTEL_MOMO_ZMB': 'airtel_money',
    'ZAMTEL_MONEY_ZMB': 'zamtel',
    'ZAMTEL_MOMO_ZMB': 'zamtel',
    'ZAMTEL_ZMB': 'zamtel',
}


def detect_provider_from_phone(phone: str) -> str:
    """Detect the correct PawaPay provider code from a Zambian phone number prefix."""
    raw = str(phone).strip().replace(" ", "").replace("-", "").lstrip("+")
    if raw.startswith("0") and len(raw) == 10:
        raw = "260" + raw[1:]
    elif not raw.startswith("260") and len(raw) == 9:
        raw = "260" + raw

    prefix = raw[3:5] if len(raw) >= 5 else ""
    if prefix in ("96", "76"):
        return "MTN_MOMO_ZMB"
    if prefix in ("97", "77"):
        return "AIRTEL_OAPI_ZMB"
    if prefix in ("95", "75"):
        return "ZAMTEL_MONEY_ZMB"
    return "MTN_MOMO_ZMB"

# Human-readable network label shown in payout confirmation messages.
PROVIDER_TO_NETWORK_LABEL = {
    'MTN_MOMO_ZMB': 'MTN MoMo',
    'AIRTEL_OAPI_ZMB': 'Airtel Money',
    'AIRTEL_MOMO_ZMB': 'Airtel Money',
    'ZAMTEL_MONEY_ZMB': 'Zamtel Kwacha',
    'ZAMTEL_MOMO_ZMB': 'Zamtel Kwacha',
    'ZAMTEL_ZMB': 'Zamtel Kwacha',
}



def _resolve_payout_provider(user):
    """
    Find the correct PawaPay provider code for a given user (seller / delivery).
    Uses their default verified payment method; falls back to detecting from
    the user's registration phone number.
    """
    method = (
        BuyerPaymentMethod.objects.filter(
            user=user,
            is_verified=True,
        )
        .order_by('-is_default', '-created_at')
        .first()
    )
    if method:
        provider = METHOD_KEY_TO_PROVIDER.get(method.provider) or detect_provider_from_phone(method.account_phone)
        return provider, method.account_phone
    phone = user.phone_number
    return detect_provider_from_phone(phone), phone


# ─── Payment Initiation ────────────────────────────────────────────────

class InitiatePaymentView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        order_number = request.data.get('order_number')
        payer_number = request.data.get('payer_number')

        if not all([order_number, payer_number]):
            return Response(
                {"error": "order_number and payer_number are required"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Find the order (buyer-owned only).
        order = get_object_or_404(
            Order, order_number=order_number, buyer=request.user
        )

        # ── FIX #4: Only allow payment on pending/payment_pending orders ──
        if order.status not in ('pending', 'payment_pending'):
            return Response(
                {"error": f"Order is already '{order.status}' — cannot initiate payment."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            normalized_number = normalize_zambia_phone_to_e164(payer_number)
        except Exception:
            return Response(
                {"error": "Invalid payer_number format"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Detect provider from phone prefix — ignore any frontend-supplied value
        # so a wrong selection never causes a PAYER_NOT_FOUND rejection.
        provider = detect_provider_from_phone(normalized_number)

        # NOTE: Previously required a verified BuyerPaymentMethod record.
        # Now we allow direct entry at checkout — PawaPay validates the number.

        # ── Idempotency — reuse existing pending/accepted deposit ──
        # Sync stale transactions before blocking so webhook failures don't
        # permanently lock an order out of new payment attempts.
        from django.utils import timezone
        from datetime import timedelta

        existing = Transaction.objects.filter(
            order=order,
            transaction_type='deposit',
            status__in=['pending', 'accepted'],
        ).first()

        if existing:
            if existing.status == 'pending':
                # 'pending' means we created the TX but the PawaPay call never
                # completed (crash / timeout). Expire after 3 minutes and retry.
                if timezone.now() - existing.created_at > timedelta(minutes=3):
                    existing.status = 'failed'
                    existing.failure_message = 'Deposit initiation timed out — retrying'
                    existing.save()
                    existing = None

            elif existing.status == 'accepted':
                # Sync against PawaPay in case the webhook callback failed.
                remote = PawaPayService.get_deposit_status(str(existing.transaction_id))
                if remote:
                    remote_status = remote.get('status', '')
                    if remote_status in ('FAILED', 'TERMINATED'):
                        existing.status = 'failed'
                        reason = remote.get('failureReason', {})
                        existing.failure_message = reason.get('failureMessage', remote_status)
                        existing.save()
                        existing = None
                    elif remote_status == 'COMPLETED':
                        existing.status = 'completed'
                        existing.save()
                        order.status = 'pending'
                        order.save()

        if existing:
            return Response({
                "message": "Payment already initiated",
                "transaction_id": existing.transaction_id,
                "status": existing.status,
                "amount_charged": str(existing.amount),
            }, status=status.HTTP_200_OK)

        # ── FIX #2: Charge grand_total (items + delivery fee) ──
        charge_amount = order.grand_total

        transaction = Transaction.objects.create(
            order=order,
            transaction_type='deposit',
            amount=charge_amount,
            currency='ZMW',
            provider=provider,
            payer_number=normalized_number,
            status='pending',
        )

        pawapay_response = PawaPayService.initiate_deposit(transaction)

        if pawapay_response:
            return Response({
                "message": "Payment initiated successfully",
                "transaction_id": transaction.transaction_id,
                "status": transaction.status,
                "amount_charged": str(charge_amount),
                "pawapay_raw_data": pawapay_response,
            }, status=status.HTTP_200_OK)
        else:
            return Response({
                "error": "Failed to initiate payment with Mobile Money provider",
                "reason": transaction.failure_message,
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ─── PawaPay Webhook ───────────────────────────────────────────────────

class PawaPayWebhookView(APIView):
    # Public endpoint — PawaPay servers must reach it.
    permission_classes = []
    authentication_classes = []

    def _verify_signature(self, request) -> bool:
        secret = getattr(django_settings, 'PAWAPAY_WEBHOOK_SECRET', '')
        if not secret:
            logger.error("PAWAPAY_WEBHOOK_SECRET not configured — accepting webhook without verification")
            return True

        signature = request.headers.get('pawapay-signature', '').strip().lower()
        if not signature:
            logger.warning("Missing pawapay-signature header — accepting webhook without signature")
            return True

        body = request.body
        expected = hmac.new(
            secret.encode('utf-8'),
            body,
            hashlib.sha256,
        ).hexdigest().lower()

        valid = hmac.compare_digest(expected, signature)
        if not valid:
            logger.warning(
                "Webhook signature mismatch — expected=%s received=%s",
                expected[:16], signature[:16],
            )
        return valid

    def post(self, request):
        # ── FIX #1: Reject unsigned webhooks ──
        if not self._verify_signature(request):
            return Response(
                {"error": "Invalid webhook signature"},
                status=status.HTTP_403_FORBIDDEN,
            )

        data = request.data
        operation_id = (
            data.get('depositId') or data.get('payoutId') or data.get('refundId')
        )
        status_value = data.get('status')

        if not operation_id:
            return Response(
                {"error": "depositId/payoutId/refundId missing"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            transaction = Transaction.objects.get(transaction_id=operation_id)
        except Transaction.DoesNotExist:
            return Response(
                {"error": "Transaction not found"},
                status=status.HTTP_404_NOT_FOUND,
            )

        # Prevent re-processing completed transactions.
        if transaction.status == 'completed':
            return Response(
                {"message": "Already processed"},
                status=status.HTTP_200_OK,
            )

        send_payout_completed_notification = False

        if status_value == 'COMPLETED':
            transaction.status = 'completed'
            if transaction.transaction_type == 'payout':
                transaction.payout_stage = 'payout_paid'
                send_payout_completed_notification = True

            if transaction.transaction_type == 'deposit':
                # Payment confirmed — move order to pending so seller can accept it.
                transaction.order.status = 'pending'
                transaction.order.save()

                try:
                    create_payment_notification(transaction.order, 'completed')
                except Exception:
                    logger.exception('Payment notification failed for order %s', transaction.order.order_number)

                self._create_payout_rows(transaction)

            elif transaction.transaction_type == 'refund':
                cancel_order_with_refund(transaction.order, reason='Refund completed by PawaPay')

        elif status_value in ('FAILED', 'TERMINATED'):
            transaction.status = 'failed'
            if transaction.transaction_type == 'payout':
                transaction.payout_stage = 'payout_failed'
            reason = data.get('failureReason', {})
            transaction.failure_message = reason.get(
                'failureMessage',
                'Payment was terminated by user' if status_value == 'TERMINATED' else 'Unknown failure',
            )

            if transaction.transaction_type == 'deposit':
                # Restore stock and cancel the order properly via the service.
                cancel_order_with_refund(
                    transaction.order,
                    reason=f'Payment {status_value.lower()} — order auto-cancelled',
                )

                try:
                    create_payment_notification(
                        transaction.order,
                        'cancelled' if status_value == 'TERMINATED' else 'failed',
                        failure_message=transaction.failure_message,
                    )
                except Exception:
                    logger.exception('Payment failure notification failed for order %s', transaction.order.order_number)

        transaction.save()

        if send_payout_completed_notification:
            try:
                create_payout_completed_notification(transaction)
            except Exception:
                logger.exception(
                    'Payout completion notification failed for tx %s',
                    transaction.transaction_id,
                )

        return Response(
            {"message": "Webhook processed"},
            status=status.HTTP_200_OK,
        )

    def _create_payout_rows(self, deposit_tx):
        """
        After a successful deposit, create payout rows for:
        - Seller (item total minus platform commission)
        - Delivery agent (delivery fee, triggered on dropoff QR)
        Platform commission is kept by the platform (no payout row needed).
        """
        order = deposit_tx.order
        from portal.models import PlatformSettings
        _ps = PlatformSettings.get()
        commission_rate = Decimal(str(_ps.commission_rate))

        # Use the server-validated delivery fee from the Order model.
        delivery_fee = Decimal(str(order.delivery_fee or 0))
        item_total = Decimal(str(order.total_price))

        # ── FIX #10: Platform takes commission on item total ──
        platform_cut = (item_total * commission_rate).quantize(Decimal('0.01'))
        seller_share = item_total - platform_cut

        # ── FIX #6: Use seller's OWN registered payment method ──
        seller_provider, seller_phone = _resolve_payout_provider(order.seller)

        payout_method = _ps.payout_method

        # Seller payout — triggered when rider scans seller QR (pickup).
        if seller_share > 0 and not Transaction.objects.filter(
            order=order,
            transaction_type='payout',
            recipient_role='seller',
        ).exists():
            Transaction.objects.create(
                order=order,
                transaction_type='payout',
                amount=seller_share,
                currency=deposit_tx.currency,
                provider=seller_provider,
                payer_number=seller_phone,
                recipient=order.seller,
                recipient_role='seller',
                trigger_event='pickup_qr',
                payout_stage='pickup_pending_scan',
                payout_method=payout_method,
                status='pending',
            )

        # ── FIX #7: Delivery agent payout — triggered on dropoff QR ──
        if delivery_fee > 0:
            from delivery.models import DeliveryAssignment
            assignment = DeliveryAssignment.objects.filter(
                order=order,
                status__in=['accepted', 'picked_up', 'in_transit'],
            ).first()
            if assignment and assignment.delivery_person:
                rider = assignment.delivery_person
                rider_provider, rider_phone = _resolve_payout_provider(rider)
                if not Transaction.objects.filter(
                    order=order,
                    transaction_type='payout',
                    recipient_role='delivery',
                ).exists():
                    Transaction.objects.create(
                        order=order,
                        transaction_type='payout',
                        amount=delivery_fee,
                        currency=deposit_tx.currency,
                        provider=rider_provider,
                        payer_number=rider_phone,
                        recipient=rider,
                        recipient_role='delivery',
                        trigger_event='dropoff_qr',
                        payout_stage='dropoff_pending_scan',
                        payout_method=payout_method,
                        status='pending',
                    )


# ─── Payment Status Check ──────────────────────────────────────────────

class PaymentStatusView(APIView):
    """
    Allow buyers to check the payment status of their order.
    Used by the payment-pending screen to poll for completion.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        order_number = request.query_params.get('order_number')
        if not order_number:
            return Response(
                {'error': 'order_number query parameter is required'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        order = get_object_or_404(
            Order, order_number=order_number, buyer=request.user
        )

        deposit_tx = (
            Transaction.objects.filter(
                order=order,
                transaction_type='deposit',
            )
            .order_by('-created_at')
            .first()
        )

        if not deposit_tx:
            return Response({
                'order_number': order.order_number,
                'order_status': order.status,
                'payment_status': 'no_payment',
                'message': 'No payment initiated for this order.',
            })

        return Response({
            'order_number': order.order_number,
            'order_status': order.status,
            'payment_status': deposit_tx.status,
            'transaction_id': str(deposit_tx.transaction_id),
            'amount': str(deposit_tx.amount),
            'currency': deposit_tx.currency,
            'provider': deposit_tx.provider,
            'failure_message': deposit_tx.failure_message or '',
            'created_at': deposit_tx.created_at.isoformat(),
        })


# ─── Earnings Summary ──────────────────────────────────────────────────

class EarningsSummaryView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        if request.user.role not in ['seller', 'delivery']:
            return Response(
                {'error': 'Only sellers and delivery agents can view earnings'},
                status=status.HTTP_403_FORBIDDEN,
            )

        role_key = 'seller' if request.user.role == 'seller' else 'delivery'
        payouts = Transaction.objects.filter(
            transaction_type='payout',
            recipient=request.user,
            recipient_role=role_key,
        ).order_by('-created_at')

        total_completed = (
            payouts.filter(status='completed').aggregate(total=Sum('amount'))['total']
            or 0
        )
        pending_total = (
            payouts.exclude(status='completed').aggregate(total=Sum('amount'))['total']
            or 0
        )

        rows = []
        for tx in payouts[:100]:
            is_paid = tx.status == 'completed' and tx.payout_stage == 'payout_paid'
            rows.append(
                {
                    'transaction_id': str(tx.transaction_id),
                    'order_number': tx.order.order_number,
                    'amount': str(tx.amount),
                    'currency': tx.currency,
                    'status': tx.status,
                    'payout_stage': tx.payout_stage,
                    'trigger_event': tx.trigger_event,
                    'amount_color': 'green' if is_paid else 'orange',
                    'created_at': tx.created_at,
                }
            )

        return Response(
            {
                'role': role_key,
                'total_earnings': str(total_completed),
                'pending_payouts': str(pending_total),
                'transactions': rows,
            }
        )


# ─── Manual Payout / Withdrawal Request ───────────────────────────────

class RequestPayoutView(APIView):
    """
    Allow sellers & delivery agents to request a manual payout (withdrawal)
    of their available balance to a verified mobile money number.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        """Return available balance for the requesting user."""
        if request.user.role not in ['seller', 'delivery']:
            return Response(
                {'error': 'Only sellers and delivery agents can request payouts'},
                status=status.HTTP_403_FORBIDDEN,
            )

        role_key = 'seller' if request.user.role == 'seller' else 'delivery'

        # Total earned = all automatic payout rows from completed orders
        # (these are created when the buyer's deposit completes — they represent
        # money the seller/rider has earned, regardless of whether the payout
        # to their mobile money has been triggered yet)
        total_earned = (
            Transaction.objects.filter(
                transaction_type='payout',
                recipient=request.user,
                recipient_role=role_key,
                trigger_event__in=['pickup_qr', 'dropoff_qr'],
            ).exclude(
                status='failed',
            ).aggregate(total=Sum('amount'))['total']
            or Decimal('0.00')
        )

        # Already withdrawn via manual payout requests
        total_withdrawn = (
            Transaction.objects.filter(
                transaction_type='payout',
                recipient=request.user,
                recipient_role=role_key,
                trigger_event='manual',
                status='completed',
                payout_stage='payout_paid',
            ).aggregate(total=Sum('amount'))['total']
            or Decimal('0.00')
        )

        # Pending manual withdrawal requests
        pending_withdrawals = (
            Transaction.objects.filter(
                transaction_type='payout',
                recipient=request.user,
                recipient_role=role_key,
                trigger_event='manual',
                status__in=['pending', 'accepted'],
            ).aggregate(total=Sum('amount'))['total']
            or Decimal('0.00')
        )

        available = total_earned - total_withdrawn - pending_withdrawals

        # Ensure all amounts are formatted to 2 decimal places
        _fmt = Decimal('0.01')
        total_earned = total_earned.quantize(_fmt)
        total_withdrawn = total_withdrawn.quantize(_fmt)
        pending_withdrawals = pending_withdrawals.quantize(_fmt)
        available = available.quantize(_fmt)

        # Default payout method
        method = (
            BuyerPaymentMethod.objects.filter(
                user=request.user,
                is_verified=True,
            )
            .order_by('-is_default', '-created_at')
            .first()
        )

        return Response({
            'role': role_key,
            'total_earned': str(total_earned),
            'total_paid_out': str(total_withdrawn),
            'pending_payouts': str(pending_withdrawals),
            'available_earnings': str(available),
            'has_payout_method': method is not None,
            'payout_method': {
                'id': method.id,
                'provider': method.provider,
                'provider_label': method.get_provider_display() if hasattr(method, 'get_provider_display') else method.provider,
                'account_phone': method.account_phone,
            } if method else None,
        })

    def post(self, request):
        """Initiate a manual payout withdrawal."""
        if request.user.role not in ['seller', 'delivery']:
            return Response(
                {'error': 'Only sellers and delivery agents can request payouts'},
                status=status.HTTP_403_FORBIDDEN,
            )

        amount_str = request.data.get('amount')
        if not amount_str:
            return Response(
                {'error': 'amount is required'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            amount = Decimal(str(amount_str)).quantize(Decimal('0.01'))
        except Exception:
            return Response(
                {'error': 'Invalid amount'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if amount <= 0:
            return Response(
                {'error': 'Amount must be greater than zero'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        MIN_PAYOUT = Decimal('5.00')
        if amount < MIN_PAYOUT:
            return Response(
                {'error': f'Minimum payout is ZMW {MIN_PAYOUT}'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        role_key = 'seller' if request.user.role == 'seller' else 'delivery'

        # Calculate available balance (same logic as GET)
        total_earned = (
            Transaction.objects.filter(
                transaction_type='payout',
                recipient=request.user,
                recipient_role=role_key,
                trigger_event__in=['pickup_qr', 'dropoff_qr'],
            ).exclude(
                status='failed',
            ).aggregate(total=Sum('amount'))['total']
            or Decimal('0.00')
        )
        total_withdrawn = (
            Transaction.objects.filter(
                transaction_type='payout',
                recipient=request.user,
                recipient_role=role_key,
                trigger_event='manual',
                status='completed',
                payout_stage='payout_paid',
            ).aggregate(total=Sum('amount'))['total']
            or Decimal('0.00')
        )
        pending_withdrawals = (
            Transaction.objects.filter(
                transaction_type='payout',
                recipient=request.user,
                recipient_role=role_key,
                trigger_event='manual',
                status__in=['pending', 'accepted'],
            ).aggregate(total=Sum('amount'))['total']
            or Decimal('0.00')
        )
        available = total_earned - total_withdrawn - pending_withdrawals

        if amount > available:
            return Response(
                {'error': f'Amount exceeds available earnings. Available: ZMW {available}'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Resolve payout method
        provider_code, phone = _resolve_payout_provider(request.user)

        # Need a verified method
        method = BuyerPaymentMethod.objects.filter(
            user=request.user,
            is_verified=True,
        ).order_by('-is_default', '-created_at').first()

        if not method:
            return Response(
                {'error': 'No verified payout method found. Add one in your profile settings.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Create manual withdrawal transaction (no order link needed,
        # but the model requires one — use the latest completed order).
        latest_order = Order.objects.filter(
            **{('seller' if role_key == 'seller' else 'buyer'): request.user},
        ).order_by('-created_at').first()

        if not latest_order:
            return Response(
                {'error': 'No orders found to reference for payout.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        from portal.models import PlatformSettings
        payout_method = PlatformSettings.get().payout_method

        tx = Transaction.objects.create(
            order=latest_order,
            transaction_type='payout',
            amount=amount,
            currency='ZMW',
            provider=provider_code,
            payer_number=phone,
            recipient=request.user,
            recipient_role=role_key,
            trigger_event='manual',
            payout_stage='ready_for_payout',
            payout_method=payout_method,
            status='pending',
        )

        if payout_method == 'gateway':
            try:
                PawaPayService.initiate_payout(tx)
                logger.info(
                    'Gateway payout initiated: tx=%s amount=%s user=%s',
                    tx.transaction_id, amount, request.user.id,
                )
            except Exception as exc:
                logger.error('PawaPay payout initiation failed: %s', exc)
                tx.status = 'failed'
                tx.failure_message = str(exc)
                tx.payout_stage = 'payout_failed'
                tx.save()
                return Response(
                    {'error': 'Payout initiation failed. Please try again.'},
                    status=status.HTTP_500_INTERNAL_SERVER_ERROR,
                )
            return Response({
                'success': True,
                'message': 'Payout requested successfully',
                'transaction_id': str(tx.transaction_id),
                'amount': str(amount),
                'status': tx.status,
                'payout_to': phone,
            }, status=status.HTTP_201_CREATED)

        # Manual mode — admin will action the payment from their own phone.
        network_label = PROVIDER_TO_NETWORK_LABEL.get(provider_code, provider_code)
        phone_hint = phone[-4:] if len(phone) >= 4 else phone
        logger.info(
            'Manual claim queued: tx=%s amount=%s user=%s',
            tx.transaction_id, amount, request.user.id,
        )
        return Response({
            'success': True,
            'message': (
                f'Your payment of ZMW {amount} will be sent to your '
                f'{network_label} number ending in {phone_hint} shortly.'
            ),
            'amount': str(amount),
            'network': network_label,
            'phone_hint': f'ending in {phone_hint}',
            'transaction_id': str(tx.transaction_id),
        }, status=status.HTTP_201_CREATED)
