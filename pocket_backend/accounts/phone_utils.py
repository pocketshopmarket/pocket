"""
Country-aware mobile normalization and validation.

Each supported country has its own calling code and set of valid mobile
prefixes, looked up by Country.code. Only Zambia's rules are defined today
(_COUNTRY_PHONE_RULES) — adding a country here is what widens phone
validation, not a rewrite of the function below. Every existing call site
keeps working unchanged, since 'ZM' is the default.
"""

from rest_framework import serializers

# Per-country: calling code (no leading '+'), valid prefixes after a
# leading 0, and a human label used in validation messages.
_COUNTRY_PHONE_RULES = {
    'ZM': {
        'calling_code': '260',
        'prefixes': frozenset({'097', '096', '095', '077', '076', '075', '057'}),
        'label': 'Zambian',
    },
}

# Kept for backward compatibility — anything importing this name directly
# still gets Zambia's prefix set.
ZM_MOBILE_PREFIXES = _COUNTRY_PHONE_RULES['ZM']['prefixes']


def digits_only(phone: str) -> str:
    return ''.join(c for c in (phone or '') if c.isdigit())


def normalize_zambia_phone_to_e164(phone: str, country_code: str = 'ZM') -> str:
    """
    Accept +<calling_code>…, 0XXXXXXXXX, or 9-digit national (no leading 0),
    for whichever country's rules are given via country_code. Returns
    E.164, e.g. +260971234567.

    country_code defaults to 'ZM' so every existing caller keeps working
    unchanged. Passing a country with no entry in _COUNTRY_PHONE_RULES
    raises a clear error rather than silently falling back to Zambia's
    rules — there's no such thing as "close enough" for a phone validator.
    """
    rules = _COUNTRY_PHONE_RULES.get(country_code)
    if rules is None:
        raise serializers.ValidationError(
            f'Phone number validation for country "{country_code}" is not configured yet.'
        )

    calling_code = rules['calling_code']
    prefixes = rules['prefixes']
    # National significant number always starts with one of these digits —
    # derived from the prefix table (each prefix's middle digit) rather than
    # hardcoded separately, so it can never drift out of sync with `prefixes`.
    leading_digits = {p[1] for p in prefixes}

    d = digits_only(phone)
    if not d:
        raise serializers.ValidationError('Phone number is required.')

    local_10: str | None = None
    if d.startswith(calling_code) and len(d) >= len(calling_code) + 9:
        rest = d[len(calling_code):]
        if len(rest) == 9 and rest.isdigit():
            local_10 = '0' + rest
    elif d.startswith('0') and len(d) == 10:
        local_10 = d
    elif len(d) == 9 and d[0] in leading_digits:
        local_10 = '0' + d

    if local_10 is None or len(local_10) != 10 or not local_10.startswith('0'):
        raise serializers.ValidationError(
            f'Enter a valid {rules["label"]} mobile number '
            f'(e.g. 097xxxxxxx or +{calling_code}97xxxxxxx).'
        )

    prefix = local_10[:3]
    if prefix not in prefixes:
        raise serializers.ValidationError(
            f'Use a supported {rules["label"]} mobile prefix: {", ".join(sorted(prefixes))}.'
        )

    national_9 = local_10[1:]
    return f'+{calling_code}' + national_9
