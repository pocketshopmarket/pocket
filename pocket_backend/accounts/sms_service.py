"""
Africa's Talking SMS service wrapper.

Usage:
    from accounts.sms_service import send_otp_sms
    send_otp_sms('+260971234567', '482910')

In development (AFRICAS_TALKING_USERNAME == 'sandbox'), messages are sent to
the AT Sandbox and also printed to the console for easy debugging.
In production, set real credentials via environment variables:
    AFRICAS_TALKING_USERNAME=<your_AT_username>
    AFRICAS_TALKING_API_KEY=<your_AT_api_key>
    AFRICAS_TALKING_SENDER_ID=<your_sender_id>   # optional
"""

import logging

from django.conf import settings

logger = logging.getLogger(__name__)

# Initialise AT SDK once at import time so we don't pay the cost per request.
_sms = None


def _get_sms_client():
    global _sms
    if _sms is not None:
        return _sms

    username = getattr(settings, 'AFRICAS_TALKING_USERNAME', 'sandbox')
    api_key = getattr(settings, 'AFRICAS_TALKING_API_KEY', '')

    if not api_key:
        logger.warning(
            '[SMS] AFRICAS_TALKING_API_KEY is not set — OTPs will only be '
            'printed to the console.'
        )
        return None

    try:
        import africastalking
        africastalking.initialize(username, api_key)
        _sms = africastalking.SMS
        logger.info('[SMS] Africa\'s Talking SDK initialised (username=%s)', username)
    except Exception as exc:
        logger.error('[SMS] Failed to initialise Africa\'s Talking SDK: %s', exc)
        return None

    return _sms


def send_sms(phone_number: str, message: str) -> bool:
    """
    Send a plain SMS message via Africa's Talking.

    Parameters
    ----------
    phone_number : str
        Recipient in E.164 format, e.g. '+260971234567'.
    message : str
        The text body to send.

    Returns
    -------
    bool
        True if the message was accepted by AT, False otherwise.
    """
    sms = _get_sms_client()
    sender_id = getattr(settings, 'AFRICAS_TALKING_SENDER_ID', '') or None

    if sms is None:
        # Graceful fallback: print to console
        logger.info('[SMS FALLBACK] To %s: %s', phone_number, message)
        print(f'[SMS FALLBACK] To {phone_number}: {message}', flush=True)
        return False

    try:
        kwargs = {'message': message, 'recipients': [phone_number]}
        if sender_id:
            kwargs['sender_id'] = sender_id

        response = sms.send(**kwargs)
        recipients = response.get('SMSMessageData', {}).get('Recipients', [])

        if recipients:
            status = recipients[0].get('status', '')
            cost = recipients[0].get('cost', '')
            logger.info(
                '[SMS] Sent to %s | status=%s | cost=%s',
                phone_number, status, cost,
            )
            # AT marks success as "Success" in the status field
            return status == 'Success'

        logger.warning('[SMS] No recipients in AT response: %s', response)
        return False

    except Exception as exc:
        logger.error('[SMS] Failed to send to %s: %s', phone_number, exc)
        return False


def send_otp_sms(phone_number: str, otp_code: str) -> bool:
    """
    Send an OTP verification code via SMS.

    Parameters
    ----------
    phone_number : str  E.164, e.g. '+260971234567'
    otp_code     : str  6-digit code, e.g. '482910'
    """
    message = f'Your Pocket Shop verification code is: {otp_code}. Valid for 10 minutes. Do not share this code.'
    return send_sms(phone_number, message)


def send_password_reset_sms(phone_number: str, otp_code: str) -> bool:
    """Send a password-reset OTP via SMS."""
    message = f'Your Pocket Shop password reset code is: {otp_code}. Valid for 10 minutes. Ignore if you did not request this.'
    return send_sms(phone_number, message)


def send_payment_method_verification_sms(phone_number: str, otp_code: str) -> bool:
    """Send a payment-method verification OTP via SMS."""
    message = f'Your Pocket Shop payment method verification code is: {otp_code}. Valid for 10 minutes.'
    return send_sms(phone_number, message)
