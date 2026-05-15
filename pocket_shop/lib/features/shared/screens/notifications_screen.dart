import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/notification_provider.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _bounceController;
  late final AnimationController _shakeController;
  late final AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(notificationProvider.notifier).fetchNotifications(),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bounceController.dispose();
    _shakeController.dispose();
    _slideController.dispose();
    super.dispose();
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
      case 'payment_pending':
        return Icons.hourglass_top_rounded;
      case 'payment_completed':
        return Icons.verified_rounded;
      case 'payment_failed':
        return Icons.error_rounded;
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
      case 'payment_pending':
        return const Color(0xFFF59E0B);
      case 'payment_completed':
        return const Color(0xFF10B981);
      case 'payment_failed':
        return const Color(0xFFEF4444);
      case 'payout_completed':
        return const Color(0xFF10B981);
      case 'delivery_assigned':
        return AppTheme.darkCyan;
      default:
        return AppTheme.textSecondary;
    }
  }

  /// Returns the animated icon widget based on notification type.
  Widget _animatedIconForType(String type, Color color) {
    final icon = _iconForType(type);
    const double iconSize = 22;

    switch (type) {
      // Pulsing glow for pending payment
      case 'payment_pending':
        return AnimatedBuilder(
          animation: _pulseController,
          builder: (_, child) {
            final scale = 1.0 + (_pulseController.value * 0.15);
            final opacity = 0.3 + (_pulseController.value * 0.4);
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 44 * scale,
                  height: 44 * scale,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14 * scale),
                    color: color.withValues(alpha: opacity * 0.15),
                  ),
                ),
                Icon(icon, color: color, size: iconSize),
              ],
            );
          },
        );

      // Bounce for delivered / payment success
      case 'order_delivered':
      case 'payment_completed':
        return AnimatedBuilder(
          animation: _bounceController,
          builder: (_, __) {
            final offset = math.sin(_bounceController.value * math.pi) * -3;
            return Transform.translate(
              offset: Offset(0, offset),
              child: Icon(icon, color: color, size: iconSize),
            );
          },
        );

      // Shake for failures / cancellations
      case 'order_cancelled':
      case 'payment_failed':
        return AnimatedBuilder(
          animation: _shakeController,
          builder: (_, __) {
            final offset =
                math.sin(_shakeController.value * math.pi * 4) * 2;
            return Transform.translate(
              offset: Offset(offset, 0),
              child: Icon(icon, color: color, size: iconSize),
            );
          },
        );

      // Slide for delivery in progress
      case 'order_out_for_delivery':
      case 'delivery_assigned':
        return AnimatedBuilder(
          animation: _slideController,
          builder: (_, __) {
            final offset =
                math.sin(_slideController.value * math.pi * 2) * 4;
            return Transform.translate(
              offset: Offset(offset, 0),
              child: Icon(icon, color: color, size: iconSize),
            );
          },
        );

      default:
        return Icon(icon, color: color, size: iconSize);
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

  void _handleNotificationTap(Map<String, dynamic> n) {
    if (n['is_read'] != true) {
      ref.read(notificationProvider.notifier).markAsRead(n['id'] as int);
    }

    // Navigate to relevant screen based on notification type
    final type = n['notification_type'] as String? ?? '';
    final data = n['data'] as Map<String, dynamic>?;

    if (data != null && data.containsKey('order_number')) {
      final orderNumber = data['order_number']?.toString() ?? '';
      if (orderNumber.isNotEmpty) {
        switch (type) {
          case 'order_out_for_delivery':
          case 'delivery_assigned':
            context.push('/buyer/track-order', extra: {'order_number': orderNumber});
            return;
          case 'payment_pending':
          case 'payment_failed':
            context.push('/buyer/payment-pending/$orderNumber');
            return;
          default:
            context.push('/buyer/orders');
            return;
        }
      }
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
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) {
              final scale = 1.0 + (_pulseController.value * 0.08);
              return Transform.scale(
                scale: scale,
                child: Container(
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
              );
            },
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
        HapticFeedback.lightImpact();
        _handleNotificationTap(n);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: isRead
            ? Colors.transparent
            : AppTheme.lightCyan.withValues(alpha: 0.15),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Animated Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: _animatedIconForType(type, color),
              ),
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
                  // Action chip for actionable notifications
                  if (!isRead && _isActionable(type)) ...[
                    const SizedBox(height: 8),
                    _buildActionChip(type, color),
                  ],
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

  bool _isActionable(String type) {
    return const {
      'order_out_for_delivery',
      'delivery_assigned',
      'payment_pending',
      'payment_failed',
    }.contains(type);
  }

  Widget _buildActionChip(String type, Color color) {
    String label;
    IconData chipIcon;

    switch (type) {
      case 'order_out_for_delivery':
      case 'delivery_assigned':
        label = 'Track Order';
        chipIcon = Icons.map_outlined;
        break;
      case 'payment_pending':
        label = 'View Payment';
        chipIcon = Icons.payment_rounded;
        break;
      case 'payment_failed':
        label = 'Retry Payment';
        chipIcon = Icons.refresh_rounded;
        break;
      default:
        label = 'View';
        chipIcon = Icons.arrow_forward_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(chipIcon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
