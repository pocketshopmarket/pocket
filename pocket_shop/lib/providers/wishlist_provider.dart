import 'package:flutter_riverpod/flutter_riverpod.dart';

class WishlistNotifier extends StateNotifier<Set<int>> {
  WishlistNotifier() : super(<int>{});

  bool isFavorite(int productId) => state.contains(productId);

  void toggle(int productId) {
    if (state.contains(productId)) {
      state = {...state}..remove(productId);
    } else {
      state = {...state, productId};
    }
  }
}

final wishlistProvider = StateNotifierProvider<WishlistNotifier, Set<int>>((ref) {
  return WishlistNotifier();
});
