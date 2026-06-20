import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../providers/payment_methods_provider.dart';

class AddPaymentMethodScreen extends ConsumerStatefulWidget {
  const AddPaymentMethodScreen({super.key});

  @override
  ConsumerState<AddPaymentMethodScreen> createState() =>
      _AddPaymentMethodScreenState();
}

class _AddPaymentMethodScreenState
    extends ConsumerState<AddPaymentMethodScreen> {
  int _step = 1;
  String _selectedProvider = 'MTN';
  int? _createdId;
  bool _loading = false;
  String? _error;

  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  static const _providers = ['MTN', 'Airtel', 'Zamtel'];
  static const _providerColors = {
    'MTN': Color(0xFFF2D23B),
    'Airtel': Color(0xFFE51E2A),
    'Zamtel': Color(0xFF008543),
  };
  static const _providerLogos = {
    'MTN': 'mtn.png',
    'Airtel': 'airtel.png',
    'Zamtel': 'zamtel.png',
  };

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<bool> _confirmLeave() async {
    if (_step == 1) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel?'),
        content: const Text('Your progress will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Yes, cancel',
              style: TextStyle(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Enter a phone number');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final id = await ref.read(paymentMethodsProvider.notifier).addMethod(
        provider: _selectedProvider,
        phoneNumber: phone,
      );
      if (!mounted) return;
      if (id != null) {
        setState(() { _createdId = id; _step = 2; _loading = false; });
      } else {
        setState(() { _error = 'Could not send OTP'; _loading = false; });
      }
    } catch (e) {
      if (!mounted) return;
      final msg = ref.read(paymentMethodsProvider.notifier).extractError(e);
      setState(() { _error = msg ?? 'Could not send OTP'; _loading = false; });
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty || _createdId == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ref
          .read(paymentMethodsProvider.notifier)
          .verifyMethod(_createdId!, otp);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final msg = ref.read(paymentMethodsProvider.notifier).extractError(e);
      setState(() { _error = msg ?? 'Verification failed'; _loading = false; });
    }
  }

  Widget _providerLogo(String provider, {double size = 30}) {
    final logo = _providerLogos[provider];
    final color = _providerColors[provider] ?? AppTheme.primaryCyan;
    if (logo == null) {
      return Container(
        width: size, height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          provider[0],
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        logo, width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size, height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(provider[0],
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (!leave || !mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.surfaceWhite,
        appBar: AppBar(
          backgroundColor: AppTheme.surfaceWhite,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Text(
            _step == 1 ? 'Add payment method' : 'Enter OTP',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: _loading
                  ? null
                  : () async {
                      final leave = await _confirmLeave();
                      if (!leave || !mounted) return;
                      Navigator.of(context).pop();
                    },
              child: const Text('Cancel'),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: _step == 1 ? _buildStep1() : _buildStep2(),
          ),
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mobile money number',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '097 XXXXXXX',
            prefixIcon: const Icon(Icons.phone_outlined, size: 20),
            filled: true,
            fillColor: const Color(0xFFF3F4F6),
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
              borderSide: const BorderSide(color: AppTheme.primaryCyan, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Select network',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        ..._providers.map((p) {
          final selected = _selectedProvider == p;
          final color = _providerColors[p]!;
          return GestureDetector(
            onTap: () => setState(() => _selectedProvider = p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? color : AppTheme.divider,
                  width: selected ? 2 : 1,
                ),
                color: selected
                    ? color.withValues(alpha: 0.07)
                    : Colors.white,
              ),
              child: Row(
                children: [
                  _providerLogo(p, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p == 'MTN' ? 'MTN Mobile Money' :
                      p == 'Airtel' ? 'Airtel Money' : 'Zamtel Kwacha',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: selected
                        ? Icon(Icons.check_circle_rounded, color: color, size: 22,
                            key: const ValueKey('check'))
                        : const Icon(Icons.circle_outlined,
                            color: AppTheme.divider, size: 22,
                            key: ValueKey('empty')),
                  ),
                ],
              ),
            ),
          );
        }),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: _loading ? null : _sendOtp,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryCyan,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _loading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Send OTP',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primaryCyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.sms_outlined, color: AppTheme.primaryCyan, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'OTP sent to ${_phoneController.text.trim()}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.primaryCyan,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Enter the 6-digit code',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 10,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '------',
            hintStyle: TextStyle(
              fontSize: 28,
              letterSpacing: 10,
              color: AppTheme.textSecondary.withValues(alpha: 0.4),
            ),
            filled: true,
            fillColor: const Color(0xFFF3F4F6),
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
              borderSide: const BorderSide(color: AppTheme.primaryCyan, width: 1.5),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
        ],
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: _loading ? null : _verifyOtp,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryCyan,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _loading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Verify',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: TextButton(
            onPressed: _loading ? null : () => setState(() { _step = 1; _otpController.clear(); _error = null; }),
            child: const Text('Resend OTP'),
          ),
        ),
      ],
    );
  }
}
