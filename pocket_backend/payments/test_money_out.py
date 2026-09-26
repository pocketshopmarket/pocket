import hashlib
import hmac
import json
from datetime import datetime, timezone as dt_timezone
from decimal import Decimal
from unittest import mock

from django.test import SimpleTestCase, override_settings
from rest_framework.test import APITestCase

from accounts.models import User
from portal.models import PlatformSettings

from .earnings import earnings_breakdown
from .lenco_transfers import CannotSend, apply_lenco_transfer, send_via_lenco
from .mobile_money import (
    InvalidMobileNumber,
    add_business_days,
    names_match,
    parse_mobile_money_number,
)
from .models import PayoutBankAccount, Transaction
from .services.lenco import LencoError, LencoService, LencoUnreachable
from .test_card import CARD_SETTINGS, CardTestBase, _make_order

LENCO_ON = dict(CARD_SETTINGS, LENCO_ACCOUNT_ID='acct-1')


class MobileMoneyHelperTests(SimpleTestCase):
    def test_numbers_are_placed_on_the_right_network_or_refused(self):
        self.assertEqual(parse_mobile_money_number('0961111111'), ('+260961111111', 'mtn'))
        self.assertEqual(parse_mobile_money_number('+260 97 111 1111'), ('+260971111111', 'airtel'))
        self.assertEqual(parse_mobile_money_number('095-1111111'), ('+260951111111', 'zamtel'))
        for bad in ('0981111111', 'abc', '', None, '12345'):
            with self.assertRaises(InvalidMobileNumber):
                parse_mobile_money_number(bad)

    def test_business_days_skip_weekends(self):
        friday = datetime(2026, 9, 25, tzinfo=dt_timezone.utc)
        self.assertEqual(add_business_days(friday, 5).strftime('%a %d %b'), 'Fri 02 Oct')
        self.assertEqual(add_business_days(friday, 1).strftime('%a'), 'Mon')

    def test_name_matching_ignores_order_and_case_but_not_strangers(self):
        self.assertTrue(names_match('KAUNDA BENSON', 'Benson Kaunda'))
        self.assertTrue(names_match('Benson M Kaunda', 'Benson Kaunda'))
        self.assertTrue(names_match('Pocketshop Market Limited', 'Benson Kaunda', 'Pocketshop Market Limited'))
        self.assertFalse(names_match('Jason Juma', 'Benson Kaunda'))
        self.assertFalse(names_match('', 'Benson Kaunda'))
        self.assertFalse(names_match('Benson Juma', 'Benson Kaunda'))  # only one name part shared


