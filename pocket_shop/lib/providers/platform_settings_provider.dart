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

final buyerServiceFeeRateProvider = Provider<double>((ref) =>
    _val(ref.watch(platformSettingsProvider), 'buyer_service_fee_rate', 0.0));

class BuyerServiceFeeTier {
  final double minOrderValue;
  final double? maxOrderValue;
  final double feeRate;

  const BuyerServiceFeeTier({
    required this.minOrderValue,
    this.maxOrderValue,
    required this.feeRate,
  });

  factory BuyerServiceFeeTier.fromJson(Map<String, dynamic> json) => BuyerServiceFeeTier(
        minOrderValue: (json['min_order_value'] as num).toDouble(),
        maxOrderValue: (json['max_order_value'] as num?)?.toDouble(),
        feeRate: (json['fee_rate'] as num).toDouble(),
      );
}

final buyerServiceFeeTiersProvider = Provider<List<BuyerServiceFeeTier>>((ref) {
  final raw = ref
      .watch(platformSettingsProvider)
      .whenData((s) => s['buyer_service_fee_tiers'] as List?)
      .valueOrNull;
  if (raw == null) return const [];
  return raw
      .map((e) => BuyerServiceFeeTier.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
});

/// Picks the tier covering [orderSubtotal], falling back to the flat
/// buyer_service_fee_rate when no tiers are configured or none match
/// (e.g. a gap left by admin misconfiguration) — mirrors
/// portal.models.get_buyer_service_fee_rate on the server, which is always
/// the authoritative calculation at order-creation time regardless of what
/// this preview shows.
double buyerServiceFeeRateForAmount(WidgetRef ref, double orderSubtotal) {
  final tiers = ref.read(buyerServiceFeeTiersProvider);
  for (final t in tiers) {
    if (orderSubtotal >= t.minOrderValue &&
        (t.maxOrderValue == null || orderSubtotal <= t.maxOrderValue!)) {
      return t.feeRate;
    }
  }
  return ref.read(buyerServiceFeeRateProvider);
}

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
