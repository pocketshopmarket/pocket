import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/order.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/cart_provider.dart';
import '../../shared/screens/refund_requests_screen.dart';
import '../../shared/screens/cancellation_requests_screen.dart';

class SellerOrdersScreen extends ConsumerStatefulWidget {
  const SellerOrdersScreen({super.key});

  @override
  ConsumerState<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends ConsumerState<SellerOrdersScreen> {
  List<Order> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await ref.read(authProvider.notifier).refreshUser();
    if (!mounted) return;
    final svc = ref.read(orderServiceProvider);
    try {
      final list = await svc.fetchOrders();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _orders = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is DioException ? svc.extractErrorMessage(e) : e.toString();
      });
    }
  }

  bool get _sellerApproved =>
      ref.watch(userProvider)?.sellerProfile?.isApproved == true;

  @override
  Widget build(BuildContext context) {
    final pendingCount = _orders.where((o) => o.status == 'pending').length;
    final activeCount = _orders
        .where((o) => o.status == 'accepted' || o.status == 'preparing')
        .length;
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Seller orders'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.textPrimary,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryCyan,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
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
                    const Text(
                      'Order Management',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Track incoming and active orders in one place.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFD1D5DB)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _OrderStatChip(
                          label: 'Total',
                          value: '${_orders.length}',
                        ),
                        const SizedBox(width: 8),
                        _OrderStatChip(
                          label: 'Pending',
                          value: '$pendingCount',
                        ),
                        const SizedBox(width: 8),
                        _OrderStatChip(label: 'Active', value: '$activeCount'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _RefundRequestsWrapper(),
                    ),
                  ),
                  icon: const Icon(Icons.assignment_return_outlined, size: 18),
                  label: const Text('Refund requests'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.warning,
                    side: BorderSide(
                        color: AppTheme.warning.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CancellationRequestsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Cancellation requests'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: BorderSide(
                        color: AppTheme.error.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!_sellerApproved)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.warning.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Text(
                      'Your shop is not verified yet. You can view orders, but '
                      'status updates stay disabled until approval.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryCyan,
                    ),
                  ),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppTheme.error),
                  ),
                )
              else if (_orders.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Text(
                        'No orders yet',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
                )
              else
                ..._orders.map(
                  (o) => _OrderCard(
                    order: o,
                    canUpdateStatus: _sellerApproved,
                    onOpen: () => _openOrderSheet(o),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openOrderSheet(Order initial) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _SellerOrderSheet(
          initialOrder: initial,
          canUpdateStatus: _sellerApproved,
          onStatusChanged: _load,
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.canUpdateStatus,
    required this.onOpen,
  });

  final Order order;
  final bool canUpdateStatus;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceWhite,
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
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.orderNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.lightCyan,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        order.statusLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.darkCyan,
                        ),
                      ),
                    ),
                  ],
                ),
                if (order.status == 'accepted') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, size: 14, color: AppTheme.warning),
                        const SizedBox(width: 6),
                        _CountdownTimer(expiresAt: order.updatedAt.add(const Duration(minutes: 30))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  order.buyerName != null && order.buyerName!.isNotEmpty
                      ? 'Buyer: ${order.buyerName}'
                      : 'Buyer #${order.buyerId}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${order.items.length} item(s) · ZMW ${order.totalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      canUpdateStatus
                          ? 'Tap to update status'
                          : 'Tap for details',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.primaryCyan.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderStatChip extends StatelessWidget {
  const _OrderStatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFFD1D5DB)),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerOrderSheet extends ConsumerStatefulWidget {
  const _SellerOrderSheet({
    required this.initialOrder,
    required this.canUpdateStatus,
    required this.onStatusChanged,
  });

  final Order initialOrder;
  final bool canUpdateStatus;
  final Future<void> Function() onStatusChanged;

  @override
  ConsumerState<_SellerOrderSheet> createState() => _SellerOrderSheetState();
}

class _SellerOrderSheetState extends ConsumerState<_SellerOrderSheet> {
  late Order _order;
  bool _busy = false;
  bool _tokenBusy = false;