@override_settings(**LENCO_ON)
class CardRefundNumberTests(CardTestBase):
    def setUp(self):
        super().setUp()
        ps = PlatformSettings.get()
        ps.card_payments_enabled = True
        ps.save()
        self.client.force_authenticate(self.buyer)

    def _initiate(self, **extra):
        body = {'order_number': self.order.order_number, 'refund_phone': '0961111111',
                'refund_policy_accepted': True, **extra}
        return self.client.post('/api/payments/card/initiate/', body, format='json')

    def test_cards_are_off_until_the_admin_switch_is_on(self):
        ps = PlatformSettings.get()
        ps.card_payments_enabled = False
        ps.save()
        self.assertEqual(self._initiate().status_code, 503)

    def test_refund_number_and_policy_acceptance_are_mandatory(self):
        self.assertEqual(self._initiate(refund_policy_accepted=False).status_code, 400)
        self.assertEqual(self._initiate(refund_policy_accepted='yes').status_code, 400)
        self.assertEqual(self._initiate(refund_phone='').status_code, 400)
        self.assertEqual(self._initiate(refund_phone='0981111111').status_code, 400)
        self.assertEqual(Transaction.objects.count(), 0)

    def test_number_is_stored_on_the_payment_with_proof_of_acceptance(self):
        r = self._initiate()
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()['refund_business_days'], 5)
        tx = Transaction.objects.get()
        self.assertEqual(tx.payer_number, '+260961111111')
        self.assertIn('accepted the card refund terms', tx.payout_notes)
        # Changing the number on a retry updates the same pending attempt.
        self._initiate(refund_phone='0971111111')
        tx.refresh_from_db()
        self.assertEqual((Transaction.objects.count(), tx.payer_number), (1, '+260971111111'))

    def test_check_shows_the_registered_name(self):
        with mock.patch.object(LencoService, 'resolve_mobile_money',
                               return_value={'account_name': 'Ann Buyer', 'phone': '0961111111', 'operator': 'mtn'}) as call:
            r = self.client.post('/api/payments/card/refund-number/check/', {'phone': '0961111111'}, format='json')
        self.assertEqual(r.json(), {'phone': '+260961111111', 'operator': 'mtn',
                                    'network': 'MTN MoMo', 'account_name': 'Ann Buyer'})
        call.assert_called_once_with('+260961111111', 'mtn')

    def test_a_connection_failure_is_not_reported_as_a_wrong_number(self):
        with mock.patch.object(LencoService, 'resolve_mobile_money', side_effect=LencoUnreachable('down')):
            r = self.client.post('/api/payments/card/refund-number/check/', {'phone': '0961111111'}, format='json')
        self.assertEqual(r.status_code, 503)
        self.assertNotIn("couldn't find", r.json()['error'])

    def test_check_rejects_bad_networks_and_unknown_accounts(self):
        self.assertEqual(self.client.post(
            '/api/payments/card/refund-number/check/', {'phone': '0981111111'}, format='json').status_code, 400)
        with mock.patch.object(LencoService, 'resolve_mobile_money', side_effect=LencoError('nope')):
            r = self.client.post('/api/payments/card/refund-number/check/', {'phone': '0961111111'}, format='json')
        self.assertEqual(r.status_code, 400)
        self.assertIn("couldn't find", r.json()['error'])


