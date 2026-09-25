import json
import logging
import uuid
from datetime import timedelta
from decimal import Decimal, InvalidOperation

from django.conf import settings
from django.core import signing
from django.db import transaction as db_transaction
from django.http import Http404, HttpResponse
from django.shortcuts import get_object_or_404, render
from django.urls import reverse
from django.utils import timezone
from django.views.decorators.http import require_GET
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from orders.models import Order
from portal.models import PlatformSettings

from .mobile_money import (
    OPERATOR_LABELS,
    InvalidMobileNumber,
    parse_mobile_money_number,
)
from .lenco_transfers import sync_lenco_transfer
from .models import Transaction
from .services.lenco import LencoError, LencoService
from .views import apply_deposit_completed, apply_deposit_failed

logger = logging.getLogger(__name__)

CHECKOUT_TOKEN_SALT = 'lenco-card-checkout'
CHECKOUT_TOKEN_MAX_AGE = 30 * 60  # seconds
# A card attempt the buyer walked away from; after this we start a fresh one.
STALE_ATTEMPT_AFTER = timedelta(minutes=30)


def _checkout_url(request, transaction):
    token = signing.dumps({'tx': str(transaction.transaction_id)}, salt=CHECKOUT_TOKEN_SALT)
    path = reverse('card-checkout', args=[transaction.transaction_id])
    base = getattr(settings, 'PUBLIC_BACKEND_URL', '').rstrip('/')
    url = f'{base}{path}' if base else request.build_absolute_uri(path)
    return f'{url}?t={token}'


def _cards_available():
    return bool(
        LencoService.is_configured()
        and settings.LENCO_PUBLIC_KEY
        and PlatformSettings.get().card_payments_enabled
    )


