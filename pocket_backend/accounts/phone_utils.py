"""Zambian mobile normalization and validation (+260 / local 0…)."""

from rest_framework import serializers

# Common Zambian mobile prefixes (after leading 0).
ZM_MOBILE_PREFIXES = frozenset({'097', '096', '095', '077', '076', '075', '057'})


def digits_only(phone: str) -> str:
    return ''.join(c for c in (phone or '') if c.isdigit())


def normalize_zambia_phone_to_e164(phone: str) -> str:
    """
    Accept +260…, 0XXXXXXXXX, or 9-digit national (no leading 0).
    Returns E.164 like +260971234567.
    """
    d = digits_only(phone)
    if not d:
        raise serializers.ValidationError('Phone number is required.')

    local_10: str | None = None
    if d.startswith('260') and len(d) >= 12:
        rest = d[3:]
        if len(rest) == 9 and rest.isdigit():
            local_10 = '0' + rest
    elif d.startswith('0') and len(d) == 10:
        local_10 = d
    elif len(d) == 9 and d[0] in '957':
        local_10 = '0' + d

    if local_10 is None or len(local_10) != 10 or not local_10.startswith('0'):
        raise serializers.ValidationError(
            'Enter a valid Zambian mobile number (e.g. 097xxxxxxx or +26097xxxxxxx).'
        )

    prefix = local_10[:3]
    if prefix not in ZM_MOBILE_PREFIXES:
        raise serializers.ValidationError(
            'Use a supported Zambian mobile prefix: 097, 096, 095, 077, 076, 075, or 057.'
        )

    national_9 = local_10[1:]
    return '+260' + national_9
