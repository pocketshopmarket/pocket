from decimal import Decimal
from unittest import mock

from rest_framework.test import APITestCase

from accounts.models import SellerProfile, User
from portal.models import PlatformSettings
from products.models import PromoBanner

from .models import Transaction


def _approved_seller(phone='+260970000210'):
    seller = User.objects.create_user(phone_number=phone, password='x', full_name='Seller', role='seller')
    SellerProfile.objects.create(user=seller, shop_name='Shop', shop_location='Lusaka', is_approved=True)
    return seller


def _staff(phone='+260970000211'):
    return User.objects.create_user(phone_number=phone, password='x', full_name='Staff', role='staff')


def _pending_payment_banner(seller, price='350.00'):
    return PromoBanner.objects.create(
        title='Big Sale', seller=seller, status='pending_payment',
        price_paid=Decimal(price), duration_days=7, action_type='shop', action_value=str(seller.id),
    )


class BannerPaymentInitiateTests(APITestCase):
    def setUp(self):
        self.seller = _approved_seller()
        self.banner = _pending_payment_banner(self.seller)
        self.client.force_authenticate(self.seller)

    def test_initiating_payment_creates_a_deposit_transaction_for_the_banner_amount(self):
        with mock.patch('payments.views.PawaPayService.initiate_deposit', return_value={'status': 'ACCEPTED'}):
            r = self.client.post('/api/payments/banner/initiate/', {
                'banner_id': self.banner.id, 'payer_number': '0970000000',
            }, format='json')
        self.assertEqual(r.status_code, 200, r.content)
        tx = Transaction.objects.get(promo_banner=self.banner)
        self.assertEqual(tx.amount, Decimal('350.00'))
        self.assertIsNone(tx.order)
        self.assertEqual(tx.recipient_role, 'platform')

    def test_cannot_pay_for_a_banner_already_paid(self):
        self.banner.status = 'pending_review'
        self.banner.save()
        r = self.client.post('/api/payments/banner/initiate/', {
            'banner_id': self.banner.id, 'payer_number': '0970000000',
        }, format='json')
        self.assertEqual(r.status_code, 400)

    def test_cannot_pay_for_another_sellers_banner(self):
        other_seller = _approved_seller('+260970000212')
        self.client.force_authenticate(other_seller)
        r = self.client.post('/api/payments/banner/initiate/', {
            'banner_id': self.banner.id, 'payer_number': '0970000000',
        }, format='json')
        self.assertEqual(r.status_code, 404)

    def test_a_failed_pawapay_call_does_not_crash_on_a_banner_transaction(self):
        # Regression check for the clientReferenceId bug: initiate_deposit
        # used to dereference transaction.order.order_number unconditionally,
        # which crashes on a banner transaction (order=None).
        with mock.patch('payments.services.pawapay.requests.post') as post:
            post.return_value.status_code = 200
            post.return_value.json.return_value = {'status': 'ACCEPTED'}
            r = self.client.post('/api/payments/banner/initiate/', {
                'banner_id': self.banner.id, 'payer_number': '0970000000',
            }, format='json')
        self.assertEqual(r.status_code, 200, r.content)
        sent_payload = post.call_args.kwargs['json']
        self.assertEqual(sent_payload['clientReferenceId'], f'BANNER-{self.banner.id}')


class BannerPaymentStatusTests(APITestCase):
    def setUp(self):
        self.seller = _approved_seller('+260970000213')
        self.banner = _pending_payment_banner(self.seller)
        self.client.force_authenticate(self.seller)
        self.tx = Transaction.objects.create(
            promo_banner=self.banner, transaction_type='deposit', amount=self.banner.price_paid,
            currency='ZMW', provider='MTN_MOMO_ZMB', payer_number='+260970000000',
            recipient_role='platform', status='accepted',
        )

    def test_completed_payment_moves_banner_to_pending_review_not_active(self):
        with mock.patch('payments.views.PawaPayService.get_deposit_status', return_value={'status': 'COMPLETED'}):
            r = self.client.get(f'/api/payments/banner/status/?banner_id={self.banner.id}')
        self.assertEqual(r.status_code, 200, r.content)
        self.banner.refresh_from_db()
        self.assertEqual(self.banner.status, 'pending_review')
        self.assertFalse(self.banner.is_active)

    def test_failed_payment_reverts_banner_to_pending_payment(self):
        with mock.patch(
            'payments.views.PawaPayService.get_deposit_status',
            return_value={'status': 'FAILED', 'failureReason': {'failureMessage': 'Insufficient funds'}},
        ):
            self.client.get(f'/api/payments/banner/status/?banner_id={self.banner.id}')
        self.banner.refresh_from_db()
        self.assertEqual(self.banner.status, 'pending_payment')


class StaffBannerQueueTests(APITestCase):
    def setUp(self):
        self.staff = _staff()
        self.seller = _approved_seller('+260970000214')
        self.client.force_authenticate(self.staff)

    def test_queue_only_lists_pending_review_banners(self):
        PromoBanner.objects.create(title='Draft', seller=self.seller, status='draft', price_paid=10, duration_days=1)
        PromoBanner.objects.create(title='Waiting', seller=self.seller, status='pending_review', price_paid=10, duration_days=1)
        PromoBanner.objects.create(title='Already live', seller=self.seller, status='active', price_paid=10, duration_days=1)
        r = self.client.get('/api/staff/banners/')
        titles = [b['title'] for b in r.json()['results']]
        self.assertEqual(titles, ['Waiting'])

    def test_non_staff_cannot_see_the_queue(self):
        self.client.force_authenticate(self.seller)
        r = self.client.get('/api/staff/banners/')
        self.assertEqual(r.status_code, 403)

    def test_approve_makes_the_banner_live_and_sets_the_date_window(self):
        banner = PromoBanner.objects.create(
            title='Waiting', seller=self.seller, status='pending_review', price_paid=10, duration_days=7,
        )
        r = self.client.post(f'/api/staff/banners/{banner.id}/approve/')
        self.assertEqual(r.status_code, 200, r.content)
        banner.refresh_from_db()
        self.assertEqual(banner.status, 'active')
        self.assertTrue(banner.is_active)
        self.assertIsNotNone(banner.starts_at)
        self.assertEqual((banner.ends_at - banner.starts_at).days, 7)

    def test_reject_requires_a_reason(self):
        banner = PromoBanner.objects.create(
            title='Waiting', seller=self.seller, status='pending_review', price_paid=10, duration_days=7,
        )
        r = self.client.post(f'/api/staff/banners/{banner.id}/reject/', {'reason': ''}, format='json')
        self.assertEqual(r.status_code, 400)
        banner.refresh_from_db()
        self.assertEqual(banner.status, 'pending_review')  # unchanged

    def test_reject_with_a_reason_rejects_and_never_activates(self):
        banner = PromoBanner.objects.create(
            title='Waiting', seller=self.seller, status='pending_review', price_paid=10, duration_days=7,
        )
        r = self.client.post(
            f'/api/staff/banners/{banner.id}/reject/',
            {'reason': 'Image is low quality'}, format='json',
        )
        self.assertEqual(r.status_code, 200, r.content)
        banner.refresh_from_db()
        self.assertEqual(banner.status, 'rejected')
        self.assertFalse(banner.is_active)

    def test_cannot_decide_a_banner_thats_not_awaiting_review(self):
        banner = PromoBanner.objects.create(
            title='Already live', seller=self.seller, status='active', price_paid=10, duration_days=7,
        )
        r = self.client.post(f'/api/staff/banners/{banner.id}/approve/')
        self.assertEqual(r.status_code, 400)
