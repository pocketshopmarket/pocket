import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/product.dart';
import '../../../../models/promo_banner.dart';
import '../../../../widgets/product_list_thumbnail.dart';
import '../../../../providers/product_provider.dart';
import '../../../../providers/category_provider.dart';
import '../../../../providers/banner_provider.dart';
import '../../../../services/product_service.dart';
import 'dart:async';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/wishlist_provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../models/category.dart';
import '../../../../widgets/notification_bell.dart';
import '../../../../widgets/qr_identity_sheet.dart';

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
  Timer? _autoScrollTimer;
  final TextEditingController _searchController = TextEditingController();
  List<Product> _searchSuggestions = [];
  bool _showSuggestions = false;
  bool _searchLoading = false;
  bool _searchFailed = false;

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    _bannerController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _startAutoScroll(int bannerCount) {
    _autoScrollTimer?.cancel();
    if (bannerCount < 2) return;
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_bannerController.hasClients) return;
      final next = ((_bannerController.page?.round() ?? 0) + 1) % bannerCount;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _onBannerTap(PromoBanner banner) async {
    switch (banner.actionType) {
      case 'category':
        final categoryId = int.tryParse(banner.actionValue);
        if (categoryId != null) {
          ref.read(selectedCategoryProvider.notifier).state = categoryId;
          ref.read(productProvider.notifier).updateFilters(
            category: banner.actionValue,
          );
          context.go('/buyer/shop');
        }
        break;
      case 'product':
        final productId = int.tryParse(banner.actionValue);
        if (productId != null) {
          final state = ref.read(productProvider);
          Product? product;
          for (final p in [...state.trendingProducts, ...state.products]) {
            if (p.id == productId) { product = p; break; }
          }
          if (product != null) {
            context.push('/buyer/product-details', extra: product);
          } else {
            // Product not in memory — fetch it then navigate
            try {
              final fetched = await ref.read(productServiceProvider).getProduct(productId);
              if (mounted) context.push('/buyer/product-details', extra: fetched);
            } catch (_) {}
          }
        }
        break;
      case 'url':
        final uri = Uri.tryParse(banner.actionValue);
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
        break;
      case 'none':
      default:
        break;
    }
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
    final productState = ref.read(productProvider);
    String tempCategory = _selectedCategory;
    bool tempInStockOnly = _inStockOnly;
    String tempSortBy = _sortBy;
    String? tempQuality = productState.quality;
    final minController = TextEditingController(
      text: productState.minPrice != null ? productState.minPrice!.toStringAsFixed(0) : '',
    );
    final maxController = TextEditingController(
      text: productState.maxPrice != null ? productState.maxPrice!.toStringAsFixed(0) : '',
    );

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
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
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
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String?>(
                      initialValue: tempQuality,
                      decoration: const InputDecoration(labelText: 'Condition', isDense: true),
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
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Min price (ZMW)', isDense: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maxController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Max price (ZMW)', isDense: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('In-stock only'),
                      value: tempInStockOnly,
                      activeThumbColor: AppTheme.primaryCyan,
                      onChanged: (value) => setModalState(() => tempInStockOnly = value),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sort',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    ...[
                      ('default', 'Default'),
                      ('popular', 'Most popular'),
                      ('latest', 'Latest'),
                      ('price_low', 'Price: low to high'),
                      ('price_high', 'Price: high to low'),
                      ('name_az', 'Name: A to Z'),
                    ].map((option) {
                        return RadioListTile<String>(
                        value: option.$1,
                        groupValue: tempSortBy,
                        // ignore: deprecated_member_use
                        activeColor: AppTheme.primaryCyan,
                        contentPadding: EdgeInsets.zero,
                        title: Text(option.$2, style: const TextStyle(fontSize: 13)),
                        onChanged: (value) {
                          if (value != null) setModalState(() => tempSortBy = value);
                        },
                      );
                    }),
                    const SizedBox(height: 8),
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
                                _sortBy = 'default';
                              });
                              ref.read(productProvider.notifier).updateFilters(
                                category: 'all',
                                inStockOnly: false,
                                sortBy: 'default',
                                clearMinPrice: true,
                                clearMaxPrice: true,
                                clearQuality: true,
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
                              final minVal = double.tryParse(minController.text.trim());
                              final maxVal = double.tryParse(maxController.text.trim());
                              minController.dispose();
                              maxController.dispose();
                              setState(() {
                                _selectedCategory = tempCategory;
                                _inStockOnly = tempInStockOnly;
                                _sortBy = tempSortBy;
                              });
                              ref.read(productProvider.notifier).updateFilters(
                                category: tempCategory,
                                inStockOnly: tempInStockOnly,
                                sortBy: tempSortBy,
                                minPrice: minVal,
                                maxPrice: maxVal,
                                quality: tempQuality,
                                clearMinPrice: minVal == null,
                                clearMaxPrice: maxVal == null,
                                clearQuality: tempQuality == null,
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
    final wishlist = ref.watch(wishlistProvider);
    final user = ref.watch(userProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final wishlistNotifier = ref.read(wishlistProvider.notifier);
    final firstName = user?.displayName.split(' ').first ?? 'Shopper';
    final allCategories = ref.watch(categoryProvider);
    final products = productState.products;
    final trendingProducts = productState.trendingProducts.isNotEmpty
        ? productState.trendingProducts
        : products.take(8).toList();
    final bannersAsync = ref.watch(bannerProvider);
    final banners = bannersAsync.valueOrNull ?? PromoBanner.defaults;

    // Start auto-scroll once banners are loaded
    if (banners.length >= 2 && _autoScrollTimer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startAutoScroll(banners.length);
      });
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(bannerProvider);
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
                  IconButton(
                    tooltip: 'My QR code',
                    onPressed: () => QrIdentitySheet.show(context),
                    icon: const Icon(
                      Icons.qr_code_rounded,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const NotificationBell(),
                ],
              ),
              SizedBox(height: isCompact ? 10 : 12),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 12 : 14,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(14),
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
                        controller: _searchController,
                        onChanged: (val) {
                          _searchDebounce?.cancel();
                          if (val.trim().isEmpty) {
                            setState(() {
                              _showSuggestions = false;
                              _searchSuggestions = [];
                            });
                            ref.read(productProvider.notifier).updateFilters(searchQuery: '');
                            return;
                          }
                          setState(() => _searchLoading = true);
                          _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
                            try {
                              final service = ref.read(productServiceProvider);
                              final page = await service.getProductsPage(
                                ProductQuery(search: val.trim(), pageSize: 6),
                              );
                              if (mounted) {
                                setState(() {
                                  _searchSuggestions = page.items;
                                  _showSuggestions = true;
                                  _searchLoading = false;
                                  _searchFailed = false;
                                });
                              }
                            } catch (_) {
                              if (mounted) {
                                setState(() {
                                  _searchLoading = false;
                                  _showSuggestions = true;
                                  _searchSuggestions = [];
                                  _searchFailed = true;
                                });
                              }
                            }
                          });
                        },
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search products',
                          hintStyle: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? GestureDetector(
                                  onTap: () {
                                    _searchController.clear();
                                    setState(() {
                                      _showSuggestions = false;
                                      _searchSuggestions = [];
                                    });
                                    ref.read(productProvider.notifier).updateFilters(searchQuery: '');
                                  },
                                  child: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textSecondary),
                                )
                              : null,
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
              // Search suggestions dropdown
              if (_showSuggestions && _searchController.text.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _searchLoading
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primaryCyan,
                              ),
                            ),
                          ),
                        )
                      : _searchSuggestions.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(
                                    _searchFailed
                                        ? Icons.cloud_off_rounded
                                        : Icons.search_off_rounded,
                                    size: 16,
                                    color: AppTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _searchFailed
                                        ? 'Search unavailable, check your connection'
                                        : 'No products found',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: _searchSuggestions.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final product = _searchSuggestions[i];
                                return ListTile(
                                  dense: true,
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: ProductListThumbnail(
                                        product: product,
                                        compactPlaceholder: true,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'ZMW ${product.price.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.darkCyan,
                                    ),
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary),
                                  onTap: () {
                                    _searchController.clear();
                                    setState(() {
                                      _showSuggestions = false;
                                      _searchSuggestions = [];
                                    });
                                    context.push('/buyer/product-details', extra: product);
                                  },
                                );
                              },
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
                child: Builder(builder: (context) {
                    final rawCategories = ref.watch(categoryProvider);
                    final catState = ref.watch(categoriesProvider);
                    if (rawCategories.isEmpty && catState.isLoading) {
                      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
                    }
                    final categories = [Category(id: 0, name: 'All', slug: 'all'), ...rawCategories];
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: categories.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final category = categories[i];
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
                  }),
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
                    final bg = banner.backgroundColor;
                    // Derive CTA colors from bg luminance: use dark button on light bg, light on dark.
                    final isDark = bg.computeLuminance() < 0.4;
                    final ctaBg = isDark ? Colors.white : Colors.black.withValues(alpha: 0.18);
                    final ctaTextColor = isDark ? bg : Colors.white;
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 320;
                        final titleSize = compact ? 18.0 : 28.0;
                        final ctaFontSize = compact ? 13.0 : 17.0;
                        final iconSize = compact ? 44.0 : 66.0;
                        final bannerPadding = compact ? 12.0 : 18.0;
                        final ctaHorizontalPadding = compact ? 12.0 : 18.0;
                        final ctaVerticalPadding = compact ? 6.0 : 8.0;
                        return GestureDetector(
                          onTap: () => _onBannerTap(banner),
                          child: Container(
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              children: [
                                // Background image if available
                                if (banner.imageUrl != null)
                                  Positioned.fill(
                                    child: CachedNetworkImage(
                                      imageUrl: banner.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                                    ),
                                  ),
                                // Semi-transparent overlay when image is present
                                if (banner.imageUrl != null)
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            bg.withValues(alpha: 0.75),
                                            bg.withValues(alpha: 0.35),
                                          ],
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                        ),
                                      ),
                                    ),
                                  ),
                                Padding(
                                  padding: EdgeInsets.all(bannerPadding),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${banner.title}\n${banner.subtitle}',
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
                                            GestureDetector(
                                              onTap: () => _onBannerTap(banner),
                                              child: Container(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: ctaHorizontalPadding,
                                                  vertical: ctaVerticalPadding,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: ctaBg,
                                                  borderRadius: BorderRadius.circular(22),
                                                ),
                                                child: Text(
                                                  banner.ctaText,
                                                  style: TextStyle(
                                                    fontSize: ctaFontSize,
                                                    fontWeight: FontWeight.w700,
                                                    color: ctaTextColor,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (banner.imageUrl == null) ...[
                                        SizedBox(width: compact ? 4 : 8),
                                        Icon(
                                          banner.icon,
                                          size: iconSize,
                                          color: Colors.white70,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
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
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
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
                error: (_, _) => Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 15,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Could not load recommendations',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(recommendedProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Builder(
                      builder: (_) {
                        final selectedId = ref.watch(selectedCategoryProvider);
                        if (selectedId == null) {
                          return const Text(
                            'Popular near you',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          );
                        }
                        final cats = allCategories;
                        final name = cats.where((c) => c.id == selectedId).firstOrNull?.name;
                        return Text(
                          name ?? 'Popular near you',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        );
                      },
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
              else if (productState.products.isEmpty && _selectedCategory == 'all' && ref.watch(selectedCategoryProvider) == null)
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
              else if (productState.products.isEmpty)
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 40,
                            color: AppTheme.textSecondary.withValues(alpha: 0.85),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Nothing here yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'No products match this category right now.\nCheck back soon or browse other categories!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.35,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton(
                            onPressed: () {
                              ref.read(selectedCategoryProvider.notifier).state = null;
                              ref.read(productProvider.notifier).updateFilters(category: 'all');
                            },
                            child: const Text('Show all products'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // "You might also like" — show popular products across ALL categories
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'You might also like',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<List<Product>>(
                      future: ref.read(productServiceProvider).fetchTrending(pageSize: 6),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                color: AppTheme.primaryCyan,
                              ),
                            ),
                          );
                        }
                        final suggestions = snapshot.data ?? [];
                        if (suggestions.isEmpty) return const SizedBox.shrink();
                        return GridView.builder(
                          itemCount: suggestions.length,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: gridSpacing,
                            childAspectRatio: gridAspectRatio,
                          ),
                          itemBuilder: (_, i) {
                            final product = suggestions[i];
                            final inStock = product.isAvailable && product.isInStock;
                            return _ProductCard(
                              product: product,
                              inStock: inStock,
                              isFavorite: wishlist.contains(product.id),
                              onToggleFavorite: () => wishlistNotifier.toggle(product.id),
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
                        );
                      },
                    ),
                  ],
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
                        const SizedBox(height: 2),
                        Text(
                          'ZMW ${product.price.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: priceSize,
                            fontWeight: FontWeight.w800,
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
                            child: inStock
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add_shopping_cart, size: 14),
                                      SizedBox(width: 4),
                                      Text(
                                        'Add to cart',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  )
                                : const Text(
                                    'Unavailable',
                                    style: TextStyle(
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
      itemBuilder: (_, _) {
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
