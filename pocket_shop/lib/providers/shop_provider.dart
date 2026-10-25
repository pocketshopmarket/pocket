import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/location_helper.dart';
import '../models/shop.dart';
import '../services/shop_service.dart';

/// Radius used for the Home "Near Me" section — city-scale, matches the
/// distances between LocationService.ZAMBIA_CITY_CENTERS on the backend.
const double _nearbyRadiusKm = 15;

class ShopState {
  final List<Shop> nearbyShops;
  final bool isLoadingNearby;
  // True once we've determined GPS is unavailable/denied — per the
  // confirmed product decision, this silently drops the Near Me section
  // rather than showing an error.
  final bool nearbyUnavailable;

  final List<Shop> allShops;
  final bool isLoadingAllShops;
  final bool isLoadingMoreAllShops;
  final bool hasMoreAllShops;
  final int allShopsPage;
  final String? error;

  // null = "All shops" (no filter narrows the feed). Changes whenever the
  // buyer taps a different shop-type chip on the home screen. Session-only
  // (not persisted) — shop type is a different taxonomy from the buyer's
  // saved preferred product category, so there's nothing to carry over.
  final int? selectedShopTypeId;

  ShopState({
    this.nearbyShops = const [],
    this.isLoadingNearby = false,
    this.nearbyUnavailable = false,
    this.allShops = const [],
    this.isLoadingAllShops = false,
    this.isLoadingMoreAllShops = false,
    this.hasMoreAllShops = true,
    this.allShopsPage = 1,
    this.error,
    this.selectedShopTypeId,
  });

  ShopState copyWith({
    List<Shop>? nearbyShops,
    bool? isLoadingNearby,
    bool? nearbyUnavailable,
    List<Shop>? allShops,
    bool? isLoadingAllShops,
    bool? isLoadingMoreAllShops,
    bool? hasMoreAllShops,
    int? allShopsPage,
    String? error,
  }) {
    return ShopState(
      nearbyShops: nearbyShops ?? this.nearbyShops,
      isLoadingNearby: isLoadingNearby ?? this.isLoadingNearby,
      nearbyUnavailable: nearbyUnavailable ?? this.nearbyUnavailable,
      allShops: allShops ?? this.allShops,
      isLoadingAllShops: isLoadingAllShops ?? this.isLoadingAllShops,
      isLoadingMoreAllShops: isLoadingMoreAllShops ?? this.isLoadingMoreAllShops,
      hasMoreAllShops: hasMoreAllShops ?? this.hasMoreAllShops,
      allShopsPage: allShopsPage ?? this.allShopsPage,
      error: error,
      // Deliberately not a copyWith param: changing it goes through
      // setShopType(), which rebuilds state directly so null ("All shops")
      // is reachable — a copyWith param can't distinguish "clear it" from
      // "leave it alone" when both look like a bare null.
      selectedShopTypeId: selectedShopTypeId,
    );
  }
}

class ShopNotifier extends StateNotifier<ShopState> {
  final ShopService _shopService;

  ShopNotifier(this._shopService) : super(ShopState()) {
    fetchAllShops(reset: true);
    fetchNearbyShops();
  }

  /// Switches the active shop-type filter and refreshes both shop lists.
  Future<void> setShopType(int? shopTypeId) async {
    state = ShopState(selectedShopTypeId: shopTypeId);
    await Future.wait([fetchAllShops(reset: true), fetchNearbyShops()]);
  }

  Future<void> fetchNearbyShops() async {
    state = state.copyWith(isLoadingNearby: true, nearbyUnavailable: false);
    final location = await LocationHelper.getCurrentPositionOrFallback();
    if (!location.isSuccess) {
      state = state.copyWith(
        isLoadingNearby: false,
        nearbyUnavailable: true,
        nearbyShops: [],
      );
      return;
    }
    try {
      final page = await _shopService.getShopsPage(ShopQuery(
        lat: location.lat,
        lng: location.lng,
        maxKm: _nearbyRadiusKm,
        shopType: state.selectedShopTypeId,
        pageSize: 10,
      ));
      state = state.copyWith(
        isLoadingNearby: false,
        nearbyShops: page.items,
        nearbyUnavailable: page.items.isEmpty,
      );
    } catch (_) {
      state = state.copyWith(isLoadingNearby: false, nearbyUnavailable: true, nearbyShops: []);
    }
  }

  Future<void> fetchAllShops({bool reset = false}) async {
    if (state.isLoadingAllShops || state.isLoadingMoreAllShops) return;
    if (!reset && !state.hasMoreAllShops) return;
    if (reset) {
      state = state.copyWith(isLoadingAllShops: true, error: null, allShopsPage: 1, hasMoreAllShops: true);
    } else {
      state = state.copyWith(isLoadingMoreAllShops: true, error: null);
    }
    try {
      final nextPage = reset ? 1 : state.allShopsPage;
      final page = await _shopService.getShopsPage(ShopQuery(
        page: nextPage,
        shopType: state.selectedShopTypeId,
      ));
      final merged = reset ? page.items : [...state.allShops, ...page.items];
      state = state.copyWith(
        allShops: merged,
        isLoadingAllShops: false,
        isLoadingMoreAllShops: false,
        hasMoreAllShops: page.nextPage != null,
        allShopsPage: page.nextPage ?? nextPage,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingAllShops: false,
        isLoadingMoreAllShops: false,
        error: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }
}

final shopServiceProvider = Provider<ShopService>((ref) => ShopService());

final shopProvider = StateNotifierProvider<ShopNotifier, ShopState>((ref) {
  return ShopNotifier(ref.read(shopServiceProvider));
});
