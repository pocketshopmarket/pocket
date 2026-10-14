import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/staff_service.dart';

final _analyticsDaysProvider = StateProvider.autoDispose<int>((ref) => 30);

final _analyticsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  final days = ref.watch(_analyticsDaysProvider);
  return StaffService().getAnalytics(days: days);
});

class StaffAnalyticsScreen extends ConsumerWidget {
  const StaffAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(_analyticsProvider);
    final days = ref.watch(_analyticsDaysProvider);

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_analyticsProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_analyticsProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Period',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondary),
                ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7d')),
                    ButtonSegment(value: 30, label: Text('30d')),
                    ButtonSegment(value: 90, label: Text('90d')),
                    ButtonSegment(value: 365, label: Text('1y')),
                  ],
                  selected: {days},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) =>
                      ref.read(_analyticsDaysProvider.notifier).state = s.first,
                ),
              ],
            ),
            const SizedBox(height: 16),
            analytics.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _ErrorCard(
                message: StaffService.errorMessage(e, fallback: 'Could not load analytics.'),
                onRetry: () => ref.invalidate(_analyticsProvider),
              ),
              data: (data) => _AnalyticsBody(data: data),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AnalyticsBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final breakdown = Map<String, dynamic>.from(data['user_breakdown'] as Map);
    final stores = List<Map<String, dynamic>>.from(
      (data['top_stores'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final products = List<Map<String, dynamic>>.from(
      (data['top_products'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Users'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.7,
          children: [
            _StatTile(label: 'Buyers', value: '${breakdown['buyer_count']}', icon: Icons.shopping_bag_outlined, color: AppTheme.primaryCyan),
            _StatTile(label: 'Sellers', value: '${breakdown['seller_count']}', icon: Icons.storefront_outlined, color: AppTheme.success),
            _StatTile(label: 'Riders', value: '${breakdown['rider_count']}', icon: Icons.delivery_dining_outlined, color: AppTheme.warning),
            _StatTile(label: 'Staff', value: '${breakdown['staff_count']}', icon: Icons.badge_outlined, color: AppTheme.accentBlue),
          ],
        ),
        const SizedBox(height: 8),
        _StatTile(
          label: 'New signups this period',
          value: '${breakdown['new_signups']}',
          icon: Icons.person_add_alt_1_outlined,
          color: AppTheme.darkCyan,
          wide: true,
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Top performing stores'),
        if (stores.isEmpty)
          const _EmptyNote('No delivered orders in this period yet.')
        else
          ...List.generate(
            stores.length,
            (i) => _RankedRow(
              rank: i + 1,
              title: stores[i]['shop_name']?.toString() ?? 'Unnamed store',
              subtitle: '${stores[i]['orders_count']} orders',
              value: 'ZMW ${stores[i]['revenue']}',
            ),
          ),
        const SizedBox(height: 20),
        const _SectionTitle('Top performing products'),
        if (products.isEmpty)
          const _EmptyNote('No delivered orders in this period yet.')
        else
          ...List.generate(
            products.length,
            (i) => _RankedRow(
              rank: i + 1,
              title: products[i]['name']?.toString() ?? 'Product',
              subtitle: '${products[i]['shop_name']} · ${products[i]['units_sold']} sold',
              value: 'ZMW ${products[i]['revenue']}',
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool wide;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: wide
          ? Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                ),
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 6),
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
    );
  }
}

class _RankedRow extends StatelessWidget {
  final int rank;
  final String title;
  final String subtitle;
  final String value;

  const _RankedRow({
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primaryCyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$rank',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.darkCyan),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