@override_settings(**LENCO_ON)
class CardRefundLifecycleTests(CardTestBase):
    def _paid_card_order(self, refund_phone='+260961111111'):
        tx = self._card_tx(status='completed')
        tx.payer_number = refund_phone
        tx.save()
        self.order.status = 'pending'
        self.order.save()
        return tx

    def _cancel(self):
        from orders.services import cancel_order_with_refund
        with mock.patch('orders.services.PawaPayService.initiate_refund') as pawapay, \
                mock.patch('orders.services._notify_staff_refund'):
            cancel_order_with_refund(self.order, reason='test')
        pawapay.assert_not_called()
        return Transaction.objects.get(transaction_type='refund')

    def test_refund_is_addressed_to_the_confirmed_number_with_a_due_date(self):
        self._paid_card_order()
        refund = self._cancel()
        self.assertEqual((refund.provider, refund.payer_number), ('MTN_MOMO_ZMB', '+260961111111'))
        self.assertEqual((refund.payment_method, refund.payout_method, refund.status), ('card', 'manual', 'pending'))
        self.assertIsNotNone(refund.due_at)
        self.assertLess(refund.due_at.weekday(), 5)  # lands on a working day
        self.assertIn('confirmed at checkout', refund.payout_notes)

    def test_a_missing_number_is_flagged_for_staff(self):
        self._paid_card_order(refund_phone='')
        refund = self._cancel()
        self.assertIn('NO valid mobile money number', refund.payout_notes)

    def test_sending_a_refund_pays_the_local_number_and_settles_on_success(self):
        self._paid_card_order()
        refund = self._cancel()
        with mock.patch.object(LencoService, 'initiate_mobile_money_transfer',
                               return_value={'status': 'pending', 'reference': str(refund.transaction_id)}) as send:
            tx = send_via_lenco(refund.pk)
        kwargs = send.call_args.kwargs
        self.assertEqual((kwargs['phone'], kwargs['operator'], kwargs['amount']), ('0961111111', 'mtn', refund.amount))
        self.assertEqual(kwargs['reference'], refund.transaction_id)
        self.assertEqual(tx.status, 'accepted')

        done = {'reference': str(refund.transaction_id), 'status': 'successful', 'fee': '8.50', 'lencoReference': 'L1'}
        with mock.patch('notifications.signals.notify_buyer_refund_completed') as notify:
            apply_lenco_transfer(refund.pk, done)
            apply_lenco_transfer(refund.pk, done)  # replay
        refund.refresh_from_db()
        self.assertEqual((refund.status, refund.gateway_reference, refund.gateway_fee), ('completed', 'L1', Decimal('8.50')))
        notify.assert_called_once()

    def test_a_failed_refund_goes_back_to_staff_not_lost(self):
        self._paid_card_order()
        refund = self._cancel()
        with mock.patch.object(LencoService, 'initiate_mobile_money_transfer', return_value={'status': 'pending'}):
            send_via_lenco(refund.pk)
        with mock.patch('payments.staff_views.notify_staff_new_refund') as staff:
            apply_lenco_transfer(refund.pk, {'reference': str(refund.transaction_id),
                                             'status': 'failed', 'reasonForFailure': 'Wallet inactive'})
        refund.refresh_from_db()
        self.assertEqual((refund.status, refund.payout_method, refund.failure_message),
                         ('pending', 'manual', 'Wallet inactive'))
        staff.assert_called_once()

    def test_lenco_refusing_leaves_the_refund_pending_for_a_retry(self):
        self._paid_card_order()
        refund = self._cancel()
        with mock.patch.object(LencoService, 'initiate_mobile_money_transfer', side_effect=LencoError('Insufficient funds')):
            with self.assertRaises(LencoError):
                send_via_lenco(refund.pk)
        refund.refresh_from_db()
        self.assertEqual((refund.status, refund.failure_message), ('pending', 'Insufficient funds'))

    def test_cannot_send_twice_or_send_a_non_lenco_transaction(self):
        self._paid_card_order()
        refund = self._cancel()
        with mock.patch.object(LencoService, 'initiate_mobile_money_transfer', return_value={'status': 'pending'}) as send:
            send_via_lenco(refund.pk)
            with self.assertRaises(CannotSend):
                send_via_lenco(refund.pk)
        self.assertEqual(send.call_count, 1)
        pawapay_tx = Transaction.objects.create(
            order=self.order, transaction_type='refund', amount=5, provider='MTN_MOMO_ZMB',
            payer_number='+260961111111', status='pending')
        with self.assertRaises(CannotSend):
            send_via_lenco(pawapay_tx.pk)

    def test_transfer_webhook_re_reads_lenco_before_settling(self):
        self._paid_card_order()
        refund = self._cancel()
        with mock.patch.object(LencoService, 'initiate_mobile_money_transfer', return_value={'status': 'pending'}):
            send_via_lenco(refund.pk)
        payload = {'event': 'transfer.successful', 'data': {'reference': str(refund.transaction_id)}}
        raw = json.dumps(payload).encode()
        sig = hmac.new(hashlib.sha256(b'tok').hexdigest().encode(), raw, hashlib.sha512).hexdigest()
        with mock.patch.object(LencoService, 'get_transfer_status',
                               return_value={'reference': str(refund.transaction_id), 'status': 'successful'}), \
                mock.patch('notifications.signals.notify_buyer_refund_completed'):
            r = self.client.generic('POST', '/api/payments/lenco/webhook/', raw,
                                    content_type='application/json', HTTP_X_LENCO_SIGNATURE=sig)
        self.assertEqual(r.status_code, 200)
        refund.refresh_from_db()
        self.assertEqual(refund.status, 'completed')

    def test_staff_endpoint_is_staff_only(self):
        self._paid_card_order()
        refund = self._cancel()
        url = f'/api/staff/send-via-lenco/{refund.transaction_id}/'
        self.client.force_authenticate(self.buyer)
        self.assertEqual(self.client.post(url).status_code, 403)
        staff = User.objects.create_user(phone_number='+260933333333', password='x', full_name='Staff', role='staff')
        self.client.force_authenticate(staff)
        with mock.patch.object(LencoService, 'initiate_mobile_money_transfer', return_value={'status': 'pending'}):
            r = self.client.post(url)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()['status'], 'accepted')
        self.assertEqual(self.client.post(url).status_code, 400)  # already sent


