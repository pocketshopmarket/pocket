"""
Auto-create Notification rows when an Order changes status.

Listens to the Order post_save signal and creates relevant
notifications for buyers, sellers, and delivery agents.
"""

import json
import logging
from django.db.models.signals import post_save, pre_save
from django.dispatch import receiver

from orders.models import Order
from accounts.models import User, VerificationRequest
from .models import Announcement, Notification

logger = logging.getLogger(__name__)


def _get_firebase_app():
    """
    Return the initialized Firebase app, or None if credentials are not configured.
    Tries FIREBASE_CREDENTIALS_JSON env var first, then firebase_creds.json in project root.
    Safe to call on any platform — returns None silently when Firebase is not set up.
    """
    try:
        import os
        import firebase_admin
        from firebase_admin import credentials

        if firebase_admin._apps:
            return firebase_admin.get_app()

        from django.conf import settings as django_settings
        cred_json = getattr(django_settings, 'FIREBASE_CREDENTIALS_JSON', '').strip()

        cred_file = os.environ.get(
            'FIREBASE_CREDENTIALS_FILE',
            os.path.join(os.path.dirname(os.path.dirname(__file__)), 'firebase_creds.json'),
        )

        if not cred_json and os.path.exists(cred_file):
            cred = credentials.Certificate(cred_file)
            return firebase_admin.initialize_app(cred)

        if not cred_json:
            return None

        cred_dict = json.loads(cred_json)
        cred = credentials.Certificate(cred_dict)
        return firebase_admin.initialize_app(cred)
    except Exception as exc:
        logger.warning('Firebase init failed: %s', exc)
        return None


def _send_push(recipient, title, message, data_payload):
    """
    Send an FCM push notification to a single device.
    Silently skips if:
      - firebase-admin is not installed
      - FIREBASE_CREDENTIALS_JSON is not configured
      - The recipient has no FCM token registered
    Never raises — failures are logged only.
    """
    try:
        token = getattr(recipient, 'fcm_token', '') or ''
        if not token:
            return

        app = _get_firebase_app()
        if app is None:
            return

        from firebase_admin import messaging
        str_data = {k: str(v) for k, v in (data_payload or {}).items()}
        msg = messaging.Message(
            notification=messaging.Notification(title=title, body=message),
            data=str_data,
            token=token,
        )
        messaging.send(msg, app=app)
        logger.info('FCM push sent to user %s', recipient.id)
    except Exception as exc:
        logger.warning('FCM push failed for user %s: %s', getattr(recipient, 'id', '?'), exc)

# Map order status → (notification_type, title_template, message_template, recipient_field)
# Recipient field: 'buyer', 'seller', or 'both'
_STATUS_MAP = {
    'pending': {
        'type': 'order_placed',
        'title': 'New Order Received!',
        'message': 'Order #{order_number} has been placed. Review and accept it.',
        'recipients': ['seller'],
        # Also notify buyer that their order was submitted
        'buyer_copy': {
            'type': 'order_placed',
            'title': 'Order Submitted',
            'message': 'Your order #{order_number} has been sent to the seller.',
        },
    },
    'payment_pending': {
        'type': 'payment_pending',
        'title': 'Awaiting Payment',
        'message': 'Order #{order_number} is waiting for payment confirmation. Please approve the prompt on your phone.',
        'recipients': ['buyer'],
    },
    'accepted': {
        'type': 'order_accepted',
        'title': 'Order Accepted',
        'message': 'Your order #{order_number} has been accepted by the seller.',
        'recipients': ['buyer'],
    },
    'preparing': {
        'type': 'order_preparing',
        'title': 'Order Being Prepared',
        'message': 'Your order #{order_number} is now being prepared.',
        'recipients': ['buyer'],
    },
    'out_for_delivery': {
        'type': 'order_out_for_delivery',
        'title': 'Out for Delivery',
        'message': 'Your order #{order_number} is on its way!',
        'recipients': ['buyer'],
    },
    'delivered': {
        'type': 'order_delivered',
        'title': 'Order Delivered',
        'message': 'Order #{order_number} has been delivered successfully.',
        'recipients': ['buyer', 'seller'],
    },
    'cancelled': {
        'type': 'order_cancelled',
        'title': 'Order Cancelled',
        'message': 'Order #{order_number} has been cancelled.',
        'recipients': ['buyer', 'seller'],
    },
}


def _get_order_image_url(order):
    """Return relative media URL for the best image representing this order, or None."""
    try:
        first_item = order.items.select_related('product').first()
        if first_item:
            product = first_item.product
            if product.image:
                return product.image.url
            if product.image_url:
                return product.image_url
    except Exception:
        pass
    try:
        if order.seller.profile_photo:
            return order.seller.profile_photo.url
    except Exception:
        pass
    return None


def _get_rider_image_url(assignment):
    """Return relative media URL for the rider's profile photo, or None."""
    try:
        dp = assignment.delivery_person.delivery_profile
        if dp.profile_photo:
            return dp.profile_photo.url
    except Exception:
        pass
    return None


