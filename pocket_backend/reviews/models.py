from django.db import models

from accounts.models import User


class ProductReview(models.Model):
    product = models.ForeignKey(
        'products.Product',
        on_delete=models.CASCADE,
        related_name='reviews',
    )
    author = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='product_reviews',
    )
    rating = models.PositiveSmallIntegerField()
    comment = models.TextField(blank=True)
    is_verified_purchase = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        constraints = [
            models.UniqueConstraint(
                fields=['product', 'author'],
                name='uniq_product_review_author',
            ),
        ]
        indexes = [
            models.Index(fields=['product', '-created_at']),
            models.Index(fields=['author', '-created_at']),
            models.Index(fields=['is_verified_purchase']),
        ]

    def __str__(self):
        return f'{self.product_id} {self.author_id} {self.rating}/5'
