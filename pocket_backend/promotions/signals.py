import logging

from django.db.models.signals import post_save
from django.dispatch import receiver

from orders.models import Order
from payments.models import Transaction

from .services import record_earning_for_delivered_order, reverse_earning_for_refunded_order

logger = logging.getLogger(__name__)


@receiver(post_save, sender=Order)
def partner_earning_on_delivery(sender, instance, **kwargs):
    if instance.status != 'delivered':
        return
    try:
        record_earning_for_delivered_order(instance)
    except Exception:  # never let partner bookkeeping break a delivery
        logger.exception('Could not record partner earning for order %s', instance.pk)


@receiver(post_save, sender=Transaction)
def partner_earning_reversed_on_refund(sender, instance, **kwargs):
    if instance.transaction_type == 'refund' and instance.status == 'completed' and instance.order_id:
        reverse_earning_for_refunded_order(instance.order_id)
