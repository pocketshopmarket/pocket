from django.contrib import admin

from .models import Product, ProductImage, ProductVariant, PromoBanner


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


@admin.register(PromoBanner)
class PromoBannerAdmin(admin.ModelAdmin):
    list_display = [
        'title', 'subtitle', 'cta_text', 'bg_color',
        'action_type', 'action_value', 'is_active', 'priority',
        'starts_at', 'ends_at',
    ]
    list_filter = ['is_active', 'action_type']
    list_editable = ['is_active', 'priority']
    search_fields = ['title', 'subtitle']
    readonly_fields = ['created_at']

    fieldsets = (
        ('Content', {
            'fields': ('title', 'subtitle', 'cta_text'),
        }),
        ('Visuals', {
            'fields': ('bg_color', 'icon_name', 'image'),
            'description': 'Upload an image OR set an icon_name. Image takes priority when both are set.',
        }),
        ('Action (what happens when tapped)', {
            'fields': ('action_type', 'action_value'),
            'description': (
                '<b>action_type = category</b> → enter the Category ID in action_value (find it in the Categories list).<br>'
                '<b>action_type = product</b> → enter the Product ID in action_value (find it in the Products list).<br>'
                '<b>action_type = url</b> → paste the full URL (https://...) in action_value.<br>'
                '<b>action_type = none</b> → leave action_value empty.'
            ),
        }),
        ('Scheduling', {
            'fields': ('is_active', 'priority', 'starts_at', 'ends_at'),
            'description': 'Leave starts_at / ends_at blank to show the banner indefinitely.',
        }),
        ('Meta', {
            'fields': ('created_at',),
            'classes': ('collapse',),
        }),
    )
