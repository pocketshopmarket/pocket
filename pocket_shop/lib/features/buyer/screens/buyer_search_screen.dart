import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/product.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/category_provider.dart';
import '../../../../providers/wishlist_provider.dart';
import '../../../../services/product_service.dart';
import '../../../../widgets/product_list_thumbnail.dart';

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

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Shop'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () => context.go('/buyer/cart'),
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: const Icon(Icons.shopping_cart_outlined, size: 20),
                  ),
                  if (cartCount > 0)
                    Positioned(
                      right: -4,
                      top: -3,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accentOrange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          cartCount > 99 ? '99+' : '$cartCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      hintStyle: const TextStyle(color: AppTheme.textSecondary),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppTheme.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppTheme.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppTheme.primaryCyan,
                        ),
                      ),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
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
                InkWell(
                  onTap: _openFilters,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: const Icon(Icons.tune_rounded),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: 1 + allCategories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final isAll = index == 0;
                final catId = isAll ? 'all' : allCategories[index - 1].id.toString();
                final catName = isAll ? 'All' : allCategories[index - 1].name;
                final selected = _selectedCategory == catId;
                return ChoiceChip(
                  label: Text(catName),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _selectedCategory = catId);
                    _fetch(reset: true);
                  },
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: selected ? Colors.white : AppTheme.textPrimary,
                  ),
                  selectedColor: AppTheme.primaryCyan,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: AppTheme.divider),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _fetch(reset: true),
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryCyan,
                      ),
                    )
                  : _error != null
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.error),
                          ),
                        ),
                      ],
                    )
                  : _items.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.divider),
                            ),
                            child: const Column(
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
                      ],
                    )
                  : GridView.builder(
                      controller: _scrollController,
                      itemCount: _items.length + (_loadingMore ? 1 : 0),
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: isCompact ? 8 : 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: isCompact ? 0.66 : 0.7,
                      ),
                      itemBuilder: (context, index) {
                        if (index >= _items.length) {
                          return const Padding(
                            padding: EdgeInsets.all(10),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppTheme.primaryCyan,
                              ),
                            ),
                          );
                        }
                        final product = _items[index];
                        final inStock =
                            product.isAvailable && product.isInStock;
                        final isFavorite = wishlist.contains(product.id);
                        return Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.divider),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0D000000),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: () => context.push(
                              '/buyer/product-details',
                              extra: product,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: ProductListThumbnail(
                                            product: product,
                                            compactPlaceholder: true,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        right: 6,
                                        top: 6,
                                        child: _ActionIconButton(
                                          icon: isFavorite
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                          color: isFavorite
                                              ? AppTheme.error
                                              : AppTheme.textSecondary,
                                          onTap: () => wishlistNotifier.toggle(
                                            product.id,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  product.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.qualityDisplayLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                    if (product.sellerName != null) ...[
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          const Icon(Icons.storefront_outlined, size: 10, color: AppTheme.textSecondary),
                                          const SizedBox(width: 3),
                                          Expanded(
                                            child: Text(
                                              product.sellerName!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'ZMW ${product.price.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: AppTheme.textPrimary,
                                                ),
                                              ),
                                              if (product.reviewCount > 0)
                                                Row(
                                                  children: [
                                                    const Icon(Icons.star_rounded, size: 11, color: Color(0xFFF59E0B)),
                                                    const SizedBox(width: 2),
                                                    Text(
                                                      '${product.reviewAverage.toStringAsFixed(1)} (${product.reviewCount})',
                                                      style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                        ),
                                        _ActionIconButton(
                                          icon: Icons.add_shopping_cart_rounded,
                                          color: inStock
                                              ? AppTheme.darkCyan
                                              : AppTheme.textSecondary,
                                          onTap: inStock
                                              ? () async {
                                                  final err = await cartNotifier
                                                      .addProduct(product);
                                                  if (!context.mounted ||
                                                      err == null) {
                                                    return;
                                                  }
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(err),
                                                      backgroundColor:
                                                          AppTheme.error,
                                                    ),
                                                  );
                                                }
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
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
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 20),
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
                  ...categories.map((c) => DropdownMenuItem(
                    value: c.id.toString(),
                    child: Text(c.name),
                  )),
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
                  DropdownMenuItem(value: 'popular', child: Text('Most popular')),
                  DropdownMenuItem(value: 'price_low', child: Text('Price: low to high')),
                  DropdownMenuItem(value: 'price_high', child: Text('Price: high to low')),
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
                        final minVal = double.tryParse(minController.text.trim());
                        final maxVal = double.tryParse(maxController.text.trim());
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

class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    required this.icon,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
