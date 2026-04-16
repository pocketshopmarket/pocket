from django.contrib import admin

from .models import Product, ProductImage, ProductVariant


class ProductImageInline(admin.TabularInline):
    model = ProductImage
    extra = 0


class ProductVariantInline(admin.TabularInline):
    model = ProductVariant
    extra = 0


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = [
        'name',
        'seller',
        'price',
        'quality',
        'stock_quantity',
        'is_available',
        'views_count',
        'purchases_count',
        'created_at',
    ]
    list_filter = ['category', 'quality', 'is_available']
    search_fields = ['name', 'seller__phone_number']
    inlines = [ProductImageInline, ProductVariantInline]


@admin.register(ProductImage)
class ProductImageAdmin(admin.ModelAdmin):
    list_display = ['id', 'product', 'sort_order']
    list_filter = ['product']


@admin.register(ProductVariant)
class ProductVariantAdmin(admin.ModelAdmin):
    list_display = ['id', 'product', 'name', 'value', 'sku', 'stock_quantity', 'is_active']
    list_filter = ['name', 'is_active']
    search_fields = ['sku', 'product__name', 'product__seller__phone_number']
