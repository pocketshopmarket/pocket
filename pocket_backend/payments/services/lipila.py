import base64
import hashlib
import hmac
import logging
import time

import requests
from django.conf import settings

logger = logging.getLogger(__name__)


class LipilaError(Exception):
    """A Lipila call failed; the message is safe to show to a user."""


class LipilaUnreachable(LipilaError):
    """We could not talk to Lipila at all (as opposed to Lipila saying no)."""


class LipilaService:
    """
    Thin client for Lipila's collections API (https://docs.lipila.io/).

    Card collections are a hosted-redirect flow: initiate_card_payment()
    returns a cardRedirectionUrl where the buyer enters their card details
    on Lipila's own page — Pocket Shop never touches card numbers. The
    order is only ever settled from get_collection_status() or a verified
    webhook, the same "never trust the client" rule as the Lenco service.
    """

    @staticmethod
    def is_configured() -> bool:
        return bool(settings.LIPILA_API_KEY)

    @staticmethod
    def _headers(callback_url=None):
        headers = {
            'x-api-key': settings.LIPILA_API_KEY,
            'accept': 'application/json',
            'Content-Type': 'application/json',
        }
        if callback_url:
            headers['callbackUrl'] = callback_url
        return headers

    @staticmethod
    def _request(method, path, *, json=None, params=None, callback_url=None, timeout=30):
        if not LipilaService.is_configured():
            raise LipilaError('Card payments are not available right now.')
        url = f'{settings.LIPILA_BASE_URL}{path}'
        try:
            response = requests.request(
                method, url, json=json, params=params,
                headers=LipilaService._headers(callback_url), timeout=timeout,
            )
        except requests.RequestException as exc:
            logger.error('Lipila %s %s failed to connect: %s', method, path, exc)
            raise LipilaUnreachable('Could not reach the payment provider. Please try again.') from exc

        try:
            body = response.json()
        except ValueError:
            body = {}

        if response.status_code >= 400:
            message = body.get('message') or f'Payment provider error ({response.status_code})'
            logger.warning('Lipila %s %s -> %s: %s', method, path, response.status_code, message)
            raise LipilaError(message)
        return body

    # ── Card collections ─────────────────────────────────────────────────

    @staticmethod
    def initiate_card_payment(*, reference_id, amount, customer, narration, back_url,
                              account_number='', currency='ZMW', reference_data='', callback_url=None):
        """
        Starts a hosted card checkout. `customer` is
        {first_name, last_name, phone_number, email, city, country, address, zip}.
        Returns Lipila's response dict — the field you want is
        `cardRedirectionUrl`, the page to send the buyer's browser/WebView to.
        """
        data = LipilaService._request('POST', '/collections/card', callback_url=callback_url, json={
            'customerInfo': {
                'firstName': customer['first_name'],
                'lastName': customer['last_name'],
                'phoneNumber': customer['phone_number'],
                'email': customer['email'],
                'city': customer.get('city', ''),
                'country': customer.get('country', 'ZM'),
                'address': customer.get('address', ''),
                'zip': customer.get('zip', ''),
            },
            'collectionRequest': {
                'referenceId': str(reference_id),
                'amount': float(amount),
                'narration': narration,
                # Lipila's own example sends the customer's phone/email here,
                # not a card number — the card itself is entered on their
                # hosted page, never passed through this API.
                'accountNumber': account_number or customer.get('phone_number', ''),
                'currency': currency,
                'backUrl': back_url,
                'referenceData': reference_data,
            },
        })
        if not data.get('cardRedirectionUrl'):
            raise LipilaError('Could not start the card payment. Please try again.')
        return data

    @staticmethod
    def get_collection_status(reference_id):
        """
        Server-side truth for a payment, by the referenceId we gave at
        initiation. Never trust a redirect/callback outcome on its own.
        """
        return LipilaService._request(
            'GET', '/collections/check-status', params={'referenceId': str(reference_id)},
        )

    # ── Webhooks ─────────────────────────────────────────────────────────

    @staticmethod
    def verify_webhook_signature(headers, raw_body: bytes) -> bool:
        """
        Svix-style signing: HMAC-SHA256 of "{id}.{timestamp}.{body}", keyed
        by the base64-decoded webhook secret from the merchant dashboard's
        Webhook Secret tab. Fails closed: no secret configured, or a stale
        (>5 min old) timestamp, both reject. `webhook-signature` can carry
        multiple space-separated "v1,<sig>" values; any match is accepted.
        """
        secret = settings.LIPILA_WEBHOOK_SECRET
        if not secret:
            return False

        webhook_id = headers.get('webhook-id', '')
        webhook_timestamp = headers.get('webhook-timestamp', '')
        webhook_signature = headers.get('webhook-signature', '')
        if not (webhook_id and webhook_timestamp and webhook_signature):
            return False

        try:
            age = abs(int(time.time()) - int(webhook_timestamp))
        except ValueError:
            return False
        if age > 300:
            logger.warning('Lipila webhook rejected: timestamp too old (%ss)', age)
            return False

        try:
            key = base64.b64decode(secret)
        except Exception:
            logger.error('LIPILA_WEBHOOK_SECRET is not valid base64')
            return False

        signed_payload = f'{webhook_id}.{webhook_timestamp}'.encode() + b'.' + raw_body
        expected = 'v1,' + base64.b64encode(
            hmac.new(key, signed_payload, hashlib.sha256).digest()
        ).decode()

        return any(
            hmac.compare_digest(expected, candidate.strip())
            for candidate in webhook_signature.split(' ')
        )
