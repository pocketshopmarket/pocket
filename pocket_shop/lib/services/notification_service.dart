import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import 'api_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final ApiService _api = ApiService();

  /// Fetch paginated notifications for the current user.
  Future<Map<String, dynamic>> getNotifications({int page = 1}) async {
    try {
      final response = await _api.get(
        AppConstants.notificationsEndpoint,
        queryParameters: {'page': page},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('[NotificationService] getNotifications error: $e');
      rethrow;
    }
  }

  /// Get unread notification count.
  Future<int> getUnreadCount() async {
    try {
      final response = await _api.get(AppConstants.notificationsUnreadCountEndpoint);
      final data = response.data as Map<String, dynamic>;
      return data['count'] as int? ?? 0;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('[NotificationService] getUnreadCount error: $e');
      return 0;
    }
  }

  /// Mark a single notification as read.
  Future<bool> markAsRead(int notificationId) async {
    try {
      await _api.post('${AppConstants.notificationsEndpoint}$notificationId/read/');
      return true;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('[NotificationService] markAsRead error: $e');
      return false;
    }
  }

  /// Mark all notifications as read.
  Future<bool> markAllAsRead() async {
    try {
      await _api.post(AppConstants.notificationsMarkAllReadEndpoint);
      return true;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('[NotificationService] markAllAsRead error: $e');
      return false;
    }
  }
}
