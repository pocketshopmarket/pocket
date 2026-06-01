import os
from django.core.management.base import BaseCommand
from accounts.models import User


class Command(BaseCommand):
    help = 'Create or update the admin superuser'

    def handle(self, *args, **options):
        raw_phone = os.environ.get('ADMIN_PHONE', '260977834810')
        password = os.environ.get('ADMIN_PASSWORD', 'pocket@admin2026!')

        # Try both formats: with and without leading +
        variants = [raw_phone, f'+{raw_phone}'] if not raw_phone.startswith('+') else [raw_phone, raw_phone[1:]]

        user = None
        for variant in variants:
            user = User.objects.filter(phone_number=variant).first()
            if user:
                self.stdout.write(f'Found existing user: {variant}')
                break

        if user:
            user.set_password(password)
            user.is_staff = True
            user.is_superuser = True
            user.is_active = True
            user.save()
            self.stdout.write(self.style.SUCCESS(f'Updated admin: {user.phone_number}'))
        else:
            User.objects.create_superuser(
                phone_number=raw_phone,
                password=password,
                full_name='Admin',
            )
            self.stdout.write(self.style.SUCCESS(f'Created admin: {raw_phone}'))
