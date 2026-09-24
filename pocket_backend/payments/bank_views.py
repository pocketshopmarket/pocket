import logging

from django.db import transaction as db_transaction
from django.shortcuts import get_object_or_404
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.throttles import BankResolveThrottle

from .models import PayoutBankAccount
from .services.lenco import LencoError, LencoService

logger = logging.getLogger(__name__)

MAX_BANK_ACCOUNTS_PER_USER = 3


class IsPayoutRecipient(permissions.BasePermission):
    """Only people who get paid out — sellers and delivery riders — have bank accounts."""

    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and user.role in ('seller', 'delivery'))


def _serialize(account):
    return {
        'id': account.id,
        'bank_id': account.bank_id,
        'bank_name': account.bank_name,
        'account_number_masked': account.masked_number,
        'account_name': account.account_name,
        'is_default': account.is_default,
    }


class BankListView(APIView):
    """GET /api/payments/banks/ — banks a payout can go to."""
    permission_classes = [IsPayoutRecipient]

    def get(self, request):
        try:
            banks = LencoService.get_banks()
        except LencoError as exc:
            return Response({'error': str(exc)}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
        return Response([
            {'id': b.get('id'), 'name': b.get('name')} for b in banks
        ])


class BankAccountResolveView(APIView):
    """
    POST /api/payments/bank-accounts/resolve/  {bank_id, account_number}

    Returns the account holder's name so the user can confirm it is really
    their account before saving. Nothing is stored here.
    """
    permission_classes = [IsPayoutRecipient]
    throttle_classes = [BankResolveThrottle]

    def post(self, request):
        bank_id = str(request.data.get('bank_id') or '').strip()
        account_number = str(request.data.get('account_number') or '').strip()
        if not bank_id or not account_number.isdigit() or not 6 <= len(account_number) <= 20:
            return Response(
                {'error': 'Choose a bank and enter a valid account number.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            resolved = LencoService.resolve_bank_account(account_number, bank_id)
        except LencoError as exc:
            return Response({'error': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return Response({
            'account_name': resolved['account_name'],
            'bank_name': (resolved['bank'] or {}).get('name', ''),
        })


class BankAccountListCreateView(APIView):
    """
    GET  /api/payments/bank-accounts/  — the user's saved accounts.
    POST /api/payments/bank-accounts/  {bank_id, account_number} — verify and save.

    The name on file always comes from the bank lookup made here, never from
    the client, so a saved account can't carry a name the bank didn't confirm.
    """
    permission_classes = [IsPayoutRecipient]
    throttle_classes = [BankResolveThrottle]

    def get_throttles(self):
        # Reading the list costs nothing; only saving triggers a lookup.
        return super().get_throttles() if self.request.method == 'POST' else []

    def get(self, request):
        accounts = PayoutBankAccount.objects.filter(user=request.user)
        return Response([_serialize(a) for a in accounts])

    def post(self, request):
        bank_id = str(request.data.get('bank_id') or '').strip()
        account_number = str(request.data.get('account_number') or '').strip()
        if not bank_id or not account_number.isdigit() or not 6 <= len(account_number) <= 20:
            return Response(
                {'error': 'Choose a bank and enter a valid account number.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if PayoutBankAccount.objects.filter(user=request.user).count() >= MAX_BANK_ACCOUNTS_PER_USER:
            return Response(
                {'error': f'You can save up to {MAX_BANK_ACCOUNTS_PER_USER} bank accounts. Remove one first.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if PayoutBankAccount.objects.filter(
            user=request.user, bank_id=bank_id, account_number=account_number
        ).exists():
            return Response(
                {'error': 'That bank account is already saved.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            resolved = LencoService.resolve_bank_account(account_number, bank_id)
        except LencoError as exc:
            return Response({'error': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        if not resolved['account_name']:
            return Response(
                {'error': 'The bank did not return an account name for that account.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        with db_transaction.atomic():
            first_account = not PayoutBankAccount.objects.filter(user=request.user).exists()
            account = PayoutBankAccount.objects.create(
                user=request.user,
                bank_id=bank_id,
                bank_name=(resolved['bank'] or {}).get('name') or bank_id,
                account_number=account_number,
                account_name=resolved['account_name'],
                is_default=first_account,
            )
        return Response(_serialize(account), status=status.HTTP_201_CREATED)


class BankAccountDetailView(APIView):
    """DELETE /api/payments/bank-accounts/<id>/"""
    permission_classes = [IsPayoutRecipient]

    def delete(self, request, pk):
        account = get_object_or_404(PayoutBankAccount, pk=pk, user=request.user)
        was_default = account.is_default
        account.delete()
        if was_default:
            # Never leave the user with accounts but no default.
            replacement = PayoutBankAccount.objects.filter(user=request.user).first()
            if replacement:
                replacement.is_default = True
                replacement.save(update_fields=['is_default'])
        return Response(status=status.HTTP_204_NO_CONTENT)


class BankAccountMakeDefaultView(APIView):
    """POST /api/payments/bank-accounts/<id>/default/"""
    permission_classes = [IsPayoutRecipient]

    def post(self, request, pk):
        account = get_object_or_404(PayoutBankAccount, pk=pk, user=request.user)
        with db_transaction.atomic():
            PayoutBankAccount.objects.filter(user=request.user).update(is_default=False)
            account.is_default = True
            account.save(update_fields=['is_default'])
        return Response(_serialize(account))
