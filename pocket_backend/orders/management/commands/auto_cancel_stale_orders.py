"""
Management command: auto_cancel_stale_orders

Finds orders stuck in 'accepted' (paid but seller hasn't started preparing)
past the configured timeout and auto-cancels + refunds them.

Usage
-----
    # One-shot (cron / ECS Scheduled Task):
    python manage.py auto_cancel_stale_orders

    # Override timeout per invocation:
    python manage.py auto_cancel_stale_orders --timeout-minutes 45

    # Continuous daemon mode (runs every --interval seconds):
    python manage.py auto_cancel_stale_orders --daemon --interval 120
"""

import time

from django.conf import settings
from django.core.management.base import BaseCommand
from django.utils import timezone
from datetime import timedelta

from orders.models import Order
from orders.services import cancel_order_with_refund


class Command(BaseCommand):
    help = (
        'Auto-cancel orders stuck in "accepted" past the acceptance timeout '
        'and refund the buyer.'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--timeout-minutes',
            type=int,
            default=None,
            help=(
                'Minutes an order may remain in "accepted" before auto-cancel. '
                'Defaults to ORDER_ACCEPTANCE_TIMEOUT_MINUTES setting.'
            ),
        )
        parser.add_argument(
            '--daemon',
            action='store_true',
            help='Run continuously instead of one-shot.',
        )
        parser.add_argument(
            '--interval',
            type=int,
            default=120,
            help='Seconds between sweeps in daemon mode (default: 120).',
        )

    def handle(self, *args, **options):
        timeout_minutes = (
            options['timeout_minutes']
            or getattr(settings, 'ORDER_ACCEPTANCE_TIMEOUT_MINUTES', 30)
        )
        daemon = options['daemon']
        interval = options['interval']

        self.stdout.write(
            f'Order acceptance timeout: {timeout_minutes} min | '
            f'Daemon: {daemon} | Interval: {interval}s'
        )

        if daemon:
            self.stdout.write('Starting daemon loop…')
            while True:
                self._sweep(timeout_minutes)
                time.sleep(interval)
        else:
            self._sweep(timeout_minutes)

    def _sweep(self, timeout_minutes: int):
        cutoff = timezone.now() - timedelta(minutes=timeout_minutes)

        # Cancel orders stuck in 'accepted' (seller not preparing)
        # and 'payment_pending' (buyer never approved payment prompt)
        stale_orders = Order.objects.filter(
            status__in=['accepted', 'payment_pending'],
            updated_at__lte=cutoff,
        ).order_by('created_at')

        count = stale_orders.count()
        if count == 0:
            self.stdout.write(self.style.SUCCESS('No stale orders found.'))
            return

        self.stdout.write(f'Found {count} stale order(s) to cancel...')

        cancelled = 0
        for order in stale_orders:
            reason = (
                f'Auto-cancelled: seller did not prepare within '
                f'{timeout_minutes} minutes'
            )
            ok = cancel_order_with_refund(order, reason=reason)
            if ok:
                cancelled += 1
                self.stdout.write(
                    self.style.WARNING(
                        f'  [X] {order.order_number} -- cancelled + refund initiated'
                    )
                )
            else:
                self.stdout.write(
                    f'  [>] {order.order_number} -- skipped '
                    f'(status={order.status})'
                )

        self.stdout.write(
            self.style.SUCCESS(f'Done. Cancelled {cancelled}/{count} orders.')
        )
