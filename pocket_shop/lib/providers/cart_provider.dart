import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cart_item.dart';
import '../models/product.dart';
import '../services/order_service.dart';
import 'auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class CartState {
  final List<CartItem> items;
  final bool isLoading;
  final bool isCheckingOut;
  final String? error;

  CartState({
    this.items = const [],
    this.isLoading = false,
    this.isCheckingOut = false,
    this.error,
  });

  CartState copyWith({
    List<CartItem>? items,
    bool? isLoading,
    bool? isCheckingOut,
    String? error,
  }) {
    return CartState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isCheckingOut: isCheckingOut ?? this.isCheckingOut,
      error: error,
    );
  }

  double get totalAmount => items.fold(0.0, (sum, item) => sum + item.subtotal);
  int get totalItems => items.fold(0, (sum, item) => sum + item.quantity);
  bool get isEmpty => items.isEmpty;
}

final orderServiceProvider = Provider<OrderService>((ref) {
  return OrderService();
});

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier(this._ref, this._orderService) : super(CartState()) {
    // Sync immediately on startup — ref.listen only fires on *changes*,
    // so a user who is already logged in at app launch would otherwise see
    // an empty cart until they log out and back in.
    Future.microtask(syncFromServer);
  }

  final Ref _ref;
  final OrderService _orderService;

  Future<void> syncFromServer() async {
    final auth = _ref.read(authProvider);
    if (!auth.isAuthenticated || auth.user?.isBuyer != true) {
      _loadLocalCart();
      return;
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      final items = await _orderService.fetchCart();
      state = state.copyWith(items: items, isLoading: false, error: null);
      _saveLocalCart(items);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e is DioException ? _orderService.extractErrorMessage(e) : e.toString(),
      );
    }
  }

  Future<void> _loadLocalCart() async {
    final prefs = await SharedPreferences.getInstance();
    final cartStr = prefs.getString('local_cart');
    if (cartStr != null) {
      try {
        final List<dynamic> decoded = jsonDecode(cartStr);
        final items = decoded.map((e) => CartItem.fromJson(e)).toList();
        state = state.copyWith(items: items, isLoading: false, error: null);
      } catch (_) {}
    }
  }

  Future<void> _saveLocalCart(List<CartItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await prefs.setString('local_cart', encoded);
  }

  void clearLocal() {
    state = CartState();
    _saveLocalCart([]);
  }

  Future<String?> addProduct(Product product, {int quantity = 1}) async {
    final auth = _ref.read(authProvider);
    if (!auth.isAuthenticated || auth.user?.isBuyer != true) {
      // Local cart persistence for unauthenticated users
      final currentItemIndex = state.items.indexWhere((i) => i.product.id == product.id);
      List<CartItem> newItems = List.from(state.items);
      if (currentItemIndex >= 0) {
        newItems[currentItemIndex] = newItems[currentItemIndex].copyWith(quantity: newItems[currentItemIndex].quantity + quantity);
      } else {
        newItems.add(CartItem(product: product, quantity: quantity));
      }
      state = state.copyWith(items: newItems);
      _saveLocalCart(newItems);
      return null;
    }

    if (state.items.isNotEmpty && product.sellerId != 0) {
      final existingSeller = state.items.first.product.sellerId;
      if (existingSeller != 0 && existingSeller != product.sellerId) {
        return 'Your cart has items from another seller. Finish checkout or remove them first.';
      }
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      final items = await _orderService.addToCart(
        productId: product.id,
        quantity: quantity,
      );
      state = state.copyWith(items: items, isLoading: false, error: null);
      _saveLocalCart(items);
      return null;
    } catch (e) {
      final msg = e is DioException
          ? _orderService.extractErrorMessage(e)
          : e.toString();
      state = state.copyWith(isLoading: false, error: msg);
      return msg ?? 'Failed to update cart';
    }
  }

  Future<String?> removeProduct(int productId) async {
    final item = _itemForProduct(productId);
    if (item?.cartItemId == null) {
      state = state.copyWith(
        items: state.items.where((i) => i.product.id != productId).toList(),
      );
      return null;
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      final items = await _orderService.removeCartItem(item!.cartItemId!);
      state = state.copyWith(items: items, isLoading: false, error: null);
      return null;
    } catch (e) {
      // 404 means the server item no longer exists — drop it from local state
      final is404 = e is DioException && e.response?.statusCode == 404;
      if (is404) {
        final updated = state.items.where((i) => i.product.id != productId).toList();
        state = state.copyWith(items: updated, isLoading: false, error: null);
        _saveLocalCart(updated);
        return null;
      }
      final msg = e is DioException
          ? _orderService.extractErrorMessage(e)
          : e.toString();
      state = state.copyWith(isLoading: false, error: msg);
      return msg;
    }
  }

  Future<String?> increaseQuantity(int productId) async {
    final item = _itemForProduct(productId);
    if (item == null) return 'Item not in cart';
    if (item.cartItemId == null) return 'Cannot update this cart line';

    state = state.copyWith(isLoading: true, error: null);
    try {
      final items = await _orderService.updateCartItemQuantity(
        cartItemId: item.cartItemId!,
        quantity: item.quantity + 1,
      );
      state = state.copyWith(items: items, isLoading: false, error: null);
      return null;
    } catch (e) {
      final is404 = e is DioException && e.response?.statusCode == 404;
      if (is404) { syncFromServer(); return null; }
      final msg = e is DioException
          ? _orderService.extractErrorMessage(e)
          : e.toString();
      state = state.copyWith(isLoading: false, error: msg);
      return msg;
    }
  }

  Future<String?> decreaseQuantity(int productId) async {
    final item = _itemForProduct(productId);
    if (item == null) return 'Item not in cart';
    if (item.cartItemId == null) return 'Cannot update this cart line';

    if (item.quantity <= 1) {
      return removeProduct(productId);
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      final items = await _orderService.updateCartItemQuantity(
        cartItemId: item.cartItemId!,
        quantity: item.quantity - 1,
      );
      state = state.copyWith(items: items, isLoading: false, error: null);
      return null;
    } catch (e) {
      final is404 = e is DioException && e.response?.statusCode == 404;
      if (is404) { syncFromServer(); return null; }
      final msg = e is DioException
          ? _orderService.extractErrorMessage(e)
          : e.toString();
      state = state.copyWith(isLoading: false, error: msg);
      return msg;
    }
  }

  CartItem? _itemForProduct(int productId) {
    for (final i in state.items) {
      if (i.product.id == productId) return i;
    }
    return null;
  }

  Future<Map<String, dynamic>> checkout({
    required String deliveryAddress,
    String specialInstructions = '',
    String fulfillmentType = 'delivery',
    double? quotedDeliveryFee,
    double? quotedDistanceKm,
    int? quotedEtaMinutes,
    double? deliveryLat,
    double? deliveryLng,
    String? pickupTimeSlot,
    String? paymentProvider,
    String? payerNumber,
  }) async {
    if (state.items.isEmpty) {
      return {'success': false, 'message': 'No items in cart.'};
    }

    final auth = _ref.read(authProvider);
    if (!auth.isAuthenticated || auth.user?.isBuyer != true) {
      return {'success': false, 'message': 'Please sign in to checkout.'};
    }

    // Save items now — the backend clears the cart on order creation, so we
    // need these to restore the cart if payment fails immediately.
    final savedItems = state.items.toList();

    state = state.copyWith(isCheckingOut: true, error: null);
    try {
      final order = await _orderService.createOrder(
        deliveryAddress: deliveryAddress.trim(),
        specialInstructions: specialInstructions.trim(),
        fulfillmentType: fulfillmentType,
        quotedDeliveryFee: quotedDeliveryFee,
        quotedDistanceKm: quotedDistanceKm,
        quotedEtaMinutes: quotedEtaMinutes,
        deliveryLat: deliveryLat,
        deliveryLng: deliveryLng,
        pickupTimeSlot: pickupTimeSlot,
      );

      Map<String, dynamic>? paymentResult;
      if (paymentProvider != null && payerNumber != null && payerNumber.trim().isNotEmpty) {
        try {
          paymentResult = await _orderService.initiatePayment(
            orderNumber: order.orderNumber,
            provider: paymentProvider,
            payerNumber: payerNumber.trim(),
          );
        } catch (e) {
          // Payment initiation failed immediately — cancel the order and
          // restore the cart so the user can fix details and retry.
          final paymentError = e is DioException
              ? (_orderService.extractErrorMessage(e) ?? 'Payment initiation failed')
              : e.toString();
          try { await _orderService.cancelOrder(order.id); } catch (_) {}
          // Re-add saved items to server cart so checkout can be retried.
          try {
            List<CartItem> restored = [];
            for (final item in savedItems) {
              restored = await _orderService.addToCart(
                productId: item.product.id,
                quantity: item.quantity,
              );
            }
            state = state.copyWith(items: restored, isCheckingOut: false, error: null);
            _saveLocalCart(restored);
          } catch (_) {
            // Fallback: restore locally so user at least sees their items.
            state = state.copyWith(items: savedItems, isCheckingOut: false, error: null);
            _saveLocalCart(savedItems);
          }
          return {'success': false, 'message': paymentError};
        }
      }

      // Defer cart clear so the UI can navigate away before the empty-cart
      // state is rendered (avoids a one-frame flash of "Your cart is empty").
      Future.microtask(() async {
        if (!mounted) return;
        try {
          final items = await _orderService.fetchCart();
          if (!mounted) return;
          state = state.copyWith(items: items, isCheckingOut: false, error: null);
          _saveLocalCart(items);
        } catch (_) {
          if (!mounted) return;
          state = state.copyWith(items: [], isCheckingOut: false, error: null);
          _saveLocalCart([]);
        }
      });

      return {'success': true, 'order': order, 'payment': paymentResult};
    } catch (e) {
      final msg = e is DioException
          ? _orderService.extractErrorMessage(e)
          : e.toString();
      state = state.copyWith(isCheckingOut: false, error: msg);
      // If server says cart is empty but we think we have items, re-sync
      if (msg != null && msg.toLowerCase().contains('cart is empty')) {
        syncFromServer();
      }
      return {'success': false, 'message': msg ?? 'Checkout failed'};
    }
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  final notifier = CartNotifier(ref, ref.read(orderServiceProvider));
  ref.listen<AuthState>(authProvider, (prev, next) {
    if (next.isAuthenticated && next.user?.isBuyer == true) {
      notifier.syncFromServer();
    }
    if (!next.isAuthenticated && (prev?.isAuthenticated ?? false)) {
      notifier.clearLocal();
    }
  });
  return notifier;
});
