import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/order.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/orders_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../widgets/osm_route_map.dart';

class BuyerOrderDetailScreen extends ConsumerWidget {
  final int orderId;

  const BuyerOrderDetailScreen({super.key, required this.orderId});

  Future<void> _cancelOrder(BuildContext context, WidgetRef ref, int orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text(
          'Your order will be cancelled. If you already paid, a refund will be sent to your mobile money account automatically within a few minutes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep order'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final api = ApiService();
      await api.post('orders/orders/$orderId/cancel/');
      ref.invalidate(orderDetailProvider(orderId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order cancelled. Refund will be sent to your mobile money account.'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _requestCancellation(BuildContext context, WidgetRef ref, int orderId) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Request cancellation', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'The seller has already accepted your order. Tell them why you want to cancel — they will review and approve or reject your request.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Why do you want to cancel?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.warning),
                child: const Text('Send request to seller'),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (reasonCtrl.text.trim().isEmpty) return;
    try {
      final api = ApiService();
      await api.post(
        'orders/orders/$orderId/cancellation-request/',
        data: {'reason': reasonCtrl.text.trim()},
      );
      ref.invalidate(orderDetailProvider(orderId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request sent — the seller will review it'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _requestRefund(BuildContext context, WidgetRef ref, int orderId) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Request a refund', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Explain why you want a refund. The seller will review your request.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Describe the issue...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Submit request'),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (reasonCtrl.text.trim().isEmpty) return;
    try {
      final api = ApiService();
      await api.post(
        'orders/orders/$orderId/refund-request/',
        data: {'reason': reasonCtrl.text.trim()},
      );
      ref.invalidate(orderDetailProvider(orderId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Refund request submitted — the seller will review it'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _showWalkToShopSheet(
    BuildContext context, {
    required double lat,
    required double lng,
    String? shopName,
    String? shopLocation,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WalkToShopSheet(
        lat: lat,
        lng: lng,
        shopName: shopName,
        shopLocation: shopLocation,
      ),
    );
  }

  Future<void> _rateOrder(BuildContext context, WidgetRef ref, int orderId) async {
    int score = 5;
    final commentController = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (_, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rate order experience',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(
                      5,
                      (i) => IconButton(
                        onPressed: () => setModalState(() => score = i + 1),
                        icon: Icon(
                          i < score ? Icons.star : Icons.star_border,
                          color: AppTheme.warning,
                        ),
                      ),
                    ),
                  ),
                  TextField(
                    controller: commentController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Optional feedback',
                      filled: true,
                      fillColor: const Color(0xFFEEEEEE),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Submit rating'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(orderServiceProvider).submitRating(
            orderId: orderId,
            targetRole: 'buyer_to_order',
            score: score,
            comment: commentController.text.trim(),
          );
      ref.invalidate(orderDetailProvider(orderId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thanks for your rating'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  String _friendlyProvider(String raw) {
    switch (raw.toUpperCase()) {
      case 'AIRTEL_OAPI_ZMB': return 'Airtel Money';
      case 'MTN_MOMO_ZMB':    return 'MTN MoMo';
      case 'ZAMTEL_ZMB':      return 'Zamtel Kwacha';
      default:                return raw;
    }
  }

  Widget _buildRefundBanner(CancellationRefund refund) {
    final isCompleted = refund.status == 'completed';
    final isFailed = refund.status == 'failed';
    final color = isCompleted
        ? AppTheme.success
        : isFailed
            ? AppTheme.error
            : const Color(0xFFF59E0B);
    final icon = isCompleted
        ? Icons.check_circle_outline_rounded
        : isFailed
            ? Icons.error_outline_rounded
            : Icons.hourglass_top_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '${refund.label} · ZMW ${refund.amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'cancelled':
        return AppTheme.error;
      case 'delivered':
        return AppTheme.success;
      case 'out_for_delivery':
        return AppTheme.accentPurple;
      case 'accepted':
      case 'preparing':
        return AppTheme.success;
      case 'payment_pending':
        return const Color(0xFFF59E0B);
      default:
        return AppTheme.darkCyan;
    }
  }

  Color _refundStatusColor(String status) {
    switch (status) {
      case 'approved_by_seller':
      case 'approved_by_admin':
      case 'refunded':
        return AppTheme.success;
      case 'rejected_by_seller':
      case 'rejected_by_admin':
        return AppTheme.error;
      case 'escalated':
        return AppTheme.accentBlue;
      default:
        return AppTheme.warning;
    }
  }

  String _refundStatusLabel(String status) {
    switch (status) {
      case 'pending_seller':
        return 'Awaiting seller review';
      case 'approved_by_seller':
        return 'Approved by seller';
      case 'rejected_by_seller':
        return 'Rejected by seller';
      case 'escalated':
        return 'Escalated to admin';
      case 'approved_by_admin':
        return 'Approved by admin';
      case 'rejected_by_admin':
        return 'Rejected by admin';
      case 'refunded':
        return 'Refunded';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Order details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/buyer/orders'),
        ),
      ),
      body: async.when(
        data: (order) {
          final hasBuyerOrderRating =
              order.ratings.any((r) => r.targetRole == 'buyer_to_order');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.orderNumber,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      order.statusLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _statusColor(order.status),
                      ),
                    ),
                    if (order.cancellationRefund != null) ...[
                      const SizedBox(height: 8),
                      _buildRefundBanner(order.cancellationRefund!),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'ZMW ${order.totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                order.isPickup ? 'Pickup' : 'Delivery',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.divider),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  order.deliveryAddress.isEmpty ? '—' : order.deliveryAddress,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
              ),
              if (order.isPickup && (order.pickupTimeSlot?.isNotEmpty ?? false))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Pickup time: ${order.pickupTimeSlot}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              if (order.isDelivery && order.quotedDeliveryFee != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Estimated delivery fee: ZMW ${order.quotedDeliveryFee!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              if (order.specialInstructions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Notes: ${order.specialInstructions}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
              if (order.paymentProviderSnapshot.isNotEmpty &&
                  order.paymentProviderSnapshot != 'payment_disabled') ...[
                const SizedBox(height: 10),
                Text(
                  'Payment: ${_friendlyProvider(order.paymentProviderSnapshot)}'
                  '${order.paymentAccountSnapshot.isNotEmpty && order.paymentAccountSnapshot != 'payment_disabled' ? ' · ${order.paymentAccountSnapshot}' : ''}',
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                'Items',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              ...order.items.map(
                (line) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.productName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              'Qty ${line.quantity} × ZMW ${line.price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'ZMW ${line.subtotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (['pending', 'payment_pending', 'accepted'].contains(order.status)) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _cancelOrder(context, ref, order.id),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel order'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error),
                  ),
                ),
              ],
              if (order.status == 'preparing') ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _requestCancellation(context, ref, order.id),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Request cancellation'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.warning),
                  ),
                ),
              ],
              if (order.isDelivery &&
                  order.status == 'out_for_delivery')
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.go(
                      '/buyer/track-order?order=${Uri.encodeComponent(order.orderNumber)}',
                    ),
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const Text('Track delivery'),
                  ),
                ),
              if (order.status == 'delivered' && !hasBuyerOrderRating) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _rateOrder(context, ref, order.id),
                    icon: const Icon(Icons.star_rate_rounded),
                    label: const Text('Rate this order'),
                  ),
                ),
              ],
              if (order.status == 'delivered') ...[
                const SizedBox(height: 10),
                if (order.refundRequestStatus == null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _requestRefund(context, ref, order.id),
                      icon: const Icon(Icons.assignment_return_outlined),
                      label: const Text('Request refund'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppTheme.warning),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _refundStatusColor(order.refundRequestStatus!)
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _refundStatusColor(order.refundRequestStatus!)
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.assignment_return_outlined,
                          size: 16,
                          color: _refundStatusColor(order.refundRequestStatus!),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Refund: ${_refundStatusLabel(order.refundRequestStatus!)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _refundStatusColor(order.refundRequestStatus!),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (order.sellerPhone?.isNotEmpty ?? false) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _call(order.sellerPhone!),
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Call seller'),
                  ),
                ),
              ],
              if (order.sellerShopLat != null && order.sellerShopLng != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showWalkToShopSheet(
                      context,
                      lat: order.sellerShopLat!,
                      lng: order.sellerShopLng!,
                      shopName: order.sellerShopName,
                      shopLocation: order.sellerShopLocation,
                    ),
                    icon: const Icon(Icons.directions_walk_rounded),
                    label: const Text('Walk / drive to shop'),
                  ),
                ),
              ],
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryCyan),
        ),
        error: (e, _) {
          final isDio = e is DioException;
          final is404 = isDio && e.response?.statusCode == 404;
          final msg = is404
              ? 'Order not found.'
              : isDio
                  ? 'Could not load order. Please try again.'
                  : 'Something went wrong.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 48,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    msg,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/buyer/orders'),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to orders'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WalkToShopSheet extends StatelessWidget {
  final double lat;
  final double lng;
  final String? shopName;
  final String? shopLocation;

  const _WalkToShopSheet({
    required this.lat,
    required this.lng,
    this.shopName,
    this.shopLocation,
  });

  Future<void> _openInMaps() async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=$lat,$lng&travelmode=walking',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.store_rounded, color: AppTheme.primaryCyan, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shopName?.isNotEmpty == true ? shopName! : 'Seller shop',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          if (shopLocation?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                shopLocation!,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: OsmRouteMap(
              height: 260,
              refitBoundsWhenDataChanges: true,
              markers: [
                MapMarker(
                  point: LatLng(lat, lng),
                  icon: Icons.store,
                  color: AppTheme.darkCyan,
                  size: 36,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openInMaps,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open in Google Maps'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryCyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
