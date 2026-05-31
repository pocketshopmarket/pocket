import os
from django.core.management.base import BaseCommand
from accounts.models import User


class Command(BaseCommand):
    help = 'Create or update the admin superuser'

    def handle(self, *args, **options):
        phone = os.environ.get('ADMIN_PHONE', '+260977834810')
        password = os.environ.get('ADMIN_PASSWORD', 'pocket@admin2026!')
        user, created = User.objects.get_or_create(
            phone_number=phone,
            defaults={
                'full_name': 'Admin',
                'role': 'admin',
                'is_staff': True,
                'is_superuser': True,
                'is_active': True,
            },
        )
        user.set_password(password)
        user.is_staff = True
        user.is_superuser = True
        user.is_active = True
        user.save()
        action = 'Created' if created else 'Updated'
        self.stdout.write(self.style.SUCCESS(f'{action} admin: {phone}'))
