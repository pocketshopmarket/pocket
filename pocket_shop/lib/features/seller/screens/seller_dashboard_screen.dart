import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/order.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/cart_provider.dart';
import '../../../widgets/notification_bell.dart';
import '../../../widgets/qr_identity_sheet.dart';

class SellerDashboardScreen extends ConsumerStatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  ConsumerState<SellerDashboardScreen> createState() =>
      _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends ConsumerState<SellerDashboardScreen> {
  bool _loading = true;
  String? _statsError;
  Map<String, dynamic> _metrics = {};
  List<Order> _recent = [];
  List<Map<String, dynamic>> _trends = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _payouts = [];
  int _days = 7;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _statsError = null;
    });
    await ref.read(authProvider.notifier).refreshUser();
    if (!mounted) return;
    final svc = ref.read(orderServiceProvider);
    try {
      final raw = await svc.fetchSellerDashboardStats(days: _days);
      if (!mounted) return;
      final m = raw['metrics'];
      final recentRaw = raw['recent_orders'];
      final recent = <Order>[];
      if (recentRaw is List) {
        for (final e in recentRaw) {
          if (e is Map<String, dynamic>) {
            recent.add(Order.fromJson(e));
          } else if (e is Map) {
            recent.add(Order.fromJson(Map<String, dynamic>.from(e)));
          }
        }
      }
      setState(() {
        _metrics = m is Map<String, dynamic>
            ? Map<String, dynamic>.from(m)
            : {};
        _recent = recent;
        _trends = ((raw['trends'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _topProducts = ((raw['top_products'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _payouts = ((raw['payouts'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      _statsError = svc.extractErrorMessage(e);
      _metrics = {};
      _recent = [];
      _trends = [];
      _topProducts = [];
      _payouts = [];
      try {
        final fallback = await svc.fetchOrders();
        fallback.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _recent = fallback.take(5).toList();
      } catch (_) {}
      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statsError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sellerName = ref.watch(userProvider)?.displayName ?? 'Seller';
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Seller dashboard'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.textPrimary,
        actions: [
          IconButton(
            tooltip: 'My QR code',
            onPressed: () => QrIdentitySheet.show(context),
            icon: const Icon(Icons.qr_code_rounded),
          ),
          const NotificationBell(),
          const SizedBox(width: 8),
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
                    Text(
                      'Welcome, $sellerName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Track revenue, monitor stock, and manage products.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFD1D5DB),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Date range filter
                    Row(
                      children: [7, 30, 90].map((d) {
                        final selected = _days == d;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () {
                              if (_days != d) {
                                setState(() => _days = d);
                                _load();
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: selected ? AppTheme.primaryCyan : Colors.white12,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${d}d',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: selected ? Colors.black : Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _heroChip(
                          label: 'Orders',
                          value: _metrics['orders_count']?.toString() ?? '0',
                        ),
                        const SizedBox(width: 8),
                        _heroChip(
                          label: 'Pending',
                          value: _metrics['pending_count']?.toString() ?? '0',
                        ),
                        const SizedBox(width: 8),
                        _heroChip(
                          label: 'Low stock',
                          value:
                              _metrics['low_stock_products']?.toString() ?? '0',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_statsError != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.error.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    _statsError!,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryCyan,
                    ),
                  ),
                )
              else ...[
                _metricRow(context),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => context.go('/seller/products'),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add product'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => context.push('/seller/payout'),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Claim earnings'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.success,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                if (_trends.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '7-day trends',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._trends.map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceWhite,
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
                              child: Text(
                                row['day']?.toString() ?? '-',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              '${row['orders_count'] ?? 0} orders',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'ZMW ${row['revenue'] ?? '0'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.darkCyan,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (_topProducts.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Top products',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._topProducts.map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceWhite,
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
                              child: Text(
                                row['name']?.toString() ?? '-',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text('${row['units_sold'] ?? 0} sold'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (_payouts.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Seller payouts',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.push(
                          '/seller/payout-history',
                          extra: _payouts,
                        ),
                        child: const Text('See all'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._payouts.take(5).map((row) {
                    final amountColor = row['amount_color'] == 'green'
                        ? AppTheme.success
                        : AppTheme.warning;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                row['order_number']?.toString() ?? '-',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              'ZMW ${row['amount'] ?? '0'}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: amountColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent orders',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.go('/seller/orders'),
                      child: const Text('See all'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_recent.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No orders yet',
                        style: TextStyle(
                          color: AppTheme.textSecondary.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  )
                else
                  ..._recent.map((o) => _RecentOrderTile(order: o)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricRow(BuildContext context) {
    final total = _metrics['orders_count']?.toString() ?? '0';
    final pending = _metrics['pending_count']?.toString() ?? '0';
    final revenue = _metrics['revenue']?.toString() ?? '0';
    final lowStock = _metrics['low_stock_products']?.toString() ?? '0';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'All orders',
                value: total,
                icon: Icons.receipt_long_outlined,
                color: AppTheme.darkCyan,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                label: 'Pending',
                value: pending,
                icon: Icons.schedule_outlined,
                color: AppTheme.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Revenue (delivered)',
                value: 'ZMW $revenue',
                icon: Icons.payments_outlined,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                label: 'Low stock (≤5)',
                value: lowStock,
                icon: Icons.inventory_2_outlined,
                color: AppTheme.primaryCyan,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              height: 1.25,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _heroChip extends StatelessWidget {
  const _heroChip({required this.label, required this.value});

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

class _RecentOrderTile extends StatelessWidget {
  const _RecentOrderTile({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          title: Text(
            order.orderNumber,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${order.items.length} item(s) · ZMW ${order.totalPrice.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          onTap: () => context.go('/seller/orders'),
        ),
      ),
    );
  }
}
