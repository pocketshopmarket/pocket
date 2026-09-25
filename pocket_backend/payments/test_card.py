import hashlib
import hmac
import json
from decimal import Decimal
from unittest import mock

from django.core import signing
from django.test import override_settings
from rest_framework.test import APITestCase

from accounts.models import User
from orders.models import Order
from portal.models import PlatformSettings

from .card_views import CHECKOUT_TOKEN_SALT, apply_lenco_collection
from .models import Transaction
from .services.lenco import LencoError, LencoService

CARD_SETTINGS = dict(
    LENCO_API_TOKEN='tok',
    LENCO_PUBLIC_KEY='pub-x',
    PUBLIC_BACKEND_URL='https://api.example.test',
)


def _make_order(buyer, seller, total='100.00', status='payment_pending'):
    return Order.objects.create(
        buyer=buyer, seller=seller, total_price=Decimal(total), status=status,
        delivery_address='Test', payment_provider_snapshot='x', payment_account_snapshot='x',
    )


class CardTestBase(APITestCase):
    def setUp(self):
        self.buyer = User.objects.create_user(
            phone_number='+260911111111', password='x', full_name='Ann Buyer', role='buyer')
        self.seller = User.objects.create_user(
            phone_number='+260922222222', password='x', full_name='Sam Seller', role='seller')
        self.order = _make_order(self.buyer, self.seller)

    def _card_tx(self, status='pending', **kw):
        return Transaction.objects.create(
            order=self.order, transaction_type='deposit', amount=self.order.grand_total,
            provider='LENCO_CARD', payer_number='', gateway='lenco', payment_method='card',
            status=status, **kw)

    def _data(self, tx, status='successful', amount=None, **extra):
        return {
            'reference': str(tx.transaction_id), 'status': status,
            'amount': str(amount if amount is not None else tx.amount),
            'fee': '3.50', 'lencoReference': '240001', **extra,
        }


@override_settings(**CARD_SETTINGS)
class CardInitiateTests(CardTestBase):
    def setUp(self):
        super().setUp()
        ps = PlatformSettings.get()
        ps.card_payments_enabled = True
        ps.save()

    def _post(self, order_number=None):
        return self.client.post('/api/payments/card/initiate/', {
            'order_number': order_number or self.order.order_number,
            'refund_phone': '0961111111',
            'refund_policy_accepted': True,
        }, format='json')

    def test_off_when_not_configured(self):
        self.client.force_authenticate(self.buyer)
        with override_settings(LENCO_API_TOKEN=''):
            r = self._post()
        self.assertEqual(r.status_code, 503)
        self.assertEqual(Transaction.objects.count(), 0)

    def test_creates_pending_card_deposit_and_reuses_it(self):
        self.client.force_authenticate(self.buyer)
        first = self._post().json()
        second = self._post().json()
        self.assertEqual(first['transaction_id'], second['transaction_id'])
        self.assertTrue(first['checkout_url'].startswith('https://api.example.test/api/payments/card/checkout/'))
        tx = Transaction.objects.get()
        self.assertEqual((tx.gateway, tx.payment_method, tx.status), ('lenco', 'card', 'pending'))
        self.assertEqual(tx.amount, self.order.grand_total)

    def test_only_the_buyer_can_pay_and_paid_orders_are_blocked(self):
        self.client.force_authenticate(self.seller)
        self.assertEqual(self._post().status_code, 404)
        self.client.force_authenticate(self.buyer)
        self._card_tx(status='completed')
        self.assertEqual(self._post().status_code, 400)


@override_settings(**CARD_SETTINGS)
class CardCheckoutPageTests(CardTestBase):
    def _url(self, tx, token=None):
        token = token or signing.dumps({'tx': str(tx.transaction_id)}, salt=CHECKOUT_TOKEN_SALT)
        return f'/api/payments/card/checkout/{tx.transaction_id}/?t={token}'

    def test_valid_link_renders_widget_with_customer_bearing_the_fee(self):
        tx = self._card_tx()
        r = self.client.get(self._url(tx))
        self.assertEqual(r.status_code, 200)
        body = r.content.decode()
        self.assertIn(str(tx.transaction_id), body)
        self.assertIn('"bearer": "customer"', body)
        self.assertIn('pub-x', body)
        self.assertNotIn('"tok"', body)  # never the secret key
        self.assertEqual(r['Cache-Control'], 'no-store')

    def test_bad_missing_or_swapped_tokens_are_refused(self):
        tx = self._card_tx()
        other = self._card_tx()
        self.assertEqual(self.client.get(f'/api/payments/card/checkout/{tx.transaction_id}/').status_code, 403)
        self.assertEqual(self.client.get(self._url(tx, token='garbage')).status_code, 403)
        swapped = signing.dumps({'tx': str(other.transaction_id)}, salt=CHECKOUT_TOKEN_SALT)
        self.assertEqual(self.client.get(self._url(tx, token=swapped)).status_code, 403)

    def test_finished_payment_page_is_closed(self):
        tx = self._card_tx(status='completed')
        self.assertEqual(self.client.get(self._url(tx)).status_code, 410)


