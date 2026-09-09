# Step 4 of the Country rollout: country becomes required now that every
# existing row was backfilled to Zambia in 0025. No default supplied here
# on purpose — Postgres's SET NOT NULL just checks for existing NULLs, and
# there are none left by the time this migration runs.

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0025_backfill_sellerprofile_country'),
    ]

    operations = [
        migrations.AlterField(
            model_name='sellerprofile',
            name='country',
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.PROTECT,
                related_name='sellers',
                to='accounts.country',
            ),
        ),
    ]
