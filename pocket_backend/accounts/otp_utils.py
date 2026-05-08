"""Shared OTP challenge validation (attempts, expiry, code match)."""

from rest_framework import serializers

from .models import PhoneOTP


def assert_phone_otp_valid(phone_number: str, otp_code: str) -> PhoneOTP:
    """
    Validates the latest unverified OTP for this phone.
    On failure raises ValidationError with `otp_code` key for DRF.
    On success returns the PhoneOTP row (caller must set is_verified).
    """
    latest_unverified_otp = (
        PhoneOTP.objects.filter(phone_number=phone_number, is_verified=False)
        .order_by('-created_at')
        .first()
    )

    if not latest_unverified_otp:
        raise serializers.ValidationError(
            {'otp_code': ['Invalid or expired code. Request a new OTP.']}
        )

    if latest_unverified_otp.attempts >= 5:
        raise serializers.ValidationError(
            {'otp_code': ['Too many attempts. Please request a new OTP.']}
        )

    if latest_unverified_otp.is_expired():
        raise serializers.ValidationError(
            {'otp_code': ['This code has expired. Request a new OTP.']}
        )

    if latest_unverified_otp.otp_code != otp_code:
        latest_unverified_otp.attempts += 1
        latest_unverified_otp.save(update_fields=['attempts'])
        remaining_attempts = max(0, 5 - latest_unverified_otp.attempts)
        if remaining_attempts == 0:
            raise serializers.ValidationError(
                {'otp_code': ['Too many attempts. Please request a new OTP.']}
            )
        raise serializers.ValidationError(
            {
                'otp_code': [
                    f'Invalid code. {remaining_attempts} attempt(s) remaining.'
                ]
            }
        )

    return latest_unverified_otp
