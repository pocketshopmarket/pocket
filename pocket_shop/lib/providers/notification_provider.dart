import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';
import 'auth_provider.dart';

/// Holds the notification state: unread count + list of notifications.
class NotificationState {
  final int unreadCount;
  final List<Map<String, dynamic>> notifications;
  final bool isLoading;

  const NotificationState({
    this.unreadCount = 0,
    this.notifications = const [],
    this.isLoading = false,
  });

  NotificationState copyWith({
    int? unreadCount,
    List<Map<String, dynamic>>? notifications,
    bool? isLoading,
  }) {
    return NotificationState(
      unreadCount: unreadCount ?? this.unreadCount,
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class NotificationNotifier extends StateNotifier<NotificationState> {
  NotificationNotifier() : super(const NotificationState());

  final NotificationService _service = NotificationService();
  Timer? _pollTimer;

  /// Start polling for unread count every [intervalSeconds].
  void startPolling({int intervalSeconds = 30}) {
    if (_pollTimer != null && _pollTimer!.isActive) return;
    fetchUnreadCount();
    _pollTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => fetchUnreadCount(),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> fetchUnreadCount() async {
    try {
      final count = await _service.getUnreadCount();
      state = state.copyWith(unreadCount: count);
    } catch (e) {
      if (kDebugMode) debugPrint('[NotificationProvider] fetchUnreadCount error: $e');
    }
  }

  Future<void> fetchNotifications({int page = 1}) async {
    state = state.copyWith(isLoading: true);
    try {
      final data = await _service.getNotifications(page: page);
      final results = (data['results'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      if (page == 1) {
        state = state.copyWith(notifications: results, isLoading: false);
      } else {
        state = state.copyWith(
          notifications: [...state.notifications, ...results],
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
      if (kDebugMode) debugPrint('[NotificationProvider] fetchNotifications error: $e');
    }
  }

  Future<void> markAsRead(int id) async {
    final ok = await _service.markAsRead(id);
    if (ok) {
      final updated = state.notifications.map((n) {
        if (n['id'] == id) return {...n, 'is_read': true};
        return n;
      }).toList();
      state = state.copyWith(
        notifications: updated,
        unreadCount: (state.unreadCount - 1).clamp(0, 999999),
      );
    }
  }

  Future<void> markAllAsRead() async {
    final ok = await _service.markAllAsRead();
    if (ok) {
      final updated = state.notifications
          .map((n) => {...n, 'is_read': true})
          .toList();
      state = state.copyWith(notifications: updated, unreadCount: 0);
    }
  }

  Future<bool> deleteNotification(int id) async {
    // Optimistically remove from state first for instant UI feedback
    final wasUnread = state.notifications
        .any((n) => n['id'] == id && n['is_read'] != true);
    final updated = state.notifications.where((n) => n['id'] != id).toList();
    state = state.copyWith(
      notifications: updated,
      unreadCount: wasUnread
          ? (state.unreadCount - 1).clamp(0, 999999)
          : state.unreadCount,
    );
    return _service.deleteNotification(id);
  }

  Future<void> clearAll() async {
    // Optimistically clear state
    state = const NotificationState();
    await _service.clearAllNotifications();
  }

  void reset() {
    stopPolling();
    state = const NotificationState();
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}

final notificationProvider =
    StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
  final notifier = NotificationNotifier();

  ref.listen<AuthState>(authProvider, (prev, next) {
    if (next.isAuthenticated && prev?.isAuthenticated != true) {
      notifier.startPolling();
    } else if (!next.isAuthenticated && prev?.isAuthenticated == true) {
      notifier.reset();
    }
  }, fireImmediately: true);

  ref.onDispose(() => notifier.stopPolling());
  return notifier;
});
