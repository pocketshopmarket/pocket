from django import forms

from .models import CODE_VALIDATOR, Partner
from .services import code_taken


def _zambian_phone(value):
    from accounts.phone_utils import normalize_zambia_phone_to_e164

    try:
        return normalize_zambia_phone_to_e164(value)
    except Exception:
        raise forms.ValidationError('Enter a Zambian mobile number, e.g. 097 123 4567.')


class _PayoutFields(forms.Form):
    payout_method = forms.ChoiceField(
        label='How should we pay you?', choices=Partner.PAYOUT_CHOICES, widget=forms.RadioSelect,
    )
    payout_details = forms.CharField(
        label='Payment details', max_length=300,
        help_text='Mobile money: number and network. Bank: bank, branch and account number.',
        widget=forms.TextInput(attrs={'placeholder': 'e.g. 097 123 4567, MTN'}),
    )
    agree = forms.BooleanField(label='I have read and agree to the partner rules.', required=True,
                               error_messages={'required': 'Please agree to the rules to continue.'})


class ApplyForm(_PayoutFields):
    name = forms.CharField(label='Full name or page name', max_length=120)
    email = forms.EmailField(label='Email')
    phone = forms.CharField(label='Phone number', max_length=20,
                            widget=forms.TextInput(attrs={'inputmode': 'tel', 'placeholder': '097 123 4567'}))
    promotes_on = forms.CharField(
        label='Where will you share Pocket Shop?', max_length=300,
        widget=forms.TextInput(attrs={'placeholder': 'e.g. TikTok @yourname, Facebook page, WhatsApp groups'}),
    )
    code = forms.CharField(
        label='Pick your code (optional)', max_length=20, required=False,
        help_text='3–20 letters or numbers. Leave blank and we will make one from your name.',
        widget=forms.TextInput(attrs={'placeholder': 'e.g. YOMAPS', 'autocapitalize': 'characters'}),
    )
    # Hidden from people; bots fill it in.
    website = forms.CharField(required=False, widget=forms.TextInput(attrs={'tabindex': '-1', 'autocomplete': 'off'}))

    field_order = ['name', 'email', 'phone', 'promotes_on', 'code', 'payout_method', 'payout_details', 'agree', 'website']

    def clean_email(self):
        email = self.cleaned_data['email'].strip().lower()
        if Partner.objects.filter(email=email).exists():
            raise forms.ValidationError(
                'We already have this email. Check your inbox, or email pocketshopmarket@gmail.com.'
            )
        return email

    def clean_phone(self):
        return _zambian_phone(self.cleaned_data['phone'])

    def clean_code(self):
        code = self.cleaned_data['code'].strip().upper()
        if not code:
            return ''
        CODE_VALIDATOR(code)
        if code_taken(code):
            raise forms.ValidationError('Someone already has this code. Try another one.')
        return code


class AcceptInviteForm(_PayoutFields):
    name = forms.CharField(label='Your name', max_length=120)
    phone = forms.CharField(label='Phone number', max_length=20,
                            widget=forms.TextInput(attrs={'inputmode': 'tel', 'placeholder': '097 123 4567'}))

    field_order = ['name', 'phone', 'payout_method', 'payout_details', 'agree']

    def clean_phone(self):
        return _zambian_phone(self.cleaned_data['phone'])
