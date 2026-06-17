import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/validators.dart';
import '../../../../providers/auth_provider.dart';
import '../../../widgets/pocket_shop_logo.dart';
import '../widgets/auth_action_button.dart';
import '../widgets/auth_message_banner.dart';

class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  String? _bannerMessage;
  bool _bannerIsError = true;

  @override
  void initState() {
    super.initState();
    // Show a banner if we were redirected here after a forced sign-out
    // (session expiry or password change). The message is a one-shot flag.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final msg = ref.read(authProvider).signOutMessage;
      if (msg != null) {
        setState(() {
          _bannerMessage = msg;
          _bannerIsError = true;
        });
        ref.read(authProvider.notifier).clearSignOutMessage();
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
        _bannerMessage = null;
      });

      final result = await ref
          .read(authProvider.notifier)
          .login(_phoneController.text, _passwordController.text);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (result['success'] == true) {
          final user = ref.read(authProvider).user;
          if (user != null) {
            switch (user.role) {
              case 'seller':
                GoRouter.of(context).go('/seller/dashboard');
                break;
              case 'delivery':
                GoRouter.of(context).go('/delivery/home');
                break;
              default:
                GoRouter.of(context).go('/buyer/home');
            }
          } else {
            GoRouter.of(context).go('/buyer/home');
          }
        } else {
          setState(() {
            _bannerMessage =
                result['message']?.toString() ?? 'Invalid credentials';
            _bannerIsError = true;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(AppSizes.padding.w),
            child: Column(
              children: [
                SizedBox(height: 60.h),

                Container(
                  width: 120.w,
                  height: 120.w,
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30.r),
                    border: Border.all(color: AppTheme.divider),
                    color: Colors.white,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22.r),
                    child: PocketShopLogo(size: 120.w),
                  ),
                ),

                SizedBox(height: AppSizes.spacingLarge.h),

                // Title
                Text(
                  "Welcome Back",
                  style: TextStyle(
                    fontSize: 28.sp,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),

                SizedBox(height: AppSizes.spacingSmall.h),

                // Subtitle
                Text(
                  "Login with your phone number and password",
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: AppTheme.textSecondary,
                  ),
                ),

                SizedBox(height: AppSizes.spacingLarge.h),

                if (_bannerMessage != null)
                  AuthMessageBanner(
                    message: _bannerMessage!,
                    isError: _bannerIsError,
                    onDismiss: () => setState(() => _bannerMessage = null),
                  ),

                Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          validator: Validators.validatePhoneNumber,
                          decoration: InputDecoration(
                            labelText: "Phone Number",
                            hintText: "097xxxxxxx",
                            filled: true,
                            fillColor: AppTheme.surfaceWhite,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16.w,
                              vertical: 16.h,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppSizes.radius.r,
                              ),
                              borderSide: const BorderSide(
                                color: AppTheme.divider,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppSizes.radius.r,
                              ),
                              borderSide: const BorderSide(
                                color: AppTheme.divider,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppSizes.radius.r,
                              ),
                              borderSide: const BorderSide(
                                color: AppTheme.primaryCyan,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: AppSizes.spacingMedium.h),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_isPasswordVisible,
                          validator: Validators.validatePasswordLength,
                          decoration: InputDecoration(
                            labelText: "Password",
                            hintText: "At least 6 characters",
                            filled: true,
                            fillColor: AppTheme.surfaceWhite,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16.w,
                              vertical: 16.h,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppSizes.radius.r,
                              ),
                              borderSide: const BorderSide(
                                color: AppTheme.divider,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppSizes.radius.r,
                              ),
                              borderSide: const BorderSide(
                                color: AppTheme.divider,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppSizes.radius.r,
                              ),
                              borderSide: const BorderSide(
                                color: AppTheme.primaryCyan,
                              ),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isPasswordVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: AppTheme.textSecondary,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: AppSizes.spacingLarge.h),

                // Continue Button
                SizedBox(
                  height: 46.h,
                  child: AuthActionButton(
                    label: 'Login',
                    onPressed: _handleLogin,
                    isLoading: _isLoading,
                    loadingLabel: 'Logging you in...',
                  ),
                ),

                SizedBox(height: 12.h),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      GoRouter.of(context).push('/forgot-password');
                    },
                    child: Text(
                      'Forgot password?',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: AppTheme.primaryCyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 8.h),

                TextButton(
                  onPressed: () {
                    GoRouter.of(context).push('/role-selection');
                  },
                  child: Text(
                    "Don't have an account? Create one",
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppTheme.primaryCyan,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                SizedBox(height: 60.h),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
