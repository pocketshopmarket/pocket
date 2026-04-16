from django.contrib import admin

from .models import ProductReview


@admin.register(ProductReview)
class ProductReviewAdmin(admin.ModelAdmin):
    list_display = [
        'id',
        'product',
        'author',
        'rating',
        'is_verified_purchase',
        'created_at',
    ]
    list_filter = ['rating', 'is_verified_purchase', 'created_at']
    search_fields = ['product__name', 'author__full_name', 'author__phone_number', 'comment']
