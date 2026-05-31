"""
Management command: seed_test_data
Creates realistic test data for end-to-end testing:
  - 1 product category + 3 products (seller id 2)
  - 5 orders in different statuses (buyer id 3)
  - Transactions (deposit) for payment-related orders
  - Notifications re-linked to real order numbers
  - Clears the fake ORD-DEMO-0001 notifications first
"""

from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db import transaction as db_transaction

from accounts.models import User
from notifications.models import Notification
from orders.models import Order, OrderItem
from payments.models import Transaction
from products.models import Category, Product


class Command(BaseCommand):
    help = "Seed test data for development/QA"

    def handle(self, *args, **options):
        with db_transaction.atomic():
            summary = self._run()
        for line in summary:
            self.stdout.write(line)

    def _run(self):
        seller = User.objects.get(id=2)
        buyer = User.objects.get(id=3)

        self.stdout.write("Clearing fake demo notifications...")
        Notification.objects.filter(data__order_number="ORD-DEMO-0001").delete()
        Notification.objects.filter(data__order_id=9999).delete()

        # ── Category ────────────────────────────────────────────────────────
        self.stdout.write("Creating category …")
        cat, _ = Category.objects.get_or_create(name="Electronics")

        # ── Products ────────────────────────────────────────────────────────
        self.stdout.write("Creating products …")
        products_data = [
            dict(
                name="Wireless Earbuds",
                description="True wireless stereo earbuds with 24-hour battery.",
                price=Decimal("149.00"),
                stock_quantity=20,
            ),
            dict(
                name="Phone Case (Universal)",
                description="Slim protective case, fits most Android phones.",
                price=Decimal("35.00"),
                stock_quantity=50,
            ),
            dict(
                name="USB-C Charging Cable",
                description="Braided 2-metre USB-C cable, fast-charge compatible.",
                price=Decimal("25.00"),
                stock_quantity=100,
            ),
        ]
        prods = []
        for pd in products_data:
            p, _ = Product.objects.get_or_create(
                name=pd["name"],
                seller=seller,
                defaults={**pd, "category": cat, "is_available": True},
            )
            prods.append(p)
        self.stdout.write(f"  {len(prods)} products ready")

        # ── Orders ──────────────────────────────────────────────────────────
        self.stdout.write("Creating orders …")

        scenarios = [
            dict(
                status="pending",
                delivery_fee=Decimal("15.00"),
                note="Awaiting payment",
                product=prods[2],
                qty=2,
                pay_status=None,
            ),
            dict(
                status="payment_pending",
                delivery_fee=Decimal("15.00"),
                note="Payment in progress",
                product=prods[1],
                qty=1,
                pay_status="pending",
            ),
            dict(
                status="accepted",
                delivery_fee=Decimal("15.00"),
                note="Payment succeeded, seller confirmed",
                product=prods[0],
                qty=1,
                pay_status="completed",
            ),
            dict(
                status="out_for_delivery",
                delivery_fee=Decimal("15.00"),
                note="Rider assigned",
                product=prods[0],
                qty=2,
                pay_status="completed",
            ),
            dict(
                status="delivered",
                delivery_fee=Decimal("15.00"),
                note="Completed order",
                product=prods[1],
                qty=3,
                pay_status="completed",
            ),
            dict(
                status="cancelled",
                delivery_fee=Decimal("0.00"),
                note="Cancelled after payment failure",
                product=prods[2],
                qty=1,
                pay_status="failed",
            ),
        ]

        created_orders = []
        for s in scenarios:
            prod: Product = s["product"]
            item_total = prod.price * s["qty"]
            grand = item_total + s["delivery_fee"]

            order = Order.objects.create(
                buyer=buyer,
                seller=seller,
                total_price=item_total,
                delivery_fee=s["delivery_fee"],
                fulfillment_type="delivery",
                status=s["status"],
                delivery_address="Plot 12, Cairo Road, Lusaka",
                delivery_lat=-15.4167,
                delivery_lng=28.2833,
                special_instructions=s["note"],
            )
            OrderItem.objects.create(
                order=order,
                product=prod,
                quantity=s["qty"],
                price=prod.price,
            )

            if s["pay_status"]:
                Transaction.objects.create(
                    order=order,
                    transaction_type="deposit",
                    amount=grand,
                    currency="ZMW",
                    provider="MTN_MOMO_ZMB",
                    payer_number=buyer.phone_number,
                    recipient=seller,
                    recipient_role="buyer",
                    status=s["pay_status"],
                )

            created_orders.append((order, s))
            self.stdout.write(
                f"  {order.order_number}  status={order.status}"
                f"  grand=ZMW {grand}"
            )

        # ── Notifications ────────────────────────────────────────────────────
        self.stdout.write("Creating notifications …")

        notif_map = [
            # (order_scenario_index, notification_type, title, message)
            (0, "order_placed",       "Order placed",              "Your order has been placed and is awaiting payment."),
            (1, "payment_pending",    "Payment in progress",       "We are waiting for your mobile-money approval."),
            (2, "payment_completed",  "Payment successful",        "Your payment was received. The seller is preparing your order."),
            (2, "order_accepted",     "Order confirmed",           "The seller has accepted your order and will start preparing it."),
            (3, "order_out_for_delivery", "On the way!",           "A rider has picked up your order and is heading to you."),
            (3, "delivery_assigned",  "Rider assigned",            "Your order has been assigned to a delivery rider."),
            (4, "order_delivered",    "Order delivered",           "Your order was delivered. Tap to rate your experience."),
            (5, "payment_failed",     "Payment failed",            "Your payment could not be completed. The order was cancelled."),
            (5, "order_cancelled",    "Order cancelled",           "Your order was cancelled due to a payment failure."),
        ]

        for idx, ntype, title, message in notif_map:
            order, _ = created_orders[idx]
            Notification.objects.create(
                recipient=buyer,
                notification_type=ntype,
                title=title,
                message=message,
                data={
                    "order_id": order.id,
                    "order_number": order.order_number,
                },
            )
        self.stdout.write(f"  {len(notif_map)} notifications created for buyer {buyer.phone_number}")

        # ── Summary ─────────────────────────────────────────────────────────
        return [
            self.style.SUCCESS("Seed complete."),
            "  Buyer  +260763887732 (lwando malekani) — 6 orders + 9 notifications",
            "  Seller +260974086484 (lwando ngosa)    — sees those orders",
            "  Rider  +260973714666 (katepwe mponda)  — test delivery flow",
        ]
