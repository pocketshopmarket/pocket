from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('delivery', '0002_route_and_zones_fields'),
    ]

    operations = [
        migrations.AddField(
            model_name='deliveryassignment',
            name='location_updated_at',
            field=models.DateTimeField(
                blank=True,
                help_text='When current_location was last set (rider GPS)',
                null=True,
            ),
        ),
    ]
