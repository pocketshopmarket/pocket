from rest_framework import serializers

from orders.models import OrderItem

from .models import ProductReview


class ProductReviewSerializer(serializers.ModelSerializer):
    author_name = serializers.CharField(source='author.full_name', read_only=True)

    class Meta:
        model = ProductReview
        fields = [
            'id',
            'product',
            'author',
            'author_name',
            'rating',
            'comment',
            'is_verified_purchase',
            'created_at',
            'updated_at',
        ]
        read_only_fields = [
            'id',
            'product',
            'author',
            'author_name',
            'is_verified_purchase',
            'created_at',
            'updated_at',
        ]

    def validate_rating(self, value):
        if value < 1 or value > 5:
            raise serializers.ValidationError('Rating must be between 1 and 5.')
        return value

    def _has_delivered_purchase(self, user, product):
        return OrderItem.objects.filter(
            order__buyer=user,
            order__status='delivered',
            product=product,
        ).exists()

    def create(self, validated_data):
        request = self.context['request']
        product = self.context['product']
        user = request.user
        verified = self._has_delivered_purchase(user, product)
        review, _ = ProductReview.objects.update_or_create(
            product=product,
            author=user,
            defaults={
                'rating': validated_data['rating'],
                'comment': validated_data.get('comment', ''),
                'is_verified_purchase': verified,
            },
        )
        return review
