import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/product.dart';
import '../../../../models/promo_banner.dart';
import '../../../../providers/product_provider.dart';
import '../../../../providers/category_provider.dart';
import '../../../../providers/banner_provider.dart';
import '../../../../providers/shop_provider.dart';
import '../../../../providers/shop_type_provider.dart';
import '../../../../widgets/shop_section_card.dart';
import '../../../../widgets/shimmer_loading.dart';
import '../../../../models/shop.dart';
import '../../../../services/shop_service.dart';
import 'dart:async';
import '../../../../providers/auth_provider.dart';
import '../widgets/birthday_nudge_card.dart';
import '../../../../widgets/notification_bell.dart';
import '../../../../widgets/qr_identity_sheet.dart';
import '../../../../widgets/sign_in_prompt.dart';

class BuyerHomeScreen extends ConsumerStatefulWidget {
  const BuyerHomeScreen({super.key});

  @override
  ConsumerState<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends ConsumerState<BuyerHomeScreen> {
  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  final ScrollController _scrollController = ScrollController();
  final PageController _bannerController = PageController(
    viewportFraction: 0.94,
  );
  int _activeBannerIndex = 0;
  Timer? _searchDebounce;
  Timer? _autoScrollTimer;
  final TextEditingController _searchController = TextEditingController();
  List<Shop> _searchSuggestions = [];
  bool _showSuggestions = false;
  bool _searchLoading = false;
  bool _searchFailed = false;
  // Suppresses the inline "Shops near you" spinner while Flutter's own
  // pull-to-refresh spinner is already showing — otherwise both appear
  // together and read as two competing/buggy loaders instead of one.
  bool _isRefreshing = false;

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

  /// A sponsored banner every 8 shops as the buyer scrolls "All shops",
  /// rotating through whichever sponsored banners are live — so a paid
  /// placement gets ongoing exposure, not just one shot in the top carousel.
  /// Null outside a banner slot, or whenever there's nothing sponsored to show.
  PromoBanner? _inFeedBannerFor(List<PromoBanner> sponsored, int shopIndex) {
    const interval = 8;
    if (sponsored.isEmpty) return null;
    if ((shopIndex + 1) % interval != 0) return null;
    final slot = (shopIndex + 1) ~/ interval - 1;
    return sponsored[slot % sponsored.length];
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
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not open this product. Please try again.')),
                );
              }
            }
          }
        }
        break;
      case 'shop':
        final sellerId = int.tryParse(banner.actionValue);
        if (sellerId != null) {
          context.push('/buyer/shop-details?id=$sellerId');
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final nearBottom =
          _scrollController.position.pixels >=
          (_scrollController.position.maxScrollExtent - 180);
      if (nearBottom) {
        ref.read(shopProvider.notifier).fetchAllShops();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 360;
    final horizontalPadding = isCompact ? 12.0 : 16.0;
    final shopState = ref.watch(shopProvider);
    final user = ref.watch(userProvider);
    final firstName = user?.displayName.split(' ').first ?? 'Shopper';
    final bannersAsync = ref.watch(bannerProvider);
    final banners = bannersAsync.valueOrNull ?? PromoBanner.defaults;
    final sponsoredBanners = banners.where((b) => b.isSponsored).toList();

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
            setState(() => _isRefreshing = true);
            try {
              ref.invalidate(bannerProvider);
              await ref.read(shopProvider.notifier).fetchAllShops(reset: true);
              await ref.read(shopProvider.notifier).fetchNearbyShops();
            } finally {
              if (mounted) setState(() => _isRefreshing = false);
            }
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
                    onPressed: () {
                      if (user == null) {
                        SignInPrompt.showSheet(
                          context,
                          message: 'Sign in to get your identity QR code.',
                        );
                        return;
                      }
                      QrIdentitySheet.show(context);
                    },
                    icon: const Icon(
                      Icons.qr_code_rounded,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const NotificationBell(),
                ],
              ),
              SizedBox(height: isCompact ? 10 : 12),
              const BirthdayNudgeCard(),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 12 : 14,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.softSurface,
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
                            return;
                          }
                          setState(() => _searchLoading = true);
                          _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
                            try {
                              final service = ref.read(shopServiceProvider);
                              final page = await service.getShopsPage(
                                ShopQuery(search: val.trim(), pageSize: 6),
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
                          hintText: 'Search shops',
                          hintStyle: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
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
                                    setState(() {
                                      _showSuggestions = false;
                                      _searchSuggestions = [];
                                    });
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
                                        : 'No shops found',
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
                                final shop = _searchSuggestions[i];
                                return ListTile(
                                  dense: true,
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: shop.shopLogo != null
                                          ? CachedNetworkImage(
                                              imageUrl: shop.shopLogo!,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, _, _) => Container(
                                                color: AppTheme.divider.withValues(alpha: 0.3),
                                                alignment: Alignment.center,
                                                child: const Icon(Icons.storefront_outlined, size: 18, color: AppTheme.textSecondary),
                                              ),
                                            )
                                          : Container(
                                              color: AppTheme.divider.withValues(alpha: 0.3),
                                              alignment: Alignment.center,
                                              child: const Icon(Icons.storefront_outlined, size: 18, color: AppTheme.textSecondary),
                                            ),
                                    ),
                                  ),
                                  title: Text(
                                    shop.shopName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${shop.productCount} item${shop.productCount == 1 ? '' : 's'}',
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
                                    context.push('/buyer/shop-details?id=${shop.id}');
                                  },
                                );
                              },
                            ),
                ),
              SizedBox(height: isCompact ? 10 : 12),
              Builder(
                builder: (context) {
                  final shopTypesState = ref.watch(shopTypesProvider);
                  final shopTypes = shopTypesState.shopTypes;
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SizeTransition(sizeFactor: animation, axisAlignment: -1, child: child),
                    ),
                    child: shopTypes.isEmpty
                        ? (shopTypesState.isLoading
                            ? const Padding(
                                key: ValueKey('types-loading'),
                                padding: EdgeInsets.only(bottom: 12),
                                child: ShopTypeChipsShimmer(),
                              )
                            : const SizedBox.shrink(key: ValueKey('types-empty')))
                        : Padding(
                            key: const ValueKey('types-loaded'),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SizedBox(
                              height: 36,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: 1 + shopTypes.length,
                                separatorBuilder: (_, _) => const SizedBox(width: 8),
                                itemBuilder: (_, index) {
                                  final isAll = index == 0;
                                  final typeId = isAll ? null : shopTypes[index - 1].id;
                                  final typeName = isAll ? 'All' : shopTypes[index - 1].name;
                                  final selected = shopState.selectedShopTypeId == typeId;
                                  return ChoiceChip(
                                    label: Text(typeName),
                                    selected: selected,
                                    onSelected: (_) {
                                      if (!selected) {
                                        ref.read(shopProvider.notifier).setShopType(typeId);
                                      }
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
                          ),
                  );
                },
              ),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isCompact ? 14 : 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: AppTheme.textPrimary,
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
                        '${_greeting()}, $firstName',
                        style: AppTheme.display(
                          fontSize: isCompact ? 22 : 25,
                          height: 1.1,
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
                    // A banner with an uploaded image is treated as a finished
                    // creative — it's never had text/gradient stamped on top
                    // of it. Only the icon+color+text style (no image) gets
                    // that treatment.
                    return banner.imageUrl != null
                        ? _ImageBannerCard(banner: banner, onTap: () => _onBannerTap(banner))
                        : _TextBannerCard(banner: banner, onTap: () => _onBannerTap(banner));
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
              // "Near Me" is silently omitted (no error UI) when location is
              // denied/unavailable — confirmed product decision, not a bug.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(sizeFactor: animation, axisAlignment: -1, child: child),
                ),
                child: shopState.isLoadingNearby && !_isRefreshing
                    ? const Padding(
                        key: ValueKey('nearby-loading'),
                        padding: EdgeInsets.only(bottom: 16),
                        child: ShopCardShimmer(),
                      )
                    : shopState.nearbyShops.isNotEmpty
                        ? Padding(
                            key: const ValueKey('nearby-loaded'),
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Shops near you',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                                ),
                                const SizedBox(height: 10),
                                ...shopState.nearbyShops.expand((shop) => [
                                      ShopSectionCard(
                                        shop: shop,
                                        onOpenShop: () => context.push('/buyer/shop-details', extra: shop),
                                        onProductTap: (product) => context.push('/buyer/product-details', extra: product),
                                      ),
                                      const SizedBox(height: 12),
                                    ]),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('nearby-empty')),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(sizeFactor: animation, axisAlignment: -1, child: child),
                ),
                child: shopState.allShops.isNotEmpty
                    ? Column(
                        key: const ValueKey('all-shops-loaded'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'All shops',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 10),
                          ...shopState.allShops.asMap().entries.expand((entry) {
                            final index = entry.key;
                            final shop = entry.value;
                            final widgets = [
                              ShopSectionCard(
                                shop: shop,
                                onOpenShop: () => context.push('/buyer/shop-details', extra: shop),
                                onProductTap: (product) => context.push('/buyer/product-details', extra: product),
                              ),
                              const SizedBox(height: 12),
                            ];
                            // A sponsored banner every few shops as the buyer scrolls —
                            // not fully random (that risks two in a row, or a whole
                            // session with none) and not purely sequential-only-at-top,
                            // which is all a paid seller used to get.
                            final inFeedBanner = _inFeedBannerFor(sponsoredBanners, index);
                            if (inFeedBanner != null) {
                              widgets.addAll([
                                _InFeedBannerCard(banner: inFeedBanner, onTap: () => _onBannerTap(inFeedBanner)),
                                const SizedBox(height: 12),
                              ]);
                            }
                            return widgets;
                          }),
                          if (shopState.isLoadingMoreAllShops) ...[
                            const SizedBox(height: 6),
                            const Center(
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryCyan),
                            ),
                          ],
                          const SizedBox(height: 6),
                        ],
                      )
                    : shopState.isLoadingAllShops
                        ? const Column(
                            key: ValueKey('all-shops-loading'),
                            children: [
                              ShopCardShimmer(),
                              SizedBox(height: 12),
                              ShopCardShimmer(),
                              SizedBox(height: 12),
                              ShopCardShimmer(),
                              SizedBox(height: 18),
                            ],
                          )
                        : const SizedBox.shrink(key: ValueKey('all-shops-empty')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small "Sponsored" tag — same look wherever a paid banner shows, so
/// buyers learn to recognize it instead of mistaking it for an organic post.
class _SponsoredBadge extends StatelessWidget {
  const _SponsoredBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Sponsored',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// A banner with an uploaded image, shown full-bleed with no text or
/// gradient stamped on top — the image is a finished creative (the seller's
/// own design, or an admin's), so adding more text on top only fights it.
class _ImageBannerCard extends StatelessWidget {
  const _ImageBannerCard({required this.banner, required this.onTap});

  final PromoBanner banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: banner.backgroundColor,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: banner.imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            if (banner.isSponsored)
              const Positioned(top: 10, right: 10, child: _SponsoredBadge()),
          ],
        ),
      ),
    );
  }
}

