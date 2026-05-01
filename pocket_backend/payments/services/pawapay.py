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
    def initiate_deposit(transaction):
        """
        Calls the PawaPay API to initiate a deposit (buyer paying).
        Takes a Transaction model instance.
        """
        url = f"{settings.PAWAPAY_BASE_URL}/deposits"
        
        # PawaPay strictly requires no '+' sign or whitespace (e.g. '260973714666')
        raw_phone = transaction.payer_number.replace('+', '') if transaction.payer_number else ""
        
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
            response = requests.post(url, json=payload, headers=PawaPayService.get_headers())
            
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
                    # Extract the exact reason for rejection (e.g. Invalid Amount)
                    reason = data.get('failureReason', {})
                    transaction.failure_message = reason.get('failureMessage', 'Unknown rejection')
                
                transaction.save()
                return data
            else:
                # Handle unexpected HTTP errors (e.g. 401 Unauthorized, 500 Server Error)
                logger.error(f"PawaPay API error: {response.text}")
                transaction.status = 'failed'
                transaction.failure_message = f"HTTP {response.status_code}: {response.text}"
                transaction.save()
                return None

        except requests.RequestException as e:
            # Handle cases where the server can't connect to internet at all
            logger.error(f"Failed to connect to PawaPay: {str(e)}")
            transaction.status = 'failed'
            transaction.failure_message = "Connection error"
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
        raw_phone = transaction.payer_number.replace('+', '') if transaction.payer_number else ""
        
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
            "clientReferenceId": transaction.order.order_number,
            "customerMessage": "Pocket payout",
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
        raw_phone = transaction.payer_number.replace('+', '') if transaction.payer_number else ""
        
        payload = {
            "refundId": str(transaction.transaction_id),
            "amount": str(transaction.amount),
            "currency": transaction.currency,
            "recipient": {
                "type": "MMO",
                "accountDetails": {
                    "phoneNumber": raw_phone,
                    "provider": transaction.provider,
                },
            },
            "clientReferenceId": transaction.order.order_number,
            "customerMessage": "Pocket refund",
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
