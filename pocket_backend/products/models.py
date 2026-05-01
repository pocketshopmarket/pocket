from django.db import models
from accounts.models import User

MAX_PRODUCT_IMAGES = 5


class Category(models.Model):
    name = models.CharField(max_length=100)
    slug = models.SlugField(unique=True)
    icon_name = models.CharField(max_length=50, blank=True, null=True)
    parent = models.ForeignKey('self', null=True, blank=True, related_name='subcategories', on_delete=models.CASCADE)
    
    class Meta:
        verbose_name_plural = 'Categories'
        ordering = ['name']
        
    def __str__(self):
        return self.name


class Product(models.Model):
    QUALITY_CHOICES = [
        ('new', 'New'),
        ('like_new', 'Like new'),
        ('good', 'Good'),
        ('fair', 'Fair'),
        ('used', 'Used'),
    ]

    name = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    category = models.ForeignKey(Category, on_delete=models.SET_NULL, null=True, related_name='products')
    quality = models.CharField(
        max_length=20,
        choices=QUALITY_CHOICES,
        default='new',
        help_text='Condition / quality label for buyers',
    )
    seller = models.ForeignKey(User, on_delete=models.CASCADE, related_name='products')
    stock_quantity = models.PositiveIntegerField(default=0)
    image = models.ImageField(
        upload_to='products/%Y/%m/',
        blank=True,
        null=True,
        help_text='Legacy single upload; prefer ProductImage gallery (max 5).',
    )
    image_url = models.URLField(
        blank=True,
        null=True,
        help_text='Legacy external URL; prefer ProductImage gallery.',
    )
    is_available = models.BooleanField(default=True)
    views_count = models.PositiveIntegerField(default=0)
    purchases_count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['category']),
            models.Index(fields=['price']),
            models.Index(fields=['is_available']),
            models.Index(fields=['created_at']),
            models.Index(fields=['seller', 'is_available']),
        ]

    def __str__(self):
        return f"{self.name} - {self.price} ZMW"

    @property
    def is_in_stock(self):
        return self.stock_quantity > 0


class ProductImage(models.Model):
    """Up to [MAX_PRODUCT_IMAGES] rows per product; ordered by sort_order."""

    product = models.ForeignKey(
        Product,
        on_delete=models.CASCADE,
        related_name='gallery_images',
    )
    image = models.ImageField(
        upload_to='products/gallery/%Y/%m/',
        blank=True,
        null=True,
    )
    image_url = models.URLField(blank=True, null=True)
    sort_order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ['sort_order', 'id']

    def __str__(self):
        return f"Image {self.sort_order} for {self.product_id}"


class ProductVariant(models.Model):
    product = models.ForeignKey(
        Product,
        on_delete=models.CASCADE,
        related_name='variants',
    )
    name = models.CharField(max_length=64, help_text='Variant group, e.g. Size')
    value = models.CharField(max_length=64, help_text='Variant value, e.g. XL')
    sku = models.CharField(max_length=64)
    stock_quantity = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['name', 'value', 'id']
        constraints = [
            models.UniqueConstraint(
                fields=['product', 'name', 'value'],
                name='uniq_product_variant_name_value',
            ),
            models.UniqueConstraint(
                fields=['product', 'sku'],
                name='uniq_product_variant_sku',
            ),
        ]
        indexes = [
            models.Index(fields=['product', 'is_active']),
            models.Index(fields=['sku']),
        ]

    def __str__(self):
        return f"{self.product_id} {self.name}:{self.value}"

class UserInterest(models.Model):
    user = models.ForeignKey('accounts.BuyerProfile', on_delete=models.CASCADE, related_name='interests')
    category = models.ForeignKey(Category, on_delete=models.CASCADE)
    weight = models.FloatField(default=1.0)
    
    class Meta:
        unique_together = ('user', 'category')

class SearchHistory(models.Model):
    user = models.ForeignKey('accounts.BuyerProfile', on_delete=models.CASCADE, related_name='search_history')
    query = models.CharField(max_length=255)
    timestamp = models.DateTimeField(auto_now_add=True)
    clicked_product = models.ForeignKey(Product, null=True, blank=True, on_delete=models.SET_NULL)

    class Meta:
        ordering = ['-timestamp']

class ProductInteraction(models.Model):
    VIEW = 'view'
    CLICK = 'click'
    ADD_TO_CART = 'cart'

    INTERACTION_CHOICES = [
        (VIEW, 'View'),
        (CLICK, 'Click'),
        (ADD_TO_CART, 'Add to Cart'),
    ]

    user = models.ForeignKey('accounts.BuyerProfile', on_delete=models.CASCADE, related_name='interactions')
    product = models.ForeignKey(Product, on_delete=models.CASCADE)
    interaction_type = models.CharField(max_length=10, choices=INTERACTION_CHOICES)
    timestamp = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-timestamp']
