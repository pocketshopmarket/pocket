import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../services/auth_service.dart';
import '../auth_navigation.dart';
import '../widgets/auth_message_banner.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.initialPhone});

  final String initialPhone;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static const _cooldown = 60;

  final _otpControllers = List<TextEditingController>.generate(
    6,
    (_) => TextEditingController(),
  );
  final _focusNodes = List<FocusNode>.generate(6, (_) => FocusNode());
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _resendLoading = false;
  String? _bannerMessage;
  bool _bannerIsError = true;
  int _secondsLeft = _cooldown;
  Timer? _timer;
  bool _pwdVisible = false;
  bool _pwd2Visible = false;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _cooldown);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onOtpChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index].unfocus();
      _focusNodes[index + 1].requestFocus();
    }
  }

  String _otp() => _otpControllers.map((c) => c.text).join();

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _resendLoading) return;
    setState(() {
      _bannerMessage = null;
      _resendLoading = true;
    });
    final result = await AuthService().sendPasswordResetOtp(
      widget.initialPhone,
    );
    if (!mounted) return;
    setState(() => _resendLoading = false);
    if (result['success'] == true) {
      _startCooldown();
      setState(() {
        _bannerMessage = 'A new code was sent if this number is registered.';
        _bannerIsError = false;
      });
    } else {
      setState(() {
        _bannerMessage =
            result['message']?.toString() ?? 'Could not resend code.';
        _bannerIsError = true;
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _bannerMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final code = _otp();
    if (code.length != 6) {
      setState(() {
        _bannerMessage = 'Enter the full 6-digit code.';
        _bannerIsError = true;
      });
      return;
    }
    setState(() => _loading = true);
    final result = await AuthService().confirmPasswordReset(
      phoneNumber: widget.initialPhone,
      otpCode: code,
      newPassword: _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result['success'] == true) {
      setState(() {
        _bannerMessage = result['message']?.toString() ?? 'Password updated.';
        _bannerIsError = false;
      });
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) GoRouter.of(context).go('/phone');
    } else {
      setState(() {
        _bannerMessage =
            result['message']?.toString() ?? 'Could not reset password.';
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
          AuthNavigation.popOrGo(context, '/forgot-password');
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
            onPressed: () =>
                AuthNavigation.popOrGo(context, '/forgot-password'),
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
                    'Reset password',
                    style: TextStyle(
                      fontSize: 28.sp,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'Code sent to ${widget.initialPhone}',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  SizedBox(height: 20.h),
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (index) {
                        return SizedBox(
                          width: 44.w,
                          height: 52.w,
                          child: TextFormField(
                            controller: _otpControllers[index],
                            focusNode: _focusNodes[index],
                            textAlign: TextAlign.center,
                            maxLength: 1,
                            keyboardType: TextInputType.number,
                            onChanged: (v) => _onOtpChanged(index, v),
                            decoration: InputDecoration(
                              counterText: '',
                              filled: true,
                              fillColor: AppTheme.surfaceWhite,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppSizes.radius.r,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: (_secondsLeft > 0 || _resendLoading)
                          ? null
                          : _resend,
                      child: _resendLoading
                          ? SizedBox(
                              width: 18.w,
                              height: 18.w,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _secondsLeft > 0
                                  ? 'Resend code in ${_secondsLeft}s'
                                  : 'Resend code',
                              style: TextStyle(
                                fontSize: 14.sp,
                                color: AppTheme.primaryCyan,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_pwdVisible,
                    validator: Validators.validatePasswordLength,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      hintText: 'At least 6 characters',
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _pwdVisible ? Icons.visibility : Icons.visibility_off,
                          color: AppTheme.textSecondary,
                        ),
                        onPressed: () =>
                            setState(() => _pwdVisible = !_pwdVisible),
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  TextFormField(
                    controller: _confirmController,
                    obscureText: !_pwd2Visible,
                    validator: (v) => Validators.validatePasswordMatch(
                      _passwordController.text,
                      v,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Confirm new password',
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _pwd2Visible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: AppTheme.textSecondary,
                        ),
                        onPressed: () =>
                            setState(() => _pwd2Visible = !_pwd2Visible),
                      ),
                    ),
                  ),
                  SizedBox(height: 28.h),
                  SizedBox(
                    height: 50.h,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
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
                              'Update password',
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
