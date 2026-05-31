from django.db import migrations, models
import django.db.models.deletion

import accounts.models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0011_sellerprofile_live_verification_photo'),
    ]

    operations = [
        migrations.CreateModel(
            name='ErrorLog',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('reference_id', models.CharField(default=accounts.models.generate_error_reference, editable=False, max_length=12, unique=True)),
                ('error_type', models.CharField(choices=[('validation', 'Validation'), ('authentication', 'Authentication'), ('permission', 'Permission'), ('not_found', 'Not Found'), ('throttled', 'Throttled'), ('external_service', 'External Service'), ('server', 'Server'), ('unknown', 'Unknown')], default='unknown', max_length=32)),
                ('error_code', models.CharField(blank=True, max_length=100)),
                ('error_class', models.CharField(blank=True, max_length=200)),
                ('message', models.TextField()),
                ('user_message', models.TextField(blank=True)),
                ('status_code', models.PositiveIntegerField(blank=True, null=True)),
                ('method', models.CharField(blank=True, max_length=10)),
                ('path', models.CharField(blank=True, max_length=255)),
                ('request_data', models.JSONField(blank=True, default=dict)),
                ('metadata', models.JSONField(blank=True, default=dict)),
                ('traceback', models.TextField(blank=True)),
                ('resolved', models.BooleanField(default=False)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='error_logs', to='accounts.user')),
            ],
            options={
                'ordering': ['-created_at'],
            },
        ),
    ]
