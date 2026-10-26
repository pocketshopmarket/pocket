import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/theme/app_theme.dart';
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
              case 'staff':
                GoRouter.of(context).go('/staff/home');
                break;
              case 'admin':
                GoRouter.of(context).go('/admin');
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

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16.r),
        borderSide: const BorderSide(color: AppTheme.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16.r),
        borderSide: const BorderSide(color: AppTheme.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16.r),
        borderSide: const BorderSide(color: AppTheme.primaryCyan, width: 1.5),
      ),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.textPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brand band
              Padding(
                padding: EdgeInsets.fromLTRB(28.w, 36.h, 28.w, 32.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56.w,
                      height: 56.w,
                      padding: EdgeInsets.all(6.w),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16.r),
                        color: Colors.white,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11.r),
                        child: PocketShopLogo(size: 44.w),
                      ),
                    ),
                    SizedBox(height: 18.h),
                    Text(
                      "Welcome back",
                      style: AppTheme.display(fontSize: 26.sp, color: Colors.white, height: 1.1),
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      "A shop in your pocket.",
                      style: AppTheme.body(fontSize: 13.5.sp, color: Colors.white.withValues(alpha: 0.65)),
                    ),
                  ],
                ),
              ),

              // Form surface
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceWhite,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: EdgeInsets.fromLTRB(24.w, 28.h, 24.w, 36.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_bannerMessage != null) ...[
                      AuthMessageBanner(
                        message: _bannerMessage!,
                        isError: _bannerIsError,
                        onDismiss: () => setState(() => _bannerMessage = null),
                      ),
                      SizedBox(height: 16.h),
                    ],

                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            validator: Validators.validatePhoneNumber,
                            style: AppTheme.body(fontSize: 14.5.sp),
                            decoration: _fieldDecoration(
                              label: "Phone number",
                              hint: "097xxxxxxx",
                            ),
                          ),
                          SizedBox(height: 16.h),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_isPasswordVisible,
                            validator: Validators.validatePasswordLength,
                            style: AppTheme.body(fontSize: 14.5.sp),
                            decoration: _fieldDecoration(
                              label: "Password",
                              hint: "At least 6 characters",
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
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
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                GoRouter.of(context).push('/forgot-password');
                              },
                              child: Text(
                                'Forgot password?',
                                style: AppTheme.body(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.darkCyan,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 8.h),

                    SizedBox(
                      height: 52.h,
                      child: AuthActionButton(
                        label: 'Log in',
                        onPressed: _handleLogin,
                        isLoading: _isLoading,
                        loadingLabel: 'Logging you in...',
                      ),
                    ),

                    SizedBox(height: 20.h),

                    Center(
                      child: GestureDetector(
                        onTap: () {
                          GoRouter.of(context).push('/role-selection');
                        },
                        child: RichText(
                          text: TextSpan(
                            style: AppTheme.body(fontSize: 13.5.sp, color: AppTheme.textSecondary),
                            children: [
                              const TextSpan(text: "New here? "),
                              TextSpan(
                                text: 'Create an account',
                                style: AppTheme.body(
                                  fontSize: 13.5.sp,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.darkCyan,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
