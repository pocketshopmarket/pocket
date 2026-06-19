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
  bool _trendsExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _statsError = null;
      _trendsExpanded = false;
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
                    label: Text(
                      () {
                        final pending = _metrics['seller_pending_payouts']?.toString() ?? '0';
                        final amt = double.tryParse(pending) ?? 0;
                        return amt > 0
                            ? 'Claim earnings · ZMW ${amt.toStringAsFixed(2)}'
                            : 'Claim earnings';
                      }(),
                    ),
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
                        '$_days-day trends',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...(_trendsExpanded ? _trends : _trends.take(5).toList()).map(
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
                              style: const TextStyle(fontWeight: FontWeight.w600),
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
                  if (_trends.length > 5)
                    TextButton(
                      onPressed: () => setState(() => _trendsExpanded = !_trendsExpanded),
                      child: Text(
                        _trendsExpanded
                            ? 'Show less'
                            : 'Show all $_days days',
                        style: const TextStyle(color: AppTheme.primaryCyan),
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
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${row['units_sold'] ?? 0} sold',
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                ),
                                Text(
                                  'ZMW ${row['revenue'] ?? '0'}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.darkCyan,
                                  ),
                                ),
                              ],
                            ),
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
                    final isPaid = row['amount_color'] == 'green';
                    final amountColor = isPaid ? AppTheme.success : AppTheme.warning;
                    final status = row['status']?.toString() ?? '';
                    final stage = row['payout_stage']?.toString() ?? '';
                    final statusLabel = isPaid
                        ? 'Paid'
                        : (status == 'pending' ? 'Pending' : _capitalize(status));
                    final rawDate = row['created_at'];
                    String dateStr = '';
                    if (rawDate != null) {
                      try {
                        final dt = DateTime.parse(rawDate.toString()).toLocal();
                        dateStr = '${dt.day}/${dt.month}/${dt.year}';
                      } catch (_) {}
                    }
                    final _ = stage; // payout_stage available if needed
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row['order_number']?.toString() ?? '-',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (dateStr.isNotEmpty)
                                    Text(
                                      dateStr,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'ZMW ${row['amount'] ?? '0'}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: amountColor,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: amountColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    statusLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: amountColor,
                                    ),
                                  ),
                                ),
                              ],
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
    final payoutTotal = _metrics['seller_payout_total']?.toString() ?? '0';
    final payoutPending = _metrics['seller_pending_payouts']?.toString() ?? '0';

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
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Total paid out',
                value: 'ZMW $payoutTotal',
                icon: Icons.check_circle_outline_rounded,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                label: 'Pending payouts',
                value: 'ZMW $payoutPending',
                icon: Icons.hourglass_empty_rounded,
                color: AppTheme.warning,
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

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _RecentOrderTile extends StatelessWidget {
  const _RecentOrderTile({required this.order});

  final Order order;

  Color get _statusColor {
    switch (order.status) {
      case 'pending':
      case 'payment_pending':
        return AppTheme.warning;
      case 'accepted':
      case 'preparing':
        return AppTheme.primaryCyan;
      case 'out_for_delivery':
        return AppTheme.accentBlue;
      case 'delivered':
        return AppTheme.success;
      case 'cancelled':
        return AppTheme.error;
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => context.go('/seller/orders'),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 8,
                offset: Offset(0, 2),
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
                      order.orderNumber,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${order.buyerName ?? 'Buyer'} · ${order.items.length} item(s) · ZMW ${order.totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  order.statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
