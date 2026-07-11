"""
Staff-only API endpoints.

All views require the requesting user to have role == 'staff'.
URL prefix: /api/staff/
"""
import logging
from decimal import Decimal

from django.db import transaction as db_transaction
from django.db.models import Count, Q, Sum, Value
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import User, VerificationRequest
from notifications.signals import _create_notification, _send_push
from orders.models import Order
from .earnings import earnings_breakdown
from .models import Transaction

logger = logging.getLogger(__name__)


class IsStaff(permissions.BasePermission):
    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.role == 'staff'
        )


def _notify_staff(title, message, data_payload=None):
    """Send FCM push + in-app notification to all staff members."""
    staff_users = User.objects.filter(role='staff', is_active=True)
    for staff in staff_users:
        try:
            _create_notification(
                recipient=staff,
                notification_type='staff_alert',
                title=title,
                message=message,
                data_payload=data_payload or {},
            )
        except Exception as exc:
            logger.warning('Staff notify failed for user %s: %s', staff.id, exc)


def notify_staff_new_withdrawal(transaction):
    """Called when a seller/rider submits a withdrawal request."""
    _notify_staff(
        title='New Withdrawal Request',
        message=(
            f'{transaction.recipient.full_name} requested ZMW {transaction.amount} payout.'
        ),
        data_payload={
            'type': 'withdrawal_request',
            'transaction_id': str(transaction.transaction_id),
            'amount': str(transaction.amount),
            'recipient_role': transaction.recipient_role,
        },
    )


def notify_staff_new_refund(refund_tx):
    """Called when a cancelled order needs a manual refund to the buyer."""
    _notify_staff(
        title='Refund Needed',
        message=(
            f'Order #{refund_tx.order.order_number} was cancelled — refund '
            f'ZMW {refund_tx.amount} to {refund_tx.payer_number}.'
        ),
        data_payload={
            'type': 'refund_request',
            'transaction_id': str(refund_tx.transaction_id),
            'order_number': refund_tx.order.order_number,
            'amount': str(refund_tx.amount),
        },
    )


def notify_staff_new_verification(verification_request):
    """Called when a seller/rider submits verification documents."""
    _notify_staff(
        title='New Verification Request',
        message=(
            f'{verification_request.user.full_name} submitted '
            f'{verification_request.get_verification_type_display()} verification.'
        ),
        data_payload={
            'type': 'verification_request',
            'verification_id': verification_request.id,
            'verification_type': verification_request.verification_type,
        },
    )


# ── Stats Overview ──────────────────────────────────────────────────────────

class StaffStatsView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsStaff]

    def get(self, request):
        today = timezone.now().date()

        # Manual claims live in the withdrawals tab only — keep the two
        # counts disjoint so the dashboard matches the tabs.
        payout_queue_count = Transaction.objects.filter(
            transaction_type='payout',
            payout_stage='ready_for_payout',
            status='pending',
        ).exclude(trigger_event='manual').count()

        withdrawal_count = Transaction.objects.filter(
            transaction_type='payout',
            trigger_event='manual',
            status='pending',
        ).count()

        verification_count = VerificationRequest.objects.filter(
            status='submitted',
        ).count()

        refund_count = Order.objects.filter(
            status='cancelled',
            transactions__transaction_type='refund',
            transactions__status='pending',
        ).distinct().count()

        today_deposits = Transaction.objects.filter(
            transaction_type='deposit',
            status='completed',
            created_at__date=today,
        ).aggregate(total=Sum('amount'))['total'] or Decimal('0.00')

        failed_payouts_count = Transaction.objects.filter(
            transaction_type='payout',
            status='failed',
        ).count()

        from accounts.models import User as _User
        buyer_count = _User.objects.filter(role='buyer', is_active=True).count()
        seller_count = _User.objects.filter(role='seller', is_active=True).count()
        rider_count = _User.objects.filter(role='delivery', is_active=True).count()

        return Response({
            'payout_queue_count': payout_queue_count,
            'withdrawal_count': withdrawal_count,
            'verification_count': verification_count,
            'refund_count': refund_count,
            'today_revenue': str(today_deposits),
            'failed_payouts_count': failed_payouts_count,
            'buyer_count': buyer_count,
            'seller_count': seller_count,
            'rider_count': rider_count,
        })


