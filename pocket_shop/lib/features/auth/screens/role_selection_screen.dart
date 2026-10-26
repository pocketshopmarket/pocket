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
      'description': 'Shop from local stores near you',
      'icon': Icons.shopping_cart_outlined,
      'value': AppConstants.buyerRole,
      'accent': AppTheme.primaryCyan,
    },
    {
      'title': 'Seller',
      'description': 'List products and run your shop',
      'icon': Icons.storefront_outlined,
      'value': AppConstants.sellerRole,
      'accent': AppTheme.accentOrange,
    },
    {
      'title': 'Rider',
      'description': 'Deliver orders and earn per drop',
      'icon': Icons.pedal_bike_outlined,
      'value': AppConstants.deliveryRole,
      'accent': AppTheme.textPrimary,
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
                  SizedBox(height: 8.h),

                  // Title
                  Text(
                    "How will you use\nPocket Shop?",
                    style: AppTheme.display(fontSize: 26.sp, height: 1.15),
                  ),

                  SizedBox(height: 8.h),

                  // Subtitle
                  Text(
                    "You can always add another role from your profile later.",
                    style: AppTheme.body(fontSize: 14.sp, color: AppTheme.textSecondary),
                  ),

                  SizedBox(height: 28.h),

                  Column(
                    children: List.generate(_roles.length, (index) {
                      final role = _roles[index];
                      final isSelected = _selectedRole == role['value'];
                      final Color accent = role['accent'] as Color;

                      return Padding(
                        padding: EdgeInsets.only(bottom: index < _roles.length - 1 ? 12.h : 0),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedRole = role['value'];
                            });
                          },
                          child: Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(18.w),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isSelected ? accent : AppTheme.divider,
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(18.r),
                              color: Colors.white,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 52.w,
                                  height: 52.w,
                                  decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(14.r),
                                  ),
                                  child: Icon(role['icon'], size: 24.sp, color: Colors.white),
                                ),
                                SizedBox(width: 14.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        role['title'],
                                        style: AppTheme.display(fontSize: 16.sp, fontWeight: FontWeight.w700),
                                      ),
                                      SizedBox(height: 2.h),
                                      Text(
                                        role['description'],
                                        style: AppTheme.body(fontSize: 12.5.sp, color: AppTheme.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 24.w,
                                  height: 24.w,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected ? accent : Colors.transparent,
                                    border: isSelected ? null : Border.all(color: AppTheme.divider, width: 2),
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),

                  SizedBox(height: 8.h),

                  // Continue Button
                  SizedBox(
                    width: double.infinity,
                    height: 52.h,
                    child: ElevatedButton(
                      onPressed: _handleContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryCyan,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                      ),
                      child: Text(
                        "Continue",
                        style: AppTheme.body(fontSize: 15.sp, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                  SizedBox(height: 40.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
