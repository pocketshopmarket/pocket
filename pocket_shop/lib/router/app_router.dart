import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../features/auth/screens/change_password_screen.dart';
import '../features/auth/screens/forgot_password_screen.dart';
import '../features/auth/screens/otp_verification_screen.dart';
import '../features/auth/screens/phone_login_screen.dart';
import '../features/auth/screens/reset_password_screen.dart';
import '../features/auth/screens/role_selection_screen.dart';
import '../features/auth/screens/signup_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/buyer/screens/buyer_home_screen.dart';
import '../features/buyer/screens/buyer_main_screen.dart';
import '../features/buyer/screens/buyer_order_detail_screen.dart';
import '../features/buyer/screens/buyer_orders_screen.dart';
import '../features/buyer/screens/buyer_product_details_screen.dart';
import '../features/buyer/screens/buyer_profile_screen.dart';
import '../features/buyer/screens/buyer_search_screen.dart';
import '../features/buyer/screens/buyer_wishlist_screen.dart';
import '../features/buyer/screens/cart_screen.dart';
import '../features/buyer/screens/order_tracking_screen.dart';
import '../features/buyer/screens/payment_pending_screen.dart';
import '../features/delivery/screens/active_delivery_screen.dart';
import '../features/delivery/screens/delivery_home_screen.dart';
import '../features/delivery/screens/delivery_main_screen.dart';
import '../features/delivery/screens/delivery_offers_screen.dart';
import '../features/delivery/screens/delivery_profile_screen.dart';
import '../features/delivery/screens/earnings_screen.dart';
import '../features/admin/screens/admin_dashboard_screen.dart';
import '../features/seller/screens/add_product_screen.dart';
import '../features/seller/screens/edit_product_screen.dart';
import '../features/seller/screens/seller_dashboard_screen.dart';
import '../features/seller/screens/seller_main_screen.dart';
import '../features/seller/screens/seller_orders_screen.dart';
import '../features/seller/screens/seller_product_reviews_screen.dart';
import '../features/seller/screens/seller_products_screen.dart';
import '../features/seller/screens/seller_profile_screen.dart';
import '../features/seller/screens/seller_payout_methods_screen.dart';
import '../features/seller/screens/seller_payout_history_screen.dart';
import '../features/shared/screens/notifications_screen.dart';
import '../features/shared/screens/payout_screen.dart';
import '../features/shared/screens/refund_requests_screen.dart';
import '../features/shared/screens/cancellation_requests_screen.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart' show AuthState, authProvider;

class RouterRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}

// Stable branch navigator keys.
// go_router keys sub-navigators as GlobalObjectKey(navigatorKey.hashCode).
// Using explicit keys here guarantees unique hashCodes and prevents the
// duplicate-page-key assertion that fires when sibling shells share a
// hashCode collision across their branch navigators.
final _buyerBranchHome = GlobalKey<NavigatorState>(debugLabel: 'buyer/home');
final _buyerBranchShop = GlobalKey<NavigatorState>(debugLabel: 'buyer/shop');
final _buyerBranchWishlist = GlobalKey<NavigatorState>(debugLabel: 'buyer/wishlist');
final _buyerBranchCart = GlobalKey<NavigatorState>(debugLabel: 'buyer/cart');
final _buyerBranchProfile = GlobalKey<NavigatorState>(debugLabel: 'buyer/profile');

final _sellerBranchDashboard = GlobalKey<NavigatorState>(debugLabel: 'seller/dashboard');
final _sellerBranchProducts = GlobalKey<NavigatorState>(debugLabel: 'seller/products');
final _sellerBranchOrders = GlobalKey<NavigatorState>(debugLabel: 'seller/orders');
final _sellerBranchShop = GlobalKey<NavigatorState>(debugLabel: 'seller/shop');

final _deliveryBranchHome = GlobalKey<NavigatorState>(debugLabel: 'delivery/home');
final _deliveryBranchActive = GlobalKey<NavigatorState>(debugLabel: 'delivery/active');
final _deliveryBranchEarnings = GlobalKey<NavigatorState>(debugLabel: 'delivery/earnings');
final _deliveryBranchAccount = GlobalKey<NavigatorState>(debugLabel: 'delivery/account');

final routerRefreshProvider = Provider<RouterRefresh>((ref) {
  final refresh = RouterRefresh();
  ref.listen<AuthState>(authProvider, (prev, next) {
    // Only fire when redirect-relevant state changes (login / logout / init).
    // Profile-data-only updates must not trigger GoRouter page-list rebuilds.
    if (prev?.isAuthenticated != next.isAuthenticated ||
        prev?.isInitialized != next.isInitialized) {
      refresh.notify();
    }
  });
  ref.onDispose(refresh.dispose);
  return refresh;
});