/// The original icon + color + title/subtitle + CTA card, for banners
/// without an uploaded image.
class _TextBannerCard extends StatelessWidget {
  const _TextBannerCard({required this.banner, required this.onTap});

  final PromoBanner banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
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
                              onTap: onTap,
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
                      SizedBox(width: compact ? 4 : 8),
                      Icon(
                        banner.icon,
                        size: iconSize,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
                if (banner.isSponsored)
                  const Positioned(top: 10, right: 10, child: _SponsoredBadge()),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A sponsored banner dropped into the "All shops" scroll feed. Reads as a
/// shop card's sibling (same radius/border/shadow) rather than an ad that
/// stands out and gets tuned out — the "Sponsored" label is what does the
/// honesty work, not a jarring visual style. Image banners show full-bleed;
/// banners without an image fall back to the color+icon+text treatment,
/// stretched to one full-width card instead of the carousel's paged strip.
class _InFeedBannerCard extends StatelessWidget {
  const _InFeedBannerCard({required this.banner, required this.onTap});

  final PromoBanner banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          color: banner.imageUrl != null ? Colors.white : banner.backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider.withValues(alpha: 0.9)),
          boxShadow: const [
            BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            if (banner.imageUrl != null)
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: banner.imageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            banner.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          if (banner.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              banner.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: Colors.white70),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(banner.icon, size: 40, color: Colors.white70),
                  ],
                ),
              ),
            const Positioned(top: 10, right: 10, child: _SponsoredBadge()),
          ],
        ),
      ),
    );
  }
}
