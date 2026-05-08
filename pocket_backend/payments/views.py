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
from orders.models import Order

logger = logging.getLogger(__name__)

# ─── Helpers ────────────────────────────────────────────────────────────

PROVIDER_TO_METHOD_KEY = {
    'MTN_MOMO_ZMB': 'mtn_momo',
    'AIRTEL_OAPI_ZMB': 'airtel_money',
    'AIRTEL_MOMO_ZMB': 'airtel_money',
    'ZAMTEL_MONEY_ZMB': 'zamtel',
    'ZAMTEL_MOMO_ZMB': 'zamtel',
}

METHOD_KEY_TO_PROVIDER = {v: k for k, v in PROVIDER_TO_METHOD_KEY.items()}


def _resolve_payout_provider(user):
    """
    Find the correct PawaPay provider code for a given user (seller / delivery).
    Uses their default verified payment method; falls back to MTN_MOMO_ZMB.
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
        return (
            METHOD_KEY_TO_PROVIDER.get(method.provider, 'MTN_MOMO_ZMB'),
            method.account_phone,
        )
    # Fallback — use the user's registration phone number.
    return 'MTN_MOMO_ZMB', user.phone_number


# ─── Payment Initiation ────────────────────────────────────────────────

class InitiatePaymentView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        order_number = request.data.get('order_number')
        provider = request.data.get('provider')  # e.g. MTN_MOMO_ZMB
        payer_number = request.data.get('payer_number')

        if not all([order_number, provider, payer_number]):
            return Response(
                {"error": "order_number, provider, and payer_number are required"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Find the order (buyer-owned only).
        order = get_object_or_404(
            Order, order_number=order_number, buyer=request.user
        )

        # ── FIX #4: Only allow payment on pending orders ──
        if order.status != 'pending':
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

        method_key = PROVIDER_TO_METHOD_KEY.get(provider)
        if not method_key:
            return Response(
                {"error": "Unsupported provider"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # NOTE: Previously required a verified BuyerPaymentMethod record.
        # Now we allow direct entry at checkout — PawaPay validates the number.

        # ── FIX #5: Idempotency — reuse existing pending/accepted deposit ──
        existing = Transaction.objects.filter(
            order=order,
            transaction_type='deposit',
            status__in=['pending', 'accepted'],
        ).first()
        if existing:
            return Response({
                "message": "Payment already initiated",
                "transaction_id": existing.transaction_id,
                "status": existing.status,
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
        """
        FIX #1: Verify PawaPay webhook HMAC signature.
        Returns True if valid or if verification is skipped (dev mode).
        """
        secret = getattr(django_settings, 'PAWAPAY_WEBHOOK_SECRET', '')
        if not secret:
            # No secret configured — allow the webhook but log a warning.
            # PawaPay sandbox does not require HMAC signatures.
            # For production with real money, set PAWAPAY_WEBHOOK_SECRET.
            logger.warning("PAWAPAY_WEBHOOK_SECRET not set — allowing webhook without signature check")
            return True

        signature = request.headers.get('pawapay-signature', '')
        if not signature:
            logger.warning("Missing pawapay-signature header")
            return False

        body = request.body
        expected = hmac.new(
            secret.encode('utf-8'),
            body,
            hashlib.sha256,
        ).hexdigest()

        return hmac.compare_digest(expected, signature)

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

        if status_value == 'COMPLETED':
            transaction.status = 'completed'
            if transaction.transaction_type == 'payout':
                transaction.payout_stage = 'payout_paid'

            if transaction.transaction_type == 'deposit':
                # Payment received — mark order as accepted.
                transaction.order.status = 'accepted'
                transaction.order.save()

                # ── FIX #6, #7, #10: Correct payout creation ──
                self._create_payout_rows(transaction)

            elif transaction.transaction_type == 'refund':
                transaction.order.status = 'cancelled'
                transaction.order.save()

        elif status_value == 'FAILED':
            transaction.status = 'failed'
            if transaction.transaction_type == 'payout':
                transaction.payout_stage = 'payout_failed'
            reason = data.get('failureReason', {})
            transaction.failure_message = reason.get(
                'failureMessage', 'Unknown async failure'
            )

            if transaction.transaction_type == 'deposit':
                transaction.order.status = 'cancelled'
                transaction.order.save()

        transaction.save()

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
        commission_rate = Decimal(str(
            getattr(django_settings, 'PLATFORM_COMMISSION_RATE', 0.05)
        ))

        # Use the server-validated delivery fee from the Order model.
        delivery_fee = Decimal(str(order.delivery_fee or 0))
        item_total = Decimal(str(order.total_price))

        # ── FIX #10: Platform takes commission on item total ──
        platform_cut = (item_total * commission_rate).quantize(Decimal('0.01'))
        seller_share = item_total - platform_cut

        # ── FIX #6: Use seller's OWN registered payment method ──
        seller_provider, seller_phone = _resolve_payout_provider(order.seller)

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
            'available_balance': str(available),
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
                {'error': f'Insufficient balance. Available: ZMW {available}'},
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
            payout_stage='payout_sent',
            status='pending',
        )

        # Initiate actual payout via PawaPay
        try:
            result = PawaPayService.initiate_payout(tx)
            logger.info(
                'Manual payout initiated: tx=%s amount=%s user=%s',
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
            'message': 'Payout requested successfully',
            'transaction_id': str(tx.transaction_id),
            'amount': str(amount),
            'status': tx.status,
            'payout_to': phone,
        }, status=status.HTTP_201_CREATED)