String? _authRedirect(Ref ref, GoRouterState state) {
  final authState = ref.read(authProvider);
  final isAuthenticated = authState.isAuthenticated;
  final isInitialized = authState.isInitialized;
  final location = state.uri.toString();
  final isSplash = location == '/splash';
  final isAuthRoute =
      location.startsWith('/phone') ||
      location.startsWith('/otp') ||
      location.startsWith('/signup') ||
      location.startsWith('/forgot-password') ||
      location.startsWith('/reset-password') ||
      location == '/role-selection';

  if (!isInitialized) {
    return isSplash ? null : '/splash';
  }

  if (isInitialized && isSplash) {
    if (isAuthenticated && authState.user != null) {
      switch (authState.user!.role) {
        case AppConstants.sellerRole:
          return '/seller/dashboard';
        case AppConstants.deliveryRole:
          return '/delivery/home';
        case 'admin':
          return '/admin';
        default:
          return '/buyer/home';
      }
    }
    return '/phone';
  }

  if (!isAuthenticated && !isSplash && !isAuthRoute) {
    return '/phone';
  }

  if (isAuthenticated &&
      (location.startsWith('/forgot-password') ||
          location.startsWith('/reset-password'))) {
    final user = authState.user;
    if (user != null) {
      switch (user.role) {
        case AppConstants.sellerRole:
          return '/seller/dashboard';
        case AppConstants.deliveryRole:
          return '/delivery/home';
        case 'admin':
          return '/admin';
        default:
          return '/buyer/home';
      }
    }
  }

  if (isAuthenticated && isAuthRoute) {
    final user = authState.user;
    if (user != null) {
      switch (user.role) {
        case AppConstants.buyerRole:
          return '/buyer/home';
        case AppConstants.sellerRole:
          return '/seller/dashboard';
        case AppConstants.deliveryRole:
          return '/delivery/home';
        case 'admin':
          return '/admin';
        default:
          return '/buyer/home';
      }
    }
  }

  return null;
}

