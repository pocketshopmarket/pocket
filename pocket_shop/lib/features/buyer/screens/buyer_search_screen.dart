import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/product.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/category_provider.dart';
import '../../../../providers/product_provider.dart';
import '../../../../providers/wishlist_provider.dart';
import '../../../../services/product_service.dart';
import '../../../../widgets/product_card.dart';
import '../../../../widgets/shimmer_loading.dart';
import '../../../../widgets/ui/ps_ui.dart';

class BuyerSearchScreen extends ConsumerStatefulWidget {
  const BuyerSearchScreen({super.key});

  @override
  ConsumerState<BuyerSearchScreen> createState() => _BuyerSearchScreenState();
}

class _BuyerSearchScreenState extends ConsumerState<BuyerSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ProductService _productService = ProductService();
  Timer? _debounce;

  List<Product> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _nextPage = 1;
  bool _hasMore = true;
  String _selectedCategory = 'all';
  bool _inStockOnly = false;
  String _sortBy = 'latest';
  double? _minPrice;
  double? _maxPrice;
  String? _quality;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    _fetch(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _scrollController.removeListener(_onScroll);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _fetch(reset: true);
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 180) {
      _fetch(reset: false);
    }
  }

  Future<void> _fetch({required bool reset}) async {
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
          search: _searchController.text.trim(),
          page: currentPage,
          sortBy: _sortBy,
          category: _selectedCategory,
          inStockOnly: _inStockOnly,
          minPrice: _minPrice,
          maxPrice: _maxPrice,
          quality: _quality,
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 360;
    final allCategories = ref.watch(categoryProvider);
    final wishlist = ref.watch(wishlistProvider);
    final wishlistNotifier = ref.read(wishlistProvider.notifier);
    final cartNotifier = ref.read(cartProvider.notifier);
    final cartCount = ref.watch(cartProvider).items.length;
    final trendingProducts = ref.watch(productProvider).trendingProducts;
    final currentUser = ref.watch(userProvider);
    final recommendedAsync = currentUser != null
        ? ref.watch(recommendedProvider)
        : null;

    final activeFilters = [
      _selectedCategory != 'all',
      _inStockOnly,
      _sortBy != 'latest',
      _minPrice != null,
      _maxPrice != null,
      _quality != null,
    ].where((f) => f).length;

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      body: SafeArea(
        bottom: false,
        child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(child: Text('Products', style: AppTheme.display(fontSize: 26))),
                _SquareIconButton(
                  icon: Icons.shopping_cart_outlined,
                  tooltip: 'Cart',
                  count: cartCount,
                  onTap: () => context.go('/buyer/cart'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search products',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              tooltip: 'Clear',
                              onPressed: () {
                                _searchController.clear();
                                _fetch(reset: true);
                              },
                              icon: const Icon(Icons.close_rounded),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _SquareIconButton(
                  icon: Icons.tune_rounded,
                  tooltip: 'Filters',
                  count: activeFilters,
                  size: 50,
                  onTap: _openFilters,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: 1 + allCategories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final isAll = index == 0;
                final catId = isAll
                    ? 'all'
                    : allCategories[index - 1].id.toString();
                final catName = isAll ? 'All' : allCategories[index - 1].name;
                return ChoiceChip(
                  label: Text(catName),
                  selected: _selectedCategory == catId,
                  onSelected: (_) {
                    setState(() => _selectedCategory = catId);
                    _fetch(reset: true);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _fetch(reset: true),
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  if (trendingProducts.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: PsSectionHeader(title: 'Trending now'),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: isCompact ? 254 : 268,
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                scrollDirection: Axis.horizontal,
                                itemCount: trendingProducts.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (_, index) {
                                  final product = trendingProducts[index];
                                  final inStock =
                                      product.isAvailable && product.isInStock;
                                  return SizedBox(
                                    width: isCompact ? 156 : 170,
                                    child: ProductCard(
                                      product: product,
                                      inStock: inStock,
                                      isFavorite: wishlist.contains(product.id),
                                      onToggleFavorite: () =>
                                          wishlistNotifier.toggle(product.id),
                                      onCardTap: () => context.push(
                                        '/buyer/product-details',
                                        extra: product,
                                      ),
                                      onAdd: () async {
                                        final err = await cartNotifier
                                            .addProduct(product);
                                        if (!context.mounted || err == null)
                                          return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(err),
                                            backgroundColor: AppTheme.error,
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Recommendations require an account (backend is IsAuthenticated,
                  // no anonymous fallback) — omit the section entirely for a guest.
                  if (recommendedAsync != null)
                    SliverToBoxAdapter(
                      child: recommendedAsync.when(
                        data: (recommendedProducts) {
                          if (recommendedProducts.isEmpty)
                            return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: PsSectionHeader(title: 'Recommended for you'),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: isCompact ? 254 : 268,
                                  child: ListView.separated(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    scrollDirection: Axis.horizontal,
                                    itemCount: recommendedProducts.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(width: 10),
                                    itemBuilder: (_, index) {
                                      final product =
                                          recommendedProducts[index];
                                      final inStock =
                                          product.isAvailable &&
                                          product.isInStock;
                                      return SizedBox(
                                        width: isCompact ? 156 : 170,
                                        child: ProductCard(
                                          product: product,
                                          inStock: inStock,
                                          isFavorite: wishlist.contains(
                                            product.id,
                                          ),
                                          onToggleFavorite: () =>
                                              wishlistNotifier.toggle(
                                                product.id,
                                              ),
                                          onCardTap: () => context.push(
                                            '/buyer/product-details',
                                            extra: product,
                                          ),
                                          onAdd: () async {
                                            final err = await cartNotifier
                                                .addProduct(product);
                                            if (!context.mounted || err == null)
                                              return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(err),
                                                backgroundColor: AppTheme.error,
                                              ),
                                            );
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ),
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
                          title: "Couldn't load products",
                          message: _error!,
                          actionLabel: 'Try again',
                          onAction: () => _fetch(reset: true),
                        ),
                      ),
                    )
                  else if (_items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.divider),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 42,
                                  color: AppTheme.textSecondary,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'No matching products found.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Try a different keyword.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  else
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
                        delegate: SliverChildBuilderDelegate((context, index) {
                          if (index >= _items.length) {
                            return const ProductCardShimmer();
                          }
                          final product = _items[index];
                          final inStock =
                              product.isAvailable && product.isInStock;
                          final isFavorite = wishlist.contains(product.id);
                          return ProductCard(
                            product: product,
                            inStock: inStock,
                            isFavorite: isFavorite,
                            onToggleFavorite: () => wishlistNotifier.toggle(product.id),
                            onCardTap: () => context.push(
                              '/buyer/product-details',
                              extra: product,
                            ),
                            onAdd: () async {
                              final err = await cartNotifier.addProduct(product);
                              if (!context.mounted || err == null) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(err), backgroundColor: AppTheme.error),
                              );
                            },
                          );
                        }, childCount: _items.length + (_loadingMore ? 1 : 0)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _openFilters() async {
    final categories = ref.read(categoryProvider);
    String tempCategory = _selectedCategory;
    bool tempInStock = _inStockOnly;
    String tempSort = _sortBy;
    final minController = TextEditingController(
      text: _minPrice != null ? _minPrice!.toStringAsFixed(0) : '',
    );
    final maxController = TextEditingController(
      text: _maxPrice != null ? _maxPrice!.toStringAsFixed(0) : '',
    );
    String? tempQuality = _quality;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Filter & sort',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: tempCategory,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All')),
                  ...categories.map(
                    (c) => DropdownMenuItem(
                      value: c.id.toString(),
                      child: Text(c.name),
                    ),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setModalState(() => tempCategory = v);
                },
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: tempQuality,
                decoration: const InputDecoration(labelText: 'Condition'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Any')),
                  DropdownMenuItem(value: 'new', child: Text('New')),
                  DropdownMenuItem(value: 'like_new', child: Text('Like new')),
                  DropdownMenuItem(value: 'good', child: Text('Good')),
                  DropdownMenuItem(value: 'fair', child: Text('Fair')),
                  DropdownMenuItem(value: 'used', child: Text('Used')),
                ],
                onChanged: (v) => setModalState(() => tempQuality = v),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: minController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Min price (ZMW)',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: maxController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Max price (ZMW)',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('In-stock only'),
                value: tempInStock,
                onChanged: (v) => setModalState(() => tempInStock = v),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: tempSort,
                decoration: const InputDecoration(labelText: 'Sort'),
                items: const [
                  DropdownMenuItem(value: 'latest', child: Text('Latest')),
                  DropdownMenuItem(
                    value: 'popular',
                    child: Text('Most popular'),
                  ),
                  DropdownMenuItem(
                    value: 'price_low',
                    child: Text('Price: low to high'),
                  ),
                  DropdownMenuItem(
                    value: 'price_high',
                    child: Text('Price: high to low'),
                  ),
                  DropdownMenuItem(value: 'name_az', child: Text('Name: A-Z')),
                ],
                onChanged: (v) {
                  if (v != null) setModalState(() => tempSort = v);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        minController.dispose();
                        maxController.dispose();
                        setState(() {
                          _selectedCategory = 'all';
                          _inStockOnly = false;
                          _sortBy = 'latest';
                          _minPrice = null;
                          _maxPrice = null;
                          _quality = null;
                        });
                        Navigator.pop(ctx);
                        _fetch(reset: true);
                      },
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final minVal = double.tryParse(
                          minController.text.trim(),
                        );
                        final maxVal = double.tryParse(
                          maxController.text.trim(),
                        );
                        minController.dispose();
                        maxController.dispose();
                        setState(() {
                          _selectedCategory = tempCategory;
                          _inStockOnly = tempInStock;
                          _sortBy = tempSort;
                          _minPrice = minVal;
                          _maxPrice = maxVal;
                          _quality = tempQuality;
                        });
                        Navigator.pop(ctx);
                        _fetch(reset: true);
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.count = 0,
    this.size = 42,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppTheme.divider),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: SizedBox.square(
                dimension: size,
                child: Icon(icon, size: 21, color: AppTheme.textPrimary),
              ),
            ),
          ),
          if (count > 0)
            Positioned(
              top: -5,
              right: -5,
              child: IgnorePointer(
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.surfaceWhite, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: AppTheme.body(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
