# Data migration: the existing DeliveryPricingConfig row (get_config()'s
# hardcoded pk=1 singleton) prices Zambian deliveries today, so it's
# Zambian by definition. Backfill it before the field becomes required.

from django.db import migrations


def backfill_zambia(apps, schema_editor):
    Country = apps.get_model('accounts', 'Country')
    DeliveryPricingConfig = apps.get_model('delivery', 'DeliveryPricingConfig')
    zambia = Country.objects.filter(code='ZM').first()
    if zambia is None:
        return
    DeliveryPricingConfig.objects.filter(country__isnull=True).update(country=zambia)


def unset_country(apps, schema_editor):
    DeliveryPricingConfig = apps.get_model('delivery', 'DeliveryPricingConfig')
    DeliveryPricingConfig.objects.update(country=None)


class Migration(migrations.Migration):

    dependencies = [
        ('delivery', '0010_deliverypricingconfig_country'),
        ('accounts', '0023_seed_zambia_country'),
    ]

    operations = [
        migrations.RunPython(backfill_zambia, unset_country),
    ]
