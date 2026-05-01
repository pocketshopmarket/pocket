import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/product.dart';
import '../../../../widgets/product_list_thumbnail.dart';
import '../../../../providers/product_provider.dart';
import '../../../../providers/category_provider.dart';
import '../../../../services/product_service.dart';
import 'dart:async';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/wishlist_provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../models/category.dart';

class BuyerHomeScreen extends ConsumerStatefulWidget {
  const BuyerHomeScreen({super.key});

  @override
  ConsumerState<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends ConsumerState<BuyerHomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final PageController _bannerController = PageController(
    viewportFraction: 0.94,
  );
  String _selectedCategory = 'all';
  bool _inStockOnly = false;
  String _sortBy = 'default';
  int _activeBannerIndex = 0;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _scrollController.dispose();
    _bannerController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  String _categoryLabel(String category) {
    final normalized = category.trim().toLowerCase();
    if (normalized.isEmpty) return 'Other';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'vegetables':
      case 'groceries':
        return Icons.eco_outlined;
      case 'fruits':
        return Icons.apple_outlined;
      case 'electronics':
        return Icons.devices_outlined;
      case 'fashion':
      case 'clothes':
        return Icons.checkroom_outlined;
      case 'beauty':
        return Icons.spa_outlined;
      default:
        return Icons.grid_view_rounded;
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final nearBottom =
          _scrollController.position.pixels >=
          (_scrollController.position.maxScrollExtent - 180);
      if (nearBottom) {
        ref.read(productProvider.notifier).fetchProducts();
      }
    });
  }

  Widget _buildCategoryChip(String id, String label, String currentCategory, Function(String) onSelect) {
    final selected = currentCategory == id;
    return InkWell(
      onTap: () => onSelect(id),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryCyan : const Color(0xFFEEEEEE),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  Future<void> _openFilterSortSheet(List<Category> allCategories) async {
    String tempCategory = _selectedCategory;
    bool tempInStockOnly = _inStockOnly;
    String tempSortBy = _sortBy;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filter & sort',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Category',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildCategoryChip('all', 'All', tempCategory, (val) => setModalState(() => tempCategory = val)),
                        ...allCategories.map((cat) => _buildCategoryChip(cat.id.toString(), cat.name, tempCategory, (val) => setModalState(() => tempCategory = val))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('In-stock only'),
                      value: tempInStockOnly,
                      activeColor: AppTheme.primaryCyan,
                      onChanged: (value) =>
                          setModalState(() => tempInStockOnly = value),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Sort',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...[
                      ('default', 'Default'),
                      ('latest', 'Latest'),
                      ('price_low', 'Price: low to high'),
                      ('price_high', 'Price: high to low'),
                      ('name_az', 'Name: A to Z'),
                    ].map((option) {
                      return RadioListTile<String>(
                        value: option.$1,
                        groupValue: tempSortBy,
                        activeColor: AppTheme.primaryCyan,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          option.$2,
                          style: const TextStyle(fontSize: 13),
                        ),
                        onChanged: (value) {
                          if (value != null) {
                            setModalState(() => tempSortBy = value);
                          }
                        },
                      );
                    }),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _selectedCategory = 'all';
                                _inStockOnly = false;
                                _sortBy = 'default';
                              });
                              ref
                                  .read(productProvider.notifier)
                                  .updateFilters(
                                    category: 'all',
                                    inStockOnly: false,
                                    sortBy: 'default',
                                  );
                              Navigator.pop(context);
                            },
                            child: const Text('Reset'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _selectedCategory = tempCategory;
                                _inStockOnly = tempInStockOnly;
                                _sortBy = tempSortBy;
                              });
                              ref
                                  .read(productProvider.notifier)
                                  .updateFilters(
                                    category: tempCategory,
                                    inStockOnly: tempInStockOnly,
                                    sortBy: tempSortBy,
                                  );
                              Navigator.pop(context);
                            },
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 360;
    final horizontalPadding = isCompact ? 12.0 : 16.0;
    final gridSpacing = isCompact ? 8.0 : 10.0;
    final gridCardHeight = isCompact ? 244.0 : 262.0;
    final gridCardWidth =
        (screenWidth - (horizontalPadding * 2) - gridSpacing) / 2;
    final gridAspectRatio = gridCardWidth / gridCardHeight;
    final productState = ref.watch(productProvider);
    final cartState = ref.watch(cartProvider);
    final wishlist = ref.watch(wishlistProvider);
    final user = ref.watch(userProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final wishlistNotifier = ref.read(wishlistProvider.notifier);
    final firstName = user?.displayName.split(' ').first ?? 'Shopper';
    final allCategories = ref.watch(categoryProvider).value ?? [];
    final products = productState.products;
    final trendingProducts = productState.trendingProducts.isNotEmpty
        ? productState.trendingProducts
        : products.take(8).toList();
    const banners = [
      {
        'title': 'Fresh picks',
        'subtitle': 'Delivered faster',
        'cta': 'Shop now',
      },
      {
        'title': 'Trending deals',
        'subtitle': 'Save on essentials',
        'cta': 'View offers',
      },
    ];

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(productProvider.notifier).fetchProducts(reset: true);
            await ref.read(productProvider.notifier).fetchTrendingProducts();
          },
          child: ListView(
            controller: _scrollController,
            padding: EdgeInsets.all(horizontalPadding),
            children: [
              Row(
                children: [
                  const Text(
                    'POCKET',
                    style: TextStyle(
                      fontSize: 21,
                      letterSpacing: 0.2,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(19),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: const Icon(
                          Icons.notifications_none_rounded,
                          size: 20,
                        ),
                      ),
                      Positioned(
                        right: -1,
                        top: -1,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppTheme.accentOrange,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: Colors.white, width: 1.4),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.lightCyan,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: const Icon(Icons.person_rounded, size: 20),
                  ),
                ],
              ),
              SizedBox(height: isCompact ? 10 : 12),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 12 : 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        onChanged: (val) {
                          if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
                          _searchDebounce = Timer(const Duration(milliseconds: 500), () {
                            ref.read(productProvider.notifier).updateFilters(searchQuery: val);
                          });
                        },
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Search products',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _openFilterSortSheet(allCategories),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryCyan,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.tune_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isCompact ? 10 : 12),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isCompact ? 14 : 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.storefront_outlined,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Material(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => context.go('/buyer/shop'),
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(
                                Icons.search_rounded,
                                size: 22,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Hello, $firstName',
                        style: TextStyle(
                          fontSize: isCompact ? 24 : 28,
                          height: 1.0,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Discover quality products from trusted sellers.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFFD1D5DB),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text(
                    'Top categories',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(onPressed: () => context.go('/buyer/shop'), child: const Text('See all')),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 42,
                child: ref.watch(categoryProvider).when(
                  data: (categories) {
                    final allCategories = [Category(id: 0, name: 'All', slug: 'all'), ...categories];
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: allCategories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final category = allCategories[i];
                        final isSelected = ref.watch(selectedCategoryProvider) == category.id || (category.id == 0 && ref.watch(selectedCategoryProvider) == null);
                        return InkWell(
                          onTap: () {
                            if (category.id == 0) {
                              ref.read(selectedCategoryProvider.notifier).state = null;
                              ref.read(productProvider.notifier).updateFilters(category: 'all');
                            } else {
                              ref.read(selectedCategoryProvider.notifier).state = category.id;
                              ref.read(productProvider.notifier).updateFilters(category: category.id.toString());
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primaryCyan
                                  : AppTheme.softSurface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                if (category.iconName != null) ...[
                                  Icon(
                                    _categoryIcon(category.name),
                                    size: 18,
                                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Text(
                                  category.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const Text('Failed to load categories'),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 154,
                child: PageView.builder(
                  controller: _bannerController,
                  onPageChanged: (index) {
                    setState(() {
                      _activeBannerIndex = index;
                    });
                  },
                  itemCount: banners.length,
                  itemBuilder: (_, i) {
                    final banner = banners[i];
                    final bg = i.isEven
                        ? AppTheme.accentOrange
                        : AppTheme.accentBlue;
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 320;
                        final titleSize = compact ? 18.0 : 28.0;
                        final ctaFontSize = compact ? 13.0 : 17.0;
                        final iconSize = compact ? 44.0 : 66.0;
                        final bannerPadding = compact ? 12.0 : 18.0;
                        final ctaHorizontalPadding = compact ? 12.0 : 18.0;
                        final ctaVerticalPadding = compact ? 6.0 : 8.0;
                        return Container(
                          margin: const EdgeInsets.only(right: 10),
                          padding: EdgeInsets.all(bannerPadding),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${banner['title']!}\n${banner['subtitle']!}',
                                      maxLines: compact ? 3 : 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: titleSize,
                                        height: 1.0,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: ctaHorizontalPadding,
                                        vertical: ctaVerticalPadding,
                                      ),
                                      decoration: BoxDecoration(
                                        color: i.isEven
                                            ? Colors.white
                                            : AppTheme.accentPurple,
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                      child: Text(
                                        banner['cta']!,
                                        style: TextStyle(
                                          fontSize: ctaFontSize,
                                          fontWeight: FontWeight.w700,
                                          color: i.isEven
                                              ? const Color(0xFFF97316)
                                              : Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: compact ? 4 : 8),
                              Icon(
                                Icons.shopping_bag_outlined,
                                size: iconSize,
                                color: Colors.white70,
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(banners.length, (index) {
                  final selected = index == _activeBannerIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: selected ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: selected ? AppTheme.primaryCyan : AppTheme.divider,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              if (trendingProducts.isNotEmpty) ...[
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Trending now',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      'Swipe',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: isCompact ? 230 : 248,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: trendingProducts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, index) {
                      final product = trendingProducts[index];
                      final inStock = product.isAvailable && product.isInStock;
                      return SizedBox(
                        width: isCompact ? 156 : 170,
                        child: _ProductCard(
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
                            final err = await cartNotifier.addProduct(product);
                            if (!context.mounted) return;
                            if (err != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(err),
                                  backgroundColor: AppTheme.error,
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${product.name} added to cart',
                                  ),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
              ],
              ref.watch(recommendedProvider).when(
                data: (recommendedProducts) {
                  if (recommendedProducts.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'What you might be interested in',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            'Swipe',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: isCompact ? 230 : 248,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: recommendedProducts.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (_, index) {
                            final product = recommendedProducts[index];
                            final inStock = product.isAvailable && product.isInStock;
                            return SizedBox(
                              width: isCompact ? 156 : 170,
                              child: _ProductCard(
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
                                  final err = await cartNotifier.addProduct(product);
                                  if (!context.mounted) return;
                                  if (err != null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(err),
                                        backgroundColor: AppTheme.error,
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '${product.name} added to cart',
                                        ),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Popular near you',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      InkWell(
                        onTap: () => _openFilterSortSheet(allCategories),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEEEEE),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.tune,
                                size: 14,
                                color: AppTheme.textPrimary,
                              ),
                              SizedBox(width: 5),
                              Text('Filter', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${productState.totalCount > 0 ? productState.totalCount : products.length}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (productState.isLoading && productState.products.isEmpty)
                const _SkeletonProductGrid()
              else if (productState.error != null &&
                  productState.products.isEmpty)
                _InfoBlock(
                  icon: Icons.error_outline,
                  title: 'Could not load products',
                  message: productState.error!,
                  actionLabel: 'Retry',
                  onAction: () => ref
                      .read(productProvider.notifier)
                      .fetchProducts(reset: true),
                )
              else if (productState.products.isEmpty)
                _InfoBlock(
                  icon: Icons.storefront_outlined,
                  title: 'No listings yet',
                  message:
                      'There are no products in the shop right now. Pull down to refresh or try again later.',
                  actionLabel: 'Refresh',
                  onAction: () => ref
                      .read(productProvider.notifier)
                      .fetchProducts(reset: true),
                )
              else if (products.isEmpty)
                const _InfoBlock(
                  icon: Icons.search_off,
                  title: 'No matches',
                  message:
                      'No products match your search or filters. Try different keywords or clear filters.',
                )
              else
                GridView.builder(
                  itemCount: products.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: gridSpacing,
                    childAspectRatio: gridAspectRatio,
                  ),
                  itemBuilder: (_, i) {
                    final product = products[i];
                    final inStock = product.isAvailable && product.isInStock;
                    return _ProductCard(
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
                        final err = await cartNotifier.addProduct(product);
                        if (!context.mounted) return;
                        if (err != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(err),
                              backgroundColor: AppTheme.error,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${product.name} added to cart'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              if (productState.isLoadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryCyan,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final bool inStock;
  final bool isFavorite;
  final VoidCallback onAdd;
  final VoidCallback onToggleFavorite;
  final VoidCallback onCardTap;

  const _ProductCard({
    required this.product,
    required this.inStock,
    required this.isFavorite,
    required this.onAdd,
    required this.onToggleFavorite,
    required this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 165;
        final imageHeight = compact ? 108.0 : 124.0;
        final nameSize = compact ? 12.0 : 13.0;
        final priceSize = compact ? 14.0 : 15.0;
        final buttonHeight = compact ? 30.0 : 32.0;
        return InkWell(
          onTap: onCardTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.divider.withValues(alpha: 0.9),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(14),
                      ),
                      child: SizedBox(
                        height: imageHeight,
                        width: double.infinity,
                        child: ProductListThumbnail(
                          product: product,
                          compactPlaceholder: true,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'Top deal',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: InkWell(
                        onTap: onToggleFavorite,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: Icon(
                            isFavorite ? Icons.favorite : Icons.favorite_border,
                            size: 15,
                            color: isFavorite
                                ? AppTheme.error
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: nameSize,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          product.qualityDisplayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.darkCyan,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'ZMW ${product.price.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: priceSize,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'ZMW ${(product.price * 1.25).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary.withValues(
                              alpha: 0.8,
                            ),
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          height: buttonHeight,
                          child: ElevatedButton(
                            onPressed: inStock ? onAdd : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: inStock
                                  ? AppTheme.primaryCyan
                                  : AppTheme.divider,
                              foregroundColor: inStock
                                  ? Colors.white
                                  : AppTheme.textSecondary,
                              elevation: 0,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              inStock ? 'Add to cart' : 'Unavailable',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
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
          ),
        );
      },
    );
  }
}

class _SkeletonProductGrid extends StatelessWidget {
  const _SkeletonProductGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: 6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.52,
      ),
      itemBuilder: (_, __) {
        return _Shimmer(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              children: [
                Container(
                  height: 108,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceWhite,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Container(height: 12, color: AppTheme.surfaceWhite),
                      const SizedBox(height: 8),
                      Container(height: 10, color: AppTheme.surfaceWhite),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: 70,
                        color: AppTheme.surfaceWhite,
                      ),
                      const SizedBox(height: 16),
                      Container(height: 30, color: AppTheme.surfaceWhite),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Shimmer extends StatefulWidget {
  final Widget child;

  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = 0.55 + (_controller.value * 0.35);
        return Opacity(opacity: opacity, child: child);
      },
      child: widget.child,
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _InfoBlock({
    required this.icon,
    required this.message,
    this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 40,
            color: AppTheme.textSecondary.withValues(alpha: 0.85),
          ),
          if (title != null) ...[
            const SizedBox(height: 12),
            Text(
              title!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.35,
              color: AppTheme.textSecondary,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
