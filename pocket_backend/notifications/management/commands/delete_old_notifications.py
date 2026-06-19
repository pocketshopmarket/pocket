from django.core.management.base import BaseCommand
from django.utils import timezone
from datetime import timedelta

from notifications.models import Notification


class Command(BaseCommand):
    help = 'Delete notifications older than a given number of days (default: 30).'

    def add_arguments(self, parser):
        parser.add_argument(
            '--days',
            type=int,
            default=30,
            help='Delete notifications older than this many days.',
        )

    def handle(self, *args, **options):
        cutoff = timezone.now() - timedelta(days=options['days'])
        deleted, _ = Notification.objects.filter(created_at__lt=cutoff).delete()
        self.stdout.write(
            self.style.SUCCESS(f'Deleted {deleted} notification(s) older than {options["days"]} days.')
        )
