import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../services/api_service.dart';

final platformSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await ApiService().get(AppConstants.settingsEndpoint);
  return Map<String, dynamic>.from(res.data as Map);
});

/// Convenience: returns the order acceptance timeout in minutes, defaulting to
/// 30 if the server hasn't responded yet or returns an unexpected value.
final orderTimeoutMinutesProvider = Provider<int>((ref) {
  return ref
      .watch(platformSettingsProvider)
      .whenData((s) => (s['order_acceptance_timeout_minutes'] as num?)?.toInt() ?? 30)
      .valueOrNull ?? 30;
});
