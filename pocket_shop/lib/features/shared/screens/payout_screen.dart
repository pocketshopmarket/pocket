import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';

// ─── Provider logo constants ───
class _ProviderVisual {
  final String label;
  final String logoAsset;
  final Color accent;
  const _ProviderVisual(this.label, this.logoAsset, this.accent);
}

const _kProviders = [
  _ProviderVisual('MTN', 'mtn.png', Color(0xFFF2D23B)),
  _ProviderVisual('Airtel', 'airtel.png', Color(0xFFE51E2A)),
  _ProviderVisual('Zamtel', 'zamtel.png', Color(0xFF008543)),
];

_ProviderVisual _visual(String raw) {
  final v = raw.toLowerCase();
  if (v.contains('airtel')) return _kProviders[1];
  if (v.contains('zamtel')) return _kProviders[2];
  return _kProviders[0];
}

class PayoutScreen extends ConsumerStatefulWidget {
  const PayoutScreen({super.key});

  @override
  ConsumerState<PayoutScreen> createState() => _PayoutScreenState();
}

class _PayoutScreenState extends ConsumerState<PayoutScreen> {
  final _api = ApiService();
  final _amountController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  // Data from backend
  String _availableEarnings = '0.00';
  String _totalEarned = '0.00';
  String _totalPaidOut = '0.00';
  String _pendingPayouts = '0.00';
  bool _hasPayoutMethod = false;
  Map<String, dynamic>? _payoutMethod;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEarnings());
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadEarnings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await _api.get(AppConstants.paymentsPayoutEndpoint);
      final data = resp.data as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _availableEarnings = data['available_earnings']?.toString() ?? '0.00';
        _totalEarned = data['total_earned']?.toString() ?? '0.00';
        _totalPaidOut = data['total_paid_out']?.toString() ?? '0.00';
        _pendingPayouts = data['pending_payouts']?.toString() ?? '0.00';
        _hasPayoutMethod = data['has_payout_method'] == true;
        _payoutMethod = data['payout_method'] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is DioException
            ? (e.response?.data is Map
                ? (e.response!.data['error']?.toString() ?? e.message)
                : e.message)
            : e.toString();
      });
    }
  }

  Future<void> _claimEarnings() async {
    final amount = _amountController.text.trim();
    if (amount.isEmpty) return;

    setState(() => _submitting = true);
    try {
      final resp = await _api.post(
        AppConstants.paymentsPayoutEndpoint,
        data: {'amount': amount},
      );
      if (!mounted) return;
      setState(() => _submitting = false);
      _amountController.clear();

      final data = resp.data as Map<String, dynamic>;
      final message = data['message']?.toString() ??
          'Your payment of ZMW $amount will be sent shortly.';

      _showConfirmationDialog(message);
      _loadEarnings();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      String msg = 'Could not process claim. Please try again.';
      if (e is DioException && e.response?.data is Map) {
        msg = e.response!.data['error']?.toString() ?? msg;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.error),
      );
    }
  }

  void _showConfirmationDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppTheme.success,
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Earnings Claimed',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerLogo(String provider, {double size = 32}) {
    final vis = _visual(provider);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        vis.logoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: vis.accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            vis.label[0],
            style: TextStyle(
              color: vis.accent,
              fontSize: size * 0.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final roleName = user?.isSeller == true ? 'Seller' : 'Rider';
    final available = double.tryParse(_availableEarnings) ?? 0.0;

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Claim Earnings'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.textPrimary,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryCyan),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.error),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadEarnings,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppTheme.primaryCyan,
                  onRefresh: _loadEarnings,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      // ─── Earnings summary card ───
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.payments_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '$roleName earnings',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFD1D5DB),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Earnings available',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ZMW $_availableEarnings',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                _miniStat(
                                    'Total earned', 'ZMW $_totalEarned'),
                                const SizedBox(width: 12),
                                _miniStat(
                                    'Paid out', 'ZMW $_totalPaidOut'),
                                const SizedBox(width: 12),
                                _miniStat(
                                    'Pending', 'ZMW $_pendingPayouts'),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ─── Payment destination card ───
                      if (_payoutMethod != null) ...[
                        const Text(
                          'Payment will be sent to',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSecondary,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.divider),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0D000000),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              _providerLogo(
                                _payoutMethod!['provider']?.toString() ?? '',
                                size: 38,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _payoutMethod!['provider_label']
                                              ?.toString() ??
                                          '',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _payoutMethod!['account_phone']
                                              ?.toString() ??
                                          '',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.verified_rounded,
                                color: AppTheme.success,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color:
                                  AppTheme.warning.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: AppTheme.warning,
                                size: 22,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'No verified payment method on file. Add one in your profile to claim earnings.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // ─── Amount input ───
                      const Text(
                        'Amount to claim',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.divider),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0D000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d+\.?\d{0,2}')),
                              ],
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                              decoration: InputDecoration(
                                prefixText: 'ZMW  ',
                                prefixStyle: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary
                                      .withValues(alpha: 0.7),
                                ),
                                hintText: '0.00',
                                hintStyle: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textSecondary
                                      .withValues(alpha: 0.3),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF8F9FA),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: AppTheme.primaryCyan,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Quick-amount chips
                            Row(
                              children: [25, 50, 100].map((v) {
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: v == 100 ? 0 : 8,
                                    ),
                                    child: OutlinedButton(
                                      onPressed: available >= v
                                          ? () {
                                              _amountController.text =
                                                  v.toString();
                                            }
                                          : null,
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        side: const BorderSide(
                                            color: AppTheme.divider),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                      child: Text(
                                        'ZMW $v',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            if (available > 0) ...[
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    _amountController.text =
                                        _availableEarnings;
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.primaryCyan,
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 30),
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  child: const Text('Claim all'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),
                      Text(
                        'Minimum claim: ZMW 5.00',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary
                              .withValues(alpha: 0.7),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ─── Claim button ───
                      SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: (_submitting ||
                                  !_hasPayoutMethod ||
                                  available <= 0)
                              ? null
                              : _claimEarnings,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.payments_rounded,
                                  size: 18,
                                ),
                          label: Text(
                            _submitting ? 'Claiming...' : 'Claim earnings',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
