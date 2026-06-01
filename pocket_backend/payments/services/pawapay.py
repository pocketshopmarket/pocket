import requests
from django.conf import settings
import logging

logger = logging.getLogger(__name__)

class PawaPayService:
    @staticmethod
    def get_headers():
        return {
            'Authorization': f'Bearer {settings.PAWAPAY_JWT_TOKEN}',
            'Content-Type': 'application/json'
        }

    @staticmethod
    def get_deposit_status(deposit_id: str) -> dict | None:
        """Query PawaPay for the current status of a deposit by its ID."""
        url = f"{settings.PAWAPAY_BASE_URL}/deposits/{deposit_id}"
        try:
            response = requests.get(url, headers=PawaPayService.get_headers(), timeout=10)
            if response.status_code == 200:
                data = response.json()
                # PawaPay returns a list with one item
                if isinstance(data, list) and data:
                    return data[0]
                if isinstance(data, dict):
                    return data
            logger.warning("PawaPay deposit status check returned %s", response.status_code)
        except requests.RequestException as e:
            logger.error("Failed to check PawaPay deposit status: %s", e)
        return None

    @staticmethod
    def initiate_deposit(transaction):
        """
        Calls the PawaPay API to initiate a deposit (buyer paying).
        Takes a Transaction model instance.
        """
        url = f"{settings.PAWAPAY_BASE_URL}/deposits"
        
        # PawaPay strictly requires no '+' sign, leading '0', or whitespace (e.g. '260973714666')
        raw_phone = str(transaction.payer_number).strip().replace(" ", "").replace("-", "")
        if raw_phone.startswith("+"):
            raw_phone = raw_phone[1:]
        if raw_phone.startswith("0"):
            raw_phone = "260" + raw_phone[1:]
        elif not raw_phone.startswith("260") and len(raw_phone) == 9:
            raw_phone = "260" + raw_phone
        
        payload = {
            "depositId": str(transaction.transaction_id),
            "amount": str(transaction.amount),
            "currency": transaction.currency,
            "payer": {
                "type": "MMO",
                "accountDetails": {
                    "phoneNumber": raw_phone,
                    "provider": transaction.provider
                }
            },
            # Passes the Pocket order number for reconciliation in PawaPay dashboard
            "clientReferenceId": transaction.order.order_number,
            "customerMessage": "Pocket Order" 
        }

        try:
            response = requests.post(url, json=payload, headers=PawaPayService.get_headers(), timeout=30)

            # PawaPay returns 200 OK even if the deposit is REJECTED
            if response.status_code == 200:
                data = response.json()
                status = data.get('status')

                if status == 'ACCEPTED':
                    transaction.status = 'accepted'
                elif status == 'DUPLICATE_IGNORED':
                    transaction.status = 'duplicate_ignored'
                elif status == 'REJECTED':
                    transaction.status = 'failed'
                    reason = data.get('failureReason', {})
                    transaction.failure_message = reason.get('failureMessage', 'Unknown rejection')
                else:
                    transaction.status = 'failed'
                    transaction.failure_message = f"Unexpected PawaPay status: {status}"
                    logger.error("Unexpected PawaPay deposit status '%s': %s", status, data)

                transaction.save()
                return data
            else:
                logger.error("PawaPay API error %s: %s", response.status_code, response.text)
                transaction.status = 'failed'
                transaction.failure_message = f"HTTP {response.status_code}: {response.text[:200]}"
                transaction.save()
                return None

        except Exception as e:
            logger.error(
                "initiate_deposit failed: %s — %s — URL: %s",
                type(e).__name__, str(e), url, exc_info=True,
            )
            transaction.status = 'failed'
            transaction.failure_message = f"{type(e).__name__}: {str(e)[:120]}"
            transaction.save()
            return None

    @staticmethod
    def _apply_common_status(transaction, data):
        status_value = data.get('status')
        if status_value == 'ACCEPTED':
            transaction.status = 'accepted'
        elif status_value == 'DUPLICATE_IGNORED':
            transaction.status = 'duplicate_ignored'
        elif status_value == 'REJECTED':
            transaction.status = 'failed'
            reason = data.get('failureReason', {})
            transaction.failure_message = reason.get(
                'failureMessage', 'Unknown rejection'
            )
        transaction.save()
        return data

    @staticmethod
    def initiate_payout(transaction):
        """
        Calls the PawaPay API to initiate a payout.
        Uses transaction.payer_number as beneficiary account number.
        """
        url = f"{settings.PAWAPAY_BASE_URL}/payouts"
        
        # PawaPay strictly requires no '+' sign, leading '0', or whitespace (e.g. '260973714666')
        raw_phone = str(transaction.payer_number).strip().replace(" ", "").replace("-", "")
        if raw_phone.startswith("+"):
            raw_phone = raw_phone[1:]
        if raw_phone.startswith("0"):
            raw_phone = "260" + raw_phone[1:]
        elif not raw_phone.startswith("260") and len(raw_phone) == 9:
            raw_phone = "260" + raw_phone
        
        payload = {
            "payoutId": str(transaction.transaction_id),
            "amount": str(transaction.amount),
            "currency": transaction.currency,
            "recipient": {
                "type": "MMO",
                "accountDetails": {
                    "phoneNumber": raw_phone,
                    "provider": transaction.provider,
                },
            },
        }
        try:
            response = requests.post(
                url, json=payload, headers=PawaPayService.get_headers()
            )
            if response.status_code == 200:
                return PawaPayService._apply_common_status(
                    transaction, response.json()
                )
            logger.error("PawaPay payout API error: %s", response.text)
            transaction.status = 'failed'
            transaction.failure_message = (
                f"HTTP {response.status_code}: {response.text}"
            )
            transaction.save()
            return None
        except requests.RequestException as exc:
            logger.error("Failed to connect to PawaPay payout API: %s", str(exc))
            transaction.status = 'failed'
            transaction.failure_message = "Connection error"
            transaction.save()
            return None

    @staticmethod
    def initiate_refund(transaction):
        """
        Calls the PawaPay API to initiate a refund.
        """
        url = f"{settings.PAWAPAY_BASE_URL}/refunds"
        
        # Retrieve the original successful deposit to link this refund to
        from payments.models import Transaction as TxModel
        deposit_tx = TxModel.objects.filter(
            order=transaction.order,
            transaction_type='deposit',
            status='completed',
        ).first()

        if not deposit_tx:
            logger.error("No completed deposit found for order %s. Cannot initiate refund.", transaction.order.order_number)
            transaction.status = 'failed'
            transaction.failure_message = "No completed deposit found to refund."
            transaction.save()
            return None

        payload = {
            "refundId": str(transaction.transaction_id),
            "depositId": str(deposit_tx.transaction_id),
            "amount": str(transaction.amount),
            "currency": transaction.currency,
        }
        try:
            response = requests.post(
                url, json=payload, headers=PawaPayService.get_headers()
            )
            if response.status_code == 200:
                return PawaPayService._apply_common_status(
                    transaction, response.json()
                )
            logger.error("PawaPay refund API error: %s", response.text)
            transaction.status = 'failed'
            transaction.failure_message = (
                f"HTTP {response.status_code}: {response.text}"
            )
            transaction.save()
            return None
        except requests.RequestException as exc:
            logger.error("Failed to connect to PawaPay refund API: %s", str(exc))
            transaction.status = 'failed'
            transaction.failure_message = "Connection error"
            transaction.save()
            return None
