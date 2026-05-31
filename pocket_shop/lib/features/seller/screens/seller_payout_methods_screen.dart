import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/seller_payout_methods_provider.dart';
import '../../../providers/payment_methods_provider.dart';

// ─── Provider-logo constants (shared with buyer_profile_screen) ───
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

class SellerPayoutMethodsScreen extends ConsumerStatefulWidget {
  const SellerPayoutMethodsScreen({super.key});

  @override
  ConsumerState<SellerPayoutMethodsScreen> createState() =>
      _SellerPayoutMethodsScreenState();
}

class _SellerPayoutMethodsScreenState
    extends ConsumerState<SellerPayoutMethodsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(sellerPayoutMethodsProvider.notifier).load(),
    );
  }

  // ─── Logo widget ───
  Widget _providerLogo(String provider, {double size = 32}) {
    final vis = _visual(provider);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        vis.logoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
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

  // ─── 3-step bottom-sheet add-flow (matches buyer profile) ───
  Future<void> _showAddPayoutFlow(BuildContext context) async {
    final phoneController = TextEditingController();
    String selectedProvider = 'MTN';
    int? createdId;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        int step = 1;
        final otpController = TextEditingController();
        bool busy = false;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Drag handle ──
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'Add payout method',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    step == 1
                        ? 'Enter the mobile money number to receive payouts.'
                        : step == 2
                            ? 'Select your provider.'
                            : 'Verify ownership with OTP.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Step indicator ──
                  Row(
                    children: List.generate(3, (i) {
                      final active = i + 1 <= step;
                      return Expanded(
                        child: Container(
                          height: 3,
                          margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                          decoration: BoxDecoration(
                            color: active
                                ? AppTheme.primaryCyan
                                : AppTheme.divider,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),

                  // ── Step 1: Phone ──
                  if (step == 1) ...[
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: '+260 97 XXXXXXX',
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppTheme.primaryCyan,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          if (phoneController.text.trim().isEmpty) return;
                          setModalState(() => step = 2);
                        },
                        child: const Text('Continue'),
                      ),
                    ),
                  ]

                  // ── Step 2: Provider ──
                  else if (step == 2) ...[
                    ..._kProviders.map((prov) {
                      final selected = selectedProvider == prov.label;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setModalState(
                            () => selectedProvider = prov.label,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.primaryCyan
                                    : AppTheme.divider,
                                width: selected ? 1.5 : 1,
                              ),
                              color: selected
                                  ? AppTheme.primaryCyan
                                      .withValues(alpha: 0.08)
                                  : Colors.white,
                            ),
                            child: Row(
                              children: [
                                _providerLogo(prov.label, size: 34),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        prov.label,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        prov.label == 'MTN'
                                            ? 'MTN Mobile Money'
                                            : prov.label == 'Airtel'
                                                ? 'Airtel Money'
                                                : 'Zamtel Kwacha',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (selected)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 20,
                                    color: AppTheme.primaryCyan,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: busy
                            ? null
                            : () async {
                                setModalState(() => busy = true);
                                try {
                                  createdId = await ref
                                      .read(sellerPayoutMethodsProvider
                                          .notifier)
                                      .addMethod(
                                        provider: selectedProvider,
                                        phoneNumber:
                                            phoneController.text.trim(),
                                      );
                                  if (createdId != null) {
                                    setModalState(() {
                                      step = 3;
                                      busy = false;
                                    });
                                  }
                                } catch (e) {
                                  setModalState(() => busy = false);
                                  if (!ctx.mounted) return;
                                  final msg = ref
                                          .read(sellerPayoutMethodsProvider
                                              .notifier)
                                          .extractError(e) ??
                                      'Could not add method';
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text(msg)),
                                  );
                                }
                              },
                        child: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Send OTP'),
                      ),
                    ),
                  ]

                  // ── Step 3: OTP ──
                  else ...[
                    Text(
                      'Enter OTP sent to ${phoneController.text.trim()}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '000000',
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        prefixIcon: const Icon(Icons.pin_outlined, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppTheme.primaryCyan,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: busy
                            ? null
                            : () async {
                                if (createdId == null ||
                                    otpController.text.trim().isEmpty) return;
                                setModalState(() => busy = true);
                                try {
                                  await ref
                                      .read(sellerPayoutMethodsProvider
                                          .notifier)
                                      .verifyMethod(
                                        createdId!,
                                        otpController.text.trim(),
                                      );
                                  if (!ctx.mounted) return;
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Payout method verified ✓'),
                                      backgroundColor: AppTheme.success,
                                    ),
                                  );
                                } catch (e) {
                                  setModalState(() => busy = false);
                                  if (!ctx.mounted) return;
                                  final msg = ref
                                          .read(sellerPayoutMethodsProvider
                                              .notifier)
                                          .extractError(e) ??
                                      'Verification failed';
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text(msg)),
                                  );
                                }
                              },
                        child: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Verify'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── Build ───
  @override
  Widget build(BuildContext context) {
    final methods = ref.watch(sellerPayoutMethodsProvider);
    final user = ref.watch(userProvider);
    final roleName =
        user?.isSeller == true ? 'Seller' : 'Rider';

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Payout methods'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.textPrimary,
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryCyan,
        onRefresh: () =>
            ref.read(sellerPayoutMethodsProvider.notifier).load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            // ─── Balance / Info card ───
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
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
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$roleName payment methods',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Add a verified mobile money number to receive automatic payouts.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFD1D5DB),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Method count badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          methods.isEmpty
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 14,
                          color: methods.isEmpty
                              ? AppTheme.warning
                              : AppTheme.success,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          methods.isEmpty
                              ? 'No payout method set up'
                              : '${methods.length} method${methods.length > 1 ? 's' : ''} registered',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ─── Section header ───
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Saved methods',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showAddPayoutFlow(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryCyan,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ─── Methods list (or empty state) ───
            if (methods.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
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
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryCyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: AppTheme.primaryCyan,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No payout methods yet',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Add a mobile money number so you can receive payouts for completed orders.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 42,
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _showAddPayoutFlow(context),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add payout method'),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...methods.map((method) => _buildMethodCard(method)),

            // ─── Accepted providers ───
            const SizedBox(height: 24),
            const Text(
              'Accepted providers',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: _kProviders.map((prov) {
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(
                      right: prov == _kProviders.last ? 0 : 8,
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.divider),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x08000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _providerLogo(prov.label, size: 36),
                        const SizedBox(height: 6),
                        Text(
                          prov.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Individual method card ───
  Widget _buildMethodCard(BuyerPaymentMethod method) {
    final vis = _visual(method.providerLabel);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: method.isDefault
              ? AppTheme.primaryCyan.withValues(alpha: 0.4)
              : AppTheme.divider,
        ),
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
          // Logo
          _providerLogo(method.providerLabel, size: 36),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      method.providerLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (method.isDefault) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              AppTheme.primaryCyan.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'DEFAULT',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.darkCyan,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        method.phoneNumber,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      method.isVerified
                          ? Icons.verified_rounded
                          : Icons.error_outline_rounded,
                      size: 14,
                      color: method.isVerified
                          ? AppTheme.success
                          : AppTheme.warning,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      method.isVerified ? 'Verified' : 'Unverified',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: method.isVerified
                            ? AppTheme.success
                            : AppTheme.warning,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Actions
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!method.isDefault)
                SizedBox(
                  height: 30,
                  child: OutlinedButton(
                    onPressed: () => ref
                        .read(sellerPayoutMethodsProvider.notifier)
                        .setDefault(method.id),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: const TextStyle(fontSize: 11),
                      side: const BorderSide(color: AppTheme.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Set default'),
                  ),
                ),
              const SizedBox(height: 4),
              SizedBox(
                height: 28,
                width: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  onPressed: () => _confirmDelete(method),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppTheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Delete confirmation ───
  void _confirmDelete(BuyerPaymentMethod method) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove method?'),
        content: Text(
          'Delete ${method.providerLabel} · ${method.phoneNumber} from your payout methods?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref
                  .read(sellerPayoutMethodsProvider.notifier)
                  .deleteMethod(method.id);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
