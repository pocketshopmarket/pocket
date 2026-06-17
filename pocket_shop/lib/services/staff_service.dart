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

  Future<Map<String, dynamic>> markPaid(String txId, {String notes = ''}) async {
    final res = await _api.post(
      '${AppConstants.staffMarkPaidPrefix}$txId/',
      data: {'notes': notes},
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
}
