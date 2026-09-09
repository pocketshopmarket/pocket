# Step 4 of the Country rollout: country becomes required now that the one
# existing row was backfilled to Zambia in 0011. No default supplied here
# on purpose — Postgres's SET NOT NULL just checks for existing NULLs, and
# there are none left by the time this migration runs.

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('delivery', '0011_backfill_deliverypricingconfig_country'),
    ]

    operations = [
        migrations.AlterField(
            model_name='deliverypricingconfig',
            name='country',
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.PROTECT,
                related_name='delivery_pricing_configs',
                to='accounts.country',
            ),
        ),
    ]
