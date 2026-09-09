# Data migration: every SellerProfile that exists today was created before
# the country field existed, so it's Zambian by definition. Backfill them
# all before the field becomes required in a later migration.

from django.db import migrations


def backfill_zambia(apps, schema_editor):
    Country = apps.get_model('accounts', 'Country')
    SellerProfile = apps.get_model('accounts', 'SellerProfile')
    zambia = Country.objects.filter(code='ZM').first()
    if zambia is None:
        return  # 0023_seed_zambia_country didn't run for some reason — nothing to backfill onto
    SellerProfile.objects.filter(country__isnull=True).update(country=zambia)


def unset_country(apps, schema_editor):
    SellerProfile = apps.get_model('accounts', 'SellerProfile')
    SellerProfile.objects.update(country=None)


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0024_sellerprofile_country'),
        ('accounts', '0023_seed_zambia_country'),
    ]

    operations = [
        migrations.RunPython(backfill_zambia, unset_country),
    ]
