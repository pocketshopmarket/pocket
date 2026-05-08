from decimal import Decimal
from django.conf import settings
from payments.models import Transaction
from orders.models import Order

# 1. Fix the completed deposit (ZMW 14.00 — PawaPay says COMPLETED)
tx = Transaction.objects.get(transaction_id='722cbe30-13da-4906-9f05-99ce83bbc10c')
tx.status = 'completed'
tx.save()
print(f'Fixed TX {tx.transaction_id}: status -> completed')

# 2. Mark the order as accepted (it's already delivered, so skip this)
order = tx.order
print(f'Order {order.order_number} status: {order.status} (keeping as-is)')

# 3. Create payout rows for seller
commission_rate = Decimal(str(getattr(settings, 'PLATFORM_COMMISSION_RATE', 0.05)))
item_total = Decimal(str(order.total_price))
delivery_fee = Decimal(str(order.delivery_fee or 0))
platform_cut = (item_total * commission_rate).quantize(Decimal('0.01'))
seller_share = item_total - platform_cut

print(f'Item total: {item_total}, Platform cut: {platform_cut}, Seller share: {seller_share}, Delivery fee: {delivery_fee}')

# Check if payout rows already exist
existing_seller = Transaction.objects.filter(order=order, transaction_type='payout', recipient_role='seller').exists()
if not existing_seller and seller_share > 0:
    seller_tx = Transaction.objects.create(
        order=order,
        transaction_type='payout',
        amount=seller_share,
        currency=tx.currency,
        provider=tx.provider,
        payer_number=tx.payer_number,
        recipient=order.seller,
        recipient_role='seller',
        trigger_event='pickup_qr',
        payout_stage='pickup_pending_scan',
        status='pending',
    )
    print(f'Created seller payout: {seller_tx.transaction_id} for ZMW {seller_share}')
else:
    print('Seller payout already exists or zero share')

# 4. Fix the 2 failed deposits — mark their orders as cancelled
for failed_tx in Transaction.objects.filter(transaction_type='deposit', status='failed'):
    o = failed_tx.order
    if o.status == 'pending':
        o.status = 'cancelled'
        o.save()
        print(f'Cancelled order {o.order_number} (payment failed)')

# Also cancel the 2 "accepted" deposits that PawaPay shows as failed (42.00 ZMW ones)
for stuck_id in ['f1da6400-a667-42f4-a73d-e3251b128f5e', '672454ea-419f-41e7-89b2-9d04b4e0b95f']:
    try:
        stx = Transaction.objects.get(transaction_id=stuck_id)
        stx.status = 'failed'
        stx.failure_message = 'PawaPay reported FAILED — reconciled manually'
        stx.save()
        o = stx.order
        if o.status == 'pending':
            o.status = 'cancelled'
            o.save()
        print(f'Fixed stuck TX {stuck_id}: marked failed, order {o.order_number} cancelled')
    except Transaction.DoesNotExist:
        print(f'TX {stuck_id} not found')

print('\nDone! All transactions reconciled.')
