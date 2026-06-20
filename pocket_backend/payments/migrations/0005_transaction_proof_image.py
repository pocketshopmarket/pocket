from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('payments', '0004_transaction_marked_paid_fields'),
    ]

    operations = [
        migrations.AddField(
            model_name='transaction',
            name='proof_image',
            field=models.ImageField(
                blank=True,
                null=True,
                upload_to='payout_proofs/',
                help_text='Screenshot of the mobile money transaction uploaded by staff',
            ),
        ),
    ]
