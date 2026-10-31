"""Monthly email update for every approved partner.

Run on the 1st of each month (cron), e.g.:
    0 8 1 * * cd /path/to/pocket_backend && .venv/bin/python manage.py send_partner_statements
"""
from datetime import datetime

from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from promotions import emails
from promotions.models import Partner
from promotions.services import partner_stats


def _month_bounds(year, month):
    tz = timezone.get_current_timezone()
    start = timezone.make_aware(datetime(year, month, 1), tz)
    end = timezone.make_aware(datetime(year + (month == 12), month % 12 + 1, 1), tz)
    return start, end


class Command(BaseCommand):
    help = "Email each approved partner last month's sign-ups, orders and earnings."

    def add_arguments(self, parser):
        parser.add_argument('--month', help='Which month to report, as YYYY-MM. Default: last month.')
        parser.add_argument('--dry-run', action='store_true', help='Show who would get an email, send nothing.')

    def handle(self, *args, **opts):
        if opts['month']:
            try:
                year, month = (int(x) for x in opts['month'].split('-'))
                start, end = _month_bounds(year, month)
            except (ValueError, TypeError):
                raise CommandError('Use --month YYYY-MM, e.g. --month 2026-10')
        else:
            today = timezone.localdate()
            year, month = (today.year, today.month - 1) if today.month > 1 else (today.year - 1, 12)
            start, end = _month_bounds(year, month)
        label = start.strftime('%B %Y')

        sent = failed = 0
        for partner in Partner.objects.filter(status=Partner.APPROVED, approved_at__lt=end):
            stats = partner_stats(partner, since=start, until=end)
            balances = partner.balances()
            if opts['dry_run']:
                self.stdout.write(f'{partner.email}: {stats} owed K{balances["owed"]}')
                continue
            if emails.send_statement(partner, label, stats, balances):
                sent += 1
            else:
                failed += 1
        if not opts['dry_run']:
            self.stdout.write(self.style.SUCCESS(f'{label}: sent {sent}, failed {failed}.'))
