import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../services/auth_service.dart';
import '../auth_navigation.dart';
import '../widgets/auth_message_banner.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _bannerMessage;
  bool _bannerIsError = true;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() {
      _bannerMessage = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    final result = await AuthService().sendPasswordResetOtp(
      _phoneController.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result['success'] == true) {
      GoRouter.of(
        context,
      ).push('/reset-password', extra: {'phone': _phoneController.text});
    } else {
      setState(() {
        _bannerMessage =
            result['message']?.toString() ?? 'Could not send reset code.';
        _bannerIsError = true;
      });
    }
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
            padding: EdgeInsets.all(AppSizes.padding.w),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Forgot password',
                    style: TextStyle(
                      fontSize: 28.sp,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'Enter the phone number for your account. If it is registered, we will send a verification code (check the server log in development).',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: 24.h),
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
                    child: TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      validator: Validators.validatePhoneNumber,
                      decoration: InputDecoration(
                        labelText: 'Phone number',
                        hintText: '097xxxxxxx',
                        filled: true,
                        fillColor: AppTheme.surfaceWhite,
                      ),
                    ),
                  ),
                  SizedBox(height: 24.h),
                  SizedBox(
                    height: 50.h,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _sendCode,
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
                      child: _loading
                          ? SizedBox(
                              width: 22.w,
                              height: 22.w,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              'Send code',
                              style: TextStyle(fontSize: 16.sp),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
