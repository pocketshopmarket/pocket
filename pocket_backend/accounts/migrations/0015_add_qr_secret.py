import uuid
from django.db import migrations, models


def populate_qr_secrets(apps, schema_editor):
    User = apps.get_model('accounts', 'User')
    for user in User.objects.all():
        user.qr_secret = uuid.uuid4()
        user.save(update_fields=['qr_secret'])


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0014_add_fcm_token'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='qr_secret',
            field=models.UUIDField(null=True, blank=True, editable=False),
        ),
        migrations.RunPython(populate_qr_secrets, migrations.RunPython.noop),
        migrations.AlterField(
            model_name='user',
            name='qr_secret',
            field=models.UUIDField(default=uuid.uuid4, editable=False, unique=True),
        ),
    ]
