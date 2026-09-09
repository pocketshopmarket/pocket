# Data migration: seed the Zambia row so every existing seller/config can
# be backfilled to it once the country FK is added to those tables. This
# migration only ever creates Zambia — Rwanda/Zimbabwe rows get added when
# those markets actually launch, not here.

from django.db import migrations


def seed_zambia(apps, schema_editor):
    Country = apps.get_model('accounts', 'Country')
    Country.objects.get_or_create(
        code='ZM',
        defaults={
            'name': 'Zambia',
            'currency_code': 'ZMW',
            'calling_code': '260',
            'is_active': True,
        },
    )


def remove_zambia(apps, schema_editor):
    Country = apps.get_model('accounts', 'Country')
    Country.objects.filter(code='ZM').delete()


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0022_country'),
    ]

    operations = [
        migrations.RunPython(seed_zambia, remove_zambia),
    ]
