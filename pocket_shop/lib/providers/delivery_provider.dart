import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/delivery_service.dart';

final deliveryServiceProvider = Provider<DeliveryService>((ref) {
  return DeliveryService();
});
