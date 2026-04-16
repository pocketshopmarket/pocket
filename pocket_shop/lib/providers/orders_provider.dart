import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/order.dart';
import 'cart_provider.dart';

final buyerOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  final svc = ref.watch(orderServiceProvider);
  return svc.fetchOrders();
});

final orderDetailProvider =
    FutureProvider.autoDispose.family<Order, int>((ref, id) async {
  final svc = ref.watch(orderServiceProvider);
  return svc.fetchOrder(id);
});
