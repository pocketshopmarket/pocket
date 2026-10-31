from datetime import timedelta
from decimal import Decimal

from django.core import mail
from django.core.cache import cache
from django.core.management import call_command
from django.test import TestCase
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from accounts.models import SellerProfile, User
from orders.models import Order
from payments.models import Transaction
from portal.models import PlatformSettings
from products.models import Category, Product

from .models import Partner, PartnerEarning, PayoutRequest, PromoCode, PromoSettings, Referral
from .services import (
    PromoError, attach_referral, best_discount, discount_amount, promo_discount, welcome_discount,
)

D = Decimal


def make_user(phone, role='buyer', **extra):
    return User.objects.create_user(phone_number=phone, password='testpass123', full_name='Test', role=role, **extra)


def make_partner(code='YOMAPS', status=Partner.APPROVED, **extra):
    fields = {
        'name': 'Yoma', 'email': f'{code.lower()}@example.com', 'phone': '+260955555555',
        'payout_method': 'mobile_money', 'payout_details': '0955555555 MTN', **extra,
    }
    return Partner.objects.create(code=code, status=status, approved_at=timezone.now(), **fields)


class Shop:
    """A seller with one product, and an order factory."""

    def __init__(self):
        self.seller = make_user('+260922222222', role='seller')
        SellerProfile.objects.create(user=self.seller, shop_name='Shop', shop_location='Lusaka', is_approved=True)
        category, _ = Category.objects.get_or_create(slug='shoes', defaults={'name': 'Shoes'})
        self.product = Product.objects.create(
            name='Shoes', description='x', price=D('200'), category=category, seller=self.seller, stock_quantity=50,
        )

    def order(self, buyer, status='payment_pending', **extra):
        fields = {'total_price': D('200'), 'delivery_fee': D('30'), 'service_fee': D('10'), **extra}
        return Order.objects.create(buyer=buyer, seller=self.seller, status=status, delivery_address='Town', **fields)


class DiscountMathTests(TestCase):
    def test_percent_with_cap(self):
        self.assertEqual(discount_amount('percent', 15, 30, 100), D('15.00'))
        self.assertEqual(discount_amount('percent', 15, 30, 400), D('30.00'))
        self.assertEqual(discount_amount('percent', 15, None, 400), D('60.00'))

    def test_fixed_never_more_than_items(self):
        self.assertEqual(discount_amount('fixed', 50, None, 200), D('50.00'))
        self.assertEqual(discount_amount('fixed', 50, None, 20), D('20.00'))


class WelcomeDiscountTests(TestCase):
    def setUp(self):
        self.shop = Shop()
        self.buyer = make_user('+260911111111')

    def test_new_buyer_gets_it(self):
        d = welcome_discount(self.buyer, D('100'))
        self.assertEqual((d.kind, d.amount), ('welcome', D('15.00')))
        self.assertEqual(welcome_discount(self.buyer, D('500')).amount, D('30.00'))

    def test_gone_after_first_order(self):
        self.shop.order(self.buyer)
        self.assertEqual(welcome_discount(self.buyer, D('100')).amount, 0)

    def test_abandoned_unpaid_order_does_not_use_it_up(self):
        old = self.shop.order(self.buyer)
        Order.objects.filter(pk=old.pk).update(created_at=timezone.now() - timedelta(hours=3))
        self.assertEqual(welcome_discount(self.buyer, D('100')).amount, D('15.00'))

    def test_cancelled_order_does_not_use_it_up(self):
        self.shop.order(self.buyer, status='cancelled')
        self.assertEqual(welcome_discount(self.buyer, D('100')).amount, D('15.00'))

    def test_expires_after_valid_days(self):
        User.objects.filter(pk=self.buyer.pk).update(date_joined=timezone.now() - timedelta(days=31))
        self.buyer.refresh_from_db()
        self.assertEqual(welcome_discount(self.buyer, D('100')).amount, 0)

    def test_settings_change_it(self):
        ps = PromoSettings.get()
        ps.welcome_discount_type, ps.welcome_discount_value, ps.welcome_min_order = 'fixed', D('25'), D('150')
        ps.save()
        self.assertEqual(welcome_discount(self.buyer, D('100')).amount, 0)
        self.assertEqual(welcome_discount(self.buyer, D('200')).amount, D('25.00'))
        ps.welcome_enabled = False
        ps.save()
        self.assertEqual(welcome_discount(self.buyer, D('200')).amount, 0)

    def test_sellers_do_not_get_it(self):
        self.assertEqual(welcome_discount(self.shop.seller, D('100')).amount, 0)


