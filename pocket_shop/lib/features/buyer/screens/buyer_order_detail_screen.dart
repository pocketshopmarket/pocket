import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/orders_provider.dart';

class BuyerOrderDetailScreen extends ConsumerWidget {
  final int orderId;

  const BuyerOrderDetailScreen({super.key, required this.orderId});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Order details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
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
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.darkCyan,
                      ),
                    ),
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
              if (order.paymentProviderSnapshot.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Payment: ${order.paymentProviderSnapshot} (${order.paymentAccountSnapshot})',
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
              if (order.isDelivery)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      context.push(
                        '/buyer/track-order?order=${Uri.encodeComponent(order.orderNumber)}',
                      );
                    },
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
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryCyan),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(e.toString(), textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}
