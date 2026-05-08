from payments.models import Transaction
print('Total Manual Withdrawals:')
for tx in Transaction.objects.filter(transaction_type='payout', trigger_event='manual').order_by('-created_at'):
    print(f'TX: {tx.transaction_id} | Amount: {tx.amount} | Status: {tx.status} | Stage: {tx.payout_stage}')