class PromoCodeRuleTests(TestCase):
    def setUp(self):
        self.shop = Shop()
        self.buyer = make_user('+260911111111')
        User.objects.filter(pk=self.buyer.pk).update(date_joined=timezone.now() - timedelta(days=90))
        self.buyer.refresh_from_db()
        self.promo = PromoCode.objects.create(code='easter30', value=D('30'), max_discount=D('100'))

    def assertRefused(self, text, code='EASTER30', subtotal=D('200')):
        with self.assertRaisesMessage(PromoError, text):
            promo_discount(self.buyer, code, subtotal)

    def test_code_is_saved_uppercase_and_matches_any_case(self):
        self.assertEqual(self.promo.code, 'EASTER30')
        self.assertEqual(promo_discount(self.buyer, ' easter30 ', D('200')).amount, D('60.00'))

    def test_unknown_and_off(self):
        self.assertRefused("isn't valid", code='NOPE')
        self.promo.is_active = False
        self.promo.save()
        self.assertRefused("isn't valid")

    def test_dates(self):
        self.promo.starts_at = timezone.now() + timedelta(days=1)
        self.promo.save()
        self.assertRefused("hasn't started")
        self.promo.starts_at, self.promo.ends_at = None, timezone.now() - timedelta(minutes=1)
        self.promo.save()
        self.assertRefused('has ended')

    def test_minimum_order(self):
        self.promo.min_order = D('300')
        self.promo.save()
        self.assertRefused('K300')

    def test_first_order_only(self):
        self.promo.first_order_only = True
        self.promo.save()
        self.shop.order(self.buyer, status='delivered')
        self.assertRefused('only for your first order')

    def test_per_buyer_and_total_limits(self):
        self.shop.order(self.buyer, promo_code=self.promo)
        self.assertRefused("You've already used")
        other = make_user('+260933333333')
        self.promo.max_uses = 1
        self.promo.save()
        with self.assertRaisesMessage(PromoError, 'fully used'):
            promo_discount(other, 'EASTER30', D('200'))

    def test_bigger_discount_wins(self):
        newbie = make_user('+260944444444')
        small = PromoCode.objects.create(code='SMALL5', discount_type='fixed', value=D('5'))
        self.assertEqual(best_discount(newbie, D('200'), 'SMALL5').kind, 'welcome')
        self.assertEqual(best_discount(newbie, D('200'), 'EASTER30').promo, self.promo)
        self.assertEqual(best_discount(newbie, D('200')).kind, 'welcome')
        self.assertTrue(small.pk)

    def test_partner_and_promo_codes_cannot_clash(self):
        partner = Partner(name='X', email='x@example.com', code='EASTER30')
        with self.assertRaises(Exception):
            partner.full_clean()


