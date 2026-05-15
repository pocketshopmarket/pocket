"""
Auto-create Notification rows when an Order changes status.

Listens to the Order post_save signal and creates relevant
notifications for buyers, sellers, and delivery agents.
"""

import logging
from django.db.models.signals import post_save
from django.dispatch import receiver

from orders.models import Order
from .models import Notification

logger = logging.getLogger(__name__)

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


def _create_notification(recipient, notification_type, title, message, data_payload):
    """Helper to create a notification and log failures."""
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


@receiver(post_save, sender=Order)
def order_status_notification(sender, instance, created, **kwargs):
    """Create notification(s) when an order status changes."""
    status = instance.status
    mapping = _STATUS_MAP.get(status)
    if not mapping:
        return

    # On creation, only fire 'pending' (new order for seller)
    if created and status != 'pending':
        return
    # On update, skip 'pending' because it was already sent on create
    if not created and status == 'pending':
        return

    order_number = instance.order_number
    data_payload = {
        'order_id': instance.id,
        'order_number': order_number,
        'status': status,
    }

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

    # Send buyer copy on order creation (so buyer also gets confirmation)
    buyer_copy = mapping.get('buyer_copy')
    if buyer_copy and created:
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
