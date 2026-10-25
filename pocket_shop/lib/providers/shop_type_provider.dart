import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shop_type.dart';
import '../services/shop_type_service.dart';

final shopTypeServiceProvider = Provider<ShopTypeService>((ref) => ShopTypeService());

class ShopTypesState {
  final List<ShopType> shopTypes;
  final bool isLoading;
  final bool hasError;

  const ShopTypesState({
    this.shopTypes = const [],
    this.isLoading = false,
    this.hasError = false,
  });

  ShopTypesState copyWith({
    List<ShopType>? shopTypes,
    bool? isLoading,
    bool? hasError,
  }) => ShopTypesState(
    shopTypes: shopTypes ?? this.shopTypes,
    isLoading: isLoading ?? this.isLoading,
    hasError: hasError ?? this.hasError,
  );
}

class ShopTypesNotifier extends StateNotifier<ShopTypesState> {
  ShopTypesNotifier(this._service) : super(const ShopTypesState(isLoading: true)) {
    _init();
  }

  final ShopTypeService _service;
  static const _cacheKey = 'cached_shop_types';

  Future<void> _init() async {
    // Show cache immediately so the home screen never shows a blank spinner.
    final cached = await _loadFromCache();
    if (cached != null && mounted) {
      state = state.copyWith(shopTypes: cached, isLoading: false);
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (!mounted) return;
    state = state.copyWith(isLoading: true, hasError: false);
    try {
      final fresh = await _service.getShopTypes();
      if (!mounted) return;
      state = ShopTypesState(shopTypes: fresh);
      _saveToCache(fresh);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, hasError: state.shopTypes.isEmpty);
    }
  }

  Future<List<ShopType>?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded.map((e) => ShopType.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToCache(List<ShopType> types) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(types.map((t) => t.toJson()).toList()));
    } catch (_) {}
  }
}

final shopTypesProvider = StateNotifierProvider<ShopTypesNotifier, ShopTypesState>((ref) {
  return ShopTypesNotifier(ref.read(shopTypeServiceProvider));
});