final goRouterProvider = Provider<GoRouter>((ref) {
  ref.watch(routerRefreshProvider);
  return GoRouter(
    refreshListenable: ref.read(routerRefreshProvider),
    initialLocation: '/splash',
    redirect: (context, state) => _authRedirect(ref, state),
    routes: [
      // ── Auth / utility routes ──────────────────────────────────────────
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/phone',
        builder: (context, state) => const PhoneLoginScreen(),
      ),
      GoRoute(
        path: '/otp',
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return OtpVerificationScreen(
            phoneNumber:
                args['phone'] ?? state.uri.queryParameters['phone'] ?? '',
            role: args['role'] as String?,
            fullName: args['name'] as String?,
            password: args['password'] as String?,
            gender: args['gender'] as String?,
            dateOfBirth: args['date_of_birth'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return SignupScreen(role: args['role'] ?? AppConstants.buyerRole);
        },
      ),
      GoRoute(
        path: '/role-selection',
        builder: (context, state) => const RoleSelectionScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        redirect: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final phone = extra['phone']?.toString().trim() ?? '';
          if (phone.isEmpty) return '/forgot-password';
          return null;
        },
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ResetPasswordScreen(
              initialPhone: extra['phone']?.toString() ?? '');
        },
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/refund-requests',
        builder: (context, state) => const RefundRequestsScreen(),
      ),
      GoRoute(
        path: '/cancellation-requests',
        builder: (context, state) => const CancellationRequestsScreen(),
      ),

      // ── Role root redirects ────────────────────────────────────────────
      GoRoute(
        path: '/buyer',
        redirect: (context, state) => '/buyer/home',
      ),
      GoRoute(
        path: '/seller',
        redirect: (context, state) => '/seller/dashboard',
      ),
      GoRoute(
        path: '/delivery',
        redirect: (context, state) => '/delivery/home',
      ),

      // ── Delivery offers — standalone, renders above the shell ──────────
      GoRoute(
        path: '/delivery/offers',
        builder: (context, state) => const DeliveryOffersScreen(),
      ),

      // ── Buyer shell ────────────────────────────────────────────────────
      // StatefulShellRoute at the top level (not wrapped in a GoRoute).
      // Branch routes use full absolute paths.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            BuyerMainScreen(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _buyerBranchHome,
            routes: [
              GoRoute(
                path: '/buyer/home',
                builder: (context, state) => const BuyerHomeScreen(),
              ),
              GoRoute(
                path: '/buyer/product-details',
                builder: (context, state) {
                  final product = state.extra as Product;
                  return BuyerProductDetailsScreen(product: product);
                },
              ),
              GoRoute(
                path: '/buyer/search',
                builder: (context, state) => const BuyerSearchScreen(),
              ),
              GoRoute(
                path: '/buyer/track-order',
                builder: (context, state) {
                  final orderNumber =
                      state.uri.queryParameters['order'] ??
                      (state.extra
                              as Map<String, dynamic>?)?['order_number']
                          as String?;
                  return OrderTrackingScreen(orderNumber: orderNumber);
                },
              ),
              GoRoute(
                path: '/buyer/orders',
                builder: (context, state) => const BuyerOrdersScreen(),
              ),
              GoRoute(
                path: '/buyer/orders/:id',
                builder: (context, state) {
                  final id =
                      int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
                  return BuyerOrderDetailScreen(orderId: id);
                },
              ),
              GoRoute(
                path: '/buyer/payment-pending',
                builder: (context, state) {
                  final params = state.uri.queryParameters;
                  final extra = state.extra as Map<String, dynamic>? ?? {};
                  return PaymentPendingScreen(
                    orderNumber: params['order'] ??
                        extra['order_number']?.toString() ??
                        '',
                    provider: params['provider'] ??
                        extra['provider']?.toString() ??
                        '',
                    amount: params['amount'] ??
                        extra['amount']?.toString() ??
                        '',
                    isDelivery: (params['delivery'] ??
                            extra['is_delivery']?.toString() ??
                            'true') ==
                        'true',
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _buyerBranchShop,
            routes: [
              GoRoute(
                path: '/buyer/shop',
                builder: (context, state) => const BuyerSearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _buyerBranchWishlist,
            routes: [
              GoRoute(
                path: '/buyer/wishlist',
                builder: (context, state) => const BuyerWishlistScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _buyerBranchCart,
            routes: [
              GoRoute(
                path: '/buyer/cart',
                builder: (context, state) => const CartScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _buyerBranchProfile,
            routes: [
              GoRoute(
                path: '/buyer/profile',
                builder: (context, state) => const BuyerProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // ── Seller shell ───────────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            SellerMainScreen(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _sellerBranchDashboard,
            routes: [
              GoRoute(
                path: '/seller/dashboard',
                builder: (context, state) => const SellerDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _sellerBranchProducts,
            routes: [
              GoRoute(
                path: '/seller/products',
                builder: (context, state) => const SellerProductsScreen(),
                routes: [
                  GoRoute(
                    path: 'add',
                    builder: (context, state) => const AddProductScreen(),
                  ),
                  GoRoute(
                    path: ':productId/edit',
                    builder: (context, state) {
                      final id = int.parse(state.pathParameters['productId']!);
                      return EditProductScreen(productId: id);
                    },
                  ),
                  GoRoute(
                    path: ':productId/reviews',
                    builder: (context, state) {
                      final id = int.parse(state.pathParameters['productId']!);
                      final name =
                          state.uri.queryParameters['name'] ?? 'Product';
                      return SellerProductReviewsScreen(
                          productId: id, productName: name);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _sellerBranchOrders,
            routes: [
              GoRoute(
                path: '/seller/orders',
                builder: (context, state) => const SellerOrdersScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _sellerBranchShop,
            routes: [
              GoRoute(
                path: '/seller/shop',
                builder: (context, state) => const SellerProfileScreen(),
              ),
              GoRoute(
                path: '/seller/payout-methods',
                builder: (context, state) =>
                    const SellerPayoutMethodsScreen(),
              ),
              GoRoute(
                path: '/seller/payout',
                builder: (context, state) => const PayoutScreen(),
              ),
              GoRoute(
                path: '/seller/payout-history',
                builder: (context, state) {
                  final payouts =
                      state.extra as List<Map<String, dynamic>>? ?? [];
                  return SellerPayoutHistoryScreen(payouts: payouts);
                },
              ),
            ],
          ),
        ],
      ),

      // ── Delivery shell ─────────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            DeliveryMainScreen(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _deliveryBranchHome,
            routes: [
              GoRoute(
                path: '/delivery/home',
                builder: (context, state) => const DeliveryHomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _deliveryBranchActive,
            routes: [
              GoRoute(
                path: '/delivery/active',
                builder: (context, state) => const ActiveDeliveryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _deliveryBranchEarnings,
            routes: [
              GoRoute(
                path: '/delivery/earnings',
                builder: (context, state) => const EarningsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _deliveryBranchAccount,
            routes: [
              GoRoute(
                path: '/delivery/account',
                builder: (context, state) => const DeliveryProfileScreen(),
              ),
              GoRoute(
                path: '/delivery/payout-methods',
                builder: (context, state) =>
                    const SellerPayoutMethodsScreen(),
              ),
              GoRoute(
                path: '/delivery/payout',
                builder: (context, state) => const PayoutScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
