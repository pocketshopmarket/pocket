import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
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
    Future.microtask(
      () => ref.read(notificationProvider.notifier).fetchNotifications(),
    );
  }

  // ── Delete helpers ────────────────────────────────────────────────────────

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text('This will permanently delete all your notifications.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ref.read(notificationProvider.notifier).clearAll();
    }
  }

  // ── Back navigation ───────────────────────────────────────────────────────

  void _goBack() {
    // Always navigate home — never pop back to whatever screen opened the bell,
    // because the bell appears on many screens and the user expects "back" to
    // mean "go home", not "go back to orders/search/wherever I was".
    final role = ref.read(authProvider).user?.role ?? AppConstants.buyerRole;
    switch (role) {
      case AppConstants.sellerRole:
        context.go('/seller/dashboard');
      case AppConstants.deliveryRole:
        context.go('/delivery/home');
      default:
        context.go('/buyer/home');
    }
  }

  // ── Notification tap ──────────────────────────────────────────────────────

  void _handleNotificationTap(Map<String, dynamic> n) {
    if (n['is_read'] != true) {
      ref.read(notificationProvider.notifier).markAsRead(n['id'] as int);
    }

    final userRole = ref.read(authProvider).user?.role ?? AppConstants.buyerRole;
    final type = n['notification_type'] as String? ?? '';
    final data = n['data'] as Map<String, dynamic>?;
    final orderId = data?['order_id']?.toString() ?? '';
    final orderNumber = data?['order_number']?.toString() ?? '';

    // Pop notifications first so the user can press back naturally
    final router = GoRouter.of(context);
    if (context.canPop()) context.pop();

    if (userRole == AppConstants.deliveryRole) {
      router.go('/delivery/active');
      return;
    }

    if (userRole == AppConstants.sellerRole) {
      router.go(type == 'payout_completed' ? '/seller/payout' : '/seller/orders');
      return;
    }

    // Buyer
    switch (type) {
      case 'order_out_for_delivery':
      case 'delivery_assigned':
        router.go(
          orderNumber.isNotEmpty
              ? '/buyer/track-order?order=${Uri.encodeComponent(orderNumber)}'
              : '/buyer/orders',
        );
      case 'payment_pending':
        router.go(
          orderNumber.isNotEmpty
              ? '/buyer/payment-pending?order=${Uri.encodeComponent(orderNumber)}'
              : '/buyer/orders',
        );
      case 'payment_failed':
        // Payment failed → order was cancelled; show order detail, not "pending"
        router.go(
          orderId.isNotEmpty ? '/buyer/orders/$orderId' : '/buyer/orders',
        );
      case 'verification_approved':
      case 'verification_rejected':
        router.go('/buyer/profile');
      case 'welcome':
      case 'announcement':
        router.go('/buyer/home');
      default:
        router.go(
          orderId.isNotEmpty ? '/buyer/orders/$orderId' : '/buyer/orders',
        );
    }
  }

  // ── Type helpers ──────────────────────────────────────────────────────────

  IconData _iconForType(String type) {
    switch (type) {
      case 'order_placed':            return Icons.shopping_bag_rounded;
      case 'order_accepted':          return Icons.check_circle_rounded;
      case 'order_preparing':         return Icons.restaurant_rounded;
      case 'order_ready':             return Icons.inventory_2_rounded;
      case 'order_out_for_delivery':  return Icons.delivery_dining_rounded;
      case 'order_delivered':         return Icons.done_all_rounded;
      case 'order_cancelled':         return Icons.cancel_rounded;
      case 'payment_pending':         return Icons.hourglass_top_rounded;
      case 'payment_completed':       return Icons.verified_rounded;
      case 'payment_failed':          return Icons.error_rounded;
      case 'payout_completed':        return Icons.account_balance_wallet_rounded;
      case 'delivery_assigned':       return Icons.local_shipping_rounded;
      case 'welcome':                 return Icons.waving_hand_rounded;
      case 'announcement':            return Icons.campaign_rounded;
      default:                        return Icons.notifications_rounded;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'order_placed':            return AppTheme.accentBlue;
      case 'order_accepted':          return AppTheme.success;
      case 'order_preparing':         return AppTheme.accentOrange;
      case 'order_ready':             return AppTheme.primaryCyan;
      case 'order_out_for_delivery':  return AppTheme.accentPurple;
      case 'order_delivered':         return AppTheme.success;
      case 'order_cancelled':         return AppTheme.error;
      case 'payment_pending':         return const Color(0xFFF59E0B);
      case 'payment_completed':       return const Color(0xFF10B981);
      case 'payment_failed':          return const Color(0xFFEF4444);
      case 'payout_completed':        return const Color(0xFF10B981);
      case 'delivery_assigned':       return AppTheme.darkCyan;
      case 'welcome':                 return AppTheme.primaryCyan;
      case 'announcement':            return const Color(0xFF7C3AED);
      default:                        return AppTheme.textSecondary;
    }
  }

  /// Colorful status badge shown on every notification card.
  _BadgeConfig _badgeForType(String type) {
    switch (type) {
      case 'order_placed':
        return _BadgeConfig('New order', Icons.shopping_bag_rounded, AppTheme.accentBlue);
      case 'order_accepted':
        return _BadgeConfig('Accepted', Icons.check_circle_rounded, AppTheme.success);
      case 'order_preparing':
        return _BadgeConfig('Preparing', Icons.restaurant_rounded, AppTheme.accentOrange);
      case 'order_ready':
        return _BadgeConfig('Ready for pickup', Icons.inventory_2_rounded, AppTheme.primaryCyan);
      case 'order_out_for_delivery':
        return _BadgeConfig('Out for delivery', Icons.delivery_dining_rounded, AppTheme.accentPurple);
      case 'order_delivered':
        return _BadgeConfig('Delivered', Icons.done_all_rounded, AppTheme.success);
      case 'order_cancelled':
        return _BadgeConfig('Cancelled', Icons.cancel_rounded, AppTheme.error);
      case 'payment_pending':
        return _BadgeConfig('Payment pending', Icons.hourglass_top_rounded, const Color(0xFFF59E0B));
      case 'payment_completed':
        return _BadgeConfig('Payment successful', Icons.check_circle_rounded, const Color(0xFF10B981));
      case 'payment_failed':
        return _BadgeConfig('Payment failed', Icons.cancel_rounded, const Color(0xFFEF4444));
      case 'payout_completed':
        return _BadgeConfig('Earnings paid', Icons.payments_rounded, const Color(0xFF10B981));
      case 'delivery_assigned':
        return _BadgeConfig('Rider assigned', Icons.local_shipping_rounded, AppTheme.darkCyan);
      case 'welcome':
        return _BadgeConfig('Welcome', Icons.waving_hand_rounded, AppTheme.primaryCyan);
      case 'announcement':
        return _BadgeConfig('Announcement', Icons.campaign_rounded, const Color(0xFF7C3AED));
      default:
        return _BadgeConfig('Notification', Icons.notifications_rounded, AppTheme.textSecondary);
    }
  }

  String _toAbsoluteUrl(String path) {
    if (path.startsWith('http')) return path;
    final base = Uri.parse(AppConstants.baseUrl);
    return '${base.scheme}://${base.host}:${base.port}$path';
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationProvider);
    final notifications = state.notifications;

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.divider.withValues(alpha: 0.6)),
        ),
        actions: [
          if (state.unreadCount > 0)
            TextButton.icon(
              onPressed: () =>
                  ref.read(notificationProvider.notifier).markAllAsRead(),
              icon: const Icon(Icons.done_all_rounded, size: 16),
              label: const Text('Mark all read'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryCyan,
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          if (notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Clear all',
              color: AppTheme.textSecondary,
              onPressed: () => _confirmClearAll(),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: state.isLoading && notifications.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryCyan),
            )
          : notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: AppTheme.primaryCyan,
                  onRefresh: () =>
                      ref.read(notificationProvider.notifier).fetchNotifications(),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final n = notifications[index];
                      final id = n['id'] as int;
                      return Dismissible(
                        key: ValueKey(id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) {
                          HapticFeedback.mediumImpact();
                          ref
                              .read(notificationProvider.notifier)
                              .deleteNotification(id);
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          margin: const EdgeInsets.only(bottom: 7),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppTheme.error,
                          ),
                        ),
                        child: _buildNotificationCard(n),
                      );
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
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppTheme.lightCyan.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_off_outlined,
              size: 44,
              color: AppTheme.primaryCyan.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "You'll be notified about order and payment updates here.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> n) {
    final isRead = n['is_read'] == true;
    final type = n['notification_type'] as String? ?? 'general';
    final color = _colorForType(type);
    final icon = _iconForType(type);
    final badge = _badgeForType(type);
    final data = n['data'] as Map<String, dynamic>?;
    final rawImageUrl = data?['image_url']?.toString();
    final imageUrl = (rawImageUrl != null && rawImageUrl.isNotEmpty)
        ? _toAbsoluteUrl(rawImageUrl)
        : null;
    final actionChip = _buildActionChip(type, color);

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _handleNotificationTap(n);
          },
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              color: isRead
                  ? Colors.white
                  : AppTheme.lightCyan.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isRead
                    ? AppTheme.divider.withValues(alpha: 0.7)
                    : AppTheme.primaryCyan.withValues(alpha: 0.25),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon / avatar
                _buildLeadingIcon(icon, color, imageUrl),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + time
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              n['title'] as String? ?? '',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isRead
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                color: AppTheme.textPrimary,
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _timeAgo(n['created_at'] as String? ?? ''),
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      // Message
                      Text(
                        n['message'] as String? ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          color: isRead
                              ? AppTheme.textSecondary
                              : AppTheme.textPrimary.withValues(alpha: 0.75),
                          fontWeight: isRead
                              ? FontWeight.w400
                              : FontWeight.w500,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 7),
                      // Colorful status badge — always visible
                      _buildBadge(badge),
                      // Action chip
                      if (actionChip != null) ...[
                        const SizedBox(height: 5),
                        actionChip,
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
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryCyan,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryCyan.withValues(alpha: 0.45),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(_BadgeConfig badge) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: badge.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: badge.color.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, size: 13, color: badge.color),
          const SizedBox(width: 5),
          Text(
            badge.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: badge.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeadingIcon(IconData icon, Color color, String? imageUrl) {
    final Widget avatar = imageUrl != null
        ? CircleAvatar(
            radius: 25,
            backgroundColor: color.withValues(alpha: 0.12),
            backgroundImage: CachedNetworkImageProvider(imageUrl),
          )
        : CircleAvatar(
            radius: 25,
            backgroundColor: AppTheme.lightCyan.withValues(alpha: 0.3),
            backgroundImage:
                const AssetImage('assets/images/logo.jpg'),
          );

    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        children: [
          avatar,
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Icon(icon, color: Colors.white, size: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildActionChip(String type, Color color) {
    final String? label;
    final IconData? icon;

    switch (type) {
      case 'order_out_for_delivery':
      case 'delivery_assigned':
        label = 'Track order';
        icon = Icons.map_outlined;
      case 'payment_pending':
        label = 'View payment';
        icon = Icons.payment_rounded;
      case 'payment_failed':
        label = 'View order';
        icon = Icons.receipt_long_outlined;
      case 'order_placed':
      case 'order_accepted':
      case 'order_preparing':
      case 'order_ready':
      case 'order_delivered':
      case 'order_cancelled':
        label = 'View order';
        icon = Icons.receipt_long_outlined;
      default:
        return null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 3),
          Icon(Icons.arrow_forward_ios_rounded, size: 10, color: color.withValues(alpha: 0.7)),
        ],
      ),
    );
  }
}

// ── Badge data class ──────────────────────────────────────────────────────────

class _BadgeConfig {
  final String label;
  final IconData icon;
  final Color color;
  const _BadgeConfig(this.label, this.icon, this.color);
}
