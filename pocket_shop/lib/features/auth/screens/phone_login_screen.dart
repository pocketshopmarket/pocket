import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/validators.dart';
import '../../../../providers/auth_provider.dart';
import '../../../widgets/pocket_shop_logo.dart';
import '../widgets/auth_action_button.dart';
import '../widgets/auth_message_banner.dart';
import '../widgets/phone_number_field.dart';

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

  Widget _fieldLabel(String text) => Padding(
        padding: EdgeInsets.only(bottom: 7.h),
        child: Text(
          text,
          style: AppTheme.body(
            fontSize: 12.5.sp,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
          ),
        ),
      );

  InputDecoration _fieldDecoration({
    String? label,
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
    final insets = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceWhite,
        // Log in stays pinned to the bottom until the keyboard needs the room.
        body: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _brandBand(insets.top),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24.w, 28.h, 24.w, 24.h + insets.bottom),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_bannerMessage != null) ...[
                            AuthMessageBanner(
                              message: _bannerMessage!,
                              isError: _bannerIsError,
                              onDismiss: () => setState(() => _bannerMessage = null),
                            ),
                            SizedBox(height: 4.h),
                          ],
                          Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                PhoneNumberField(
                                  controller: _phoneController,
                                  label: 'Phone number',
                                  validator: Validators.validatePhoneNumber,
                                ),
                                SizedBox(height: 16.h),
                                _fieldLabel('Password'),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: !_isPasswordVisible,
                                  validator: Validators.validatePasswordLength,
                                  style: AppTheme.body(fontSize: 14.5.sp),
                                  decoration: _fieldDecoration(
                                    hint: 'At least 6 characters',
                                    suffixIcon: IconButton(
                                      tooltip: _isPasswordVisible ? 'Hide password' : 'Show password',
                                      icon: Icon(
                                        _isPasswordVisible
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: AppTheme.textSecondary,
                                        size: 22,
                                      ),
                                      onPressed: () =>
                                          setState(() => _isPasswordVisible = !_isPasswordVisible),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => GoRouter.of(context).push('/forgot-password'),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 10.h),
                                    ),
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
                          const Spacer(),
                          SizedBox(height: 20.h),
                          AuthActionButton(
                            label: 'Log in',
                            onPressed: _handleLogin,
                            isLoading: _isLoading,
                            loadingLabel: 'Logging you in...',
                            height: 52.h,
                          ),
                          SizedBox(height: 10.h),
                          Center(
                            child: TextButton(
                              onPressed: () => GoRouter.of(context).push('/role-selection'),
                              child: RichText(
                                text: TextSpan(
                                  style: AppTheme.body(fontSize: 13.5.sp, color: AppTheme.textSecondary),
                                  children: [
                                    const TextSpan(text: 'New here? '),
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
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _brandBand(double topInset) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(color: AppTheme.textPrimary),
      padding: EdgeInsets.fromLTRB(28.w, topInset + 40.h, 28.w, 30.h),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -52.w,
            top: -(topInset + 52.h),
            child: Icon(
              Icons.shopping_bag_outlined,
              size: 150.w,
              color: AppTheme.accentOrange.withValues(alpha: 0.22),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52.w,
                height: 52.w,
                padding: EdgeInsets.all(5.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11.r),
                  child: PocketShopLogo(size: 42.w),
                ),
              ),
              SizedBox(height: 18.h),
              Text(
                'Welcome back',
                style: AppTheme.display(fontSize: 26.sp, color: Colors.white, height: 1.1),
              ),
              SizedBox(height: 6.h),
              Text(
                'A shop in your pocket.',
                style: AppTheme.body(fontSize: 13.5.sp, color: Colors.white.withValues(alpha: 0.65)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
