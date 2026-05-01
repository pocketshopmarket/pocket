import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/delivery_provider.dart';

class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  Map<String, dynamic>? _stats;
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
    try {
      final svc = ref.read(deliveryServiceProvider);
      final s = await svc.fetchStats();
      if (mounted) {
        setState(() {
          _stats = s;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e is DioException
              ? ref.read(deliveryServiceProvider).extractErrorMessage(e)
              : e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _stats?['completed_deliveries'];
    final km = _stats?['total_estimated_km'];
    final payoutTotal =
        (_stats?['delivery_payout_total']?.toString() ?? '0').trim();
    final payoutPending =
        (_stats?['delivery_pending_payouts']?.toString() ?? '0').trim();
    final payoutsRaw = _stats?['payouts'];
    final payouts = payoutsRaw is List
        ? payoutsRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : const <Map<String, dynamic>>[];
    final count = n is int ? n : (n is num ? n.toInt() : 0);
    final totalKm = km is num ? km.toDouble() : 0.0;

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryCyan,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Earnings',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Completed trips and distance from your deliveries.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFFD1D5DB),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
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
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppTheme.error),
                  ),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
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
                      Row(
                        children: [
                          Expanded(
                            child: _metricTile(
                              label: 'Completed',
                              value: '$count',
                              icon: Icons.local_shipping_outlined,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _metricTile(
                              label: 'Paid',
                              value: 'ZMW $payoutTotal',
                              icon: Icons.payments_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _metricTile(
                              label: 'Distance',
                              value: '${totalKm.toStringAsFixed(1)} km',
                              icon: Icons.route_outlined,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _metricTile(
                              label: 'Pending',
                              value: 'ZMW $payoutPending',
                              icon: Icons.schedule_outlined,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryCyan.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          count == 0
                              ? 'No completed deliveries yet. Keep going, your stats will update automatically.'
                              : 'Great work! You have completed $count deliveries so far.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.darkCyan,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => context.push('/delivery/payout'),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('Request Payout'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.success,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (payouts.isNotEmpty) ...[
                  const Text(
                    'Recent payout status',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...payouts.take(5).map((row) {
                    final amountColor = row['amount_color'] == 'green'
                        ? AppTheme.success
                        : AppTheme.warning;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              row['order_number']?.toString() ?? '-',
                              style: const TextStyle(fontSize: 12),
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
                    );
                  }),
                ] else
                  Text(
                    'Payout rows will appear here once pickup/dropoff scans trigger payouts.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary.withValues(alpha: 0.9),
                      height: 1.4,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppTheme.primaryCyan),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
