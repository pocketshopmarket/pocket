import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/notification_provider.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch full list on screen open.
    Future.microtask(
      () => ref.read(notificationProvider.notifier).fetchNotifications(),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'order_placed':
        return Icons.shopping_bag_rounded;
      case 'order_accepted':
        return Icons.check_circle_rounded;
      case 'order_preparing':
        return Icons.restaurant_rounded;
      case 'order_ready':
        return Icons.inventory_2_rounded;
      case 'order_out_for_delivery':
        return Icons.delivery_dining_rounded;
      case 'order_delivered':
        return Icons.done_all_rounded;
      case 'order_cancelled':
        return Icons.cancel_rounded;
      case 'payout_completed':
        return Icons.account_balance_wallet_rounded;
      case 'delivery_assigned':
        return Icons.local_shipping_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'order_placed':
        return AppTheme.accentBlue;
      case 'order_accepted':
        return AppTheme.success;
      case 'order_preparing':
        return AppTheme.accentOrange;
      case 'order_ready':
        return AppTheme.primaryCyan;
      case 'order_out_for_delivery':
        return AppTheme.accentPurple;
      case 'order_delivered':
        return AppTheme.success;
      case 'order_cancelled':
        return AppTheme.error;
      case 'payout_completed':
        return const Color(0xFF10B981);
      case 'delivery_assigned':
        return AppTheme.darkCyan;
      default:
        return AppTheme.textSecondary;
    }
  }

  String _timeAgo(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationProvider);
    final notifications = state.notifications;

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppTheme.softSurface,
        actions: [
          if (state.unreadCount > 0)
            TextButton.icon(
              onPressed: () =>
                  ref.read(notificationProvider.notifier).markAllAsRead(),
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Read all'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryCyan,
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: state.isLoading && notifications.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: AppTheme.primaryCyan,
                  onRefresh: () => ref
                      .read(notificationProvider.notifier)
                      .fetchNotifications(),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: AppTheme.divider.withValues(alpha: 0.5),
                      indent: 72,
                    ),
                    itemBuilder: (context, index) {
                      final n = notifications[index];
                      return _buildNotificationTile(n);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppTheme.lightCyan.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_off_outlined,
              size: 40,
              color: AppTheme.primaryCyan.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: AppTheme.headline3.copyWith(color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'ll be notified about order updates here.',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationTile(Map<String, dynamic> n) {
    final isRead = n['is_read'] == true;
    final type = n['notification_type'] as String? ?? 'general';
    final color = _colorForType(type);

    return InkWell(
      onTap: () {
        if (!isRead) {
          ref.read(notificationProvider.notifier).markAsRead(n['id'] as int);
        }
      },
      child: Container(
        color: isRead ? Colors.transparent : AppTheme.lightCyan.withValues(alpha: 0.15),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_iconForType(type), color: color, size: 22),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n['title'] as String? ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isRead ? FontWeight.w500 : FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _timeAgo(n['created_at'] as String? ?? ''),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    n['message'] as String? ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      fontWeight:
                          isRead ? FontWeight.w400 : FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Unread dot
            if (!isRead) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryCyan,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryCyan.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
