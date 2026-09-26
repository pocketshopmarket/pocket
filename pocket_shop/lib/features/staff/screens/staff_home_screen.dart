import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../services/staff_service.dart';
import 'staff_payouts_screen.dart';

final _statsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return StaffService().getStats();
});

class StaffHomeScreen extends ConsumerWidget {
  const StaffHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(_statsProvider);
    final user = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Dashboard'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_statsProvider),
          ),
          TextButton.icon(
            onPressed: () async {
              // baseUrl is e.g. "http://host/api/" — strip /api/ to reach root
              final root = AppConstants.baseUrl.replaceAll(RegExp(r'/api/?$'), '');
              final uri = Uri.parse('$root/manual/');
              if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.menu_book_rounded, size: 18),
            label: const Text('Manual'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryCyan),
          ),
          Consumer(
            builder: (context, ref, _) {
              final unread = ref.watch(notificationProvider).unreadCount;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () => context.push('/notifications'),
                  ),
                  if (unread > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_statsProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (user != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Welcome, ${user.displayName}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            stats.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => _ErrorCard(
                message: StaffService.errorMessage(e, fallback: 'Could not load the dashboard. Check your connection.'),
                onRetry: () => ref.invalidate(_statsProvider),
              ),
              data: (data) => _StatsGrid(data: data),
            ),
          ],
        ),
      ),
    );
  }
}

// Bottom-navigation positions in StaffMainScreen.
const _branchPayouts = 1;
const _branchVerify = 2;
const _branchRefunds = 3;

class _StatsGrid extends ConsumerWidget {
  final Map<String, dynamic> data;

  const _StatsGrid({required this.data});

  /// Jump to the tab that holds the work behind a number, so the dashboard
  /// is a starting point rather than a dead end.
  void _open(BuildContext context, WidgetRef ref, int branch, {int? payoutsTab}) {
    if (payoutsTab != null) ref.read(staffPayoutsTabProvider.notifier).state = payoutsTab;
    StatefulNavigationShell.of(context).goBranch(branch);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Payout Queue',
                value: '${data['payout_queue_count'] ?? 0}',
                icon: Icons.pending_actions_rounded,
                color: Colors.orange,
                onTap: () => _open(context, ref, _branchPayouts, payoutsTab: staffPayoutsTabSellers),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Earnings Claims',
                value: '${data['withdrawal_count'] ?? 0}',
                icon: Icons.request_quote_rounded,
                color: Colors.blue,
                onTap: () => _open(context, ref, _branchPayouts, payoutsTab: staffPayoutsTabClaims),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Verifications',
                value: '${data['verification_count'] ?? 0}',
                icon: Icons.verified_user_rounded,
                color: Colors.green,
                onTap: () => _open(context, ref, _branchVerify),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Refunds',
                value: '${data['refund_count'] ?? 0}',
                icon: Icons.assignment_return_rounded,
                color: Colors.red,
                onTap: () => _open(context, ref, _branchRefunds),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                // This is money collected from buyers today (gross), not
                // Pocket Shop's own revenue, so don't call it revenue.
                label: 'Collected today',
                value: 'ZMW ${data['today_revenue'] ?? '0.00'}',
                icon: Icons.trending_up_rounded,
                color: Colors.purple,
                wide: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Failed Payouts',
                value: '${data['failed_payouts_count'] ?? 0}',
                icon: Icons.error_outline_rounded,
                color: Colors.red,
                onTap: () => _open(context, ref, _branchPayouts, payoutsTab: staffPayoutsTabFailed),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Users', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _userTypeChip(Icons.shopping_bag_rounded, 'Buyers', '${data['buyer_count'] ?? 0}', Colors.blue),
                  const SizedBox(width: 8),
                  _userTypeChip(Icons.storefront_rounded, 'Sellers', '${data['seller_count'] ?? 0}', Colors.green),
                  const SizedBox(width: 8),
                  _userTypeChip(Icons.delivery_dining_rounded, 'Riders', '${data['rider_count'] ?? 0}', Colors.orange),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _userTypeChip(IconData icon, String label, String count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(count, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool wide;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.wide = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
      ),
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
