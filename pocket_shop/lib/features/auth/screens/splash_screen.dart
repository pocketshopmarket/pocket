import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/auth_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../widgets/pocket_shop_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _animationController.forward();

    // Schedule navigation after animation completes
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _navigateToNextScreen();
      }
    });
  }

  void _navigateToNextScreen() {
    // Get the current auth state
    final authInitState = ref.read(authInitializationProvider);

    authInitState.when(
      data: (_) {
        // Auth initialization completed
        if (mounted) {
          _performNavigation();
        }
      },
      error: (error, stackTrace) {
        // Error during initialization - navigate to login
        if (mounted) {
          GoRouter.of(context).go('/phone');
        }
      },
      loading: () {
        // Still loading - wait a bit more then try again
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _navigateToNextScreen();
          }
        });
      },
    );
  }

  void _performNavigation() {
    final authState = ref.read(authProvider);
    if (authState.isAuthenticated && authState.user != null) {
      switch (authState.user!.role) {
        case AppConstants.sellerRole:
          if (mounted) GoRouter.of(context).go('/seller/dashboard');
          break;
        case AppConstants.deliveryRole:
          if (mounted) GoRouter.of(context).go('/delivery/home');
          break;
        case AppConstants.staffRole:
          if (mounted) GoRouter.of(context).go('/staff/home');
          break;
        case AppConstants.adminRole:
          if (mounted) GoRouter.of(context).go('/admin');
          break;
        default:
          if (mounted) GoRouter.of(context).go('/buyer/home');
      }
    } else {
      if (mounted) {
        GoRouter.of(context).go('/phone');
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Logo
              Container(
                width: 120,
                height: 120,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: AppTheme.divider),
                  color: Colors.white,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: const PocketShopLogo(size: 120),
                ),
              ),

              const SizedBox(height: 24),

              // App Name
              Text(
                AppConstants.appName,
                style: AppTheme.headline1.copyWith(
                  color: AppTheme.primaryCyan,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              // Tagline
              Text(
                'Your local marketplace',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),

              const SizedBox(height: 48),

              // Loading indicator
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppTheme.primaryCyan,
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
