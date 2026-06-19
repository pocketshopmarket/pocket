import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/category.dart';
import '../services/category_service.dart';

final categoryServiceProvider = Provider<CategoryService>((ref) => CategoryService());

class CategoriesState {
  final List<Category> categories;
  final bool isLoading;
  final bool hasError;

  const CategoriesState({
    this.categories = const [],
    this.isLoading = false,
    this.hasError = false,
  });

  CategoriesState copyWith({
    List<Category>? categories,
    bool? isLoading,
    bool? hasError,
  }) => CategoriesState(
    categories: categories ?? this.categories,
    isLoading: isLoading ?? this.isLoading,
    hasError: hasError ?? this.hasError,
  );
}

class CategoriesNotifier extends StateNotifier<CategoriesState> {
  CategoriesNotifier(this._service) : super(const CategoriesState(isLoading: true)) {
    _init();
  }

  final CategoryService _service;
  static const _cacheKey = 'cached_categories';

  Future<void> _init() async {
    // Show cache immediately so home screen never shows a blank spinner
    final cached = await _loadFromCache();
    if (cached != null && mounted) {
      state = state.copyWith(categories: cached, isLoading: false);
    }
    // Then refresh silently in background
    await refresh();
  }

  Future<void> refresh() async {
    if (!mounted) return;
    state = state.copyWith(isLoading: true, hasError: false);
    try {
      final fresh = await _service.getCategories();
      if (!mounted) return;
      state = CategoriesState(categories: fresh);
      _saveToCache(fresh);
    } catch (_) {
      if (!mounted) return;
      // Keep whatever we have (cache or empty); just flag error if nothing loaded
      state = state.copyWith(
        isLoading: false,
        hasError: state.categories.isEmpty,
      );
    }
  }

  Future<List<Category>?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded
          .map((e) => Category.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToCache(List<Category> cats) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(cats.map((c) => c.toJson()).toList()));
    } catch (_) {}
  }
}

final categoriesProvider =
    StateNotifierProvider<CategoriesNotifier, CategoriesState>((ref) {
  return CategoriesNotifier(ref.read(categoryServiceProvider));
});

// Top-level categories only (no parent) — used on the home screen
final topLevelCategoriesProvider = Provider<List<Category>>((ref) {
  return ref.watch(categoriesProvider).categories
      .where((c) => c.parentId == null)
      .toList();
});

// Keeps the old names alive so existing consumers compile without changes
final allCategoriesProvider = Provider<List<Category>>((ref) {
  return ref.watch(categoriesProvider).categories;
});

final categoryProvider = Provider<List<Category>>((ref) {
  return ref.watch(topLevelCategoriesProvider);
});

final selectedCategoryProvider = StateProvider<int?>((ref) => null);
