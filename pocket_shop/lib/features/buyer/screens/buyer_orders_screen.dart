import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/order.dart';
import '../../../../providers/orders_provider.dart';
import '../../../../widgets/ui/ps_ui.dart';

class BuyerOrdersScreen extends ConsumerWidget {
  const BuyerOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(buyerOrdersProvider);

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('My Orders'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/buyer/home'),
        ),
      ),
      body: async.when(
        data: (orders) {
          if (orders.isEmpty) {
            return Center(
              child: PsEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No orders yet',
                message: 'Your first order will show up here, with live tracking once it is on the way.',
                actionLabel: 'Start shopping',
                onAction: () => context.go('/buyer/home'),
              ),
            );
          }
          return RefreshIndicator(
            color: AppTheme.primaryCyan,
            onRefresh: () async {
              ref.invalidate(buyerOrdersProvider);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: AppTheme.textPrimary,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.receipt_long_rounded,
                          color: AppTheme.surfaceWhite,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${orders.length} order${orders.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final o = orders[i - 1];
                return _OrderTile(order: o);
              },
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryCyan),
        ),
        error: (e, _) => Center(
          child: PsEmptyState(
            icon: Icons.cloud_off_rounded,
            title: "Couldn't load your orders",
            message: 'Check your connection, then try again.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(buyerOrdersProvider),
          ),
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final Order order;

  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final stages = _stages;
    final currentIndex = _stageIndex(order.status);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/buyer/orders/${order.id}'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.orderNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _statusColor(order.status),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        order.statusLabel,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _statusColor(order.status),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${order.items.length} item(s) · ${order.isPickup ? 'Pickup' : 'Delivery'} · ZMW ${order.totalPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDate(order.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 10),
              if (order.status == 'cancelled')
                Row(
                  children: [
                    const Icon(Icons.cancel_outlined, size: 14, color: AppTheme.error),
                    const SizedBox(width: 5),
                    Text(
                      'Order cancelled',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.error.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: List.generate(stages.length, (index) {
                    final active = index <= currentIndex;
                    final isLast = index == stages.length - 1;
                    return Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: active ? AppTheme.primaryCyan : AppTheme.divider,
                              shape: BoxShape.circle,
                            ),
                          ),
                          if (!isLast)
                            Expanded(
                              child: Container(
                                height: 2,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                color: active
                                    ? AppTheme.primaryCyan.withValues(alpha: 0.55)
                                    : AppTheme.divider,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'cancelled':        return AppTheme.error;
      case 'delivered':        return AppTheme.success;
      case 'payment_pending':  return const Color(0xFFB45309);
      case 'out_for_delivery': return AppTheme.accentPurple;
      default:                 return AppTheme.darkCyan;
    }
  }

  static const List<String> _stages = [
    'pending',
    'accepted',
    'out_for_delivery',
    'delivered',
  ];

  int _stageIndex(String status) {
    final idx = _stages.indexOf(status);
    if (idx >= 0) return idx;
    if (status == 'preparing') return 1;
    if (status == 'cancelled') return 0;
    return 0;
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
