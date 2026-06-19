from decimal import Decimal
from django.db import models
from django.db.models import Count, Sum, Q


class PlatformSettings(models.Model):
    """
    Singleton model — only one row ever exists.
    All business-critical tunable values live here and are editable from Django admin.
    """

    # Charges
    buyer_service_fee_rate = models.DecimalField(
        max_digits=5, decimal_places=4, default=0.00,
        help_text='Service fee added to buyer order total. 0.02 = 2%, 0 = no fee.'
    )
    seller_commission_rate = models.DecimalField(
        max_digits=5, decimal_places=4, default=0.05,
        help_text='Commission deducted from seller earnings per order. 0.05 = 5%.'
    )
    rider_commission_rate = models.DecimalField(
        max_digits=5, decimal_places=4, default=0.00,
        help_text='Commission deducted from rider delivery earnings. 0.10 = 10%, 0 = no cut.'
    )
    payout_fee_rate = models.DecimalField(
        max_digits=5, decimal_places=4, default=0.00,
        help_text='Fee charged when paying out to sellers or riders. 0.01 = 1%, 0 = no fee.'
    )

    # Order management
    order_acceptance_timeout_minutes = models.PositiveIntegerField(
        default=30,
        help_text='Minutes a paid order can sit in accepted status before auto-cancel.'
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
        return f'Platform Settings (seller commission={self.seller_commission_rate*100:.1f}%)'

    def save(self, *args, **kwargs):
        self.pk = 1
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        pass  # prevent deletion

    @classmethod
    def get(cls):
        obj, _ = cls.objects.get_or_create(pk=1)
        return obj


class RevenueSnapshot(models.Model):
    year = models.PositiveIntegerField()
    month = models.PositiveIntegerField()  # 1–12

    order_count = models.PositiveIntegerField(default=0)
    gmv = models.DecimalField(max_digits=14, decimal_places=2, default=0, verbose_name='GMV (order totals)')
    delivery_collected = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    seller_commission = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    rider_commission = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    buyer_fees = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    total_revenue = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    total_payouts = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    total_refunds = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    net_revenue = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('year', 'month')
        ordering = ['-year', '-month']
        verbose_name = 'Revenue Snapshot'
        verbose_name_plural = 'Revenue Snapshots'

    def __str__(self):
        import calendar
        return f'{calendar.month_name[self.month]} {self.year}'

    @classmethod
    def refresh_all(cls):
        from payments.models import Transaction
        from orders.models import Order
        from django.utils import timezone
        import calendar

        now = timezone.now()

        # Find earliest transaction to know how far back to go
        first_tx = Transaction.objects.order_by('created_at').first()
        if not first_tx:
            return

        start = first_tx.created_at.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

        year, month = start.year, start.month
        while (year, month) <= (now.year, now.month):
            # Date range for this month
            last_day = calendar.monthrange(year, month)[1]
            from django.utils.timezone import make_aware
            import datetime
            month_start = make_aware(datetime.datetime(year, month, 1))
            month_end = make_aware(datetime.datetime(year, month, last_day, 23, 59, 59))

            # Completed orders this month
            orders = Order.objects.filter(
                status='delivered',
                updated_at__range=(month_start, month_end),
            )
            agg = orders.aggregate(
                count=Count('id'),
                gmv=Sum('total_price'),
                delivery=Sum('delivery_fee'),
            )
            order_count = agg['count'] or 0
            gmv = Decimal(str(agg['gmv'] or 0))
            delivery_collected = Decimal(str(agg['delivery'] or 0))

            # Deposits from buyers
            buyer_deposits = Transaction.objects.filter(
                transaction_type='deposit',
                status='completed',
                created_at__range=(month_start, month_end),
            ).aggregate(s=Sum('amount'))['s'] or Decimal('0')
            buyer_deposits = Decimal(str(buyer_deposits))

            # Seller payouts
            seller_payouts = Transaction.objects.filter(
                transaction_type='payout',
                recipient_role='seller',
                status='completed',
                created_at__range=(month_start, month_end),
            ).aggregate(s=Sum('amount'))['s'] or Decimal('0')
            seller_payouts = Decimal(str(seller_payouts))

            # Rider payouts
            rider_payouts = Transaction.objects.filter(
                transaction_type='payout',
                recipient_role='delivery',
                status='completed',
                created_at__range=(month_start, month_end),
            ).aggregate(s=Sum('amount'))['s'] or Decimal('0')
            rider_payouts = Decimal(str(rider_payouts))

            # Refunds
            refunds = Transaction.objects.filter(
                transaction_type='refund',
                status='completed',
                created_at__range=(month_start, month_end),
            ).aggregate(s=Sum('amount'))['s'] or Decimal('0')
            refunds = Decimal(str(refunds))

            # Platform kept = what came in minus what went out
            seller_commission = buyer_deposits - seller_payouts
            rider_commission = delivery_collected - rider_payouts
            buyer_fees = Decimal('0')  # placeholder until buyer_service_fee_rate > 0

            total_revenue = seller_commission + rider_commission + buyer_fees
            total_payouts = seller_payouts + rider_payouts
            net_revenue = total_revenue - refunds

            cls.objects.update_or_create(
                year=year,
                month=month,
                defaults=dict(
                    order_count=order_count,
                    gmv=gmv,
                    delivery_collected=delivery_collected,
                    seller_commission=max(seller_commission, Decimal('0')),
                    rider_commission=max(rider_commission, Decimal('0')),
                    buyer_fees=buyer_fees,
                    total_revenue=max(total_revenue, Decimal('0')),
                    total_payouts=total_payouts,
                    total_refunds=refunds,
                    net_revenue=net_revenue,
                ),
            )

            # Advance to next month
            if month == 12:
                year += 1
                month = 1
            else:
                month += 1
