from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0015_add_qr_secret'),
    ]

    operations = [
        migrations.AddField(
            model_name='deliveryprofile',
            name='vehicle_make',
            field=models.CharField(blank=True, max_length=60),
        ),
        migrations.AddField(
            model_name='deliveryprofile',
            name='vehicle_model',
            field=models.CharField(blank=True, max_length=60),
        ),
    ]