  bool get _sellerVerified => ref.watch(userProvider)?.isVerified == true;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
  }

  Future<void> _setStatus(String next) async {
    if (!widget.canUpdateStatus || _busy) return;
    setState(() => _busy = true);
    final svc = ref.read(orderServiceProvider);
    try {
      final updated = await svc.updateOrderStatus(
        orderId: _order.id,
        status: next,
      );
      if (!mounted) return;
      setState(() {
        _order = updated;
        _busy = false;
      });
      await widget.onStatusChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order is now ${updated.statusLabel}'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e is DioException ? svc.extractErrorMessage(e) : e.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg ?? 'Update failed')));
    }
  }

  List<({String label, String value})> _actionsFor(String status) {
    if (_order.isPickup) {
      switch (status) {
        case 'pending':
          return [
            (label: 'Accept order', value: 'accepted'),
            (label: 'Cancel', value: 'cancelled'),
          ];
        case 'accepted':
          return [
            (label: 'Start preparing', value: 'preparing'),
            (label: 'Cancel', value: 'cancelled'),
          ];
        case 'preparing':
          return [(label: 'Ready for pickup', value: 'out_for_delivery')];
        case 'out_for_delivery':
          return [(label: 'Mark delivered (picked up)', value: 'delivered')];
        default:
          return [];
      }
    } else {
      switch (status) {
        case 'pending':
          return [
            (label: 'Accept order', value: 'accepted'),
            (label: 'Cancel', value: 'cancelled'),
          ];
        case 'accepted':
          return [
            (label: 'Start preparing', value: 'preparing'),
            (label: 'Cancel', value: 'cancelled'),
          ];
        case 'preparing':
          return [(label: 'Ready — request rider', value: 'out_for_delivery')];
        default:
          return [];
      }
    }
  }

  Future<void> _generatePickupToken() async {
    final assignmentId = _order.deliveryAssignmentId;
    if (assignmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery rider has not been assigned yet')),
      );
      return;
    }
    setState(() => _tokenBusy = true);
    final svc = ref.read(orderServiceProvider);
    try {
      final payload = await svc.generateSellerPickupToken(assignmentId);
      if (!mounted) return;
      setState(() => _tokenBusy = false);
      final token = (payload['token'] ?? '').toString();
      showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: AppTheme.surfaceWhite,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 48,
                  color: AppTheme.primaryCyan,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Seller pickup QR code',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Show this to the rider so they can scan it to confirm pickup.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                if (token.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                    ),
                    child: QrImageView(
                      data: token,
                      version: QrVersions.auto,
                      size: 180.0,
                    ),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'Or type token manually:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.lightCyan.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    token.isEmpty ? 'No token returned' : token,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      letterSpacing: 2.0,
                      color: AppTheme.darkCyan,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _tokenBusy = false);
      final msg = e is DioException ? svc.extractErrorMessage(e) : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg ?? 'Could not generate pickup token')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;
    final actions = _actionsFor(_order.status);

    return Padding(
      padding: EdgeInsets.only(bottom: pad),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _order.orderNumber,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _order.statusLabel,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.darkCyan,
              ),
            ),
            if (_order.status == 'accepted') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined, size: 16, color: AppTheme.warning),
                    const SizedBox(width: 8),
                    _CountdownTimer(expiresAt: _order.updatedAt.add(const Duration(minutes: 30))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Deliver to',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _order.deliveryAddress,
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                color: AppTheme.textPrimary,
              ),
            ),
            if (_order.specialInstructions.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Instructions',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _order.specialInstructions,
                style: const TextStyle(fontSize: 14, height: 1.35),
              ),
            ],
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Items',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ..._order.items.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${line.quantity}× ${line.productName}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    Text(
                      'ZMW ${line.subtotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total ZMW ${_order.totalPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppTheme.darkCyan,
                ),
              ),
            ),
            if (_order.buyerPhone?.isNotEmpty ?? false) ...[
              const SizedBox(height: 10),
              if (_sellerVerified)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri(scheme: 'tel', path: _order.buyerPhone!);
                      if (await canLaunchUrl(uri)) await launchUrl(uri);
                    },
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Call buyer'),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 16, color: AppTheme.warning),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Verify your account to call buyers directly.',
                          style: TextStyle(fontSize: 12, color: AppTheme.warning),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (widget.canUpdateStatus && actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Next step',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
              if (_busy)
                const LinearProgressIndicator(color: AppTheme.primaryCyan),
              const SizedBox(height: 10),
              ...actions.map((a) {
                final cancel = a.value == 'cancelled';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: cancel
                        ? OutlinedButton(
                            onPressed: _busy ? null : () => _setStatus(a.value),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.error,
                              side: const BorderSide(color: AppTheme.error),
                            ),
                            child: Text(a.label),
                          )
                        : FilledButton(
                            onPressed: _busy ? null : () => _setStatus(a.value),
                            child: Text(a.label),
                          ),
                  ),
                );
              }),
            ],
            if (widget.canUpdateStatus && _order.isDelivery && _order.status == 'out_for_delivery') ...[
              const SizedBox(height: 14),
              if (_order.deliveryAssignmentId != null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _tokenBusy ? null : _generatePickupToken,
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: Text(
                      _tokenBusy ? 'Generating token...' : 'Generate pickup QR token',
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryCyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.pedal_bike_rounded, color: AppTheme.primaryCyan, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Waiting for a rider to accept the delivery. The QR button will appear here once a rider is assigned.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (!widget.canUpdateStatus)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'Verification required to change order status.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RefundRequestsWrapper extends StatelessWidget {
  const _RefundRequestsWrapper();

  @override
  Widget build(BuildContext context) => const RefundRequestsScreen();
}

class _CountdownTimer extends StatefulWidget {
  const _CountdownTimer({required this.expiresAt});
  final DateTime expiresAt;

  @override
  State<_CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<_CountdownTimer> {
  late Timer _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    final diff = widget.expiresAt.difference(DateTime.now());
    if (mounted) {
      setState(() {
        _remaining = diff.isNegative ? Duration.zero : diff;
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining == Duration.zero) {
      return const Text(
        'Time expired (auto-canceling...)',
        style: TextStyle(
          color: AppTheme.error,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    final m = _remaining.inMinutes.toString().padLeft(2, '0');
    final s = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    return Text(
      'Action required in $m:$s',
      style: const TextStyle(
        color: AppTheme.warning,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
