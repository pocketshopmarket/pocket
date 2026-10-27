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
import '../../../../widgets/ui/ps_ui.dart';

class BuyerHomeScreen extends ConsumerStatefulWidget {
  const BuyerHomeScreen({super.key});

  @override
  ConsumerState<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends ConsumerState<BuyerHomeScreen>
    with SingleTickerProviderStateMixin {
  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  final ScrollController _scrollController = ScrollController();
  final PageController _bannerController = PageController();
  int _activeBannerIndex = 0;
  int _bannerCount = 0;
  // Drives both the story-style progress bars and the auto-advance.
  late final AnimationController _bannerProgress = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) _advanceBanner();
    });
  Timer? _searchDebounce;
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
    _bannerProgress.dispose();
    _scrollController.dispose();
    _bannerController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _advanceBanner() {
    if (!_bannerController.hasClients || _bannerCount < 2) return;
    _bannerController.animateToPage(
      (_activeBannerIndex + 1) % _bannerCount,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  /// The product shown in a banner's photo frame. A banner that links to a
  /// product shows that product. Only platform banners borrow a trending
  /// product, so a paid banner never shows another seller's goods.
  Product? _bannerProduct(PromoBanner banner, int index, ProductState ps) {
    final withPhoto = [...ps.trendingProducts, ...ps.products]
        .where((p) => p.imageUrl != null && p.isAvailable && p.isInStock)
        .toList();
    if (banner.actionType == 'product') {
      final id = int.tryParse(banner.actionValue);
      for (final p in withPhoto) {
        if (p.id == id) return p;
      }
    }
    final platform = !banner.isSponsored &&
        (banner.actionType == 'none' || banner.actionType == 'category');
    if (!platform) return null;
    final trending = ps.trendingProducts
        .where((p) => p.imageUrl != null && p.isAvailable && p.isInStock)
        .toList();
    if (trending.isEmpty) return null;
    return trending[index % trending.length];
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
    // The provider already falls back to built-in banners on error, so
    // "no value yet" only ever means still loading: show a skeleton, never
    // flash the fallbacks first.
    final bannersLoading = !bannersAsync.hasValue;
    final banners = bannersAsync.valueOrNull ?? const <PromoBanner>[];
    final sponsoredBanners = banners.where((b) => b.isSponsored).toList();

    final productState = ref.watch(productProvider);
    _bannerCount = banners.length;
    if (banners.length >= 2 && _bannerProgress.status == AnimationStatus.dismissed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bannerProgress.forward(from: 0);
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
                  Text(
                    'POCKET',
                    style: AppTheme.display(fontSize: 21, letterSpacing: -0.4),
                  ),
                  const Spacer(),
                  _HeaderTile(
                    child: IconButton(
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
                        size: 19,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _HeaderTile(child: NotificationBell()),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '${_greeting()}, $firstName',
                style: AppTheme.display(fontSize: isCompact ? 20 : 22, height: 1.15),
              ),
              const SizedBox(height: 3),
              Text(
                'What are we shopping for today?',
                style: AppTheme.body(fontSize: 13.5, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              const BirthdayNudgeCard(),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 12 : 14,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
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
                        style: AppTheme.body(fontSize: 14.5),
                        decoration: InputDecoration(
                          hintText: 'Search shops',
                          hintStyle: AppTheme.body(fontSize: 14.5, color: AppTheme.textSecondary),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 13),
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
                fadeInDuration: const Duration(milliseconds: 220),
                placeholder: (_, _) => const ShimmerFill(),
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
              const SizedBox(height: 4),
              if (bannersLoading)
                const BannerShimmer()
              else if (banners.isNotEmpty)
              SizedBox(
                height: 176,
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _bannerController,
                      onPageChanged: (index) {
                        setState(() => _activeBannerIndex = index);
                        if (banners.length >= 2) _bannerProgress.forward(from: 0);
                      },
                      itemCount: banners.length,
                      itemBuilder: (_, i) {
                        final banner = banners[i];
                        // An uploaded image is a finished creative: shown as-is.
                        return banner.imageUrl != null
                            ? _ImageBannerCard(banner: banner, onTap: () => _onBannerTap(banner))
                            : _HeroBannerCard(
                                banner: banner,
                                product: _bannerProduct(banner, i, productState),
                                photoPending: !productState.trendingLoaded &&
                                    !banner.isSponsored &&
                                    const {'none', 'category', 'product'}.contains(banner.actionType),
                                onTap: () => _onBannerTap(banner),
                              );
                      },
                    ),
                    if (banners.length >= 2)
                      Positioned(
                        top: 12,
                        left: 16,
                        right: 16,
                        child: IgnorePointer(
                          child: _StoryBars(
                            count: banners.length,
                            active: _activeBannerIndex.clamp(0, banners.length - 1),
                            progress: _bannerProgress,
                            onLight: banners[_activeBannerIndex.clamp(0, banners.length - 1)]
                                    .imageUrl == null &&
                                banners[_activeBannerIndex.clamp(0, banners.length - 1)]
                                        .backgroundColor
                                        .computeLuminance() >=
                                    0.5,
                          ),
                        ),
                      ),
                  ],
                ),
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
                                const PsSectionHeader(title: 'Shops near you'),
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
                          const PsSectionHeader(title: 'All shops'),
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: banner.backgroundColor,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: banner.imageUrl!,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 220),
                placeholder: (_, _) => const ShimmerFill(),
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            if (banner.isSponsored)
              const Positioned(top: 26, right: 14, child: _SponsoredBadge()),
          ],
        ),
      ),
    );
  }
}