@override_settings(**CARD_SETTINGS)
class CardSettlementTests(CardTestBase):
    def test_successful_payment_completes_once(self):
        tx = self._card_tx()
        apply_lenco_collection(tx.pk, self._data(tx))
        tx.refresh_from_db()
        self.order.refresh_from_db()
        self.assertEqual(tx.status, 'completed')
        self.assertEqual(tx.gateway_fee, Decimal('3.50'))
        self.assertEqual(tx.gateway_reference, '240001')
        self.assertEqual(self.order.status, 'pending')
        payouts = Transaction.objects.filter(transaction_type='payout').count()
        apply_lenco_collection(tx.pk, self._data(tx))  # replay
        self.assertEqual(Transaction.objects.filter(transaction_type='payout').count(), payouts)

    def test_fee_on_top_is_accepted_but_a_short_payment_is_not(self):
        tx = self._card_tx()
        apply_lenco_collection(tx.pk, self._data(tx, amount=Decimal(tx.amount) - 1))
        tx.refresh_from_db()
        self.order.refresh_from_db()
        self.assertEqual(tx.status, 'pending')
        self.assertEqual(self.order.status, 'payment_pending')
        apply_lenco_collection(tx.pk, self._data(tx, amount=Decimal(tx.amount) + Decimal('3.50')))
        tx.refresh_from_db()
        self.assertEqual(tx.status, 'completed')

    def test_wrong_reference_is_ignored(self):
        tx = self._card_tx()
        data = self._data(tx)
        data['reference'] = 'someone-elses'
        apply_lenco_collection(tx.pk, data)
        tx.refresh_from_db()
        self.assertEqual(tx.status, 'pending')

    def test_failed_payment_cancels_the_order(self):
        tx = self._card_tx()
        apply_lenco_collection(tx.pk, self._data(tx, status='failed', reasonForFailure='Card declined'))
        tx.refresh_from_db()
        self.order.refresh_from_db()
        self.assertEqual((tx.status, tx.failure_message), ('failed', 'Card declined'))
        self.assertEqual(self.order.status, 'cancelled')

    def test_in_flight_statuses_change_nothing(self):
        tx = self._card_tx()
        for s in ('pending', '3ds-auth-required', 'pay-offline'):
            apply_lenco_collection(tx.pk, self._data(tx, status=s))
        tx.refresh_from_db()
        self.assertEqual(tx.status, 'pending')


@override_settings(**CARD_SETTINGS)
class LencoWebhookAndStatusTests(CardTestBase):
    def _post(self, payload, sign=True):
        raw = json.dumps(payload).encode()
        key = hashlib.sha256(b'tok').hexdigest()
        sig = hmac.new(key.encode(), raw, hashlib.sha512).hexdigest() if sign else 'bad'
        return self.client.generic(
            'POST', '/api/payments/lenco/webhook/', raw,
            content_type='application/json', HTTP_X_LENCO_SIGNATURE=sig)

    def test_unsigned_webhook_is_rejected_and_changes_nothing(self):
        tx = self._card_tx()
        with mock.patch.object(LencoService, 'get_collection_status') as status_call:
            r = self._post({'event': 'collection.successful', 'data': {'reference': str(tx.transaction_id)}}, sign=False)
        self.assertEqual(r.status_code, 401)
        status_call.assert_not_called()

    def test_signed_webhook_re_reads_status_from_lenco(self):
        tx = self._card_tx()
        # The payload LIES (says failed); Lenco's API says successful. The API wins.
        with mock.patch.object(LencoService, 'get_collection_status', return_value=self._data(tx)):
            r = self._post({'event': 'collection.successful',
                            'data': {'reference': str(tx.transaction_id), 'status': 'failed'}})
        self.assertEqual(r.status_code, 200)
        tx.refresh_from_db()
        self.assertEqual(tx.status, 'completed')

    def test_unknown_reference_and_other_events_are_acknowledged(self):
        r = self._post({'event': 'collection.successful', 'data': {'reference': 'nope'}})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(self._post({'event': 'transfer.successful', 'data': {}}).status_code, 200)

    def test_status_endpoint_settles_a_card_payment_without_the_webhook(self):
        tx = self._card_tx()
        self.client.force_authenticate(self.buyer)
        with mock.patch.object(LencoService, 'get_collection_status', return_value=self._data(tx)):
            r = self.client.get('/api/payments/status/', {'order_number': self.order.order_number})
        self.assertEqual(r.json()['payment_status'], 'completed')
        self.assertEqual(r.json()['order_status'], 'pending')
        self.assertEqual(r.json()['payment_method'], 'card')

    def test_status_endpoint_survives_lenco_being_down(self):
        self._card_tx()
        self.client.force_authenticate(self.buyer)
        with mock.patch.object(LencoService, 'get_collection_status', side_effect=LencoError('down')):
            r = self.client.get('/api/payments/status/', {'order_number': self.order.order_number})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()['payment_status'], 'pending')


class CardRefundRoutingTests(CardTestBase):
    def test_card_refund_goes_to_staff_queue_and_never_calls_pawapay(self):
        from orders.services import cancel_order_with_refund
        self._card_tx(status='completed')
        self.order.status = 'pending'
        self.order.save()
        with mock.patch('orders.services.PawaPayService.initiate_refund') as pawapay, \
                mock.patch('orders.services._notify_staff_refund') as notify:
            cancel_order_with_refund(self.order, reason='test')
        pawapay.assert_not_called()
        notify.assert_called_once()
        refund = Transaction.objects.get(transaction_type='refund')
        self.assertEqual(
            (refund.gateway, refund.payment_method, refund.payout_method, refund.status),
            ('lenco', 'card', 'manual', 'pending'),
        )
        self.assertIn('NO valid mobile money number', refund.payout_notes)  # this deposit has no refund number
