from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0008_buyer_payment_method'),
    ]

    operations = [
        migrations.AddField(
            model_name='sellerprofile',
            name='business_name',
            field=models.CharField(blank=True, max_length=200),
        ),
        migrations.AddField(
            model_name='sellerprofile',
            name='business_registration_number',
            field=models.CharField(blank=True, max_length=80),
        ),
        migrations.AddField(
            model_name='sellerprofile',
            name='nrc_front_image',
            field=models.ImageField(blank=True, null=True, upload_to='seller_nrc/'),
        ),
        migrations.AddField(
            model_name='sellerprofile',
            name='nrc_back_image',
            field=models.ImageField(blank=True, null=True, upload_to='seller_nrc/'),
        ),
        migrations.AddField(
            model_name='sellerprofile',
            name='tier1_status',
            field=models.CharField(
                choices=[
                    ('not_started', 'Not Started'),
                    ('submitted', 'Submitted'),
                    ('approved', 'Approved'),
                    ('rejected', 'Rejected'),
                ],
                default='not_started',
                max_length=20,
            ),
        ),
        migrations.AddField(
            model_name='sellerprofile',
            name='tier2_status',
            field=models.CharField(
                choices=[
                    ('not_started', 'Not Started'),
                    ('submitted', 'Submitted'),
                    ('approved', 'Approved'),
                    ('rejected', 'Rejected'),
                ],
                default='not_started',
                max_length=20,
            ),
        ),
        migrations.AddField(
            model_name='sellerprofile',
            name='verification_rejection_reason',
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name='sellerprofile',
            name='submitted_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='sellerprofile',
            name='reviewed_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='deliveryprofile',
            name='province',
            field=models.CharField(blank=True, max_length=80),
        ),
        migrations.AddField(
            model_name='deliveryprofile',
            name='town',
            field=models.CharField(blank=True, max_length=80),
        ),
        migrations.AddField(
            model_name='deliveryprofile',
            name='area',
            field=models.CharField(blank=True, max_length=120),
        ),
        migrations.AddField(
            model_name='deliveryprofile',
            name='live_verification_photo',
            field=models.ImageField(
                blank=True,
                null=True,
                upload_to='delivery_verification/',
            ),
        ),
        migrations.AddField(
            model_name='deliveryprofile',
            name='profile_photo',
            field=models.ImageField(blank=True, null=True, upload_to='profile_photos/'),
        ),
        migrations.AddField(
            model_name='deliveryprofile',
            name='verification_status',
            field=models.CharField(
                choices=[
                    ('not_started', 'Not Started'),
                    ('submitted', 'Submitted'),
                    ('approved', 'Approved'),
                    ('rejected', 'Rejected'),
                ],
                default='not_started',
                max_length=20,
            ),
        ),
        migrations.AddField(
            model_name='deliveryprofile',
            name='verification_rejection_reason',
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name='deliveryprofile',
            name='submitted_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='deliveryprofile',
            name='reviewed_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
