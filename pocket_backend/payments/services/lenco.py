import hashlib
import hmac
import logging

import requests
from django.conf import settings

logger = logging.getLogger(__name__)


class LencoError(Exception):
    """A Lenco call failed; the message is safe to show to a user."""


class LencoService:
    """
    Thin client for Lenco's v2 API (https://lenco-api.readme.io/v2.0).

    Every response is {status, message, data, meta}. Methods return the
    `data` payload on success and raise LencoError (with Lenco's own
    message where it gave one) otherwise.
    """

    @staticmethod
    def is_configured() -> bool:
        return bool(settings.LENCO_API_TOKEN)

    @staticmethod
    def _headers():
        return {
            'Authorization': f'Bearer {settings.LENCO_API_TOKEN}',
            'Content-Type': 'application/json',
        }

    @staticmethod
    def _request(method, path, *, json=None, timeout=30):
        if not LencoService.is_configured():
            raise LencoError('Card and bank payments are not available right now.')
        url = f'{settings.LENCO_BASE_URL}{path}'
        try:
            response = requests.request(
                method, url, json=json, headers=LencoService._headers(), timeout=timeout,
            )
        except requests.RequestException as exc:
            logger.error('Lenco %s %s failed to connect: %s', method, path, exc)
            raise LencoError('Could not reach the payment provider. Please try again.') from exc

        try:
            body = response.json()
        except ValueError:
            body = {}

        if response.status_code >= 400 or not body.get('status', False):
            message = body.get('message') or f'Payment provider error ({response.status_code})'
            logger.warning('Lenco %s %s -> %s: %s', method, path, response.status_code, message)
            raise LencoError(message)
        return body.get('data')

    # ── Banks ────────────────────────────────────────────────────────────

    @staticmethod
    def get_banks(country='zm'):
        """[{id, name, country}, ...] of banks Lenco can pay into."""
        data = LencoService._request('GET', f'/banks?country={country}')
        return data or []

    @staticmethod
    def resolve_bank_account(account_number, bank_id, country='zm'):
        """
        Look up the account holder's name for a bank account.
        Returns {'account_name', 'account_number', 'bank': {id, name, country}}.
        """
        data = LencoService._request('POST', '/resolve/bank-account', json={
            'accountNumber': str(account_number).strip(),
            'bankId': str(bank_id).strip(),
            'country': country,
        })
        if not data:
            raise LencoError('Account details were not found.')
        return {
            'account_name': data.get('accountName') or '',
            'account_number': data.get('accountNumber') or str(account_number).strip(),
            'bank': data.get('bank') or {},
        }

    # ── Card collections ─────────────────────────────────────────────────

    @staticmethod
    def get_collection_status(reference):
        """
        Server-side truth for a card payment, by the reference we gave the
        widget. Never trust the widget's onSuccess callback on its own.
        """
        return LencoService._request('GET', f'/collections/status/{reference}')

    # ── Bank payouts ─────────────────────────────────────────────────────

    @staticmethod
    def initiate_bank_transfer(*, reference, amount, account_number, bank_id,
                               narration='Pocket Shop payout', country='zm'):
        """Pay out of the platform's Lenco account into a bank account."""
        if not settings.LENCO_ACCOUNT_ID:
            raise LencoError('Bank payouts are not available right now.')
        return LencoService._request('POST', '/transfers/bank-account', json={
            'accountId': settings.LENCO_ACCOUNT_ID,
            'amount': float(amount),
            'reference': str(reference),
            'narration': narration,
            'accountNumber': str(account_number).strip(),
            'bankId': str(bank_id).strip(),
            'country': country,
        })

    @staticmethod
    def get_transfer_status(reference):
        return LencoService._request('GET', f'/transfers/status/{reference}')

    # ── Webhooks ─────────────────────────────────────────────────────────

    @staticmethod
    def verify_webhook_signature(raw_body: bytes, signature: str) -> bool:
        """
        X-Lenco-Signature is HMAC-SHA512 of the request body, keyed by the
        SHA256 hash (hex) of the API token. Fails closed: with no token
        configured, nothing verifies.
        """
        token = settings.LENCO_API_TOKEN
        if not token or not signature:
            return False
        key = hashlib.sha256(token.encode('utf-8')).hexdigest()
        expected = hmac.new(key.encode('utf-8'), raw_body, hashlib.sha512).hexdigest()
        return hmac.compare_digest(expected.lower(), signature.strip().lower())