# ── Payout Queue ────────────────────────────────────────────────────────────

class StaffPayoutQueueView(APIView):
    """
    GET /api/staff/payout-queue/?role=seller|delivery
    List transactions at ready_for_payout stage.
    """
    permission_classes = [permissions.IsAuthenticated, IsStaff]

    def get(self, request):
        role_filter = request.query_params.get('role', '')
        # Manual withdrawal claims are handled in the Earnings Claims tab —
        # exclude them here so the same money can't be paid from two places.
        qs = Transaction.objects.filter(
            transaction_type='payout',
            payout_stage='ready_for_payout',
            status='pending',
        ).exclude(trigger_event='manual').select_related('recipient', 'order').order_by('created_at')

        if role_filter in ('seller', 'delivery'):
            qs = qs.filter(recipient_role=role_filter)

        rows = []
        for tx in qs[:100]:
            rows.append({
                'transaction_id': str(tx.transaction_id),
                'order_number': tx.order.order_number,
                'recipient_name': tx.recipient.full_name if tx.recipient else '',
                'recipient_phone': tx.payer_number,
                'recipient_role': tx.recipient_role,
                'amount': str(tx.amount),
                'currency': tx.currency,
                'provider': tx.provider,
                'trigger_event': tx.trigger_event,
                'payout_method': tx.payout_method,
                'payout_notes': tx.payout_notes,
                'proof_image_url': request.build_absolute_uri(tx.proof_image.url) if tx.proof_image else None,
                'created_at': tx.created_at.isoformat(),
            })

        return Response({'results': rows, 'count': len(rows)})


class StaffMarkPaidView(APIView):
    """
    POST /api/staff/mark-paid/<tx_id>/
    Mark a payout transaction as paid (manual mode only).
    """
    permission_classes = [permissions.IsAuthenticated, IsStaff]

    def post(self, request, tx_id):
        notes = request.data.get('notes', '')
        proof_image = request.FILES.get('proof_image')

        with db_transaction.atomic():
            try:
                # of=('self',) locks only the transaction row — Postgres rejects
                # FOR UPDATE across the LEFT JOIN that the nullable recipient
                # FK introduces via select_related.
                tx = (
                    Transaction.objects
                    .select_for_update(of=('self',))
                    .select_related('recipient', 'order')
                    .get(transaction_id=tx_id, transaction_type='payout')
                )
            except Transaction.DoesNotExist:
                return Response({'error': 'Transaction not found'}, status=status.HTTP_404_NOT_FOUND)

            if tx.payout_stage == 'payout_paid' and tx.status == 'completed':
                return Response({'detail': 'Already marked as paid.'})

            tx.payout_stage = 'payout_paid'
            tx.status = 'completed'
            tx.marked_paid_by = request.user
            tx.marked_paid_at = timezone.now()
            if notes:
                tx.payout_notes = notes
            if proof_image:
                tx.proof_image = proof_image
            tx.save()

        # Notify recipient
        if tx.recipient:
            role_label = 'delivery earnings' if tx.recipient_role == 'delivery' else 'payout'
            try:
                _create_notification(
                    recipient=tx.recipient,
                    notification_type='payout_completed',
                    title='Payout Completed',
                    message=(
                        f'Your {role_label} of ZMW {tx.amount} for order '
                        f'#{tx.order.order_number} has been paid.'
                    ),
                    data_payload={
                        'order_number': tx.order.order_number,
                        'transaction_id': str(tx.transaction_id),
                        'amount': str(tx.amount),
                    },
                )
            except Exception as exc:
                logger.warning('Mark-paid notification failed: %s', exc)

        proof_url = None
        if tx.proof_image:
            proof_url = request.build_absolute_uri(tx.proof_image.url)

        return Response({
            'success': True,
            'transaction_id': str(tx.transaction_id),
            'payout_stage': tx.payout_stage,
            'status': tx.status,
            'marked_paid_at': tx.marked_paid_at.isoformat(),
            'proof_image_url': proof_url,
        })