class CardRefundNumberCheckView(APIView):
    """
    POST /api/payments/card/refund-number/check/  {phone}

    Card payments can't be reversed to the card, so refunds go to a mobile
    money number the buyer confirms BEFORE paying. This validates the
    number and returns the name registered on it, so the buyer can see
    exactly who a refund would be sent to.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        if not _cards_available():
            return Response(
                {'error': 'Card payments are not available right now.'},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        try:
            phone, operator = parse_mobile_money_number(request.data.get('phone'))
        except InvalidMobileNumber as exc:
            return Response({'error': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        try:
            resolved = LencoService.resolve_mobile_money(phone, operator)
        except LencoError:
            return Response(
                {'error': "We couldn't find a mobile money account for that number. Check it and try again."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return Response({
            'phone': phone,
            'operator': operator,
            'network': OPERATOR_LABELS[operator],
            'account_name': resolved['account_name'],
        })


class CardInitiateView(APIView):
    """
    POST /api/payments/card/initiate/  {order_number, refund_phone, refund_policy_accepted}

    Creates (or reuses) a pending card deposit for the buyer's order and
    returns the URL of the hosted checkout page to open in a WebView. The
    order is only marked paid later, from Lenco's confirmed collection
    status — never from anything the app or the page reports.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        if not _cards_available():
            return Response(
                {'error': 'Card payments are not available right now.'},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        order_number = request.data.get('order_number')
        if not order_number:
            return Response({'error': 'order_number is required'}, status=status.HTTP_400_BAD_REQUEST)

        # Card payments can't be reversed to the card, so the buyer must
        # agree to the refund terms and name the mobile money number any
        # refund would be paid to — decided now, not after something goes wrong.
        if request.data.get('refund_policy_accepted') is not True:
            return Response(
                {'error': 'Please accept the card refund terms to continue.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            refund_phone, _operator = parse_mobile_money_number(request.data.get('refund_phone'))
        except InvalidMobileNumber as exc:
            return Response(
                {'error': f'A mobile money number for refunds is required. {exc}'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        order = get_object_or_404(Order, order_number=order_number, buyer=request.user)
        if order.status not in ('pending', 'payment_pending'):
            return Response(
                {'error': f"Order is already '{order.status}' — cannot initiate payment."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        with db_transaction.atomic():
            order = Order.objects.select_for_update().get(pk=order.pk)

            # Never let a second payment start while another may still land.
            blocking = Transaction.objects.filter(
                order=order, transaction_type='deposit',
            ).exclude(gateway='lenco', payment_method='card', status__in=['pending', 'failed'])
            if blocking.filter(status__in=['accepted', 'completed']).exists() or blocking.filter(
                status='pending', created_at__gte=timezone.now() - timedelta(minutes=3)
            ).exists():
                return Response(
                    {'error': 'A payment for this order is already in progress.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            attempt = Transaction.objects.filter(
                order=order, transaction_type='deposit',
                gateway='lenco', payment_method='card', status='pending',
                created_at__gte=timezone.now() - STALE_ATTEMPT_AFTER,
            ).first()
            if attempt is None:
                attempt = Transaction.objects.create(
                    order=order,
                    transaction_type='deposit',
                    amount=order.grand_total,
                    currency='ZMW',
                    provider='LENCO_CARD',
                    payer_number=refund_phone,
                    gateway='lenco',
                    payment_method='card',
                    payout_notes=f'Buyer accepted the card refund terms at {timezone.now():%Y-%m-%d %H:%M} UTC.',
                    status='pending',
                )
            elif attempt.payer_number != refund_phone:
                attempt.payer_number = refund_phone
                attempt.save(update_fields=['payer_number', 'updated_at'])

        return Response({
            'transaction_id': str(attempt.transaction_id),
            'checkout_url': _checkout_url(request, attempt),
            'amount': str(attempt.amount),
            'currency': attempt.currency,
            'status': attempt.status,
            'refund_business_days': PlatformSettings.get().card_refund_business_days,
        })


@require_GET
def card_checkout_page(request, tx_id):
    """
    The hosted card page the app opens in a WebView. It is authorised by the
    short-lived signed token minted in CardInitiateView (a WebView can't
    attach the buyer's JWT), and only ever shows a pending card attempt.
    """
    try:
        payload = signing.loads(
            request.GET.get('t', ''), salt=CHECKOUT_TOKEN_SALT, max_age=CHECKOUT_TOKEN_MAX_AGE,
        )
    except signing.BadSignature:
        return HttpResponse('This payment link has expired. Go back and try again.', status=403)
    if payload.get('tx') != str(tx_id):
        return HttpResponse('Invalid payment link.', status=403)

    transaction = get_object_or_404(
        Transaction.objects.select_related('order__buyer'),
        pk=tx_id, gateway='lenco', payment_method='card', transaction_type='deposit',
    )
    if transaction.status != 'pending':
        return HttpResponse('This payment is already complete or closed.', status=410)

    buyer = transaction.order.buyer
    name_parts = (buyer.full_name or '').strip().split(' ', 1)
    widget_url = settings.LENCO_WIDGET_URL
    response = render(request, 'payments/card_checkout.html', {
        'widget_url': widget_url,
        'config': {
            'key': settings.LENCO_PUBLIC_KEY,
            'reference': str(transaction.transaction_id),
            'amount': float(transaction.amount),
            'currency': transaction.currency,
            'email': buyer.email or f'buyer{buyer.id}@mypocketshop.store',
            'label': f'Pocket Shop order {transaction.order.order_number}',
            'channels': ['card'],
            # The buyer covers Lenco's card processing fee, so card orders
            # never eat into the platform's margin.
            'bearer': 'customer',
            'customer': {
                'firstName': name_parts[0] or 'Customer',
                'lastName': name_parts[1] if len(name_parts) > 1 else '-',
                'phone': buyer.phone_number,
            },
        },
    })
    response['Cache-Control'] = 'no-store'
    return response


# ─── Settling a card payment ───────────────────────────────────────────

def _money(value):
    try:
        return Decimal(str(value))
    except (InvalidOperation, TypeError):
        return None


def apply_lenco_collection(transaction_id, data):
    """
    Apply a Lenco collection (the `data` object from GET
    /collections/status/{reference}) to our deposit. Idempotent and
    race-safe: the webhook and the app's status polling can both call it
    and the order is only ever settled once.
    """
    with db_transaction.atomic():
        transaction = Transaction.objects.select_for_update().select_related('order').get(pk=transaction_id)
        if transaction.status in ('completed', 'failed'):
            return transaction

        if str(data.get('reference')) != str(transaction.transaction_id):
            logger.error('Lenco reference mismatch for tx %s: %s', transaction.transaction_id, data.get('reference'))
            return transaction

        outcome = data.get('status')
        transaction.gateway_reference = str(data.get('lencoReference') or '')[:64]
        fee = _money(data.get('fee'))
        if fee is not None:
            transaction.gateway_fee = fee

        if outcome == 'successful':
            paid = _money(data.get('amount'))
            if paid is None or paid < transaction.amount:
                # Never mark an order paid on a short payment.
                logger.error(
                    'Lenco amount mismatch on tx %s: paid=%s expected=%s',
                    transaction.transaction_id, data.get('amount'), transaction.amount,
                )
                transaction.failure_message = f'Amount mismatch (got {data.get("amount")}, expected {transaction.amount})'
                transaction.save()
                return transaction
            transaction.status = 'completed'
            transaction.save()
            apply_deposit_completed(transaction)
        elif outcome == 'failed':
            transaction.status = 'failed'
            transaction.failure_message = data.get('reasonForFailure') or 'Card payment failed'
            transaction.save()
            apply_deposit_failed(transaction, word='failed')
        else:
            # pending / 3ds-auth-required / pay-offline — still in flight.
            transaction.save()
        return transaction


def sync_lenco_deposit(transaction):
    """
    Ask Lenco for the truth about a pending card deposit and apply it.
    Safe to call often; a network hiccup just leaves the deposit pending.
    """
    if (transaction.gateway != 'lenco' or transaction.transaction_type != 'deposit'
            or transaction.status not in ('pending', 'accepted')):
        return transaction
    try:
        data = LencoService.get_collection_status(str(transaction.transaction_id))
    except LencoError:
        return transaction  # not started / not found yet, or provider unreachable
    if not data:
        return transaction
    return apply_lenco_collection(transaction.pk, data)


class LencoWebhookView(APIView):
    """
    POST /api/payments/lenco/webhook/

    Lenco calls this on collection/transfer events. The signature is checked
    first (fails closed), and then the event is treated only as a *nudge*:
    the outcome is re-read from Lenco's API rather than trusted from the
    payload, so a forged or replayed body can't move an order.
    """
    permission_classes = []
    authentication_classes = []

    def post(self, request):
        signature = request.headers.get('X-Lenco-Signature', '')
        if not LencoService.verify_webhook_signature(request.body, signature):
            logger.warning('Lenco webhook rejected: bad or missing signature')
            return Response({'error': 'Invalid signature'}, status=status.HTTP_401_UNAUTHORIZED)

        try:
            body = json.loads(request.body or b'{}')
        except ValueError:
            return Response({'error': 'Invalid JSON'}, status=status.HTTP_400_BAD_REQUEST)

        event = str(body.get('event') or '')
        data = body.get('data') or {}

        if event.startswith('collection.') and event != 'collection.settled':
            try:
                tx_id = uuid.UUID(str(data.get('reference')))
            except ValueError:
                return Response({'message': 'ignored'})  # not one of ours
            transaction = Transaction.objects.filter(
                pk=tx_id, gateway='lenco', transaction_type='deposit',
            ).first()
            if transaction:
                sync_lenco_deposit(transaction)

        elif event in ('transfer.successful', 'transfer.failed'):
            try:
                tx_id = uuid.UUID(str(data.get('reference')))
            except ValueError:
                return Response({'message': 'ignored'})  # not one of ours
            transaction = Transaction.objects.filter(pk=tx_id, gateway='lenco').first()
            if transaction:
                sync_lenco_transfer(transaction)

        # Everything else (settlements, transactions) is acknowledged so
        # Lenco stops retrying.
        return Response({'message': 'ok'})
