from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('orders', '0007_add_payment_pending_status'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='RefundRequest',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('reason', models.TextField()),
                ('status', models.CharField(
                    choices=[
                        ('pending_seller', 'Pending Seller Review'),
                        ('approved_by_seller', 'Approved by Seller'),
                        ('rejected_by_seller', 'Rejected by Seller'),
                        ('escalated', 'Escalated to Admin'),
                        ('approved_by_admin', 'Approved by Admin'),
                        ('rejected_by_admin', 'Rejected by Admin'),
                        ('refunded', 'Refunded'),
                    ],
                    default='pending_seller',
                    max_length=30,
                )),
                ('seller_note', models.TextField(blank=True)),
                ('admin_note', models.TextField(blank=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('order', models.OneToOneField(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name='refund_request',
                    to='orders.order',
                )),
                ('requested_by', models.ForeignKey(
                    on_delete=django.db.models.deletion.CASCADE,
                    related_name='refund_requests',
                    to=settings.AUTH_USER_MODEL,
                )),
            ],
            options={'ordering': ['-created_at']},
        ),
    ]
