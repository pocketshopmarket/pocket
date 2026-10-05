import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transport_request.dart';
import '../services/transport_service.dart';

final transportServiceProvider = Provider<TransportService>((ref) => TransportService());

final transportRequestsProvider =
    FutureProvider.autoDispose<List<TransportRequest>>((ref) async {
  final svc = ref.watch(transportServiceProvider);
  return svc.list();
});
