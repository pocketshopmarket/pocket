from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0003_user_full_name_user_gender'),
    ]

    operations = [
        migrations.AddField(
            model_name='deliveryprofile',
            name='license_back_image',
            field=models.ImageField(blank=True, null=True, upload_to='delivery_licenses/'),
        ),
        migrations.AddField(
            model_name='deliveryprofile',
            name='license_front_image',
            field=models.ImageField(blank=True, null=True, upload_to='delivery_licenses/'),
        ),
        migrations.AddField(
            model_name='sellerprofile',
            name='nrc_number',
            field=models.CharField(blank=True, max_length=30, null=True),
        ),
    ]