class CheckoutDiscountTests(APITestCase):
    def setUp(self):
        self.shop = Shop()
        self.buyer = make_user('+260911111111')
        self.client.force_authenticate(self.buyer)
        self.client.post('/api/orders/cart/', {'product_id': self.shop.product.id, 'quantity': 1})
        ps = PlatformSettings.get()
        ps.buyer_service_fee_rate = D('0.05')
        ps.save()

    def checkout(self, **extra):
        return self.client.post('/api/orders/orders/create/', {'delivery_address': 'Town', **extra})

    def test_welcome_discount_lowers_the_charge_not_the_payouts(self):
        r = self.checkout()
        self.assertEqual(r.status_code, status.HTTP_201_CREATED, r.data)
        self.assertEqual(r.data['discount_kind'], 'welcome')
        self.assertEqual(D(r.data['discount_amount']), D('30.00'))  # 15% of 200
        order = Order.objects.get(order_number=r.data['order_number'])
        self.assertEqual(order.total_price, D('200'))
        self.assertEqual(order.grand_total, order.total_price + order.delivery_fee + order.service_fee - D('30'))

        from payments.views import create_payout_rows_for_deposit
        deposit = Transaction.objects.create(
            order=order, transaction_type='deposit', amount=order.grand_total,
            provider='MTN_MOMO_ZMB', payer_number='0911111111', status='completed',
        )
        create_payout_rows_for_deposit(deposit)
        seller_payout = Transaction.objects.get(order=order, transaction_type='payout', recipient_role='seller')
        rate = D(str(PlatformSettings.get().seller_commission_rate))
        expected = D('200') - (D('200') * rate).quantize(D('0.01'))
        expected -= (expected * D(str(PlatformSettings.get().payout_fee_rate))).quantize(D('0.01'))
        self.assertEqual(seller_payout.amount, expected)

    def test_promo_code_used_when_bigger(self):
        PromoCode.objects.create(code='BIG40', value=D('40'))
        r = self.checkout(promo_code='big40')
        self.assertEqual(r.status_code, status.HTTP_201_CREATED, r.data)
        self.assertEqual((r.data['discount_kind'], r.data['promo_code']), ('promo', 'BIG40'))
        self.assertEqual(D(r.data['discount_amount']), D('80.00'))

    def test_bad_promo_code_stops_checkout_with_a_message(self):
        r = self.checkout(promo_code='NOPE')
        self.assertEqual(r.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("isn't valid", r.data['promo_code_error'])
        self.assertFalse(Order.objects.exists())

    def test_check_endpoint_matches_checkout(self):
        r = self.client.post('/api/promotions/check/', {}, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data['discount']['amount'], '30.00')
        r = self.client.post('/api/promotions/check/', {'promo_code': 'NOPE'}, format='json')
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.data['discount']['kind'], 'welcome')


class ReferralTests(APITestCase):
    def setUp(self):
        self.partner = make_partner()

    def test_code_lookup(self):
        r = self.client.get('/api/promotions/referral/yomaps/')
        self.assertEqual((r.status_code, r.data['partner_name']), (200, 'Yoma'))
        self.assertEqual(self.client.get('/api/promotions/referral/NOPE/').status_code, 404)
        self.partner.status = Partner.PAUSED
        self.partner.save()
        self.assertEqual(self.client.get('/api/promotions/referral/YOMAPS/').status_code, 404)

    def test_attach_once_and_not_to_yourself(self):
        buyer = make_user('+260911111111')
        self.assertIsNotNone(attach_referral(buyer, 'yomaps'))
        self.assertIsNone(attach_referral(buyer, 'YOMAPS'))
        self_ref = make_user('+260955555555')  # the partner's own phone
        self.assertIsNone(attach_referral(self_ref, 'YOMAPS'))
        self.assertIsNone(attach_referral(make_user('+260966666666'), 'NOPE'))
        self.assertEqual(Referral.objects.count(), 1)


class PartnerEarningTests(TestCase):
    def setUp(self):
        self.shop = Shop()
        self.partner = make_partner()
        self.buyer = make_user('+260911111111')
        attach_referral(self.buyer, 'YOMAPS')

    def deliver(self, order):
        order.status = 'delivered'
        order.save()
        return PartnerEarning.objects.filter(order=order).first()

    def test_earns_share_of_service_fee_on_delivery_only(self):
        order = self.shop.order(self.buyer, status='accepted', service_fee=D('12.50'))
        self.assertFalse(PartnerEarning.objects.exists())
        earning = self.deliver(order)
        self.assertEqual(earning.amount, D('1.25'))
        order.save()  # saving again doesn't double it
        self.assertEqual(PartnerEarning.objects.count(), 1)

    def test_partner_own_rate(self):
        self.partner.commission_rate = D('0.20')
        self.partner.save()
        self.assertEqual(self.deliver(self.shop.order(self.buyer, service_fee=D('10'))).amount, D('2.00'))

    def test_no_earning_after_window_or_when_paused(self):
        Referral.objects.update(created_at=timezone.now() - timedelta(days=31))
        self.assertIsNone(self.deliver(self.shop.order(self.buyer)))
        Referral.objects.update(created_at=timezone.now())
        self.partner.status = Partner.PAUSED
        self.partner.save()
        self.assertIsNone(self.deliver(self.shop.order(self.buyer)))

    def test_refund_removes_the_earning(self):
        order = self.shop.order(self.buyer)
        earning = self.deliver(order)
        Transaction.objects.create(
            order=order, transaction_type='refund', amount=order.grand_total,
            provider='MTN_MOMO_ZMB', payer_number='0911111111', status='completed',
        )
        earning.refresh_from_db()
        self.assertEqual(earning.status, PartnerEarning.REVERSED)
        self.assertEqual(self.partner.balances()['earned'], 0)


