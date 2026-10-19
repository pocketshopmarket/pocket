from django.contrib import admin

from .models import Category, Product, ProductImage, ProductVariant, PromoBanner


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ['name', 'slug', 'parent', 'is_age_restricted']
    list_filter = ['is_age_restricted', 'parent']
    list_editable = ['is_age_restricted']
    search_fields = ['name', 'slug']


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
        'title', 'seller', 'status', 'price_paid', 'duration_days',
        'action_type', 'action_value', 'is_active', 'priority',
        'starts_at', 'ends_at',
    ]
    list_filter = ['status', 'is_active', 'action_type']
    list_editable = ['priority']
    search_fields = ['title', 'subtitle', 'seller__phone_number', 'seller__full_name']
    readonly_fields = ['created_at']
    autocomplete_fields = ['seller']

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
                '<b>action_type = shop</b> → enter the seller User ID in action_value (find it in the Users list).<br>'
                '<b>action_type = url</b> → paste the full URL (https://...) in action_value.<br>'
                '<b>action_type = none</b> → leave action_value empty.'
            ),
        }),
        ('Seller-paid slot', {
            'fields': ('seller', 'status', 'price_paid', 'duration_days'),
            'description': (
                'Leave seller blank for an ordinary admin-authored banner. When seller is set, '
                'is_active is forced off until status is moved to "active" — use the staff banner '
                'review queue (or set status to active here) to publish it, never is_active alone.'
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
