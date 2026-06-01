import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/orders_provider.dart';
import '../../../services/order_service.dart';

/// Shown after checkout while the buyer authorises payment on their phone.
/// Displays a clear status and a manual "Refresh" button + optional auto-poll.
class PaymentPendingScreen extends ConsumerStatefulWidget {
  final String orderNumber;
  final String provider;
  final String amount;
  final bool isDelivery;

  const PaymentPendingScreen({
    super.key,
    required this.orderNumber,
    this.provider = '',
    this.amount = '',
    this.isDelivery = true,
  });

  @override
  ConsumerState<PaymentPendingScreen> createState() =>
      _PaymentPendingScreenState();
}

class _PaymentPendingScreenState extends ConsumerState<PaymentPendingScreen>
    with SingleTickerProviderStateMixin {
  final OrderService _orderService = OrderService();

  String _paymentStatus = 'pending';
  String _orderStatus = 'pending';
  String _failureMessage = '';
  String _amount = '';
  bool _isChecking = false;
  Timer? _autoRefreshTimer;
  int _pollCount = 0;
  static const int _maxPolls = 60; // 5 minutes at 5s interval

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _amount = widget.amount;

    // Start auto-polling every 5 seconds
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkStatus(),
    );
    // Initial check after a small delay
    Future.delayed(const Duration(seconds: 2), _checkStatus);
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    if (_isChecking) return;
    if (_paymentStatus == 'completed' || _paymentStatus == 'failed') return;
    if (_pollCount >= _maxPolls) {
      _autoRefreshTimer?.cancel();
      return;
    }

    setState(() => _isChecking = true);
    _pollCount++;

    try {
      final result = await _orderService.checkPaymentStatus(
        orderNumber: widget.orderNumber,
      );
      if (!mounted) return;

      final newPaymentStatus =
          result['payment_status']?.toString() ?? _paymentStatus;
      final newOrderStatus =
          result['order_status']?.toString() ?? _orderStatus;
      final failMsg = result['failure_message']?.toString() ?? '';
      final polledAmount = result['amount']?.toString() ?? '';

      setState(() {
        _paymentStatus = newPaymentStatus;
        _orderStatus = newOrderStatus;
        _failureMessage = failMsg;
        if (_amount.isEmpty && polledAmount.isNotEmpty) _amount = polledAmount;
        _isChecking = false;
      });

      // If payment completed or failed, stop auto-polling
      if (_paymentStatus == 'completed' || _paymentStatus == 'failed') {
        _autoRefreshTimer?.cancel();
        ref.invalidate(buyerOrdersProvider);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  void _navigateToOrderTracking() {
    ref.invalidate(buyerOrdersProvider);
    if (widget.isDelivery) {
      context.go(
        '/buyer/track-order?order=${Uri.encodeComponent(widget.orderNumber)}',
      );
    } else {
      context.go('/buyer/orders');
    }
  }

  void _navigateToOrders() {
    ref.invalidate(buyerOrdersProvider);
    context.go('/buyer/orders');
  }

  String _providerLabel(String provider) {
    switch (provider) {
      case 'AIRTEL_OAPI_ZMB':
      case 'AIRTEL_MOMO_ZMB':
        return 'Airtel Money';
      case 'MTN_MOMO_ZMB':
        return 'MTN MoMo';
      case 'ZAMTEL_MONEY_ZMB':
      case 'ZAMTEL_MOMO_ZMB':
        return 'Zamtel Kwacha';
      default:
        return 'Mobile Money';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPending =
        _paymentStatus == 'pending' || _paymentStatus == 'accepted';
    final isCompleted = _paymentStatus == 'completed';
    final isFailed = _paymentStatus == 'failed';
    final isNoPayment = _paymentStatus == 'no_payment';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceWhite,
        appBar: AppBar(
          title: const Text('Payment'),
          automaticallyImplyLeading: false,
          actions: [
            if (isCompleted || isFailed || isNoPayment)
              TextButton(
                onPressed: _navigateToOrders,
                child: const Text('My Orders'),
              ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    kToolbarHeight -
                    MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 32),
                  // Status Icon
                  _buildStatusIcon(isPending, isCompleted, isFailed),
                  const SizedBox(height: 28),
                  // Status Title
                  Text(
                    _statusTitle(isPending, isCompleted, isFailed, isNoPayment),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Status Message
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _statusMessage(
                          isPending, isCompleted, isFailed, isNoPayment),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (_failureMessage.isNotEmpty && isFailed) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _failureMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  // Order summary card
                  _buildOrderSummaryCard(),
                  const SizedBox(height: 32),
                  // Action buttons
                  if (isPending) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _isChecking ? null : _checkStatus,
                        icon: _isChecking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: Text(
                            _isChecking ? 'Checking...' : 'Refresh status'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _navigateToOrders,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Cancel & Close'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Auto-refreshing every 5 seconds. Approve the payment on your phone.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (isCompleted) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _navigateToOrderTracking,
                        icon: Icon(
                          widget.isDelivery
                              ? Icons.local_shipping_outlined
                              : Icons.list_alt_rounded,
                        ),
                        label: Text(widget.isDelivery
                            ? 'Track my order'
                            : 'View my orders'),
                      ),
                    ),
                  ] else if (isFailed) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _navigateToOrders,
                        icon: const Icon(Icons.list_alt_rounded),
                        label: const Text('View my orders'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'You can retry payment from your order details.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary.withValues(alpha: 0.8),
                      ),
                    ),
                  ] else if (isNoPayment) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _navigateToOrders,
                        icon: const Icon(Icons.list_alt_rounded),
                        label: const Text('View my orders'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(bool isPending, bool isCompleted, bool isFailed) {
    if (isCompleted) {
      return Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check_circle_rounded,
          size: 56,
          color: AppTheme.success,
        ),
      );
    }

    if (isFailed) {
      return Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.cancel_rounded,
          size: 56,
          color: AppTheme.error,
        ),
      );
    }

    // Pending — animated pulsing icon with glowing ring
    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppTheme.primaryCyan.withValues(alpha: 0.25),
            width: 3,
          ),
        ),
        child: Center(
          child: Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: AppTheme.primaryCyan.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryCyan.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.phone_android_rounded,
              size: 46,
              color: AppTheme.primaryCyan,
            ),
          ),
        ),
      ),
    );
  }

  String _statusTitle(
      bool isPending, bool isCompleted, bool isFailed, bool isNoPayment) {
    if (isCompleted) return 'Payment successful!';
    if (isFailed) return 'Payment failed or terminated';
    if (isNoPayment) return 'No payment found';
    return 'Waiting for payment';
  }

  String _statusMessage(
      bool isPending, bool isCompleted, bool isFailed, bool isNoPayment) {
    if (isCompleted) {
      return 'Your payment has been confirmed. Your order is now being processed by the seller.';
    }
    if (isFailed) {
      return 'The payment could not be completed. Your order has been cancelled.';
    }
    if (isNoPayment) {
      return 'No payment was initiated for this order.';
    }
    return 'Please approve the ${_providerLabel(widget.provider)} prompt on your phone to complete the payment.';
  }

  Widget _buildOrderSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _infoRow('Order', widget.orderNumber),
          const SizedBox(height: 10),
          _infoRow('Amount', _amount.isNotEmpty ? 'ZMW $_amount' : '—'),
          const SizedBox(height: 10),
          _infoRow('Provider', _providerLabel(widget.provider)),
          const SizedBox(height: 10),
          _infoRow('Payment', _paymentStatusLabel),
          const SizedBox(height: 10),
          _infoRow('Order status', _orderStatusLabel),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    Color valueColor = AppTheme.textPrimary;
    if (label == 'Payment') {
      if (_paymentStatus == 'completed') {
        valueColor = AppTheme.success;
      } else if (_paymentStatus == 'failed') {
        valueColor = AppTheme.error;
      } else if (_paymentStatus == 'pending' ||
          _paymentStatus == 'accepted') {
        valueColor = AppTheme.warning;
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }

  String get _paymentStatusLabel {
    switch (_paymentStatus) {
      case 'pending':
        return 'Waiting for approval';
      case 'accepted':
        return 'Processing...';
      case 'completed':
        return 'Paid ✓';
      case 'failed':
      case 'cancelled':
      case 'terminated':
        return 'Terminated / Failed ✗';
      case 'no_payment':
        return 'Not initiated';
      default:
        return _paymentStatus;
    }
  }

  String get _orderStatusLabel {
    switch (_orderStatus) {
      case 'pending':
        return 'Awaiting payment';
      case 'payment_pending':
        return 'Payment in progress';
      case 'accepted':
        return 'Confirmed';
      case 'preparing':
        return 'Preparing';
      case 'out_for_delivery':
        return 'Out for delivery';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      default:
        return _orderStatus;
    }
  }
}