class PartnerWebsiteTests(TestCase):
    def setUp(self):
        cache.clear()
        self.shop = Shop()

    def apply_data(self, **extra):
        return {
            'name': 'Mwila Banda', 'email': 'Mwila@Example.com', 'phone': '0977123456',
            'promotes_on': 'TikTok @mwila', 'code': '', 'payout_method': 'mobile_money',
            'payout_details': '0977123456 MTN', 'agree': 'on', 'website': '', **extra,
        }

    def test_landing_and_rules_show_the_settings(self):
        ps = PromoSettings.get()
        ps.partner_commission_rate, ps.partner_min_payout = D('0.15'), D('75')
        ps.save()
        r = self.client.get('/partners/')
        self.assertContains(r, '15%')
        self.assertContains(r, 'K75')
        self.assertContains(self.client.get('/partners/rules/'), '15%')

    def test_apply(self):
        r = self.client.post('/partners/', self.apply_data())
        self.assertContains(r, 'We got your application')
        p = Partner.objects.get()
        self.assertEqual((p.status, p.source, p.code, p.email, p.phone),
                         ('applied', 'website', 'MWILABANDA', 'mwila@example.com', '+260977123456'))
        self.assertEqual(sorted(m.to[0] for m in mail.outbox), ['mwila@example.com', 'pocketshopmarket@gmail.com'])
        r = self.client.post('/partners/', self.apply_data(code='other1'))
        self.assertContains(r, 'already have this email')

    def test_apply_needs_rules_and_a_free_code(self):
        PromoCode.objects.create(code='TAKEN', value=5)
        r = self.client.post('/partners/', self.apply_data(agree='', code='taken'))
        self.assertContains(r, 'agree to the rules')
        self.assertContains(r, 'already has this code')
        self.assertFalse(Partner.objects.exists())

    def test_honeypot_creates_nothing(self):
        self.client.post('/partners/', self.apply_data(website='http://spam'))
        self.assertFalse(Partner.objects.exists())

    def test_accept_invite(self):
        p = make_partner('INVITEE', status=Partner.INVITED)
        p.new_invite()
        p.save()
        url = f'/partners/invite/{p.invite_token}/'
        self.assertContains(self.client.get(url), 'INVITEE')
        r = self.client.post(url, {'name': 'Invitee', 'phone': '0966000000', 'payout_method': 'bank',
                                   'payout_details': 'Zanaco 123', 'agree': 'on'})
        p.refresh_from_db()
        self.assertRedirects(r, f'/partners/p/{p.access_token}/')
        self.assertEqual((p.status, p.payout_method, p.invite_token), ('approved', 'bank', None))
        self.assertIsNotNone(p.agreed_terms_at)
        self.assertEqual(mail.outbox[-1].to, [p.email])
        self.assertEqual(self.client.get(url).status_code, 410)  # used

    def test_expired_invite(self):
        p = make_partner('LATE', status=Partner.INVITED)
        p.new_invite()
        p.invite_expires_at = timezone.now() - timedelta(minutes=1)
        p.save()
        self.assertEqual(self.client.get(f'/partners/invite/{p.invite_token}/').status_code, 410)

    def test_partner_page_and_payment_request(self):
        p = make_partner()
        buyer = make_user('+260911111111')
        attach_referral(buyer, p.code)
        for _ in range(6):
            o = self.shop.order(buyer, service_fee=D('100'))
            o.status = 'delivered'
            o.save()
        url = f'/partners/p/{p.access_token}/'
        self.assertContains(self.client.get(url), 'K60.00')  # 6 x 10% of K100, still on hold

        self.client.post(url, {'action': 'request_payment'})
        self.assertFalse(PayoutRequest.objects.exists())  # still waiting the hold days

        PartnerEarning.objects.update(available_at=timezone.now() - timedelta(minutes=1))
        with self.captureOnCommitCallbacks(execute=True):
            r = self.client.post(url, {'action': 'request_payment'})
        self.assertRedirects(r, url + '?requested=1')
        payout = PayoutRequest.objects.get()
        self.assertEqual(payout.amount_requested, D('60.00'))
        self.assertEqual(mail.outbox[-1].to, ['pocketshopmarket@gmail.com'])

        self.client.post(url, {'action': 'request_payment'})
        self.assertEqual(PayoutRequest.objects.count(), 1)  # one open request at a time

    def test_partner_page_hidden_for_unknown_or_invited(self):
        self.assertEqual(self.client.get('/partners/p/nope/').status_code, 404)
        p = make_partner('NEW1', status=Partner.INVITED)
        self.assertEqual(self.client.get(f'/partners/p/{p.access_token}/').status_code, 404)

    def test_share_page(self):
        make_partner()
        r = self.client.get('/r/yomaps/')
        self.assertContains(r, 'Yoma invited you')
        self.assertContains(r, '15% off (up to K30)')
        self.assertEqual(self.client.get('/r/NOPE/').status_code, 404)


