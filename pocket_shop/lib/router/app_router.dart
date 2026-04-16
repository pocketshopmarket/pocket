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
import '../features/delivery/screens/active_delivery_screen.dart';
import '../features/delivery/screens/delivery_home_screen.dart';
import '../features/delivery/screens/delivery_main_screen.dart';
import '../features/delivery/screens/delivery_profile_screen.dart';
import '../features/delivery/screens/earnings_screen.dart';
import '../features/seller/screens/add_product_screen.dart';
import '../features/seller/screens/seller_dashboard_screen.dart';
import '../features/seller/screens/seller_main_screen.dart';
import '../features/seller/screens/seller_orders_screen.dart';
import '../features/seller/screens/seller_profile_screen.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart' show AuthState, authProvider;

class RouterRefresh extends ChangeNotifier {}

final routerRefreshProvider = Provider<RouterRefresh>((ref) {
  final refresh = RouterRefresh();
  ref.listen<AuthState>(authProvider, (prev, next) {
    refresh.notifyListeners();
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
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
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
          if (phone.isEmpty) {
            return '/forgot-password';
          }
          return null;
        },
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final phone = extra['phone']?.toString() ?? '';
          return ResetPasswordScreen(initialPhone: phone);
        },
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      // One StatefulShellRoute per role, nested under its own parent path, so
      // buyer / seller / delivery shells are never mounted at the same time.
      // That avoids go_router's GlobalObjectKey(navigatorKey.hashCode) collisions
      // across sibling shells (see _CustomNavigator in go_router builder.dart).
      GoRoute(
        path: '/buyer',
        redirect: (context, state) {
          final p = state.uri.path;
          if (p == '/buyer' || p == '/buyer/') {
            return '/buyer/home';
          }
          return null;
        },
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) {
              return BuyerMainScreen(navigationShell: navigationShell);
            },
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'home',
                    builder: (context, state) => const BuyerHomeScreen(),
                  ),
                  GoRoute(
                    path: 'product-details',
                    builder: (context, state) {
                      final product = state.extra as Product;
                      return BuyerProductDetailsScreen(product: product);
                    },
                  ),
                  GoRoute(
                    path: 'search',
                    builder: (context, state) => const BuyerSearchScreen(),
                  ),
                  GoRoute(
                    path: 'track-order',
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
                    path: 'orders',
                    builder: (context, state) => const BuyerOrdersScreen(),
                  ),
                  GoRoute(
                    path: 'orders/:id',
                    builder: (context, state) {
                      final id =
                          int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
                      return BuyerOrderDetailScreen(orderId: id);
                    },
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'shop',
                    builder: (context, state) => const BuyerSearchScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'wishlist',
                    builder: (context, state) => const BuyerWishlistScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'cart',
                    builder: (context, state) => const CartScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'profile',
                    builder: (context, state) => const BuyerProfileScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/seller',
        redirect: (context, state) {
          final p = state.uri.path;
          if (p == '/seller' || p == '/seller/') {
            return '/seller/dashboard';
          }
          return null;
        },
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) {
              return SellerMainScreen(navigationShell: navigationShell);
            },
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'dashboard',
                    builder: (context, state) => const SellerDashboardScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'products',
                    builder: (context, state) => const AddProductScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'orders',
                    builder: (context, state) => const SellerOrdersScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'shop',
                    builder: (context, state) => const SellerProfileScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/delivery',
        redirect: (context, state) {
          final p = state.uri.path;
          if (p == '/delivery' || p == '/delivery/') {
            return '/delivery/home';
          }
          return null;
        },
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) {
              return DeliveryMainScreen(navigationShell: navigationShell);
            },
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'home',
                    builder: (context, state) => const DeliveryHomeScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'active',
                    builder: (context, state) => const ActiveDeliveryScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'earnings',
                    builder: (context, state) => const EarningsScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'account',
                    builder: (context, state) => const DeliveryProfileScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
