"""Add 'payment_pending' to Order.STATUS_CHOICES."""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('orders', '0006_add_delivery_fee_and_fulfillment_type'),
    ]

    operations = [
        migrations.AlterField(
            model_name='order',
            name='status',
            field=models.CharField(
                choices=[
                    ('pending', 'Pending'),
                    ('payment_pending', 'Payment Pending'),
                    ('accepted', 'Accepted'),
                    ('preparing', 'Preparing'),
                    ('out_for_delivery', 'Out for Delivery'),
                    ('delivered', 'Delivered'),
                    ('cancelled', 'Cancelled'),
                ],
                default='pending',
                max_length=20,
            ),
        ),
    ]
