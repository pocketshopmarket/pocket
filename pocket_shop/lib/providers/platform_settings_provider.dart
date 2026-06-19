import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../services/api_service.dart';

final platformSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await ApiService().get(AppConstants.settingsEndpoint);
  return Map<String, dynamic>.from(res.data as Map);
});

T _val<T>(AsyncValue<Map<String, dynamic>> v, String key, T fallback) =>
    v.whenData((s) => s[key] as T? ?? fallback).valueOrNull ?? fallback;

final orderTimeoutMinutesProvider = Provider<int>((ref) {
  final v = ref.watch(platformSettingsProvider);
  return v.whenData((s) => (s['order_acceptance_timeout_minutes'] as num?)?.toInt() ?? 30).valueOrNull ?? 30;
});

final commissionRateProvider = Provider<double>((ref) =>
    _val(ref.watch(platformSettingsProvider), 'commission_rate', 0.05));

final deliveryPerKmRateProvider = Provider<double>((ref) =>
    _val(ref.watch(platformSettingsProvider), 'delivery_per_km_rate', 8.0));

final deliveryShortDistanceThresholdProvider = Provider<double>((ref) =>
    _val(ref.watch(platformSettingsProvider), 'delivery_short_distance_threshold_km', 2.0));

final deliveryShortDistanceFlatRateProvider = Provider<double>((ref) =>
    _val(ref.watch(platformSettingsProvider), 'delivery_short_distance_flat_rate', 12.0));

final maintenanceModeProvider = Provider<bool>((ref) =>
    _val(ref.watch(platformSettingsProvider), 'maintenance_mode', false));

final maintenanceMessageProvider = Provider<String>((ref) =>
    _val(ref.watch(platformSettingsProvider), 'maintenance_message', 'Under maintenance. Please try again shortly.'));