/// Banner without an uploaded image: brand color, eyebrow + headline, a pill
/// CTA, and a real product photo in a tilted frame with its price. Falls back
/// to the banner's icon as a corner watermark when there's no photo to show.
class _HeroBannerCard extends StatelessWidget {
  const _HeroBannerCard({
    required this.banner,
    required this.product,
    required this.photoPending,
    required this.onTap,
  });

  final PromoBanner banner;
  final Product? product;
  // Keep the photo slot (shimmering) while trending products load, so the
  // headline doesn't reflow when the photo arrives.
  final bool photoPending;
  final VoidCallback onTap;

  String get _headline {
    final t = banner.title.trim();
    final sub = banner.subtitle.trim();
    if (sub.isEmpty) return t;
    if (t.isEmpty) return sub;
    // "Fresh picks" + "Delivered faster" -> "Fresh picks, delivered faster",
    // leaving acronyms and ALL-CAPS words alone.
    final soft = sub.length > 1 && sub[1] == sub[1].toLowerCase()
        ? sub[0].toLowerCase() + sub.substring(1)
        : sub;
    return '$t, $soft';
  }

  @override
  Widget build(BuildContext context) {
    final bg = banner.backgroundColor;
    final isDark = bg.computeLuminance() < 0.5;
    final fg = isDark ? Colors.white : AppTheme.textPrimary;
    final ctaBg = isDark ? Colors.white : AppTheme.textPrimary;
    final ctaFg = isDark ? bg : Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        final url = product?.imageUrl;
        final showFrame = constraints.maxWidth >= 330 && (url != null || photoPending);
        return Material(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!showFrame)
                  Positioned(
                    right: -24,
                    bottom: -30,
                    child: Icon(banner.icon, size: 156, color: fg.withValues(alpha: 0.16)),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 32, showFrame ? 150 : 20, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        banner.isSponsored ? 'SPONSORED' : 'THIS WEEK ON POCKET',
                        style: AppTheme.body(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: fg.withValues(alpha: 0.85),
                        ).copyWith(letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _headline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.display(fontSize: 22, color: fg, height: 1.15),
                      ),
                      const Spacer(),
                      Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        decoration: BoxDecoration(
                          color: ctaBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              banner.ctaText,
                              style: AppTheme.body(fontSize: 13.5, fontWeight: FontWeight.w700, color: ctaFg),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.arrow_forward_rounded, size: 15, color: ctaFg),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (showFrame)
                  Positioned(
                    right: 20,
                    top: 30,
                    child: Transform.rotate(
                      angle: 0.087, // ~5 degrees
                      child: _PhotoFrame(url: url, price: url != null ? product?.price : null),
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

class _PhotoFrame extends StatelessWidget {
  const _PhotoFrame({required this.url, required this.price});

  final String? url;
  final double? price;

  @override
  Widget build(BuildContext context) {
    final p = price;
    final label = p == null
        ? null
        : (p.truncateToDouble() == p ? p.toStringAsFixed(0) : p.toStringAsFixed(2));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 108,
          height: 132,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(color: Color(0x2E000000), blurRadius: 18, offset: Offset(0, 8)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: url == null
                ? const ShimmerFill()
                : CachedNetworkImage(
                    imageUrl: url!,
                    fit: BoxFit.cover,
                    memCacheWidth: (132 * MediaQuery.devicePixelRatioOf(context) * 1.35).round(),
                    fadeInDuration: const Duration(milliseconds: 220),
                    placeholder: (_, _) => const ShimmerFill(),
                    errorWidget: (_, _, _) => const ColoredBox(color: AppTheme.softSurface),
                  ),
          ),
        ),
        if (label != null)
        Positioned(
          left: -10,
          bottom: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.textPrimary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'ZMW $label',
              style: AppTheme.body(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// Story-style segments: done ones full, the current one filling over the
/// slide's time, upcoming ones faint.
class _StoryBars extends StatelessWidget {
  const _StoryBars({
    required this.count,
    required this.active,
    required this.progress,
    required this.onLight,
  });

  final int count;
  final int active;
  final Animation<double> progress;
  final bool onLight;

  @override
  Widget build(BuildContext context) {
    final color = onLight ? AppTheme.textPrimary : Colors.white;
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) => Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: color.withValues(alpha: 0.35)),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: i < active ? 1 : (i == active ? progress.value : 0),
                        child: ColoredBox(color: color),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderTile extends StatelessWidget {
  const _HeaderTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: AppTheme.divider),
        ),
        child: child,
      ),
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
                fadeInDuration: const Duration(milliseconds: 220),
                placeholder: (_, _) => const ShimmerFill(),
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
                            style: AppTheme.display(fontSize: 18, color: Colors.white),
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