# ── Withdrawal Requests ─────────────────────────────────────────────────────

class StaffWithdrawalsView(APIView):
    """
    GET /api/staff/withdrawals/
    List manual withdrawal requests from sellers and riders.
    """
    permission_classes = [permissions.IsAuthenticated, IsStaff]

    def get(self, request):
        qs = Transaction.objects.filter(
            transaction_type='payout',
            trigger_event='manual',
            status='pending',
        ).select_related('recipient', 'order').order_by('created_at')

        rows = []
        for tx in qs[:100]:
            recipient = tx.recipient
            role_key = tx.recipient_role

            if recipient:
                # Same math as the seller/rider payout screen — one source
                # of truth in payments.earnings.
                totals = earnings_breakdown(recipient, role_key)
                total_earned = totals['total_earned']
                queue_already_paid = totals['queue_already_paid']
                available_balance = totals['available']
            else:
                total_earned = Decimal('0.00')
                queue_already_paid = Decimal('0.00')
                available_balance = Decimal('0.00')

            rows.append({
                'transaction_id': str(tx.transaction_id),
                'order_number': tx.order.order_number,
                'recipient_name': recipient.full_name if recipient else '',
                'recipient_phone': tx.payer_number,
                'recipient_role': role_key,
                'amount': str(tx.amount),
                'currency': tx.currency,
                'provider': tx.provider,
                'payout_stage': tx.payout_stage,
                'payout_notes': tx.payout_notes,
                'proof_image_url': request.build_absolute_uri(tx.proof_image.url) if tx.proof_image else None,
                'created_at': tx.created_at.isoformat(),
                'total_earned': str(total_earned.quantize(Decimal('0.01'))),
                'queue_already_paid': str(queue_already_paid.quantize(Decimal('0.01'))),
                'available_balance': str(available_balance.quantize(Decimal('0.01'))),
            })

        return Response({'results': rows, 'count': len(rows)})


# ── Seller Verifications ────────────────────────────────────────────────────

class StaffVerificationsView(APIView):
    """
    GET /api/staff/verifications/
    List pending seller and delivery verification requests.
    """
    permission_classes = [permissions.IsAuthenticated, IsStaff]

    def get(self, request):
        qs = VerificationRequest.objects.filter(
            status='submitted',
        ).select_related('user', 'seller_profile', 'delivery_profile').order_by('submitted_at')

        rows = []
        for vr in qs[:100]:
            row = {
                'id': vr.id,
                'user_name': vr.user.full_name,
                'user_phone': vr.user.phone_number,
                'verification_type': vr.verification_type,
                'status': vr.status,
                'submitted_at': vr.submitted_at.isoformat() if vr.submitted_at else None,
            }
            if vr.seller_profile:
                row['shop_name'] = vr.seller_profile.shop_name
                row['nrc_number'] = vr.seller_profile.nrc_number or ''
            if vr.delivery_profile:
                row['vehicle_type'] = vr.delivery_profile.vehicle_type
                row['license_number'] = vr.delivery_profile.license_number or ''
            rows.append(row)

        return Response({'results': rows, 'count': len(rows)})


class StaffApproveVerificationView(APIView):
    """
    POST /api/staff/verifications/<pk>/approve/
    POST /api/staff/verifications/<pk>/reject/
    """
    permission_classes = [permissions.IsAuthenticated, IsStaff]

    def post(self, request, pk, action):
        try:
            vr = VerificationRequest.objects.select_related('user').get(pk=pk)
        except VerificationRequest.DoesNotExist:
            return Response({'error': 'Verification request not found'}, status=status.HTTP_404_NOT_FOUND)

        if action == 'approve':
            vr.approve(reviewer=request.user)
            return Response({'success': True, 'status': 'approved'})
        elif action == 'reject':
            reason = request.data.get('reason', '')
            vr.rejection_reason = reason
            vr.reject(reviewer=request.user)
            return Response({'success': True, 'status': 'rejected'})
        else:
            return Response({'error': 'Invalid action'}, status=status.HTTP_400_BAD_REQUEST)


