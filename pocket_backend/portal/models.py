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
                service=Sum('service_fee'),
            )
            order_count = agg['count'] or 0
            gmv = Decimal(str(agg['gmv'] or 0))
            delivery_collected = Decimal(str(agg['delivery'] or 0))
            service_fee_collected = Decimal(str(agg['service'] or 0))

            # Seller payouts — scoped to *this month's delivered orders*
            # (order__in=orders), not the payout transaction's own created_at.
            # A payout can be created in a different month than the order was
            # delivered in, so filtering independently by date mixed unrelated
            # orders into the subtraction. Only orders whose payout has
            # actually completed count toward commission — one still sitting
            # pending hasn't generated commission yet, it's just unpaid.
            completed_seller_payouts = Transaction.objects.filter(
                transaction_type='payout',
                recipient_role='seller',
                status='completed',
                order__in=orders,
            )
            seller_payouts = completed_seller_payouts.aggregate(s=Sum('amount'))['s'] or Decimal('0')
            seller_payouts = Decimal(str(seller_payouts))
            seller_gmv_paid = orders.filter(
                id__in=completed_seller_payouts.values_list('order_id', flat=True)
            ).aggregate(s=Sum('total_price'))['s'] or Decimal('0')
            seller_gmv_paid = Decimal(str(seller_gmv_paid))

            # Rider payouts — same scoping and same-order logic, against
            # delivery_fee instead of total_price.
            completed_rider_payouts = Transaction.objects.filter(
                transaction_type='payout',
                recipient_role='delivery',
                status='completed',
                order__in=orders,
            )
            rider_payouts = completed_rider_payouts.aggregate(s=Sum('amount'))['s'] or Decimal('0')
            rider_payouts = Decimal(str(rider_payouts))
            rider_delivery_paid = orders.filter(
                id__in=completed_rider_payouts.values_list('order_id', flat=True)
            ).aggregate(s=Sum('delivery_fee'))['s'] or Decimal('0')
            rider_delivery_paid = Decimal(str(rider_delivery_paid))

            # Refunds — deliberately NOT scoped to this month's delivered
            # orders. A refund can belong to an order that was never
            # delivered at all (e.g. a failed-payment auto-cancel), so it's
            # counted by when the refund itself happened instead.
            refunds = Transaction.objects.filter(
                transaction_type='refund',
                status='completed',
                created_at__range=(month_start, month_end),
            ).aggregate(s=Sum('amount'))['s'] or Decimal('0')
            refunds = Decimal(str(refunds))

            # Platform kept = what came in minus what went out, computed only
            # against orders whose payout has actually completed. buyer_fees
            # is realized immediately at deposit time (nothing further has to
            # happen), so unlike commission it isn't gated on payout status.
            seller_commission = seller_gmv_paid - seller_payouts
            rider_commission = rider_delivery_paid - rider_payouts
            buyer_fees = service_fee_collected

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
