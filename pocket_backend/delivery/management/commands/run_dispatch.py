"""Backup for rider offer rounds. Rider apps move rounds on when they check in; this
covers quiet moments when no rider app is open.

Cron, every minute:
    * * * * * cd /path/to/pocket_backend && .venv/bin/python manage.py run_dispatch
"""
from django.core.management.base import BaseCommand

from delivery.dispatch import advance_dispatch


class Command(BaseCommand):
    help = 'Move on delivery offer rounds that have run out.'

    def handle(self, *args, **options):
        moved = advance_dispatch()
        if moved:
            self.stdout.write(f'Moved on {moved} order(s).')
