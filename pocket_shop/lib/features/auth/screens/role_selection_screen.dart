import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_constants.dart';
import '../auth_navigation.dart';

class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  String? _selectedRole;

  final List<Map<String, dynamic>> _roles = [
    {
      'title': 'Buyer',
      'description': 'Shop from local stores',
      'icon': Icons.shopping_cart_outlined,
      'value': AppConstants.buyerRole,
    },
    {
      'title': 'Seller',
      'description': 'Sell your products',
      'icon': Icons.store_outlined,
      'value': AppConstants.sellerRole,
    },
    {
      'title': 'Delivery',
      'description': 'Deliver orders',
      'icon': Icons.delivery_dining_outlined,
      'value': AppConstants.deliveryRole,
    },
  ];

  void _handleContinue() {
    if (_selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a role'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    // Go to signup and pass the role forward
    GoRouter.of(context).push('/signup', extra: {'role': _selectedRole});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          AuthNavigation.popOrGo(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.surfaceWhite,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppTheme.textPrimary,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: () => AuthNavigation.popOrGo(context),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(AppSizes.padding.w),
              child: Column(
                children: [
                  SizedBox(height: 16.h),

                  // Title
                  Text(
                    "Choose Your Role",
                    style: TextStyle(
                      fontSize: 28.sp,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),

                  SizedBox(height: AppSizes.spacingSmall.h),

                  // Subtitle
                  Text(
                    "Select how you want to use Pocket Shop",
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppTheme.textSecondary,
                    ),
                  ),

                  SizedBox(height: AppSizes.spacingLarge.h),

                  Container(
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Column(
                      children: List.generate(_roles.length, (index) {
                        final role = _roles[index];
                        final isSelected = _selectedRole == role['value'];

                        return Column(
                          children: [
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedRole = role['value'];
                                });
                              },
                              child: Container(
                                width: double.infinity,
                                height: 80.h,
                                padding: EdgeInsets.symmetric(horizontal: 16.w),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primaryCyan
                                        : AppTheme.divider,
                                    width: isSelected ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.radius.r,
                                  ),
                                  color: isSelected
                                      ? AppTheme.lightCyan.withValues(alpha: 0.08)
                                      : AppTheme.surfaceWhite,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      role['icon'],
                                      size: 24.sp,
                                      color: isSelected
                                          ? AppTheme.primaryCyan
                                          : AppTheme.textSecondary,
                                    ),
                                    SizedBox(width: 16.w),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            role['title'],
                                            style: TextStyle(
                                              fontSize: 16.sp,
                                              fontWeight: FontWeight.w600,
                                              color: isSelected
                                                  ? AppTheme.primaryCyan
                                                  : AppTheme.textPrimary,
                                            ),
                                          ),
                                          SizedBox(height: 2.h),
                                          Text(
                                            role['description'],
                                            style: TextStyle(
                                              fontSize: 12.sp,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle,
                                        color: AppTheme.primaryCyan,
                                        size: 20.sp,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (index < _roles.length - 1)
                              SizedBox(height: AppSizes.roleCardSpacing.h),
                          ],
                        );
                      }),
                    ),
                  ),

                  SizedBox(height: 40.h),

                  // Continue Button
                  SizedBox(
                    width: double.infinity,
                    height: 50.h,
                    child: ElevatedButton(
                      onPressed: _handleContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryCyan,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSizes.radius.r,
                          ),
                        ),
                      ),
                      child: Text(
                        "Continue",
                        style: TextStyle(fontSize: 16.sp),
                      ),
                    ),
                  ),
                  SizedBox(height: 60.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
