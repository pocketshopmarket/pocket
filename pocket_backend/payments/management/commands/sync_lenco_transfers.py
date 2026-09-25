from django.core.management.base import BaseCommand

from payments.lenco_transfers import sync_lenco_transfer
from payments.models import Transaction


class Command(BaseCommand):
    help = (
        'Ask Lenco how in-flight refunds and bank payouts ended. A safety net '
        'for missed webhooks — run it every few minutes from cron.'
    )

    def handle(self, *args, **options):
        in_flight = Transaction.objects.filter(
            gateway='lenco', status='accepted', transaction_type__in=['refund', 'payout'],
        ).select_related('order', 'bank_account', 'recipient')
        settled = 0
        for tx in in_flight:
            if sync_lenco_transfer(tx).status != 'accepted':
                settled += 1
        self.stdout.write(f'Checked {in_flight.count()} transfer(s); {settled} settled.')
