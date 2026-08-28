from rest_framework import serializers

from products.models import Category, Product
from products.serializers import CategorySerializer, replace_variants


class PartnerProductSerializer(serializers.ModelSerializer):
    """
    JSON contract for external inventory sync — deliberately separate from
    ProductSerializer (the mobile app's multipart, IsAuthenticated-only
    contract) so the two can evolve independently. category_slug is used
    instead of the raw category id: partners shouldn't need to know Pocket
    Shop's internal category ids, and categories stay curated by Pocket
    Shop rather than partner-defined.
    """
    external_id = serializers.CharField(max_length=100)
    category = CategorySerializer(read_only=True)
    category_slug = serializers.SlugField(required=False, allow_null=True, write_only=True)
    variants = serializers.ListField(
        child=serializers.DictField(), write_only=True, required=False,
    )

    class Meta:
        model = Product
        fields = [
            'id', 'external_id', 'name', 'description', 'price',
            'category', 'category_slug', 'quality', 'stock_quantity',
            'is_available', 'image_url', 'variants',
            'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'category', 'created_at', 'updated_at']

    def validate_category_slug(self, value):
        if not value:
            return None
        if not Category.objects.filter(slug=value).exists():
            valid = list(Category.objects.order_by('name').values_list('slug', flat=True))
            preview = ', '.join(valid[:20])
            more = f' (+{len(valid) - 20} more)' if len(valid) > 20 else ''
            raise serializers.ValidationError(
                f"Unknown category_slug '{value}'. Valid slugs: {preview}{more}. "
                f"See GET /api/products/categories/ for the full list."
            )
        return value

    def create(self, validated_data):
        variants = validated_data.pop('variants', None)
        slug = validated_data.pop('category_slug', None)
        category = Category.objects.get(slug=slug) if slug else None
        product = Product.objects.create(category=category, **validated_data)
        if variants:
            replace_variants(product, variants)
        return product

    def update(self, instance, validated_data):
        variants = validated_data.pop('variants', None)
        if 'category_slug' in validated_data:
            slug = validated_data.pop('category_slug')
            instance.category = Category.objects.get(slug=slug) if slug else None
        for attr, val in validated_data.items():
            setattr(instance, attr, val)
        instance.save()
        if variants is not None:
            replace_variants(instance, variants)
        return instance