# ── Refunds / Cancellations ─────────────────────────────────────────────────

class StaffMarkRefundedView(APIView):
    """
    POST /api/staff/mark-refunded/<tx_id>/
    Mark a refund transaction as completed (manual mode — staff sent the
    money from the platform phone). Mirrors StaffMarkPaidView.
    """
    permission_classes = [permissions.IsAuthenticated, IsStaff]

    def post(self, request, tx_id):
        notes = request.data.get('notes', '')
        proof_image = request.FILES.get('proof_image')

        with db_transaction.atomic():
            try:
                tx = (
                    Transaction.objects
                    .select_for_update(of=('self',))
                    .select_related('recipient', 'order')
                    .get(transaction_id=tx_id, transaction_type='refund')
                )
            except Transaction.DoesNotExist:
                return Response({'error': 'Refund not found'}, status=status.HTTP_404_NOT_FOUND)

            if tx.status == 'completed':
                return Response({'detail': 'Already marked as refunded.'})

            tx.status = 'completed'
            tx.marked_paid_by = request.user
            tx.marked_paid_at = timezone.now()
            if notes:
                tx.payout_notes = notes
            if proof_image:
                tx.proof_image = proof_image
            tx.save()

        if tx.recipient:
            try:
                _create_notification(
                    recipient=tx.recipient,
                    notification_type='refund_completed',
                    title='Refund Sent',
                    message=(
                        f'Your refund of ZMW {tx.amount} for cancelled order '
                        f'#{tx.order.order_number} has been sent to {tx.payer_number}.'
                    ),
                    data_payload={
                        'order_number': tx.order.order_number,
                        'transaction_id': str(tx.transaction_id),
                        'amount': str(tx.amount),
                    },
                )
            except Exception as exc:
                logger.warning('Mark-refunded notification failed: %s', exc)

        return Response({
            'success': True,
            'transaction_id': str(tx.transaction_id),
            'status': tx.status,
            'marked_refunded_at': tx.marked_paid_at.isoformat(),
        })


class StaffRefundsView(APIView):
    """
    GET /api/staff/refunds/
    List cancelled orders that have pending refund transactions.
    """
    permission_classes = [permissions.IsAuthenticated, IsStaff]

    def get(self, request):
        cancelled_orders = Order.objects.filter(
            status='cancelled',
        ).prefetch_related('transactions', 'buyer', 'seller').order_by('-updated_at')[:100]

        rows = []
        for order in cancelled_orders:
            refund_txs = [
                tx for tx in order.transactions.all()
                if tx.transaction_type == 'refund'
            ]
            deposit_txs = [
                tx for tx in order.transactions.all()
                if tx.transaction_type == 'deposit' and tx.status == 'completed'
            ]
            was_paid = bool(deposit_txs)

            # Only manual refunds wait on staff; a gateway refund in flight
            # has status 'accepted' and completes via the webhook.
            pending_refund = next(
                (tx for tx in refund_txs if tx.status == 'pending'),
                None,
            )
            completed_refund = next(
                (tx for tx in refund_txs if tx.status == 'completed'),
                None,
            )

            rows.append({
                'order_id': order.id,
                'order_number': order.order_number,
                'buyer_name': order.buyer.full_name,
                'buyer_phone': order.buyer.phone_number,
                'seller_name': order.seller.full_name,
                'total_price': str(order.total_price),
                'grand_total': str(order.grand_total),
                'was_paid': was_paid,
                'refund_count': len(refund_txs),
                'refund_statuses': [tx.status for tx in refund_txs],
                'pending_refund': {
                    'transaction_id': str(pending_refund.transaction_id),
                    'amount': str(pending_refund.amount),
                    'refund_phone': pending_refund.payer_number,
                    'payout_method': pending_refund.payout_method,
                } if pending_refund else None,
                'refund_completed': completed_refund is not None,
                'refund_proof_url': (
                    request.build_absolute_uri(completed_refund.proof_image.url)
                    if completed_refund and completed_refund.proof_image else None
                ),
                'cancelled_at': order.updated_at.isoformat(),
            })

        return Response({'results': rows, 'count': len(rows)})
