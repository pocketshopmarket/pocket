from django.core.management.base import BaseCommand, CommandError
from accounts.models import User
from notifications.signals import _create_notification


class Command(BaseCommand):
    help = 'Send a test push notification to a user by phone number'

    def add_arguments(self, parser):
        parser.add_argument('phone', help='Phone number e.g. 0974086484 or +260974086484')
        parser.add_argument('--title', default='Test Notification', help='Notification title')
        parser.add_argument('--message', default='This is a test push notification from Pocket Shop.', help='Notification body')

    def handle(self, *args, **options):
        phone = options['phone'].strip()
        # Normalise: accept 0974... or +260974...
        variants = [phone]
        if phone.startswith('0'):
            variants.append('+260' + phone[1:])
        elif phone.startswith('+260'):
            variants.append('0' + phone[4:])

        user = User.objects.filter(phone_number__in=variants).first()
        if not user:
            raise CommandError(f'No user found with phone number: {phone}')

        self.stdout.write(f'Found user: {user.phone_number} (role={user.role}, id={user.id})')
        self.stdout.write(f'FCM token: {user.fcm_token or "(none registered)"}')

        if not user.fcm_token:
            self.stdout.write(self.style.WARNING(
                'User has no FCM token — in-app notification will be created but no push will be sent.'
            ))

        _create_notification(
            recipient=user,
            notification_type='announcement',
            title=options['title'],
            message=options['message'],
            data_payload={'test': 'true'},
        )

        self.stdout.write(self.style.SUCCESS('Notification sent successfully.'))