def _create_notification(recipient, notification_type, title, message, data_payload):
    """Save in-app notification and fire FCM push if the device token is registered."""
    try:
        Notification.objects.create(
            recipient=recipient,
            notification_type=notification_type,
            title=title,
            message=message,
            data=data_payload,
        )
    except Exception:
        logger.exception(
            'Failed to create %s notification for user %s',
            notification_type, recipient.id,
        )
    _send_push(recipient, title, message, data_payload)


@receiver(pre_save, sender=Order)
def store_previous_order_status(sender, instance, **kwargs):
    """Attach the persisted status before save so post_save can detect real changes."""
    if not instance.pk:
        instance._previous_status = None
        return

    instance._previous_status = (
        sender.objects.filter(pk=instance.pk).values_list('status', flat=True).first()
    )


@receiver(post_save, sender=Order)
def order_status_notification(sender, instance, created, **kwargs):
    """Create notification(s) when an order status changes."""
    status = instance.status
    mapping = _STATUS_MAP.get(status)
    if not mapping:
        return

    # Orders default to 'payment_pending' and only reach 'pending' via a
    # status transition after payment is confirmed — never at creation.
    # Skip status changes that aren't real transitions (no-ops).
    if not created and getattr(instance, '_previous_status', None) == status:
        return
    # On creation, skip everything except orders that start directly as 'pending'
    # (rare/admin path — normally orders are created as 'payment_pending').
    if created and status != 'pending':
        return

    # Don't send "Order Cancelled" if the buyer never successfully paid.
    # The payment-failure notification already covers this case and the
    # seller should not be alarmed by a cancellation they never saw an order for.
    if status == 'cancelled':
        from payments.models import Transaction
        paid = Transaction.objects.filter(
            order=instance, transaction_type='deposit', status='completed',
        ).exists()
        if not paid:
            return

    order_number = instance.order_number
    data_payload = {
        'order_id': instance.id,
        'order_number': order_number,
        'status': status,
    }
    image_url = _get_order_image_url(instance)
    if image_url:
        data_payload['image_url'] = image_url

    for role in mapping['recipients']:
        if role == 'buyer':
            recipient = instance.buyer
        elif role == 'seller':
            recipient = instance.seller
        else:
            continue

        _create_notification(
            recipient=recipient,
            notification_type=mapping['type'],
            title=mapping['title'],
            message=mapping['message'].format(order_number=order_number),
            data_payload=data_payload,
        )

    # Send buyer copy when the order first becomes 'pending' (payment confirmed).
    # This covers both direct creation as 'pending' and the normal path where
    # a 'payment_pending' order transitions to 'pending' after payment.
    prev = getattr(instance, '_previous_status', None)
    first_pending = status == 'pending' and (created or prev == 'payment_pending')
    buyer_copy = mapping.get('buyer_copy')
    if buyer_copy and first_pending:
        _create_notification(
            recipient=instance.buyer,
            notification_type=buyer_copy['type'],
            title=buyer_copy['title'],
            message=buyer_copy['message'].format(order_number=order_number),
            data_payload=data_payload,
        )


def create_payment_notification(order, payment_status, failure_message=''):
    """Called from payment webhook handler to notify buyer about payment result."""
    order_number = order.order_number
    data_payload = {
        'order_id': order.id,
        'order_number': order_number,
        'payment_status': payment_status,
    }
    image_url = _get_order_image_url(order)
    if image_url:
        data_payload['image_url'] = image_url

    if payment_status == 'completed':
        _create_notification(
            recipient=order.buyer,
            notification_type='payment_completed',
            title='Payment Successful',
            message=f'Payment for order #{order_number} has been confirmed. Your order is being processed!',
            data_payload=data_payload,
        )
    elif payment_status in ('failed', 'cancelled', 'terminated'):
        msg = f'Payment for order #{order_number} was not completed.'
        if failure_message:
            msg += f' Reason: {failure_message}'
        _create_notification(
            recipient=order.buyer,
            notification_type='payment_failed',
            title='Payment Failed',
            message=msg,
            data_payload=data_payload,
        )


def create_delivery_assignment_notification(assignment):
    """Notify the buyer that a rider has been assigned to their order."""
    order = assignment.order
    data_payload = {
        'order_id': order.id,
        'order_number': order.order_number,
        'assignment_id': assignment.id,
        'status': order.status,
    }
    image_url = _get_rider_image_url(assignment) or _get_order_image_url(order)
    if image_url:
        data_payload['image_url'] = image_url

    _create_notification(
        recipient=order.buyer,
        notification_type='delivery_assigned',
        title='Delivery Assigned',
        message=(
            f'A delivery rider has been assigned to order #{order.order_number}. '
            'You can now track your order.'
        ),
        data_payload=data_payload,
    )


