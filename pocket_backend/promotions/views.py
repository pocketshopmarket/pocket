"""Website pages for the partner program. The app's endpoints live in api_views.py."""
from django.core.cache import cache
from django.db import transaction
from django.http import Http404
from django.shortcuts import redirect, render
from django.urls import reverse
from django.utils import timezone
from django.views.decorators.http import require_http_methods

from . import emails
from .forms import AcceptInviteForm, ApplyForm
from .models import Partner, PayoutRequest, PromoSettings
from .services import find_partner_code, partner_stats, suggest_code

APPLY_LIMIT = 5          # applications per IP per hour
APPLY_WINDOW = 60 * 60


def _client_ip(request):
    forwarded = request.META.get('HTTP_X_FORWARDED_FOR', '')
    return forwarded.split(',')[0].strip() if forwarded else request.META.get('REMOTE_ADDR', '')


def _program(ps=None):
    """The numbers every partner page shows, straight from the admin settings."""
    ps = ps or PromoSettings.get()
    return {
        'rate_percent': emails.percent(ps.partner_commission_rate),
        'window_days': ps.partner_window_days,
        'hold_days': ps.partner_hold_days,
        'min_payout': _kwacha(ps.partner_min_payout),
        'welcome': _welcome_text(ps),
    }


def _kwacha(value):
    """50.00 -> '50', 12.50 -> '12.50' (settings amounts read better without .00)."""
    return f'{value:.0f}' if value == value.to_integral() else f'{value:.2f}'


def _welcome_text(ps):
    if not ps.welcome_enabled or ps.welcome_discount_value <= 0:
        return ''
    value = ps.welcome_discount_value
    value = value.quantize(1) if value == value.to_integral() else value.normalize()
    if ps.welcome_discount_type == 'fixed':
        return f'K{_kwacha(ps.welcome_discount_value)} off'
    cap = ''
    if ps.welcome_max_discount is not None:
        cap = f' (up to K{_kwacha(ps.welcome_max_discount)})'
    return f'{value}% off{cap}'


@require_http_methods(['GET', 'POST'])
def landing(request):
    form = ApplyForm(request.POST or None)
    if request.method == 'POST':
        if request.POST.get('website'):
            return render(request, 'promotions/site/applied.html', {'email': ''})
        key = f'partner-apply:{_client_ip(request)}'
        tries = cache.get(key, 0)
        if tries >= APPLY_LIMIT:
            form.add_error(None, 'Too many applications from this connection. Please try again in an hour.')
        elif form.is_valid():
            cache.set(key, tries + 1, APPLY_WINDOW)
            d = form.cleaned_data
            partner = Partner.objects.create(
                name=d['name'], email=d['email'], phone=d['phone'], promotes_on=d['promotes_on'],
                code=d['code'] or suggest_code(d['name']),
                payout_method=d['payout_method'], payout_details=d['payout_details'],
                status=Partner.APPLIED, source='website', agreed_terms_at=timezone.now(),
            )
            emails.send_application_received(partner)
            return render(request, 'promotions/site/applied.html', {'email': partner.email})
    return render(request, 'promotions/site/landing.html', {'form': form, **_program()})


def rules(request):
    return render(request, 'promotions/site/rules.html', _program())


@require_http_methods(['GET', 'POST'])
def accept_invite(request, token):
    partner = Partner.objects.filter(invite_token=token).first()
    if partner is None or partner.status != Partner.INVITED or (
        partner.invite_expires_at and partner.invite_expires_at < timezone.now()
    ):
        return render(request, 'promotions/site/invite_invalid.html', status=410)

    initial = {
        'name': partner.name, 'phone': partner.phone,
        'payout_method': partner.payout_method, 'payout_details': partner.payout_details,
    }
    form = AcceptInviteForm(request.POST or None, initial=initial)
    if request.method == 'POST' and form.is_valid():
        d = form.cleaned_data
        now = timezone.now()
        partner.name = d['name']
        partner.phone = d['phone']
        partner.payout_method = d['payout_method']
        partner.payout_details = d['payout_details']
        partner.status = Partner.APPROVED
        partner.agreed_terms_at = now
        partner.approved_at = now
        partner.invite_token = None
        partner.invite_expires_at = None
        partner.save()
        emails.send_approved(partner)
        return redirect('promotions:partner-page', token=partner.access_token)
    return render(request, 'promotions/site/invite.html', {'form': form, 'partner': partner, **_program()})


@require_http_methods(['GET', 'POST'])
def partner_page(request, token):
    partner = Partner.objects.filter(access_token=token).first()
    if partner is None or partner.status in (Partner.INVITED, Partner.REJECTED):
        raise Http404
    ps = PromoSettings.get()
    error = ''

    if request.method == 'POST' and request.POST.get('action') == 'request_payment':
        with transaction.atomic():
            partner = Partner.objects.select_for_update().get(pk=partner.pk)
            balances = partner.balances()
            if partner.status != Partner.APPROVED:
                error = 'Your partner account is paused. Email us to sort it out.'
            elif partner.payout_requests.filter(status=PayoutRequest.REQUESTED).exists():
                error = 'You already have a request waiting. We will email you when it is paid.'
            elif balances['requestable'] <= 0 or balances['requestable'] < ps.partner_min_payout:
                error = f'You can request payment once you have K{ps.partner_min_payout} ready.'
            else:
                payout = PayoutRequest.objects.create(partner=partner, amount_requested=balances['requestable'])
                transaction.on_commit(lambda: emails.send_payout_requested(payout))
        if not error:
            return redirect(reverse('promotions:partner-page', args=[partner.access_token]) + '?requested=1')

    month_start = timezone.localtime().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    balances = partner.balances()
    ctx = {
        'partner': partner,
        'share_url': emails.share_url(partner),
        'all_time': partner_stats(partner),
        'this_month': partner_stats(partner, since=month_start),
        'balances': balances,
        'can_request': (
            partner.status == Partner.APPROVED
            and balances['requestable'] > 0
            and balances['requestable'] >= ps.partner_min_payout
            and not partner.payout_requests.filter(status=PayoutRequest.REQUESTED).exists()
        ),
        'earnings': partner.earnings.select_related('order')[:30],
        'payouts': partner.payout_requests.all()[:20],
        'requested': request.GET.get('requested') == '1',
        'now': timezone.now(),
        'error': error,
        **_program(ps),
        'rate_percent': emails.percent(partner.effective_rate(ps)),
    }
    return render(request, 'promotions/site/partner_page.html', ctx)


def share(request, code):
    partner = find_partner_code(code)
    return render(request, 'promotions/site/share.html', {
        'partner': partner,
        'code': (code or '').upper()[:20],
        **_program(),
    }, status=200 if partner else 404)
