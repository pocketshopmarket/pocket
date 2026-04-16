import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../services/product_service.dart';

class ProductState {
  final List<Product> products;
  final List<Product> trendingProducts;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int page;
  final int totalCount;
  final String searchQuery;
  final String selectedCategory;
  final bool inStockOnly;
  final String sortBy;
  final String? error;

  ProductState({
    this.products = const [],
    this.trendingProducts = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.page = 1,
    this.totalCount = 0,
    this.searchQuery = '',
    this.selectedCategory = 'all',
    this.inStockOnly = false,
    this.sortBy = 'default',
    this.error,
  });

  ProductState copyWith({
    List<Product>? products,
    List<Product>? trendingProducts,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? page,
    int? totalCount,
    String? searchQuery,
    String? selectedCategory,
    bool? inStockOnly,
    String? sortBy,
    String? error,
  }) {
    return ProductState(
      products: products ?? this.products,
      trendingProducts: trendingProducts ?? this.trendingProducts,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      totalCount: totalCount ?? this.totalCount,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      inStockOnly: inStockOnly ?? this.inStockOnly,
      sortBy: sortBy ?? this.sortBy,
      error: error,
    );
  }
}

class ProductNotifier extends StateNotifier<ProductState> {
  final ProductService _productService;

  ProductNotifier(this._productService) : super(ProductState()) {
    fetchProducts(reset: true);
    fetchTrendingProducts();
  }

  ProductQuery _buildQuery({required int page}) {
    return ProductQuery(
      page: page,
      search: state.searchQuery,
      category: state.selectedCategory,
      inStockOnly: state.inStockOnly,
      sortBy: state.sortBy,
    );
  }

  Future<void> updateFilters({
    String? searchQuery,
    String? category,
    bool? inStockOnly,
    String? sortBy,
  }) async {
    state = state.copyWith(
      searchQuery: searchQuery ?? state.searchQuery,
      selectedCategory: category ?? state.selectedCategory,
      inStockOnly: inStockOnly ?? state.inStockOnly,
      sortBy: sortBy ?? state.sortBy,
    );
    await fetchProducts(reset: true);
  }

  Future<void> fetchProducts({bool reset = false}) async {
    if (state.isLoading || state.isLoadingMore) return;
    if (!reset && !state.hasMore) return;
    if (reset) {
      state = state.copyWith(
        isLoading: true,
        error: null,
        page: 1,
        hasMore: true,
      );
    } else {
      state = state.copyWith(isLoadingMore: true, error: null);
    }

    try {
      final nextPage = reset ? 1 : state.page;
      final pageData = await _productService.getProductsPage(
        _buildQuery(page: nextPage),
      );
      final merged = reset
          ? pageData.items
          : [...state.products, ...pageData.items];
      state = state.copyWith(
        products: merged,
        isLoading: false,
        isLoadingMore: false,
        hasMore: pageData.nextPage != null,
        page: pageData.nextPage ?? nextPage,
        totalCount: pageData.totalCount,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: e.toString(),
      );
    }
  }

  Future<void> fetchTrendingProducts() async {
    try {
      final rows = await _productService.fetchTrending();
      state = state.copyWith(trendingProducts: rows);
    } catch (_) {
      // keep trending optional
    }
  }

  Future<Map<String, dynamic>> addProduct({
    required String name,
    required double price,
    required int stockQuantity,
    String description = '',
    String category = 'other',
    String quality = 'new',
    List<ProductImageUpload> images = const [],
    List<Map<String, dynamic>> variants = const [],
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final newProduct = await _productService.addProduct(
        name: name,
        price: price,
        stockQuantity: stockQuantity,
        description: description,
        category: category,
        quality: quality,
        images: images,
        variants: variants,
      );
      state = state.copyWith(
        products: [newProduct, ...state.products],
        isLoading: false,
      );
      return {'success': true};
    } catch (e) {
      state = ProductState(
        products: state.products,
        isLoading: false,
        error: e.toString().replaceAll('Exception: ', ''),
      );
      return {'success': false, 'message': state.error};
    }
  }

  Future<Map<String, dynamic>> deleteProduct(int productId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _productService.deleteProduct(productId);
      state = state.copyWith(
        products: state.products.where((p) => p.id != productId).toList(),
        isLoading: false,
      );
      return {'success': true};
    } catch (e) {
      state = ProductState(
        products: state.products,
        isLoading: false,
        error: e.toString().replaceAll('Exception: ', ''),
      );
      return {'success': false, 'message': state.error};
    }
  }

  Future<Map<String, dynamic>> updateProduct({
    required int productId,
    required Map<String, dynamic> data,
    List<ProductImageUpload>? replacementImages,
    List<Map<String, dynamic>>? variants,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final updated = await _productService.updateProduct(
        productId: productId,
        data: data,
        replacementImages: replacementImages,
        variants: variants,
      );
      state = state.copyWith(
        products: state.products.map((p) => p.id == productId ? updated : p).toList(),
        isLoading: false,
      );
      return {'success': true};
    } catch (e) {
      state = ProductState(
        products: state.products,
        isLoading: false,
        error: e.toString().replaceAll('Exception: ', ''),
      );
      return {'success': false, 'message': state.error};
    }
  }
}

final productServiceProvider = Provider<ProductService>((ref) {
  return ProductService();
});

final productProvider = StateNotifierProvider<ProductNotifier, ProductState>((ref) {
  return ProductNotifier(ref.read(productServiceProvider));
});
