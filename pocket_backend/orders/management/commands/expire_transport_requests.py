"""
Management command: expire_transport_requests

A seller has 24 hours to propose or decline a transport request before it
auto-expires, so a buyer is never left waiting indefinitely. Run this
every few minutes from cron.

Usage
-----
    python manage.py expire_transport_requests
"""
import logging

from django.core.management.base import BaseCommand
from django.utils import timezone

from orders.models import TransportRequest

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = 'Expire transport requests the seller never responded to within the 24-hour window.'

    def handle(self, *args, **options):
        stale = TransportRequest.objects.filter(status='pending', expires_at__lt=timezone.now())
        count = 0
        for tr in stale.select_related('buyer', 'product'):
            tr.status = 'expired'
            tr.decided_at = timezone.now()
            tr.save(update_fields=['status', 'decided_at', 'updated_at'])
            try:
                from notifications.signals import _create_notification
                _create_notification(
                    recipient=tr.buyer, notification_type='transport_expired',
                    title='Transport request expired',
                    message=f'The seller didn’t respond in time for {tr.product.name}. You can try again.',
                    data_payload={'transport_request_id': tr.id},
                )
            except Exception:
                logger.exception('Expiry notification failed for transport request %s', tr.id)
            count += 1
        self.stdout.write(f'Expired {count} transport request(s).')
