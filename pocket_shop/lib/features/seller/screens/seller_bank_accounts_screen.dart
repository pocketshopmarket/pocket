import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/bank_account_service.dart';

/// Bank accounts a seller can withdraw earnings to.
///
/// An account is only saved after the bank has confirmed who it belongs to, so
/// the name on file is the bank's, not something typed in. If that name does
/// not match the seller's registered name it is flagged, and payouts to it are
/// held for a staff check rather than sent automatically.
class SellerBankAccountsScreen extends ConsumerStatefulWidget {
  const SellerBankAccountsScreen({super.key});

  @override
  ConsumerState<SellerBankAccountsScreen> createState() => _SellerBankAccountsScreenState();
}

class _SellerBankAccountsScreenState extends ConsumerState<SellerBankAccountsScreen> {
  final BankAccountService _service = BankAccountService();
  List<BankAccount> _accounts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final accounts = await _service.getAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _loading = false;
      });
    } on BankAccountException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _snack(String message, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: ok ? AppTheme.success : AppTheme.error),
    );
  }

  Future<void> _add() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _AddBankAccountSheet(service: _service),
    );
    if (added == true) {
      _snack('Bank account saved');
      _load();
    }
  }

  Future<void> _remove(BankAccount account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this account?'),
        content: Text('${account.bankName} ${account.maskedNumber} will no longer be used for payouts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.delete(account.id);
      _snack('Account removed');
      _load();
    } on BankAccountException catch (e) {
      _snack(e.message, ok: false);
    }
  }

  Future<void> _makeDefault(BankAccount account) async {
    try {
      await _service.makeDefault(account.id);
      _load();
    } on BankAccountException catch (e) {
      _snack(e.message, ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Bank accounts'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.textPrimary,
      ),
      floatingActionButton: _accounts.length < 3
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add account'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryCyan))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        TextButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      const Text(
                        'Withdraw your earnings to a bank account in your own name. A flat bank fee is '
                        'deducted from each bank payout, and there is a minimum amount. '
                        'You can save up to 3 accounts.',
                        style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.45),
                      ),
                      const SizedBox(height: 14),
                      if (_accounts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: Text('No bank accounts yet.')),
                        ),
                      for (final account in _accounts)
                        _AccountCard(
                          account: account,
                          onMakeDefault: () => _makeDefault(account),
                          onRemove: () => _remove(account),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final BankAccount account;
  final VoidCallback onMakeDefault;
  final VoidCallback onRemove;

  const _AccountCard({required this.account, required this.onMakeDefault, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_rounded, color: AppTheme.primaryCyan),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${account.bankName}  ${account.maskedNumber}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                ),
              ),
              if (account.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryCyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Default',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.darkCyan),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(account.accountName, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          if (!account.nameMatches) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "This name doesn't match your registered name, so payouts to it are checked by our team "
                'first and may take longer.',
                style: TextStyle(fontSize: 12, color: AppTheme.textPrimary, height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!account.isDefault) TextButton(onPressed: onMakeDefault, child: const Text('Make default')),
              TextButton(
                onPressed: onRemove,
                style: TextButton.styleFrom(foregroundColor: AppTheme.error),
                child: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pick a bank, enter the number, confirm the holder name, save.
class _AddBankAccountSheet extends ConsumerStatefulWidget {
  final BankAccountService service;
  const _AddBankAccountSheet({required this.service});

  @override
  ConsumerState<_AddBankAccountSheet> createState() => _AddBankAccountSheetState();
}

class _AddBankAccountSheetState extends ConsumerState<_AddBankAccountSheet> {
  final TextEditingController _number = TextEditingController();
  List<Bank> _banks = [];
  Bank? _bank;
  ResolvedBankAccount? _resolved;
  bool _loadingBanks = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _loadBanks() async {
    try {
      final banks = await widget.service.getBanks();
      if (!mounted) return;
      setState(() {
        _banks = banks;
        _loadingBanks = false;
      });
    } on BankAccountException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBanks = false;
        _error = e.message;
      });
    }
  }

  void _invalidate() {
    if (_resolved != null) setState(() => _resolved = null);
  }

  Future<void> _verify() async {
    final number = _number.text.trim();
    if (_bank == null) {
      setState(() => _error = 'Choose your bank.');
      return;
    }
    if (number.length < 6) {
      setState(() => _error = 'Enter your full account number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final resolved = await widget.service.resolve(bankId: _bank!.id, accountNumber: number);
      if (!mounted) return;
      setState(() {
        _resolved = resolved;
        _busy = false;
      });
    } on BankAccountException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.save(bankId: _bank!.id, accountNumber: _number.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on BankAccountException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final resolved = _resolved;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add a bank account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            if (_loadingBanks)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else
              DropdownButtonFormField<Bank>(
                initialValue: _bank,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Bank', border: OutlineInputBorder()),
                items: [for (final b in _banks) DropdownMenuItem(value: b, child: Text(b.name))],
                onChanged: (b) {
                  setState(() => _bank = b);
                  _invalidate();
                },
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _number,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => _invalidate(),
              decoration: const InputDecoration(labelText: 'Account number', border: OutlineInputBorder()),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 12.5)),
            ],
            const SizedBox(height: 12),
            if (resolved == null)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _busy || _loadingBanks ? null : _verify,
                  child: Text(_busy ? 'Checking…' : 'Check account'),
                ),
              )
            else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'The bank says this account belongs to\n${resolved.accountName}',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4),
                ),
              ),
              if (user != null &&
                  !_looksLikeSameName(resolved.accountName, user.displayName)) ...[
                const SizedBox(height: 8),
                const Text(
                  "This doesn't look like your registered name. You can still save it, but payouts to "
                  'it are checked by our team first.',
                  style: TextStyle(fontSize: 12, color: AppTheme.warning, height: 1.4),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Saving…' : 'Yes, this is my account — save'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Only for the friendly heads-up above. The server does the authoritative
  /// name check when the account is saved.
  bool _looksLikeSameName(String a, String b) {
    Set<String> parts(String v) =>
        v.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((t) => t.length > 1).toSet();
    final left = parts(a);
    final right = parts(b);
    if (left.isEmpty || right.isEmpty) return true;
    return left.intersection(right).length >= (right.length < 2 ? right.length : 2);
  }
}
