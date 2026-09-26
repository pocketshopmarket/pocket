"""
Small pure helpers shared by the card-refund and payout code: mobile money
network detection, refund due dates, and account-name matching.
"""
import re
from datetime import timedelta

from accounts.phone_utils import normalize_zambia_phone_to_e164

# National prefix (the two digits after 260) -> Lenco operator key.
_PREFIX_TO_OPERATOR = {
    '96': 'mtn', '76': 'mtn',
    '97': 'airtel', '77': 'airtel', '57': 'airtel',
    '95': 'zamtel', '75': 'zamtel', '55': 'zamtel',
}

OPERATOR_LABELS = {'mtn': 'MTN MoMo', 'airtel': 'Airtel Money', 'zamtel': 'Zamtel Kwacha'}

# The PawaPay provider codes the rest of the payments code already keys off.
OPERATOR_TO_PROVIDER = {
    'mtn': 'MTN_MOMO_ZMB',
    'airtel': 'AIRTEL_OAPI_ZMB',
    'zamtel': 'ZAMTEL_MONEY_ZMB',
}


class InvalidMobileNumber(ValueError):
    pass


def parse_mobile_money_number(raw):
    """
    Returns (e164, operator) for a Zambian mobile money number, e.g.
    ('+260961111111', 'mtn'). Unlike PawaPay's best-effort provider guess,
    this is strict: a number we can't place on MTN/Airtel/Zamtel is refused,
    because a refund sent to the wrong network can't be recovered.
    """
    try:
        e164 = normalize_zambia_phone_to_e164(str(raw or ''))
    except Exception as exc:
        raise InvalidMobileNumber('Enter a valid Zambian mobile number.') from exc
    if not re.fullmatch(r'\+260\d{9}', e164 or ''):
        raise InvalidMobileNumber('Enter a valid Zambian mobile number.')
    operator = _PREFIX_TO_OPERATOR.get(e164[4:6])
    if not operator:
        raise InvalidMobileNumber('That number is not on MTN, Airtel or Zamtel.')
    return e164, operator


def add_business_days(start, days):
    """`start` plus N Monday–Friday days (public holidays are not modelled)."""
    current = start
    remaining = int(days)
    while remaining > 0:
        current += timedelta(days=1)
        if current.weekday() < 5:
            remaining -= 1
    return current


def _tokens(name):
    return {t for t in re.split(r'[^a-z0-9]+', (name or '').lower()) if len(t) > 1}


def names_match(account_name, *candidates):
    """
    True when the bank's account holder name plausibly belongs to the same
    person/business as one of `candidates`: it shares at least two name
    parts with it (or every part, for a one-word candidate). Order and
    middle names don't matter, so "KAUNDA BENSON" matches "Benson Kaunda".
    """
    account = _tokens(account_name)
    if not account:
        return False
    for candidate in candidates:
        wanted = _tokens(candidate)
        if not wanted:
            continue
        if len(account & wanted) >= min(2, len(wanted)):
            return True
    return False
