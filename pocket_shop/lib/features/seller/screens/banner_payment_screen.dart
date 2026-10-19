import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/seller_banner.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/banner_service.dart';

/// Charges a seller's "promote your shop" banner. No provider picker like
/// checkout's — the server auto-detects MTN/Airtel/Zamtel from the phone
/// number (see payments.views.BannerPaymentInitiateView), so this only ever
/// needs the phone number itself.
class BannerPaymentScreen extends ConsumerStatefulWidget {
  final SellerBanner banner;
  const BannerPaymentScreen({super.key, required this.banner});

  @override
  ConsumerState<BannerPaymentScreen> createState() => _BannerPaymentScreenState();
}

class _BannerPaymentScreenState extends ConsumerState<BannerPaymentScreen> {
  final _phoneController = TextEditingController();
  final _service = BannerService();

  bool _initiating = false;
  bool _polling = false;
  String? _error;
  String _paymentStatus = 'not_started';
  Timer? _pollTimer;
  int _pollCount = 0;
  static const int _maxPolls = 60;

  @override
  void initState() {
    super.initState();
    final phone = ref.read(userProvider)?.phoneNumber ?? '';
    _phoneController.text = phone.replaceFirst('+260', '');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Enter the phone number to pay from.');
      return;
    }
    setState(() {
      _initiating = true;
      _error = null;
    });
    try {
      await _service.initiatePayment(bannerId: widget.banner.id, payerNumber: phone);
      if (!mounted) return;
      setState(() {
        _initiating = false;
        _paymentStatus = 'pending';
      });
      _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() {
          _initiating = false;
          _error = BannerService.errorMessage(e, fallback: 'Could not start the payment.');
        });
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
    Future.delayed(const Duration(seconds: 2), _checkStatus);
  }

  Future<void> _checkStatus() async {
    if (_polling) return;
    if (_paymentStatus == 'completed' || _paymentStatus == 'failed') return;
    if (_pollCount >= _maxPolls) {
      _pollTimer?.cancel();
      return;
    }
    setState(() => _polling = true);
    _pollCount++;
    try {
      final result = await _service.checkPaymentStatus(widget.banner.id);
      if (!mounted) return;
      final status = result['payment_status']?.toString() ?? _paymentStatus;
      setState(() {
        _paymentStatus = status;
        _polling = false;
      });
      if (status == 'completed' || status == 'failed') {
        _pollTimer?.cancel();
      }
    } catch (_) {
      if (mounted) setState(() => _polling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPending = _paymentStatus == 'pending' || _paymentStatus == 'accepted';
    final isCompleted = _paymentStatus == 'completed';
    final isFailed = _paymentStatus == 'failed';

    return PopScope(
      canPop: !isPending,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceWhite,
        appBar: AppBar(
          title: const Text('Pay for promotion'),
          automaticallyImplyLeading: !isPending,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.banner.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 8),
                      _row('Duration', '${widget.banner.durationDays} day(s)'),
                      _row('Amount', 'ZMW ${widget.banner.pricePaid}'),
                      _row('Status', _statusLabel),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_paymentStatus == 'not_started') ...[
                  const Text(
                    'Mobile money number',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      prefixText: '+260 ',
                      hintText: '97XXXXXXX',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.phone_android_rounded),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _initiating ? null : _pay,
                      child: _initiating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text('Pay ZMW ${widget.banner.pricePaid}'),
                    ),
                  ),
                ] else ...[
                  Center(
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        if (isPending)
                          const CircularProgressIndicator()
                        else
                          Icon(
                            isCompleted ? Icons.check_circle_rounded : Icons.cancel_rounded,
                            size: 64,
                            color: isCompleted ? AppTheme.success : AppTheme.error,
                          ),
                        const SizedBox(height: 16),
                        Text(
                          isPending
                              ? 'Waiting for payment'
                              : isCompleted
                                  ? 'Payment successful!'
                                  : 'Payment failed',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isPending
                              ? 'Approve the Mobile Money prompt on your phone.'
                              : isCompleted
                                  ? 'Your promotion is now awaiting staff review.'
                                  : 'The payment could not be completed. You can try again from your promotions list.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 24),
                        if (isCompleted || isFailed)
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton(
                              onPressed: () => context.go('/seller/shop'),
                              child: const Text('Back to promotions'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _statusLabel {
    switch (_paymentStatus) {
      case 'pending':
        return 'Processing';
      case 'completed':
        return 'Paid';
      case 'failed':
        return 'Failed';
      default:
        return widget.banner.statusLabel;
    }
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
