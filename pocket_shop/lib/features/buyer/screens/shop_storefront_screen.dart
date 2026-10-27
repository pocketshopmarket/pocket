import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/product.dart';
import '../../../models/shop.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/wishlist_provider.dart';
import '../../../services/product_service.dart';
import '../../../services/shop_service.dart';
import '../../../widgets/product_card.dart';
import '../../../widgets/shimmer_loading.dart';
import '../../../widgets/ui/ps_ui.dart';

/// A single seller's public storefront: header + their full in-stock catalog.
/// Reached from a `ShopSectionCard` tap on Home (Near Me / All Shops) — the `Shop`
/// is usually passed via `extra`; `shopId` is a fallback for a direct link
/// (deep link, or a search result) that only has the id.
class ShopStorefrontScreen extends ConsumerStatefulWidget {
  const ShopStorefrontScreen({super.key, this.shop, this.shopId});

  final Shop? shop;
  final int? shopId;

  @override
  ConsumerState<ShopStorefrontScreen> createState() => _ShopStorefrontScreenState();
}

class _ShopStorefrontScreenState extends ConsumerState<ShopStorefrontScreen> {
  final ScrollController _scrollController = ScrollController();
  final ProductService _productService = ProductService();
  final ShopService _shopService = ShopService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  Shop? _shop;
  bool _loadingShop = false;
  String? _shopError;

  List<ShopCategory> _categories = [];
  int? _selectedCategoryId; // null = All

  List<Product> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _nextPage = 1;
  bool _hasMore = true;

  int? get _sellerId => _shop?.id ?? widget.shopId;

  @override
  void initState() {
    super.initState();
    _shop = widget.shop;
    _scrollController.addListener(_onScroll);
    if (_shop == null && widget.shopId != null) {
      _loadShop();
    } else {
      _fetchProducts(reset: true);
      _loadCategories();
    }
  }

  /// Chips are a nicety — if this fails the storefront still works, just
  /// without the category row.
  Future<void> _loadCategories() async {
    final sellerId = _sellerId;
    if (sellerId == null) return;
    try {
      final cats = await _shopService.getShopCategories(sellerId);
      if (!mounted) return;
      setState(() => _categories = cats);
    } catch (_) {}
  }

