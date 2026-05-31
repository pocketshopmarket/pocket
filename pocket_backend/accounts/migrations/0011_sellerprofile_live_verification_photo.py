from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0010_verificationrequest'),
    ]

    operations = [
        migrations.AddField(
            model_name='sellerprofile',
            name='live_verification_photo',
            field=models.ImageField(
                blank=True,
                null=True,
                upload_to='seller_verification/',
            ),
        ),
    ]
