# Data migration: seed two default promo banners so the home screen
# always has content even before the admin creates any.

from django.db import migrations


def seed_banners(apps, schema_editor):
    PromoBanner = apps.get_model('products', 'PromoBanner')
    if PromoBanner.objects.exists():
        return  # Don't duplicate if banners already exist

    PromoBanner.objects.create(
        title='Fresh picks',
        subtitle='Delivered faster',
        cta_text='Shop now',
        bg_color='#F97316',
        icon_name='shopping_bag_outlined',
        action_type='none',
        action_value='',
        is_active=True,
        priority=10,
    )
    PromoBanner.objects.create(
        title='Trending deals',
        subtitle='Save on essentials',
        cta_text='View offers',
        bg_color='#3B82F6',
        icon_name='shopping_bag_outlined',
        action_type='none',
        action_value='',
        is_active=True,
        priority=5,
    )


def remove_banners(apps, schema_editor):
    PromoBanner = apps.get_model('products', 'PromoBanner')
    PromoBanner.objects.filter(
        title__in=['Fresh picks', 'Trending deals'],
    ).delete()


class Migration(migrations.Migration):

    dependencies = [
        ('products', '0008_promobanner'),
    ]

    operations = [
        migrations.RunPython(seed_banners, remove_banners),
    ]
