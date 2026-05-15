"""Add payment notification types to Notification.TYPE_CHOICES."""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('notifications', '0001_initial'),
    ]

    operations = [
        migrations.AlterField(
            model_name='notification',
            name='notification_type',
            field=models.CharField(
                choices=[
                    ('order_placed', 'New Order Placed'),
                    ('order_accepted', 'Order Accepted'),
                    ('order_preparing', 'Order Being Prepared'),
                    ('order_ready', 'Order Ready for Pickup'),
                    ('order_out_for_delivery', 'Order Out for Delivery'),
                    ('order_delivered', 'Order Delivered'),
                    ('order_cancelled', 'Order Cancelled'),
                    ('payment_pending', 'Payment Pending'),
                    ('payment_completed', 'Payment Completed'),
                    ('payment_failed', 'Payment Failed'),
                    ('payout_completed', 'Payout Completed'),
                    ('delivery_assigned', 'Delivery Assigned'),
                    ('general', 'General'),
                ],
                default='general',
                max_length=32,
            ),
        ),
    ]
