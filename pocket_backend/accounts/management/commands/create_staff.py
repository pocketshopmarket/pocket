import random
import string

from django.core.management.base import BaseCommand, CommandError

from accounts.models import User
from accounts.phone_utils import normalize_zambia_phone_to_e164


def _gen_password(length=8):
    chars = string.ascii_letters + string.digits
    return ''.join(random.choices(chars, k=length))


class Command(BaseCommand):
    help = 'Create a staff user account'

    def add_arguments(self, parser):
        parser.add_argument('phone', help='Phone number, e.g. 0973714666 or +260973714666')
        parser.add_argument('name', help='Full name, e.g. "Mponda Katepwe"')
        parser.add_argument('--gender', default='male', choices=['male', 'female'])
        parser.add_argument('--password', help='Set a specific password (optional — auto-generated if omitted)')

    def handle(self, *args, **options):
        phone = normalize_zambia_phone_to_e164(options['phone'].strip())
        name = options['name'].strip()
        gender = options['gender']
        password = options['password'] or _gen_password()

        if User.objects.filter(phone_number=phone).exists():
            raise CommandError(f'A user with phone number {phone} already exists.')

        user = User.objects.create_user(
            phone_number=phone,
            password=password,
            full_name=name,
            gender=gender,
            role='staff',
            is_phone_verified=True,
            is_active=True,
        )

        self.stdout.write(self.style.SUCCESS(
            f'\nStaff account created successfully.\n'
            f'  Name   : {user.full_name}\n'
            f'  Phone  : {user.phone_number}\n'
            f'  Role   : staff\n'
            f'  Password (app login not needed — uses OTP): {password}\n'
        ))
