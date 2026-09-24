import hashlib
import hmac
from unittest import mock

from django.test import SimpleTestCase, TestCase, override_settings
from rest_framework.test import APITestCase

from accounts.models import User

from .models import PayoutBankAccount
from .services.lenco import LencoError, LencoService

BANK = {'id': '002', 'name': 'Absa Bank', 'country': 'zm'}


class LencoWebhookSignatureTests(SimpleTestCase):
    body = b'{"event":"collection.successful","data":{"reference":"abc"}}'

    def _sign(self, token, body):
        key = hashlib.sha256(token.encode()).hexdigest()
        return hmac.new(key.encode(), body, hashlib.sha512).hexdigest()

    @override_settings(LENCO_API_TOKEN='secret-token')
    def test_valid_signature_verifies(self):
        sig = self._sign('secret-token', self.body)
        self.assertTrue(LencoService.verify_webhook_signature(self.body, sig))
        self.assertTrue(LencoService.verify_webhook_signature(self.body, sig.upper()))

    @override_settings(LENCO_API_TOKEN='secret-token')
    def test_tampered_body_or_wrong_key_fails(self):
        sig = self._sign('secret-token', self.body)
        self.assertFalse(LencoService.verify_webhook_signature(self.body + b' ', sig))
        self.assertFalse(LencoService.verify_webhook_signature(self.body, self._sign('other', self.body)))
        self.assertFalse(LencoService.verify_webhook_signature(self.body, ''))

    @override_settings(LENCO_API_TOKEN='')
    def test_fails_closed_when_not_configured(self):
        self.assertFalse(LencoService.verify_webhook_signature(self.body, self._sign('', self.body)))


class LencoServiceUnconfiguredTests(SimpleTestCase):
    @override_settings(LENCO_API_TOKEN='')
    def test_calls_refuse_without_token(self):
        self.assertFalse(LencoService.is_configured())
        with self.assertRaises(LencoError):
            LencoService.get_banks()


@override_settings(LENCO_API_TOKEN='t')
class BankAccountEndpointTests(APITestCase):
    def setUp(self):
        self.seller = User.objects.create_user(
            phone_number='+260911111111', password='x', full_name='Seller', role='seller')
        self.buyer = User.objects.create_user(
            phone_number='+260922222222', password='x', full_name='Buyer', role='buyer')
        self.resolve = mock.patch.object(
            LencoService, 'resolve_bank_account',
            return_value={'account_name': 'BEATA JEAN', 'account_number': '9130000000000', 'bank': BANK},
        )
        self.resolve_mock = self.resolve.start()
        self.addCleanup(self.resolve.stop)

    def _save(self, number='9130000000000', **extra):
        return self.client.post(
            '/api/payments/bank-accounts/',
            {'bank_id': '002', 'account_number': number, **extra},
            format='json',
        )

    def test_buyers_and_guests_are_refused(self):
        self.assertEqual(self.client.get('/api/payments/bank-accounts/').status_code, 401)
        self.client.force_authenticate(self.buyer)
        self.assertEqual(self.client.get('/api/payments/bank-accounts/').status_code, 403)

    def test_resolve_returns_name_and_stores_nothing(self):
        self.client.force_authenticate(self.seller)
        r = self.client.post(
            '/api/payments/bank-accounts/resolve/',
            {'bank_id': '002', 'account_number': '9130000000000'}, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json(), {'account_name': 'BEATA JEAN', 'bank_name': 'Absa Bank'})
        self.assertEqual(PayoutBankAccount.objects.count(), 0)

    def test_resolve_rejects_bad_input_without_calling_lenco(self):
        self.client.force_authenticate(self.seller)
        for body in ({'bank_id': '', 'account_number': '9130000000000'},
                     {'bank_id': '002', 'account_number': 'abc'},
                     {'bank_id': '002', 'account_number': '123'}):
            r = self.client.post('/api/payments/bank-accounts/resolve/', body, format='json')
            self.assertEqual(r.status_code, 400)
        self.resolve_mock.assert_not_called()

    def test_resolve_surfaces_lenco_error(self):
        self.resolve_mock.side_effect = LencoError('Account details was not found')
        self.client.force_authenticate(self.seller)
        r = self.client.post(
            '/api/payments/bank-accounts/resolve/',
            {'bank_id': '002', 'account_number': '9130000000000'}, format='json')
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.json()['error'], 'Account details was not found')

    def test_saved_name_comes_from_the_bank_not_the_client(self):
        self.client.force_authenticate(self.seller)
        r = self._save(account_name='SOMEONE ELSE')
        self.assertEqual(r.status_code, 201)
        self.assertEqual(r.json()['account_name'], 'BEATA JEAN')
        self.assertEqual(r.json()['account_number_masked'], '••••0000')
        self.assertNotIn('9130000000000', r.content.decode())
        self.assertTrue(r.json()['is_default'])

    def test_second_account_is_not_default_and_duplicates_are_refused(self):
        self.client.force_authenticate(self.seller)
        self._save('9130000000000')
        second = self._save('9130000000001')
        self.assertFalse(second.json()['is_default'])
        self.assertEqual(self._save('9130000000000').status_code, 400)

    def test_account_limit(self):
        self.client.force_authenticate(self.seller)
        for n in range(3):
            self.assertEqual(self._save(f'913000000000{n}').status_code, 201)
        self.assertEqual(self._save('9130000000009').status_code, 400)

    def test_delete_promotes_a_new_default_and_is_owner_only(self):
        self.client.force_authenticate(self.seller)
        first = self._save('9130000000000').json()
        second = self._save('9130000000001').json()
        other = User.objects.create_user(
            phone_number='+260933333333', password='x', full_name='Other', role='delivery')
        self.client.force_authenticate(other)
        self.assertEqual(self.client.delete(f'/api/payments/bank-accounts/{first["id"]}/').status_code, 404)
        self.client.force_authenticate(self.seller)
        self.assertEqual(self.client.delete(f'/api/payments/bank-accounts/{first["id"]}/').status_code, 204)
        self.assertTrue(PayoutBankAccount.objects.get(pk=second['id']).is_default)

    def test_make_default_switches_exactly_one(self):
        self.client.force_authenticate(self.seller)
        first = self._save('9130000000000').json()
        second = self._save('9130000000001').json()
        r = self.client.post(f'/api/payments/bank-accounts/{second["id"]}/default/')
        self.assertEqual(r.status_code, 200)
        defaults = list(PayoutBankAccount.objects.filter(user=self.seller, is_default=True))
        self.assertEqual([a.id for a in defaults], [second['id']])
        self.assertFalse(PayoutBankAccount.objects.get(pk=first['id']).is_default)
