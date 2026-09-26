import json
from decimal import Decimal
from unittest import mock

from django.test import override_settings

from portal.models import PlatformSettings

from .models import Transaction
from .test_card import CARD_SETTINGS, CardTestBase


@override_settings(**CARD_SETTINGS)
class PaymentOptionsTests(CardTestBase):
    def test_requires_login(self):
        self.assertEqual(self.client.get('/api/payments/options/').status_code, 401)

    def test_cards_are_offered_only_when_switched_on_and_configured(self):
        self.client.force_authenticate(self.buyer)
        self.assertFalse(self.client.get('/api/payments/options/').json()['card_enabled'])
        ps = PlatformSettings.get()
        ps.card_payments_enabled = True
        ps.card_fee_percent = Decimal('3.80')
        ps.card_fee_fixed = Decimal('1.00')
        ps.save()
        r = self.client.get('/api/payments/options/').json()
        self.assertEqual((r['card_enabled'], r['card_refund_business_days'], r['card_fee_percent'], r['card_fee_fixed']),
                         (True, 5, '3.80', '1.00'))
        with override_settings(LENCO_API_TOKEN=''):
            self.assertFalse(self.client.get('/api/payments/options/').json()['card_enabled'])


@override_settings(**CARD_SETTINGS)
class BuyerRefundVisibilityTests(CardTestBase):
    def test_order_shows_the_card_refund_due_date_and_a_masked_number_only(self):
        from orders.services import cancel_order_with_refund
        deposit = self._card_tx(status='completed')
        deposit.payer_number = '+260961111111'
        deposit.save()
        self.order.status = 'pending'
        self.order.save()
        with mock.patch('orders.services._notify_staff_refund'):
            cancel_order_with_refund(self.order, reason='changed my mind')

        self.client.force_authenticate(self.buyer)
        body = self.client.get(f'/api/orders/orders/{self.order.pk}/')
        self.assertEqual(body.status_code, 200)
        refund = body.json()['cancellation_refund']
        self.assertTrue(refund['is_card_refund'])
        self.assertIsNotNone(refund['due_at'])
        self.assertEqual(refund['status'], 'pending')
        self.assertTrue(refund['sent_to'].startswith('+26096'))
        self.assertNotIn('961111111', json.dumps(body.json()))  # the full number never leaves the server

    def test_mobile_money_refunds_carry_no_card_fields(self):
        from orders.serializers import refund_summary
        tx = Transaction.objects.create(
            order=self.order, transaction_type='refund', amount=Decimal('10.00'), provider='MTN_MOMO_ZMB',
            payer_number='+260961111111', status='pending')
        self.assertEqual(refund_summary(tx), {'status': 'pending', 'amount': '10.00'})