class PartnerAdminTests(TestCase):
    def setUp(self):
        self.staff = User.objects.create_superuser(phone_number='+260900000000', password='x', full_name='Staff')
        self.client.force_login(self.staff)

    def test_adding_a_partner_sends_an_invite(self):
        data = {
            'name': 'Chanda', 'email': 'chanda@example.com', 'phone': '', 'code': 'chanda',
            'status': 'invited', 'promotes_on': '', 'payout_method': '', 'payout_details': '',
            'commission_rate': '', 'staff_notes': '',
        }
        for prefix in ('payout_requests', 'earnings'):
            data.update({f'{prefix}-TOTAL_FORMS': '0', f'{prefix}-INITIAL_FORMS': '0',
                         f'{prefix}-MIN_NUM_FORMS': '0', f'{prefix}-MAX_NUM_FORMS': '1000'})
        r = self.client.post('/admin/promotions/partner/add/', data)
        self.assertEqual(r.status_code, 302)
        p = Partner.objects.get()
        self.assertEqual((p.code, p.source, p.status), ('CHANDA', 'admin', 'invited'))
        self.assertIsNotNone(p.invite_token)
        self.assertIn(f'/partners/invite/{p.invite_token}/', mail.outbox[0].body)

    def test_approve_action_and_mark_paid(self):
        p = make_partner('APPLY1', status=Partner.APPLIED)
        self.client.post('/admin/promotions/partner/', {'action': 'approve', '_selected_action': [p.pk]})
        p.refresh_from_db()
        self.assertEqual(p.status, 'approved')
        self.assertIn(p.access_token, mail.outbox[-1].body)

        payout = PayoutRequest.objects.create(partner=p, amount_requested=D('55'))
        r = self.client.post(f'/admin/promotions/payoutrequest/{payout.pk}/change/', {
            'status': 'paid', 'paid_amount': '', 'reference': 'MP123', 'staff_note': '',
        })
        self.assertEqual(r.status_code, 302)
        payout.refresh_from_db()
        self.assertEqual((payout.paid_amount, payout.reference), (D('55'), 'MP123'))
        self.assertIsNotNone(payout.paid_at)
        self.assertIn('We sent you K55', mail.outbox[-1].subject)

    def test_settings_page_opens(self):
        PromoSettings.get()
        self.assertEqual(self.client.get('/admin/promotions/promosettings/1/change/').status_code, 200)
        self.assertEqual(self.client.get('/admin/promotions/promocode/').status_code, 200)
        self.assertEqual(self.client.get('/admin/promotions/partner/').status_code, 200)


class StatementCommandTests(TestCase):
    def test_monthly_update_goes_to_approved_partners(self):
        make_partner()
        make_partner('PAUSED1', status=Partner.PAUSED)
        call_command('send_partner_statements', month=timezone.localdate().strftime('%Y-%m'))
        self.assertEqual([m.to for m in mail.outbox], [['yomaps@example.com']])
