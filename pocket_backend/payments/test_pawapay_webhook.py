from django.test import override_settings
from rest_framework.test import APITestCase

from accounts.models import User

from .models import Transaction
from .test_card import _make_order


@override_settings(PAWAPAY_WEBHOOK_SECRET='')
class PawaPayDepositWebhookTests(APITestCase):
    """Guards the deposit outcomes that PawaPay and Lenco now share."""

    def setUp(self):
        buyer = User.objects.create_user(
            phone_number='+260911111111', password='x', full_name='Ann', role='buyer')
        seller = User.objects.create_user(
            phone_number='+260922222222', password='x', full_name='Sam', role='seller')
        self.order = _make_order(buyer, seller)
        self.tx = Transaction.objects.create(
            order=self.order, transaction_type='deposit', amount=self.order.grand_total,
            provider='MTN_MOMO_ZMB', payer_number='260961111111', status='accepted')

    def _hook(self, status, **extra):
        return self.client.post(
            '/api/payments/webhook/', {'depositId': str(self.tx.transaction_id), 'status': status, **extra},
            format='json')

    def test_completed_deposit_releases_the_order_and_creates_payouts(self):
        self.assertEqual(self._hook('COMPLETED').status_code, 200)
        self.tx.refresh_from_db()
        self.order.refresh_from_db()
        self.assertEqual((self.tx.status, self.order.status), ('completed', 'pending'))
        self.assertTrue(Transaction.objects.filter(transaction_type='payout', recipient_role='seller').exists())

    def test_failed_deposit_cancels_the_order(self):
        self._hook('FAILED', failureReason={'failureMessage': 'Insufficient funds'})
        self.tx.refresh_from_db()
        self.order.refresh_from_db()
        self.assertEqual((self.tx.status, self.tx.failure_message), ('failed', 'Insufficient funds'))
        self.assertEqual(self.order.status, 'cancelled')

    def test_terminated_deposit_cancels_the_order_with_the_user_message(self):
        self._hook('TERMINATED')
        self.tx.refresh_from_db()
        self.order.refresh_from_db()
        self.assertEqual(self.tx.failure_message, 'Payment was terminated by user')
        self.assertEqual(self.order.status, 'cancelled')

    def test_replayed_completed_webhook_is_a_no_op(self):
        self._hook('COMPLETED')
        payouts = Transaction.objects.filter(transaction_type='payout').count()
        self.assertEqual(self._hook('COMPLETED').json()['message'], 'Already processed')
        self.assertEqual(Transaction.objects.filter(transaction_type='payout').count(), payouts)
