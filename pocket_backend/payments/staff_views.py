"""
Staff-only API endpoints.

All views require the requesting user to have role == 'staff'.
URL prefix: /api/staff/
"""
import logging
from datetime import datetime, time, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

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
from .lenco_transfers import CannotSend, is_lenco_transfer, send_via_lenco
from .models import Transaction
from .services.lenco import LencoError

logger = logging.getLogger(__name__)


ZAMBIA_TZ = ZoneInfo('Africa/Lusaka')


def provider_label(code):
    """'MTN_MOMO_ZMB' -> 'MTN MoMo'. Staff shouldn't have to read gateway codes."""
    from .views import PROVIDER_TO_NETWORK_LABEL
    if code == 'LENCO_CARD':
        return 'Card (Lenco)'
    if code == 'LENCO_BANK':
        return 'Bank transfer'
    return PROVIDER_TO_NETWORK_LABEL.get(code, code)


def zambia_today_bounds():
    """Start/end of *today in Zambia* as aware datetimes. The project runs on UTC,
    which would roll the day over at 02:00 local time."""
    local_today = timezone.now().astimezone(ZAMBIA_TZ).date()
    start = datetime.combine(local_today, time.min, tzinfo=ZAMBIA_TZ)
    return start, start + timedelta(days=1)


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
    """Called when an order needs a manual refund to the buyer — either a
    pre-delivery cancellation or an approved post-delivery refund request."""
    context = (
        f'Order #{refund_tx.order.order_number} was cancelled'
        if refund_tx.order.status == 'cancelled'
        else f'Refund approved for order #{refund_tx.order.order_number}'
    )
    _notify_staff(
        title='Refund Needed',
        message=f'{context} — refund ZMW {refund_tx.amount} to {refund_tx.payer_number}.',
        data_payload={
            'type': 'refund_request',
            'transaction_id': str(refund_tx.transaction_id),
            'order_number': refund_tx.order.order_number,
            'amount': str(refund_tx.amount),
        },
    )


