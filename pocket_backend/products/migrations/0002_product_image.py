from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('products', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='product',
            name='image',
            field=models.ImageField(
                blank=True,
                help_text='Uploaded product photo (shown in buyer app)',
                null=True,
                upload_to='products/%Y/%m/',
            ),
        ),
    ]
