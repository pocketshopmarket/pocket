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
import '../../../widgets/shimmer_loading.dart';
import '../../../widgets/ui/ps_ui.dart';

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
        _statsError = "Couldn't load your shop stats. Pull down to try again.";
      });
    }
  }

  static const _cardDeco = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.all(Radius.circular(16)),
    border: Border.fromBorderSide(BorderSide(color: AppTheme.divider)),
  );

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  double _num(String key) => double.tryParse(_metrics[key]?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final profile = user?.sellerProfile;
    final firstName = (user?.firstName ?? '').trim().split(' ').first;
    final shopName = profile?.shopName ?? user?.displayName ?? 'Your shop';

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryCyan,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _header(firstName),
              const SizedBox(height: 16),
              _shopCard(shopName, profile?.shopLocation, profile?.isApproved ?? false),
              if (_statsError != null) ...[
                const SizedBox(height: 12),
                _ErrorNote(message: _statsError!, onRetry: _load),
              ],
              const SizedBox(height: 16),
              if (_loading)
                const _DashboardSkeleton()
              else ...[
                _statsGrid(),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => context.go('/seller/products'),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.accentOrange),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add product'),
                  ),
                ),
                const SizedBox(height: 26),
                PsSectionHeader(
                  title: 'Recent orders',
                  actionLabel: 'See all',
                  onAction: () => context.go('/seller/orders'),
                ),
                const SizedBox(height: 10),
                if (_recent.isEmpty)
                  _quietNote(
                    Icons.receipt_long_outlined,
                    'No orders yet',
                    'When a buyer orders from your shop, it lands here first.',
                  )
                else
                  ..._recent.map((o) => _RecentOrderTile(order: o)),
                const SizedBox(height: 16),
                _earningsCard(),
                if (_trends.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  PsSectionHeader(title: 'Sales, last $_days days'),
                  const SizedBox(height: 10),
                  _TrendChart(rows: _trendsExpanded ? _trends : _trends.take(7).toList()),
                  if (_trends.length > 7)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() => _trendsExpanded = !_trendsExpanded),
                        child: Text(_trendsExpanded ? 'Show less' : 'Show all $_days days'),
                      ),
                    ),
                ],
                if (_topProducts.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  const PsSectionHeader(title: 'Best sellers'),
                  const SizedBox(height: 10),
                  _listCard([
                    for (var i = 0; i < _topProducts.length; i++)
                      _TopProductRow(rank: i + 1, row: _topProducts[i]),
                  ]),
                ],
                if (_payouts.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  PsSectionHeader(
                    title: 'Payouts',
                    actionLabel: 'See all',
                    onAction: () => context.push('/seller/payout-history', extra: _payouts),
                  ),
                  const SizedBox(height: 10),
                  _listCard(_payouts.take(5).map((r) => _PayoutRow(row: r)).toList()),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String firstName) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dashboard', style: AppTheme.display(fontSize: 26)),
              const SizedBox(height: 2),
              Text(
                firstName.isEmpty ? '$_greeting.' : '$_greeting, $firstName.',
                style: AppTheme.body(fontSize: 13.5, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        _HeaderButton(
          child: IconButton(
            tooltip: 'My QR code',
            onPressed: () => QrIdentitySheet.show(context),
            icon: const Icon(Icons.qr_code_rounded, size: 20),
          ),
        ),
        const SizedBox(width: 8),
        const _HeaderButton(child: NotificationBell()),
      ],
    );
  }

  Widget _shopCard(String name, String? location, bool verified) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco,
      child: Column(
        children: [
          Row(
            children: [
              const PsIconBadge(icon: Icons.storefront_rounded, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body(fontSize: 15.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (verified) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.verified_rounded, size: 16, color: AppTheme.success),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (location ?? '').isEmpty ? 'Your shop' : location!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(fontSize: 12.5, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PeriodSwitch(
            days: _days,
            onChanged: (d) {
              if (_days == d) return;
              setState(() => _days = d);
              _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _statsGrid() {
    final pending = _num('pending_count');
    final low = _num('low_stock_products');
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: PsStatTile(
                label: 'All orders',
                value: _formatAmount(_num('orders_count')),
                onTap: () => context.go('/seller/orders'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PsStatTile(
                label: 'Pending',
                value: _formatAmount(pending),
                accent: pending > 0 ? AppTheme.accentOrange : null,
                onTap: () => context.go('/seller/orders'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: PsStatTile(
                label: 'Revenue (delivered)',
                value: 'ZMW ${_formatAmount(_num('revenue'))}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PsStatTile(
                label: 'Low stock (≤5)',
                value: _formatAmount(low),
                accent: low > 0 ? AppTheme.accentOrange : null,
                onTap: () => context.go('/seller/products'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _earningsCard() {
    final ready = _num('seller_pending_payouts');
    final paid = _num('seller_payout_total');
    return PsHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ready to claim',
            style: AppTheme.body(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text('ZMW ${_formatAmount(ready)}', style: AppTheme.display(fontSize: 26, color: Colors.white)),
          const SizedBox(height: 4),
          Text(
            'ZMW ${_formatAmount(paid)} paid out so far',
            style: AppTheme.body(fontSize: 12.5, color: Colors.white60),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: () => context.push('/seller/payout'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
              child: Text(ready > 0 ? 'Claim earnings' : 'Payout details'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quietNote(IconData icon, String title, String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco,
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.body(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(message, style: AppTheme.body(fontSize: 12.5, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listCard(List<Widget> rows) {
    return Container(
      decoration: _cardDeco,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// 18420 -> "18,420"; keeps cents only when there are any.
String _formatAmount(double v) {
  final whole = v.truncateToDouble() == v;
  final parts = (whole ? v.toStringAsFixed(0) : v.toStringAsFixed(2)).split('.');
  final digits = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    buf.write(digits[i]);
    final fromEnd = digits.length - i;
    if (fromEnd > 1 && fromEnd % 3 == 1 && digits[i] != '-') buf.write(',');
  }
  return parts.length > 1 ? '$buf.${parts[1]}' : buf.toString();
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _timeAgo(DateTime t) {
  final d = DateTime.now().difference(t.toLocal());
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} hr ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  final l = t.toLocal();
  return '${l.day}/${l.month}/${l.year}';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: child,
      ),
    );
  }
}

class _PeriodSwitch extends StatelessWidget {
  const _PeriodSwitch({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.softSurface,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [7, 30, 90].map((d) {
          final selected = d == days;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(d),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppTheme.textPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$d days',
                  style: AppTheme.body(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.error, width: 1.2),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTheme.body(fontSize: 13, height: 1.35),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.rows});

  final List<Map<String, dynamic>> rows;

  String _dayLabel(dynamic raw) {
    final d = DateTime.tryParse(raw?.toString() ?? '');
    if (d == null) return raw?.toString() ?? '-';
    return '${_weekdays[d.weekday - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final values = rows
        .map((r) => double.tryParse(r['revenue']?.toString() ?? '') ?? 0)
        .toList();
    final maxV = values.fold<double>(0, (a, b) => b > a ? b : a);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      decoration: _SellerDashboardScreenState._cardDeco,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _dayLabel(rows[i]['day']),
                          style: AppTheme.body(fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${rows[i]['orders_count'] ?? 0} orders',
                          style: AppTheme.body(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final f = maxV <= 0 ? 0.0 : values[i] / maxV;
                        return Stack(
                          children: [
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: AppTheme.softSurface,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            Container(
                              width: c.maxWidth * f,
                              height: 8,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryCyan,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 96,
                    child: Text(
                      'ZMW ${_formatAmount(values[i])}',
                      textAlign: TextAlign.right,
                      style: AppTheme.body(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TopProductRow extends StatelessWidget {
  const _TopProductRow({required this.rank, required this.row});

  final int rank;
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final revenue = double.tryParse(row['revenue']?.toString() ?? '') ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$rank',
              style: AppTheme.display(fontSize: 15, color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['name']?.toString() ?? '-',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${row['units_sold'] ?? 0} sold',
                  style: AppTheme.body(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            'ZMW ${_formatAmount(revenue)}',
            style: AppTheme.body(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final isPaid = row['amount_color'] == 'green';
    final color = isPaid ? AppTheme.success : AppTheme.warning;
    final status = row['status']?.toString() ?? '';
    final label = isPaid ? 'Paid' : (status == 'pending' ? 'Pending' : _capitalize(status));
    final amount = double.tryParse(row['amount']?.toString() ?? '') ?? 0;
    String date = '';
    final raw = row['created_at'];
    if (raw != null) {
      final dt = DateTime.tryParse(raw.toString())?.toLocal();
      if (dt != null) date = '${dt.day}/${dt.month}/${dt.year}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['order_number']?.toString() ?? '-',
                  style: AppTheme.body(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                if (date.isNotEmpty)
                  Text(date, style: AppTheme.body(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'ZMW ${_formatAmount(amount)}',
                style: AppTheme.body(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              PsStatusLabel(label: label, color: color, fontSize: 11.5),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentOrderTile extends StatelessWidget {
  const _RecentOrderTile({required this.order});

  final Order order;

  Color get _statusColor {
    switch (order.status) {
      case 'pending':
      case 'payment_pending':
        return AppTheme.accentOrange;
      case 'accepted':
      case 'preparing':
        return AppTheme.darkCyan;
      case 'out_for_delivery':
        return AppTheme.accentPurple;
      case 'delivered':
        return AppTheme.success;
      case 'cancelled':
        return AppTheme.error;
      default:
        return AppTheme.textSecondary;
    }
  }

  String get _buyer {
    final parts = (order.buyerName ?? '').trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'Buyer';
    if (parts.length == 1) return parts.first;
    return '${parts.first} ${parts.last[0]}.';
  }

  @override
  Widget build(BuildContext context) {
    final n = order.items.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => context.go('/seller/orders'),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${order.orderNumber} · $_buyer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$n item${n == 1 ? '' : 's'} · ${_timeAgo(order.createdAt)}',
                        style: AppTheme.body(fontSize: 12.5, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'ZMW ${order.totalPrice.toStringAsFixed(2)}',
                      style: AppTheme.body(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    PsStatusLabel(label: order.statusLabel, color: _statusColor, fontSize: 12),
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

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  Widget _block(double h) => Container(
        height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Column(
        children: [
          Row(children: [Expanded(child: _block(84)), const SizedBox(width: 12), Expanded(child: _block(84))]),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: _block(84)), const SizedBox(width: 12), Expanded(child: _block(84))]),
          const SizedBox(height: 16),
          _block(52),
          const SizedBox(height: 26),
          _block(64),
          const SizedBox(height: 10),
          _block(64),
        ],
      ),
    );
  }
}