def notify_staff_payout_failed(transaction):
    """Called when a gateway payout to a seller/rider fails or is terminated
    by PawaPay — either at initiation or via the webhook."""
    _notify_staff(
        title='Payout Failed',
        message=(
            f'Automatic payout of ZMW {transaction.amount} to '
            f'{transaction.recipient.full_name if transaction.recipient else transaction.payer_number} '
            f'failed: {transaction.failure_message or "Unknown error"}'
        ),
        data_payload={
            'type': 'payout_failed',
            'transaction_id': str(transaction.transaction_id),
            'order_number': transaction.order.order_number,
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

        # Same definition the Refunds tab uses: any order with a refund still
        # waiting on staff. (This used to require the order to be 'cancelled',
        # so approved refunds on delivered orders never showed up here.)
        refund_count = Transaction.objects.filter(
            transaction_type='refund', status='pending',
        ).values('order_id').distinct().count()

        start, end = zambia_today_bounds()
        today_deposits = Transaction.objects.filter(
            transaction_type='deposit',
            status='completed',
            updated_at__gte=start,
            updated_at__lt=end,
        ).aggregate(total=Sum('amount'))['total'] or Decimal('0.00')

        # Only payouts that genuinely failed to send. Payouts auto-failed
        # because their order was cancelled are not failures and must not
        # inflate this number.
        failed_payouts_count = Transaction.objects.filter(
            transaction_type='payout',
            status='failed',
            payout_stage='payout_failed',
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
                'provider_label': provider_label(tx.provider),
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
        # 'accepted' = already sent through a gateway and awaiting its result.
        # Showing those (read-only) stops a payout vanishing from staff's view
        # between "sent" and "confirmed".
        qs = Transaction.objects.filter(
            transaction_type='payout',
            trigger_event='manual',
            status__in=['pending', 'accepted'],
        ).select_related('recipient', 'order', 'bank_account').order_by('status', 'created_at')

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
                'provider_label': provider_label(tx.provider),
                'status': tx.status,
                'failure_message': tx.failure_message or '',
                'payout_stage': tx.payout_stage,
                'payout_notes': tx.payout_notes,
                'payment_method': tx.payment_method,
                'fee_deducted': str(tx.fee_deducted),
                'can_send_via_lenco': is_lenco_transfer(tx),
                'bank': {
                    'bank_name': tx.bank_account.bank_name,
                    'account_number': tx.bank_account.account_number,
                    'account_name': tx.bank_account.account_name,
                    'name_matches': tx.bank_account.name_matches,
                } if tx.bank_account else None,
                'proof_image_url': request.build_absolute_uri(tx.proof_image.url) if tx.proof_image else None,
                'created_at': tx.created_at.isoformat(),
                'total_earned': str(total_earned.quantize(Decimal('0.01'))),
                'queue_already_paid': str(queue_already_paid.quantize(Decimal('0.01'))),
                'available_balance': str(available_balance.quantize(Decimal('0.01'))),
            })

        return Response({'results': rows, 'count': len(rows)})


class StaffSendViaLencoView(APIView):
    """
    POST /api/staff/send-via-lenco/<tx_id>/   {confirm_name_mismatch?: bool}

    Pays a card refund (to the buyer's mobile money number) or a seller's
    bank withdrawal straight from the Lenco account, instead of staff sending
    it by hand. The result arrives from Lenco (webhook / sync) and settles the
    transaction; a failure leaves it pending so staff can retry or pay manually.
    """
    permission_classes = [permissions.IsAuthenticated, IsStaff]

    def post(self, request, tx_id):
        try:
            tx = send_via_lenco(
                tx_id,
                allow_name_mismatch=request.data.get('confirm_name_mismatch') is True,
            )
        except Transaction.DoesNotExist:
            return Response({'error': 'Transaction not found'}, status=status.HTTP_404_NOT_FOUND)
        except CannotSend as exc:
            return Response({'error': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        except LencoError as exc:
            return Response(
                {'error': f'Lenco could not send this: {exc}'},
                status=status.HTTP_502_BAD_GATEWAY,
            )
        return Response({
            'success': True,
            'transaction_id': str(tx.transaction_id),
            'status': tx.status,
            'message': 'Sent. It will show as paid once Lenco confirms.' if tx.status == 'accepted' else 'Paid.',
        })


class StaffFailedPayoutsView(APIView):
    """
    GET /api/staff/failed-payouts/
    Payouts the gateway failed to send. Until now the dashboard counted these
    but there was nowhere to see or fix them.
    """
    permission_classes = [permissions.IsAuthenticated, IsStaff]

    def get(self, request):
        qs = Transaction.objects.filter(
            transaction_type='payout', status='failed', payout_stage='payout_failed',
        ).select_related('recipient', 'order', 'bank_account').order_by('-updated_at')[:100]
        rows = []
        for tx in qs:
            rows.append({
                'transaction_id': str(tx.transaction_id),
                'order_number': tx.order.order_number,
                'recipient_name': tx.recipient.full_name if tx.recipient else '',
                'recipient_phone': tx.payer_number,
                'recipient_role': tx.recipient_role,
                'amount': str(tx.amount),
                'provider_label': provider_label(tx.provider),
                'payment_method': tx.payment_method,
                'failure_message': tx.failure_message or 'Unknown error',
                'trigger_event': tx.trigger_event,
                # A failed *withdrawal* returns to the person's earnings on its
                # own (they can ask again). Only per-order payouts need requeuing.
                'can_requeue': tx.trigger_event in ('pickup_qr', 'dropoff_qr') and tx.order.status != 'cancelled',
                'failed_at': tx.updated_at.isoformat(),
            })
        return Response({'results': rows, 'count': len(rows)})


class StaffRequeuePayoutView(APIView):
    """
    POST /api/staff/failed-payouts/<tx_id>/requeue/
    Put a failed per-order payout back in the payout queue so staff can pay it.
    """
    permission_classes = [permissions.IsAuthenticated, IsStaff]

    def post(self, request, tx_id):
        with db_transaction.atomic():
            try:
                tx = (
                    Transaction.objects.select_for_update(of=('self',))
                    .select_related('order').get(pk=tx_id, transaction_type='payout')
                )
            except Transaction.DoesNotExist:
                return Response({'error': 'Payout not found'}, status=status.HTTP_404_NOT_FOUND)
            if tx.status != 'failed' or tx.payout_stage != 'payout_failed':
                return Response({'error': 'This payout has not failed.'}, status=status.HTTP_400_BAD_REQUEST)
            if tx.trigger_event not in ('pickup_qr', 'dropoff_qr') or tx.order.status == 'cancelled':
                return Response(
                    {'error': 'This payout cannot be requeued. A failed withdrawal returns to the '
                              "person's earnings so they can request it again."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            previous = tx.failure_message or 'unknown error'
            tx.status = 'pending'
            tx.payout_stage = 'ready_for_payout'
            tx.payout_method = 'manual'
            tx.payout_notes = f'Requeued after gateway failure: {previous}'
            tx.failure_message = ''
            tx.save()
        return Response({'success': True, 'transaction_id': str(tx.transaction_id), 'status': tx.status})


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

        if action not in ('approve', 'reject'):
            return Response({'error': 'Invalid action'}, status=status.HTTP_400_BAD_REQUEST)

        # Only a request that is actually waiting for review can be decided.
        # Without this, a stale screen (or a second staff member) could flip an
        # already-approved seller to rejected, or approve a rejected one.
        if vr.status != 'submitted':
            return Response(
                {'error': f'This request was already {vr.status}.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if action == 'approve':
            vr.approve(reviewer=request.user)
            return Response({'success': True, 'status': 'approved'})

        # The applicant sees this text, so a rejection must say why.
        reason = str(request.data.get('reason', '')).strip()
        if len(reason) < 3:
            return Response(
                {'error': 'Give a reason so the applicant knows what to fix.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        # Pass the reason INTO reject(): it stores its own default text
        # otherwise, which used to silently replace what staff typed.
        vr.reject(reviewer=request.user, reason=reason)
        return Response({'success': True, 'status': 'rejected'})


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

        if not proof_image:
            return Response(
                {'error': 'A screenshot of the mobile money transaction is required to mark a refund as sent.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

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
            tx.proof_image = proof_image
            tx.save()

            from orders.services import sync_refund_request_status
            sync_refund_request_status(tx)

        try:
            from notifications.signals import notify_buyer_refund_completed
            notify_buyer_refund_completed(tx)
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
    List orders that have refund transactions — both pre-delivery
    cancellations (Order.status='cancelled') and post-delivery
    refund-request approvals (Order.status stays 'delivered'). Driven by
    "has a refund Transaction" rather than Order.status so the latter
    isn't invisible to staff.
    """
    permission_classes = [permissions.IsAuthenticated, IsStaff]

    def get(self, request):
        order_ids = (
            Transaction.objects.filter(transaction_type='refund')
            .values_list('order_id', flat=True)
            .distinct()
        )
        orders_with_refunds = Order.objects.filter(
            id__in=order_ids,
        ).distinct().prefetch_related('transactions', 'buyer', 'seller').order_by('-updated_at')[:100]

        rows = []
        for order in orders_with_refunds:
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
            in_flight_refund = next(
                (tx for tx in refund_txs if tx.status == 'accepted'),
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
                    'is_card_refund': pending_refund.payment_method == 'card',
                    'can_send_via_lenco': is_lenco_transfer(pending_refund),
                    'due_at': pending_refund.due_at.isoformat() if pending_refund.due_at else None,
                    'notes': pending_refund.payout_notes,
                    'failure_message': pending_refund.failure_message or '',
                } if pending_refund else None,
                'order_status': order.status,
                'refund_in_flight': in_flight_refund is not None,
                'refund_completed': completed_refund is not None,
                'refund_proof_url': (
                    request.build_absolute_uri(completed_refund.proof_image.url)
                    if completed_refund and completed_refund.proof_image else None
                ),
                'cancelled_at': order.updated_at.isoformat(),
            })

        # Work that needs a person first (oldest promise first), then the rest.
        rows.sort(key=lambda r: (
            r['pending_refund'] is None,
            (r['pending_refund'] or {}).get('due_at') or '9999',
        ))
        return Response({'results': rows, 'count': len(rows)})
