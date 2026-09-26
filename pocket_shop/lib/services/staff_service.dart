import 'package:dio/dio.dart';

import '../core/constants/app_constants.dart';
import 'api_service.dart';

class StaffService {
  final ApiService _api = ApiService();

  Future<Map<String, dynamic>> getStats() async {
    final res = await _api.get(AppConstants.staffStatsEndpoint);
    return res.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getPayoutQueue({String? role}) async {
    final params = <String, dynamic>{};
    if (role != null && role.isNotEmpty) params['role'] = role;
    final res = await _api.get(AppConstants.staffPayoutQueueEndpoint, queryParameters: params);
    final data = res.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['results'] as List);
  }

  Future<Map<String, dynamic>> markPaid(
    String txId, {
    String notes = '',
    String? proofImagePath,
  }) async {
    final FormData form = FormData.fromMap({
      'notes': notes,
      if (proofImagePath != null && proofImagePath.isNotEmpty)
        'proof_image': await MultipartFile.fromFile(proofImagePath),
    });
    final res = await _api.post(
      '${AppConstants.staffMarkPaidPrefix}$txId/',
      data: form,
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> markRefunded(
    String txId, {
    String notes = '',
    String? proofImagePath,
  }) async {
    final FormData form = FormData.fromMap({
      'notes': notes,
      if (proofImagePath != null && proofImagePath.isNotEmpty)
        'proof_image': await MultipartFile.fromFile(proofImagePath),
    });
    final res = await _api.post(
      '${AppConstants.staffMarkRefundedPrefix}$txId/',
      data: form,
    );
    return res.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getWithdrawals() async {
    final res = await _api.get(AppConstants.staffWithdrawalsEndpoint);
    final data = res.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['results'] as List);
  }

  Future<List<Map<String, dynamic>>> getVerifications() async {
    final res = await _api.get(AppConstants.staffVerificationsEndpoint);
    final data = res.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['results'] as List);
  }

  Future<void> approveVerification(int id) async {
    await _api.post('${AppConstants.staffVerificationsEndpoint}$id/approve/');
  }

  Future<void> rejectVerification(int id, {String reason = ''}) async {
    await _api.post(
      '${AppConstants.staffVerificationsEndpoint}$id/reject/',
      data: {'reason': reason},
    );
  }

  Future<List<Map<String, dynamic>>> getRefunds() async {
    final res = await _api.get(AppConstants.staffRefundsEndpoint);
    final data = res.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['results'] as List);
  }

  /// Pays a card refund (to the buyer's mobile money) or a seller's bank
  /// withdrawal straight from the Lenco account. The result arrives from
  /// Lenco afterwards; the server refuses a second send.
  Future<Map<String, dynamic>> sendViaLenco(String txId, {bool confirmNameMismatch = false}) async {
    final res = await _api.post(
      '${AppConstants.staffSendViaLencoPrefix}$txId/',
      data: {'confirm_name_mismatch': confirmNameMismatch},
    );
    return res.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getFailedPayouts() async {
    final res = await _api.get(AppConstants.staffFailedPayoutsEndpoint);
    final data = res.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['results'] as List);
  }

  Future<void> requeuePayout(String txId) async {
    await _api.post('${AppConstants.staffFailedPayoutsEndpoint}$txId/requeue/');
  }

  /// One place that turns a failed request into something a staff member can
  /// read — the server's own `error` message when it sent one, never a raw
  /// exception dump.
  static String errorMessage(Object e, {String fallback = 'Something went wrong. Please try again.'}) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] is String) return data['error'] as String;
      if (data is Map && data['detail'] is String) return data['detail'] as String;
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Could not reach the server. Check your connection.';
      }
    }
    return fallback;
  }
}
