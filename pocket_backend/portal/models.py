from django.db import models


class PlatformSettings(models.Model):
    """
    Singleton model — only one row ever exists.
    All business-critical tunable values live here and are editable from Django admin.
    """

    # Commission
    commission_rate = models.DecimalField(
        max_digits=5, decimal_places=4, default=0.05,
        help_text='Platform commission taken from each order. 0.05 = 5%, 0.10 = 10%.'
    )

    # Order management
    order_acceptance_timeout_minutes = models.PositiveIntegerField(
        default=30,
        help_text='Minutes a paid order can sit in accepted status before auto-cancel.'
    )

    # Delivery pricing
    delivery_per_km_rate = models.DecimalField(
        max_digits=8, decimal_places=2, default=8.00,
        help_text='ZMW charged per km for long-distance deliveries.'
    )
    delivery_short_distance_threshold_km = models.DecimalField(
        max_digits=5, decimal_places=2, default=2.00,
        help_text='Distances at or below this get the flat rate instead.'
    )
    delivery_short_distance_flat_rate = models.DecimalField(
        max_digits=8, decimal_places=2, default=12.00,
        help_text='ZMW flat rate charged for short deliveries.'
    )

    # Payout
    payout_method = models.CharField(
        max_length=10,
        choices=[('manual', 'Manual (admin sends from phone)'), ('gateway', 'Gateway (PawaPay automated)')],
        default='manual',
        help_text='How seller and rider payouts are processed after delivery.'
    )

    # Maintenance
    maintenance_mode = models.BooleanField(
        default=False,
        help_text='When True, API returns 503 for all non-admin requests.'
    )
    maintenance_message = models.TextField(
        blank=True,
        default='We are performing maintenance. Please try again shortly.',
    )

    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Platform Settings'
        verbose_name_plural = 'Platform Settings'

    def __str__(self):
        return f'Platform Settings (commission={self.commission_rate*100:.1f}%)'

    def save(self, *args, **kwargs):
        self.pk = 1
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        pass  # prevent deletion

    @classmethod
    def get(cls):
        obj, _ = cls.objects.get_or_create(pk=1)
        return obj
