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

        payout_queue_count = Transaction.objects.filter(
            transaction_type='payout',
            payout_stage='ready_for_payout',
            status='pending',
        ).count()

        withdrawal_count = Transaction.objects.filter(
            transaction_type='payout',
            trigger_event='manual',
            payout_stage='ready_for_payout',
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

        total_users = User.objects.filter(is_active=True).exclude(role__in=['admin', 'staff']).count()

        return Response({
            'payout_queue_count': payout_queue_count,
            'withdrawal_count': withdrawal_count,
            'verification_count': verification_count,
            'refund_count': refund_count,
            'today_revenue': str(today_deposits),
            'total_users': total_users,
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
        qs = Transaction.objects.filter(
            transaction_type='payout',
            payout_stage='ready_for_payout',
            status='pending',
        ).select_related('recipient', 'order').order_by('created_at')

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

        with db_transaction.atomic():
            try:
                tx = (
                    Transaction.objects
                    .select_for_update()
                    .select_related('recipient', 'order')
                    .get(transaction_id=tx_id, transaction_type='payout')
                )
            except Transaction.DoesNotExist:
                return Response({'error': 'Transaction not found'}, status=status.HTTP_404_NOT_FOUND)

            if tx.payout_stage == 'payout_paid' and tx.status == 'completed':
                return Response({'detail': 'Already marked as paid.'})

            if tx.payout_method != 'manual':
                return Response(
                    {'error': 'Only manual payouts can be marked paid from the app.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            tx.payout_stage = 'payout_paid'
            tx.status = 'completed'
            tx.marked_paid_by = request.user
            tx.marked_paid_at = timezone.now()
            if notes:
                tx.payout_notes = notes
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

        return Response({
            'success': True,
            'transaction_id': str(tx.transaction_id),
            'payout_stage': tx.payout_stage,
            'status': tx.status,
            'marked_paid_at': tx.marked_paid_at.isoformat(),
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
                # Total earned from completed deliveries / sales
                total_earned = (
                    Transaction.objects.filter(
                        transaction_type='payout',
                        recipient=recipient,
                        recipient_role=role_key,
                        trigger_event__in=['pickup_qr', 'dropoff_qr'],
                    ).exclude(status='failed')
                    .aggregate(total=Sum('amount'))['total']
                    or Decimal('0.00')
                )
                # Paid directly from payout queue (per-delivery, not via claim)
                queue_already_paid = (
                    Transaction.objects.filter(
                        transaction_type='payout',
                        recipient=recipient,
                        recipient_role=role_key,
                        trigger_event__in=['pickup_qr', 'dropoff_qr'],
                        status='completed',
                        payout_stage='payout_paid',
                    ).aggregate(total=Sum('amount'))['total']
                    or Decimal('0.00')
                )
                # All completed payouts any method
                total_paid_out = (
                    Transaction.objects.filter(
                        transaction_type='payout',
                        recipient=recipient,
                        recipient_role=role_key,
                        status='completed',
                        payout_stage='payout_paid',
                    ).aggregate(total=Sum('amount'))['total']
                    or Decimal('0.00')
                )
                # All pending manual claims (includes this one)
                pending_claims = (
                    Transaction.objects.filter(
                        transaction_type='payout',
                        recipient=recipient,
                        recipient_role=role_key,
                        trigger_event='manual',
                        status__in=['pending', 'accepted'],
                    ).aggregate(total=Sum('amount'))['total']
                    or Decimal('0.00')
                )
                available_balance = total_earned - total_paid_out - pending_claims
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
                'cancelled_at': order.updated_at.isoformat(),
            })

        return Response({'results': rows, 'count': len(rows)})