@override_settings(**LENCO_ON)
class BankWithdrawalTests(APITestCase):
    def setUp(self):
        self.seller = User.objects.create_user(
            phone_number='+260911111111', password='x', full_name='Sam Seller', role='seller')
        self.buyer = User.objects.create_user(
            phone_number='+260922222222', password='x', full_name='Ann Buyer', role='buyer')
        self.order = _make_order(self.buyer, self.seller, status='delivered')
        # K3,000 earned from a completed handover, unpaid.
        Transaction.objects.create(
            order=self.order, transaction_type='payout', amount=Decimal('3000.00'), provider='MTN_MOMO_ZMB',
            payer_number='+260961111111', recipient=self.seller, recipient_role='seller',
            trigger_event='pickup_qr', payout_stage='ready_for_payout', status='pending')
        self.account = PayoutBankAccount.objects.create(
            user=self.seller, bank_id='002', bank_name='Absa Bank', account_number='9130000000000',
            account_name='SAM SELLER', name_matches=True, is_default=True)
        ps = PlatformSettings.get()
        ps.bank_payouts_enabled = True
        ps.bank_payout_min_amount = Decimal('1000')
        ps.bank_payout_fee = Decimal('50')
        ps.save()
        self.client.force_authenticate(self.seller)

    def _withdraw(self, amount, **extra):
        return self.client.post('/api/payments/payout/', {'amount': amount, 'method': 'bank', **extra}, format='json')

    def _available(self):
        return earnings_breakdown(self.seller, 'seller')['available']

    def test_off_by_default_and_riders_are_refused(self):
        ps = PlatformSettings.get()
        ps.bank_payouts_enabled = False
        ps.save()
        self.assertEqual(self._withdraw('1500').status_code, 400)
        ps.bank_payouts_enabled = True
        ps.save()
        rider = User.objects.create_user(phone_number='+260944444444', password='x', full_name='Rider', role='delivery')
        self.client.force_authenticate(rider)
        self.assertEqual(self._withdraw('1500').status_code, 400)

    def test_admin_minimum_is_enforced_and_configurable(self):
        r = self._withdraw('999')
        self.assertEqual(r.status_code, 400)
        self.assertIn('minimum bank payout is ZMW 1000', r.json()['error'])
        ps = PlatformSettings.get()
        ps.bank_payout_min_amount = Decimal('500')
        ps.save()
        self.assertEqual(self._withdraw('600').status_code, 201)

    def test_fee_is_deducted_from_what_the_seller_receives_and_from_earnings(self):
        r = self._withdraw('1500')
        self.assertEqual(r.status_code, 201)
        self.assertEqual((r.json()['fee'], r.json()['you_receive']), ('50.00', '1450.00'))
        tx = Transaction.objects.get(payment_method='bank')
        self.assertEqual((tx.amount, tx.fee_deducted, tx.gateway, tx.bank_account_id),
                         (Decimal('1450.00'), Decimal('50.00'), 'lenco', self.account.id))
        self.assertEqual(self._available(), Decimal('1500.00'))  # 3000 - 1500 gross, fee included

    def test_cannot_withdraw_more_than_earned_or_less_than_the_fee(self):
        self.assertEqual(self._withdraw('3500').status_code, 400)
        ps = PlatformSettings.get()
        ps.bank_payout_min_amount = Decimal('10')
        ps.save()
        self.assertEqual(self._withdraw('40').status_code, 400)  # 40 - 50 fee <= 0

    def test_a_failed_bank_payout_returns_the_money_to_earnings(self):
        self._withdraw('1500')
        tx = Transaction.objects.get(payment_method='bank')
        with mock.patch.object(LencoService, 'initiate_bank_transfer', return_value={'status': 'pending'}):
            send_via_lenco(tx.pk)
        self.assertEqual(self._available(), Decimal('1500.00'))
        with mock.patch('payments.staff_views.notify_staff_payout_failed'):
            apply_lenco_transfer(tx.pk, {'reference': str(tx.transaction_id), 'status': 'failed',
                                         'reasonForFailure': 'Account closed'})
        tx.refresh_from_db()
        self.assertEqual((tx.status, tx.payout_stage), ('failed', 'payout_failed'))
        self.assertEqual(self._available(), Decimal('3000.00'))

    def test_a_paid_bank_payout_stays_deducted(self):
        self._withdraw('1500')
        tx = Transaction.objects.get(payment_method='bank')
        with mock.patch.object(LencoService, 'initiate_bank_transfer', return_value={'status': 'pending'}) as send:
            send_via_lenco(tx.pk)
        self.assertEqual(send.call_args.kwargs['account_number'], '9130000000000')
        self.assertEqual(send.call_args.kwargs['amount'], Decimal('1450.00'))
        with mock.patch('notifications.signals.create_payout_completed_notification'):
            apply_lenco_transfer(tx.pk, {'reference': str(tx.transaction_id), 'status': 'successful'})
        tx.refresh_from_db()
        self.assertEqual((tx.status, tx.payout_stage), ('completed', 'payout_paid'))
        self.assertEqual(self._available(), Decimal('1500.00'))

    def test_a_mismatched_account_name_needs_staff_confirmation(self):
        self.account.name_matches = False
        self.account.save()
        self.assertEqual(self._withdraw('1500').status_code, 201)
        tx = Transaction.objects.get(payment_method='bank')
        self.assertIn('does not match', tx.payout_notes)
        with self.assertRaises(CannotSend):
            send_via_lenco(tx.pk)
        with mock.patch.object(LencoService, 'initiate_bank_transfer', return_value={'status': 'pending'}):
            self.assertEqual(send_via_lenco(tx.pk, allow_name_mismatch=True).status, 'accepted')

    def test_automatic_mode_sends_straight_away_only_for_a_matching_account(self):
        ps = PlatformSettings.get()
        ps.payout_method = 'gateway'
        ps.save()
        with mock.patch.object(LencoService, 'initiate_bank_transfer', return_value={'status': 'pending'}) as send:
            self.assertEqual(self._withdraw('1500').status_code, 201)
        send.assert_called_once()
        self.assertEqual(Transaction.objects.get(payment_method='bank').status, 'accepted')

        self.account.name_matches = False
        self.account.save()
        with mock.patch.object(LencoService, 'initiate_bank_transfer') as send:
            self.assertEqual(self._withdraw('1000').status_code, 201)
        send.assert_not_called()

    def test_get_reports_bank_options_only_to_sellers_when_enabled(self):
        r = self.client.get('/api/payments/payout/').json()
        self.assertTrue(r['bank_payouts_enabled'])
        self.assertEqual((r['bank_payout_min_amount'], r['bank_payout_fee']), ('1000.00', '50.00'))
        self.assertEqual(r['bank_accounts'][0]['account_number_masked'], '••••0000')
        self.assertNotIn('9130000000000', json.dumps(r))

    def test_mobile_money_withdrawals_are_unchanged(self):
        # No `method` -> the original path; with no verified wallet it refuses exactly as before.
        r = self.client.post('/api/payments/payout/', {'amount': '100'}, format='json')
        self.assertEqual(r.status_code, 400)
        self.assertIn('No verified payout method', r.json()['error'])