  void _selectCategory(int? id) {
    if (_selectedCategoryId == id) return;
    setState(() => _selectedCategoryId = id);
    _fetchProducts(reset: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {}); // refresh the clear (x) button's visibility
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _fetchProducts(reset: true);
    });
  }

  Future<void> _loadShop() async {
    setState(() => _loadingShop = true);
    try {
      final shop = await _shopService.getShop(widget.shopId!);
      if (!mounted) return;
      setState(() {
        _shop = shop;
        _loadingShop = false;
      });
      _fetchProducts(reset: true);
      _loadCategories();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingShop = false;
        _shopError = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 180) {
      _fetchProducts(reset: false);
    }
  }

  Future<void> _fetchProducts({required bool reset}) async {
    final sellerId = _sellerId;
    if (sellerId == null) return;
    if (_loading || _loadingMore) return;
    if (!reset && !_hasMore) return;

    setState(() {
      if (reset) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });

    try {
      final currentPage = reset ? 1 : _nextPage;
      final page = await _productService.getProductsPage(
        ProductQuery(
          sellerId: sellerId,
          category: _selectedCategoryId?.toString(),
          page: currentPage,
          inStockOnly: true,
          sortBy: 'latest',
          search: _searchController.text.trim(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _nextPage = page.nextPage ?? currentPage;
        _hasMore = page.nextPage != null;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wishlist = ref.watch(wishlistProvider);
    final wishlistNotifier = ref.read(wishlistProvider.notifier);
    final cartNotifier = ref.read(cartProvider.notifier);
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 360;

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: Text(_shop?.shopName ?? 'Shop'),
      ),
      body: _loadingShop
          ? CustomScrollView(
              physics: const NeverScrollableScrollPhysics(),
              slivers: [
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
                  sliver: SliverToBoxAdapter(
                    child: AppShimmer(child: SkeletonBox(height: 110, radius: 18)),
                  ),
                ),
                SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: isCompact ? 8 : 10,
                          mainAxisSpacing: 12,
                          mainAxisExtent: ProductCard.gridExtent(
                            (screenWidth - 28 - (isCompact ? 8 : 10)) / 2,
                          ),
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, _) => const ProductCardShimmer(),
                          childCount: 4,
                        ),
                      ),
                    ),
              ],
            )
          : _shopError != null
              ? Center(
                  child: PsEmptyState(
                    icon: Icons.storefront_outlined,
                    title: "Couldn't open this shop",
                    message: _shopError!,
                    actionLabel: 'Try again',
                    onAction: _loadShop,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _fetchProducts(reset: true),
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeader()),
                      SliverToBoxAdapter(child: _buildSearchBar()),
                      if (_categories.length > 1)
                        SliverToBoxAdapter(child: _buildCategoryChips()),
                      if (_loading)
                        SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: isCompact ? 8 : 10,
                          mainAxisSpacing: 12,
                          mainAxisExtent: ProductCard.gridExtent(
                            (screenWidth - 28 - (isCompact ? 8 : 10)) / 2,
                          ),
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, _) => const ProductCardShimmer(),
                          childCount: 6,
                        ),
                      ),
                    )
                      else if (_error != null)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: PsEmptyState(
                              icon: Icons.cloud_off_rounded,
                              title: "Couldn't load this shop's products",
                              message: _error!,
                              actionLabel: 'Try again',
                              onAction: () => _fetchProducts(reset: true),
                            ),
                          ),
                        )
                      else if (_items.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _searchController.text.trim().isNotEmpty
                                    ? 'No products match "${_searchController.text.trim()}" in this shop.'
                                    : 'This shop has no items in stock right now.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppTheme.textSecondary),
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                          sliver: SliverGrid(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: isCompact ? 8 : 10,
                              mainAxisSpacing: 12,
                              mainAxisExtent: ProductCard.gridExtent(
                                (screenWidth - 28 - (isCompact ? 8 : 10)) / 2,
                              ),
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (index >= _items.length) {
                                  return const ProductCardShimmer();
                                }
                                final product = _items[index];
                                return ProductCard(
                                  product: product,
                                  inStock: product.isAvailable && product.isInStock,
                                  isFavorite: wishlist.contains(product.id),
                                  onToggleFavorite: () => wishlistNotifier.toggle(product.id),
                                  onCardTap: () => context.push('/buyer/product-details', extra: product),
                                  onAdd: () async {
                                    final err = await cartNotifier.addProduct(product);
                                    if (!context.mounted || err == null) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(err), backgroundColor: AppTheme.error),
                                    );
                                  },
                                );
                              },
                              childCount: _items.length + (_loadingMore ? 1 : 0),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader() {
    final shop = _shop;
    if (shop == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 64,
              height: 64,
              child: shop.shopLogo != null
                  ? CachedNetworkImage(
                      imageUrl: shop.shopLogo!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => _headerFallbackIcon(),
                    )
                  : _headerFallbackIcon(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        shop.shopName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                      ),
                    ),
                    if (shop.isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified_rounded, size: 16, color: AppTheme.success),
                    ],
                  ],
                ),
                if ((shop.shopType ?? shop.topCategory) != null) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(color: AppTheme.primaryCyan),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      (shop.shopType ?? shop.topCategory)!,
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.darkCyan),
                    ),
                  ),
                ],
                if (shop.shopDescription.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    shop.shopDescription,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 12, color: AppTheme.textSecondary),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        shop.distanceKm != null
                            ? '${shop.shopLocation} · ${shop.distanceKm!.toStringAsFixed(1)} km away'
                            : shop.shopLocation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppTheme.softSurface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search this shop',
                  hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _fetchProducts(reset: true);
                          },
                          child: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textSecondary),
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        scrollDirection: Axis.horizontal,
        itemCount: 1 + _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final isAll = index == 0;
          final cat = isAll ? null : _categories[index - 1];
          final selected = isAll ? _selectedCategoryId == null : _selectedCategoryId == cat!.id;
          return ChoiceChip(
            label: Text(isAll ? 'All' : cat!.name),
            selected: selected,
            onSelected: (_) => _selectCategory(cat?.id),
          );
        },
      ),
    );
  }

  Widget _headerFallbackIcon() {
    return Container(
      color: AppTheme.divider.withValues(alpha: 0.3),
      alignment: Alignment.center,
      child: const Icon(Icons.storefront_outlined, size: 28, color: AppTheme.textSecondary),
    );
  }
}
