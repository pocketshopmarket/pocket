import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/delivery_service.dart';

final deliveryServiceProvider = Provider<DeliveryService>((ref) {
  return DeliveryService();
});

final deliveryPricingProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final service = ref.read(deliveryServiceProvider);
  return service.fetchPricingConfig();
});

// Incrementing this triggers ActiveDeliveryScreen to reload its assignment.
final activeDeliveryReloadTriggerProvider = StateProvider<int>((ref) => 0);
