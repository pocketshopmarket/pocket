from datetime import datetime, timezone as dt_timezone
from decimal import Decimal
from unittest import mock

from rest_framework.test import APITestCase

from accounts.models import User

from .models import Transaction
from .test_card import _make_order


class StaffApiBase(APITestCase):
    def setUp(self):
        self.staff = User.objects.create_user(
            phone_number='+260900000001', password='x', full_name='Staff', role='staff')
        self.buyer = User.objects.create_user(
            phone_number='+260911111111', password='x', full_name='Ann Buyer', role='buyer')
        self.seller = User.objects.create_user(
            phone_number='+260922222222', password='x', full_name='Sam Seller', role='seller')
        self.client.force_authenticate(self.staff)

    def _tx(self, order, **kw):
        defaults = dict(order=order, transaction_type='payout', amount=Decimal('50.00'),
                        provider='MTN_MOMO_ZMB', payer_number='+260961111111',
                        recipient=self.seller, recipient_role='seller', status='pending')
        defaults.update(kw)
        return Transaction.objects.create(**defaults)


class StaffStatsTests(StaffApiBase):
    def test_refund_count_includes_approved_refunds_on_delivered_orders(self):
        delivered = _make_order(self.buyer, self.seller, status='delivered')
        self._tx(delivered, transaction_type='refund', recipient=self.buyer, recipient_role='buyer')
        cancelled = _make_order(self.buyer, self.seller, status='cancelled')
        self._tx(cancelled, transaction_type='refund', recipient=self.buyer, recipient_role='buyer')
        self._tx(cancelled, transaction_type='refund', recipient=self.buyer, recipient_role='buyer')  # same order
        self.assertEqual(self.client.get('/api/staff/stats/').json()['refund_count'], 2)
        # ...which is exactly what the Refunds tab lists.
        rows = self.client.get('/api/staff/refunds/').json()['results']
        self.assertEqual(len([r for r in rows if r['pending_refund']]), 2)

    def test_failed_payouts_ignores_payouts_voided_by_a_cancelled_order(self):
        order = _make_order(self.buyer, self.seller)
        self._tx(order, status='failed', payout_stage='ready_for_payout', failure_message='Order cancelled')
        self._tx(order, status='failed', payout_stage='payout_failed', failure_message='PawaPay timeout')
        self.assertEqual(self.client.get('/api/staff/stats/').json()['failed_payouts_count'], 1)

    def test_todays_collections_follow_the_zambian_day_not_utc(self):
        order = _make_order(self.buyer, self.seller)
        tx = self._tx(order, transaction_type='deposit', amount=Decimal('200.00'),
                      recipient=None, recipient_role='', status='completed')
        # 00:30 on 26 Sep in Lusaka is 22:30 on 25 Sep in UTC.
        stamp = datetime(2026, 9, 25, 22, 30, tzinfo=dt_timezone.utc)
        Transaction.objects.filter(pk=tx.pk).update(updated_at=stamp)
        with mock.patch('payments.staff_views.timezone.now',
                        return_value=datetime(2026, 9, 25, 23, 0, tzinfo=dt_timezone.utc)):  # 01:00 26 Sep Lusaka
            self.assertEqual(self.client.get('/api/staff/stats/').json()['today_revenue'], '200.00')
        with mock.patch('payments.staff_views.timezone.now',
                        return_value=datetime(2026, 9, 26, 23, 0, tzinfo=dt_timezone.utc)):  # next day
            self.assertEqual(self.client.get('/api/staff/stats/').json()['today_revenue'], '0.00')


class StaffListTests(StaffApiBase):
    def test_withdrawals_show_in_flight_payouts_read_only_with_friendly_network(self):
        order = _make_order(self.buyer, self.seller, status='delivered')
        self._tx(order, trigger_event='manual', payout_stage='ready_for_payout', status='pending')
        self._tx(order, trigger_event='manual', payout_stage='payout_sent', status='accepted', provider='AIRTEL_OAPI_ZMB')
        rows = self.client.get('/api/staff/withdrawals/').json()['results']
        self.assertEqual(sorted((r['status'], r['provider_label']) for r in rows),
                         [('accepted', 'Airtel Money'), ('pending', 'MTN MoMo')])
        # The dashboard only counts what still needs a person.
        self.assertEqual(self.client.get('/api/staff/stats/').json()['withdrawal_count'], 1)

    def test_refunds_are_sorted_pending_first_and_flag_in_flight_ones(self):
        done = _make_order(self.buyer, self.seller, status='cancelled')
        self._tx(done, transaction_type='refund', status='completed', recipient=self.buyer, recipient_role='buyer')
        sending = _make_order(self.buyer, self.seller, status='cancelled')
        self._tx(sending, transaction_type='refund', status='accepted', recipient=self.buyer, recipient_role='buyer')
        waiting = _make_order(self.buyer, self.seller, status='delivered')
        self._tx(waiting, transaction_type='refund', status='pending', recipient=self.buyer, recipient_role='buyer')
        rows = self.client.get('/api/staff/refunds/').json()['results']
        self.assertEqual(rows[0]['order_number'], waiting.order_number)
        self.assertEqual(rows[0]['order_status'], 'delivered')
        by_order = {r['order_number']: r for r in rows}
        self.assertTrue(by_order[sending.order_number]['refund_in_flight'])
        self.assertFalse(by_order[done.order_number]['refund_in_flight'])


