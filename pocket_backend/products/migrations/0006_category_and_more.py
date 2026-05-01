# Rewritten migration: safely converts Product.category from CharField → ForeignKey
# by creating Category rows from existing data first, then linking products.
#
# SQLite-safe: drops the old index on `category` before renaming/removing the column.

import django.db.models.deletion
from django.db import migrations, models
from django.utils.text import slugify


def populate_categories_and_link_products(apps, schema_editor):
    """
    1. Read every unique category string from products_product.category_legacy.
    2. Create a Category row for each one.
    3. Set category_fk on every product to the matching Category row.
    """
    Category = apps.get_model('products', 'Category')
    Product = apps.get_model('products', 'Product')

    seen = {}
    for product in Product.objects.all():
        raw = (product.category_legacy or '').strip().lower() or 'other'
        if raw not in seen:
            slug = slugify(raw) or 'other'
            base_slug = slug
            counter = 1
            while Category.objects.filter(slug=slug).exists():
                slug = f"{base_slug}-{counter}"
                counter += 1
            cat = Category.objects.create(
                name=raw.replace('_', ' ').title(),
                slug=slug,
            )
            seen[raw] = cat
        product.category_fk = seen[raw]
        product.save(update_fields=['category_fk'])


def reverse_populate(apps, schema_editor):
    Product = apps.get_model('products', 'Product')
    for product in Product.objects.select_related('category_fk').all():
        if product.category_fk:
            product.category_legacy = product.category_fk.slug
        else:
            product.category_legacy = 'other'
        product.save(update_fields=['category_legacy'])


class Migration(migrations.Migration):

    dependencies = [
        ('products', '0005_productvariant_product_purchases_count_and_more'),
    ]

    operations = [
        # ── Step 1: Create Category model ──
        migrations.CreateModel(
            name='Category',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(max_length=100)),
                ('slug', models.SlugField(unique=True)),
                ('icon_name', models.CharField(blank=True, max_length=50, null=True)),
                ('parent', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='subcategories', to='products.category')),
            ],
            options={
                'verbose_name_plural': 'Categories',
                'ordering': ['name'],
            },
        ),

        # ── Step 2: Drop the old index on `category` (CharField) BEFORE renaming ──
        migrations.RemoveIndex(
            model_name='product',
            name='products_pr_categor_14b9c0_idx',
        ),

        # ── Step 3: Rename old CharField 'category' → 'category_legacy' ──
        migrations.RenameField(
            model_name='product',
            old_name='category',
            new_name='category_legacy',
        ),

        # ── Step 4: Add temporary FK field 'category_fk' ──
        migrations.AddField(
            model_name='product',
            name='category_fk',
            field=models.ForeignKey(
                null=True,
                blank=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='products_new',
                to='products.category',
            ),
        ),

        # ── Step 5: Data migration — create Category rows, link products ──
        migrations.RunPython(
            populate_categories_and_link_products,
            reverse_populate,
        ),

        # ── Step 6: Remove old string field ──
        migrations.RemoveField(
            model_name='product',
            name='category_legacy',
        ),

        # ── Step 7: Rename 'category_fk' → 'category' ──
        migrations.RenameField(
            model_name='product',
            old_name='category_fk',
            new_name='category',
        ),

        # ── Step 8: Final FK definition (correct related_name, no blank) ──
        migrations.AlterField(
            model_name='product',
            name='category',
            field=models.ForeignKey(
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='products',
                to='products.category',
            ),
        ),

        # ── Step 9: Re-add the index on the new FK column ──
        migrations.AddIndex(
            model_name='product',
            index=models.Index(fields=['category'], name='products_pr_categor_9edb3d_idx'),
        ),
    ]