@receiver(post_save, sender=VerificationRequest)
def verification_request_notification(sender, instance, created, **kwargs):
    """Notify user when their verification request is approved or rejected."""
    if created:
        return
    prev_status = getattr(instance, '_prev_status', None)
    if prev_status == instance.status:
        return

    user = instance.user
    vtype_labels = {
        'seller_tier1': 'Seller Tier 1',
        'seller_tier2': 'Seller Tier 2',
        'delivery': 'Delivery',
    }
    label = vtype_labels.get(instance.verification_type, 'Account')

    if instance.status == 'approved':
        _create_notification(
            recipient=user,
            notification_type='verification_approved',
            title='Verification Approved!',
            message=f'Your {label} verification has been approved. You can now start using all features.',
            data_payload={
                'verification_type': instance.verification_type,
                'status': 'approved',
            },
        )
    elif instance.status == 'rejected':
        reason = instance.rejection_reason or 'Please review your submitted documents.'
        _create_notification(
            recipient=user,
            notification_type='verification_rejected',
            title='Verification Rejected',
            message=f'Your {label} verification was not approved. Reason: {reason}',
            data_payload={
                'verification_type': instance.verification_type,
                'status': 'rejected',
                'rejection_reason': reason,
            },
        )


@receiver(pre_save, sender=VerificationRequest)
def store_prev_verification_status(sender, instance, **kwargs):
    """Store the current status before save so post_save can detect real changes."""
    if not instance.pk:
        instance._prev_status = None
        return
    instance._prev_status = (
        sender.objects.filter(pk=instance.pk)
        .values_list('status', flat=True)
        .first()
    )


def create_payout_completed_notification(transaction):
    """Notify the payout recipient after a payout completes successfully."""
    recipient = transaction.recipient
    if recipient is None:
        return

    role_label = 'delivery earnings' if transaction.recipient_role == 'delivery' else 'payout'
    order = transaction.order
    _create_notification(
        recipient=recipient,
        notification_type='payout_completed',
        title='Payout Completed',
        message=(
            f'Your {role_label} of {transaction.amount} {transaction.currency} '
            f'for order #{order.order_number} has been paid successfully.'
        ),
        data_payload={
            'order_id': order.id,
            'order_number': order.order_number,
            'transaction_id': str(transaction.transaction_id),
            'amount': str(transaction.amount),
            'currency': transaction.currency,
            'recipient_role': transaction.recipient_role,
        },
    )


# ── Welcome notification ──────────────────────────────────────────────────────

_WELCOME_MESSAGES = {
    'buyer': (
        'Welcome to Pocket Shop!',
        'Your account is ready. Browse products from local sellers and place your first order.',
    ),
    'seller': (
        'Welcome to Pocket Shop!',
        'Your seller account is set up. Complete your verification to start listing products.',
    ),
    'delivery': (
        'Welcome to Pocket Shop!',
        'Your delivery account is set up. Complete your verification to start accepting deliveries.',
    ),
}


@receiver(post_save, sender=User)
def send_welcome_notification(sender, instance, created, **kwargs):
    """Send a role-specific welcome notification when a new user registers."""
    if not created:
        return
    if instance.role == 'admin':
        return

    title, message = _WELCOME_MESSAGES.get(
        instance.role,
        ('Welcome to Pocket Shop!', 'Your account is ready.'),
    )
    _create_notification(
        recipient=instance,
        notification_type='welcome',
        title=title,
        message=message,
        data_payload={'role': instance.role},
    )


# ── Announcement broadcast ────────────────────────────────────────────────────

def _send_announcement_push_batch(tokens, title, message):
    """Send FCM pushes to up to 500 tokens in one multicast call."""
    if not tokens:
        return 0
    app = _get_firebase_app()
    if app is None:
        return 0
    try:
        from firebase_admin import messaging
        multicast = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=message),
            data={'notification_type': 'announcement'},
            tokens=tokens,
        )
        response = messaging.send_each_for_multicast(multicast, app=app)
        logger.info('Announcement FCM: %s success, %s failure', response.success_count, response.failure_count)
        return response.success_count
    except Exception as exc:
        logger.warning('Announcement FCM batch failed: %s', exc)
        return 0


@receiver(post_save, sender=Announcement)
def broadcast_announcement(sender, instance, created, **kwargs):
    """
    When an Announcement is saved for the first time, create individual
    Notification records for all targeted users and send FCM pushes.
    Skipped on subsequent saves so edits don't re-send.
    """
    if not created:
        return

    audience = instance.target_audience
    qs = User.objects.filter(is_active=True).exclude(role='admin')
    if audience == 'buyers':
        qs = qs.filter(role='buyer')
    elif audience == 'sellers':
        qs = qs.filter(role='seller')
    elif audience == 'delivery':
        qs = qs.filter(role='delivery')

    users = list(qs)
    if not users:
        return

    # Bulk-create in-app notification records
    notifications = [
        Notification(
            recipient=user,
            notification_type='announcement',
            title=instance.title,
            message=instance.message,
            data={'announcement_id': instance.id},
        )
        for user in users
    ]
    Notification.objects.bulk_create(notifications, ignore_conflicts=True)

    # Send FCM pushes in batches of 500
    tokens = [u.fcm_token for u in users if u.fcm_token]
    sent = 0
    for i in range(0, len(tokens), 500):
        sent += _send_announcement_push_batch(
            tokens[i:i + 500], instance.title, instance.message
        )

    # Mark as sent
    Announcement.objects.filter(pk=instance.pk).update(
        is_sent=True, sent_count=len(users)
    )