class FailedPayoutTests(StaffApiBase):
    def _failed(self, order, **kw):
        return self._tx(order, status='failed', payout_stage='payout_failed',
                        failure_message='PawaPay timeout', trigger_event='pickup_qr', **kw)

    def test_lists_only_real_failures_and_says_which_can_be_requeued(self):
        order = _make_order(self.buyer, self.seller, status='delivered')
        per_order = self._failed(order)
        claim = self._tx(order, status='failed', payout_stage='payout_failed',
                         trigger_event='manual', failure_message='x')
        self._tx(order, status='failed', payout_stage='ready_for_payout', failure_message='Order cancelled')
        rows = {r['transaction_id']: r for r in self.client.get('/api/staff/failed-payouts/').json()['results']}
        self.assertEqual(set(rows), {str(per_order.pk), str(claim.pk)})
        self.assertTrue(rows[str(per_order.pk)]['can_requeue'])
        self.assertFalse(rows[str(claim.pk)]['can_requeue'])

    def test_requeue_puts_a_per_order_payout_back_in_the_queue(self):
        order = _make_order(self.buyer, self.seller, status='delivered')
        tx = self._failed(order)
        r = self.client.post(f'/api/staff/failed-payouts/{tx.pk}/requeue/')
        self.assertEqual(r.status_code, 200)
        tx.refresh_from_db()
        self.assertEqual((tx.status, tx.payout_stage, tx.payout_method), ('pending', 'ready_for_payout', 'manual'))
        self.assertIn('PawaPay timeout', tx.payout_notes)
        queue = self.client.get('/api/staff/payout-queue/').json()['results']
        self.assertEqual([q['transaction_id'] for q in queue], [str(tx.pk)])
        self.assertEqual(self.client.post(f'/api/staff/failed-payouts/{tx.pk}/requeue/').status_code, 400)  # not failed now

    def test_a_failed_withdrawal_is_not_requeued_because_it_would_double_pay(self):
        order = _make_order(self.buyer, self.seller, status='delivered')
        claim = self._tx(order, status='failed', payout_stage='payout_failed', trigger_event='manual')
        self.assertEqual(self.client.post(f'/api/staff/failed-payouts/{claim.pk}/requeue/').status_code, 400)

    def test_staff_only(self):
        self.client.force_authenticate(self.buyer)
        self.assertEqual(self.client.get('/api/staff/failed-payouts/').status_code, 403)


class VerificationDecisionTests(StaffApiBase):
    def setUp(self):
        super().setUp()
        from accounts.models import VerificationRequest
        # A delivery-type request needs no seller profile, which keeps this test small.
        self.vr = VerificationRequest.objects.create(user=self.seller, verification_type='delivery')

    def _act(self, action, **body):
        return self.client.post(f'/api/staff/verifications/{self.vr.pk}/{action}/', body, format='json')

    def test_a_rejection_must_give_a_reason(self):
        for reason in ('', '  ', 'no'):
            self.assertEqual(self._act('reject', reason=reason).status_code, 400)
        self.vr.refresh_from_db()
        self.assertEqual(self.vr.status, 'submitted')
        self.assertEqual(self._act('reject', reason='NRC photo is blurry').status_code, 200)
        self.vr.refresh_from_db()
        self.assertEqual((self.vr.status, self.vr.rejection_reason), ('rejected', 'NRC photo is blurry'))

    def test_a_decided_request_cannot_be_decided_again(self):
        self.assertEqual(self._act('approve').status_code, 200)
        self.assertEqual(self._act('approve').status_code, 400)
        r = self._act('reject', reason='changed my mind')
        self.assertEqual(r.status_code, 400)
        self.assertIn('already approved', r.json()['error'])
        self.vr.refresh_from_db()
        self.assertEqual(self.vr.status, 'approved')
