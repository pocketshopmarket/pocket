from rest_framework import serializers

from .models import MAX_PRODUCT_IMAGES, Product, ProductVariant


def _absolute_media_url(request, relative_url):
    if request is not None:
        return request.build_absolute_uri(relative_url)
    return relative_url


def gallery_payload_for_product(product, request):
    """Ordered list of {url, sort_order} for API responses."""
    rows = list(product.gallery_images.all())
    if not rows:
        if product.image:
            url = product.image.url
            return [
                {
                    'url': _absolute_media_url(request, url),
                    'sort_order': 0,
                }
            ]
        if product.image_url:
            return [{'url': product.image_url, 'sort_order': 0}]
        return []

    out = []
    for pi in rows:
        if pi.image:
            url = pi.image.url
            out.append(
                {
                    'url': _absolute_media_url(request, url),
                    'sort_order': pi.sort_order,
                }
            )
        elif pi.image_url:
            out.append({'url': pi.image_url, 'sort_order': pi.sort_order})
    return out


def first_image_url_for_product(product, request):
    payload = gallery_payload_for_product(product, request)
    if not payload:
        return None
    return payload[0]['url']


class ProductSerializer(serializers.ModelSerializer):
    seller_name = serializers.CharField(source='seller.full_name', read_only=True)
    seller_phone = serializers.CharField(source='seller.phone_number', read_only=True)
    images = serializers.SerializerMethodField()
    image_url = serializers.SerializerMethodField()
    variants = serializers.SerializerMethodField()
    variant_payload = serializers.ListField(
        child=serializers.DictField(),
        write_only=True,
        required=False,
    )
    review_avg = serializers.FloatField(read_only=True)
    review_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = Product
        fields = [
            'id',
            'name',
            'description',
            'price',
            'category',
            'quality',
            'seller',
            'seller_name',
            'seller_phone',
            'stock_quantity',
            'images',
            'image_url',
            'is_available',
            'views_count',
            'purchases_count',
            'review_avg',
            'review_count',
            'variants',
            'variant_payload',
            'created_at',
            'updated_at',
            'is_in_stock',
        ]
        read_only_fields = [
            'id',
            'seller',
            'created_at',
            'updated_at',
            'is_in_stock',
            'images',
            'image_url',
            'views_count',
            'purchases_count',
            'review_avg',
            'review_count',
            'variants',
        ]

    def get_images(self, obj):
        return gallery_payload_for_product(obj, self.context.get('request'))

    def get_image_url(self, obj):
        return first_image_url_for_product(obj, self.context.get('request'))

    def get_variants(self, obj):
        rows = obj.variants.filter(is_active=True).order_by('name', 'value', 'id')
        return [
            {
                'id': variant.id,
                'name': variant.name,
                'value': variant.value,
                'sku': variant.sku,
                'stock_quantity': variant.stock_quantity,
                'is_active': variant.is_active,
            }
            for variant in rows
        ]

    def _replace_variants(self, product, payload):
        product.variants.all().delete()
        for index, row in enumerate(payload):
            name = str(row.get('name', '')).strip()
            value = str(row.get('value', '')).strip()
            sku = str(row.get('sku', '')).strip()
            stock = row.get('stock_quantity', 0)
            if not name or not value or not sku:
                raise serializers.ValidationError(
                    {
                        'variant_payload': [
                            f'Variant #{index + 1} requires name, value, and sku.'
                        ]
                    }
                )
            ProductVariant.objects.create(
                product=product,
                name=name,
                value=value,
                sku=sku,
                stock_quantity=max(int(stock), 0),
                is_active=bool(row.get('is_active', True)),
            )

    def create(self, validated_data):
        variant_payload = validated_data.pop('variant_payload', None)
        product = super().create(validated_data)
        if variant_payload:
            self._replace_variants(product, variant_payload)
        return product

    def update(self, instance, validated_data):
        variant_payload = validated_data.pop('variant_payload', None)
        product = super().update(instance, validated_data)
        if variant_payload is not None:
            self._replace_variants(product, variant_payload)
        return product
