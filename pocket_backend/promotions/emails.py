import logging
import re

from django.conf import settings
from django.core.mail import EmailMultiAlternatives
from django.template.loader import render_to_string
from django.utils.html import strip_tags

from .models import PromoSettings

logger = logging.getLogger(__name__)


def site_url(path=''):
    return f'{settings.SITE_URL}{path}'


def partner_page_url(partner):
    return site_url(f'/partners/p/{partner.access_token}/')


def share_url(partner):
    return site_url(f'/r/{partner.code}/')


def _send(to, subject, template, context) -> bool:
    context = {
        'site_url': settings.SITE_URL,
        'logo_url': site_url('/static/portal/images/logo.jpg'),
        **context,
    }
    html = render_to_string(f'promotions/email/{template}.html', context)
    text = _plain_text(html)
    msg = EmailMultiAlternatives(subject, text, settings.DEFAULT_FROM_EMAIL, [to])
    msg.attach_alternative(html, 'text/html')
    try:
        msg.send()
        return True
    except Exception:
        logger.exception('Email "%s" to %s failed', subject, to)
        return False


_LINK = re.compile(r'<a\s[^>]*href="([^"]+)"[^>]*>(.*?)</a>', re.S | re.I)


def _plain_text(html):
    """Text version for mail apps that don't show HTML. Buttons keep their address."""
    def link(m):
        url, label = m.group(1), strip_tags(m.group(2)).strip()
        return url if label in ('', url) else f'{label}: {url}'
    text = strip_tags(_LINK.sub(link, html))
    lines = [line.strip() for line in text.splitlines()]
    return re.sub(r'\n{3,}', '\n\n', '\n'.join(lines)).strip() + '\n'


def _staff():
    return PromoSettings.get().staff_email


def send_invite(partner):
    return _send(partner.email, "You're invited to the Pocket Shop partner program", 'invite', {
        'partner': partner,
        'accept_url': site_url(f'/partners/invite/{partner.invite_token}/'),
    })


def send_application_received(partner):
    _send(_staff(), f'New partner application: {partner.name} ({partner.code})', 'staff_new_application', {
        'partner': partner,
        'admin_url': site_url(f'/admin/promotions/partner/{partner.pk}/change/'),
    })
    return _send(partner.email, 'We got your Pocket Shop partner application', 'application_received', {
        'partner': partner,
    })


def send_approved(partner):
    return _send(partner.email, "You're a Pocket Shop partner", 'approved', {
        'partner': partner,
        'partner_url': partner_page_url(partner),
        'share_url': share_url(partner),
        'rate_percent': percent(partner.effective_rate()),
        'window_days': PromoSettings.get().partner_window_days,
    })


def send_rejected(partner):
    return _send(partner.email, 'Your Pocket Shop partner application', 'rejected', {'partner': partner})


def send_statement(partner, period_label, stats, balances):
    return _send(partner.email, f'Your Pocket Shop partner update: {period_label}', 'statement', {
        'partner': partner,
        'period_label': period_label,
        'stats': stats,
        'balances': balances,
        'partner_url': partner_page_url(partner),
        'min_payout': PromoSettings.get().partner_min_payout,
    })


def send_payout_requested(payout):
    return _send(_staff(), f'Payment request: {payout.partner.name} K{payout.amount_requested}', 'staff_payout_requested', {
        'payout': payout,
        'partner': payout.partner,
        'admin_url': site_url(f'/admin/promotions/payoutrequest/{payout.pk}/change/'),
    })


def send_payout_sent(payout):
    return _send(payout.partner.email, f'We sent you K{payout.paid_amount}', 'payout_sent', {
        'payout': payout,
        'partner': payout.partner,
        'partner_url': partner_page_url(payout.partner),
    })


def percent(rate):
    v = rate * 100
    return v.quantize(1) if v == v.to_integral() else v.normalize()
