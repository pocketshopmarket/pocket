import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../services/auth_service.dart';
import '../../../../providers/auth_provider.dart';
import '../auth_navigation.dart';
import '../widgets/auth_message_banner.dart';

class OtpVerificationScreen extends ConsumerStatefulWidget {
  final String phoneNumber;
  final String? role;
  final String? fullName;
  final String? password;
  final String? gender;
  final String? dateOfBirth;

  /// When null, uses [AuthService.sendOtp] for [phoneNumber].
  final Future<Map<String, dynamic>> Function()? resendOtp;
  final int resendCooldownSeconds;

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    this.role,
    this.fullName,
    this.password,
    this.gender,
    this.dateOfBirth,
    this.resendOtp,
    this.resendCooldownSeconds = 60,
  });

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _resendLoading = false;
  int _secondsLeft = 0;
  Timer? _timer;
  String? _bannerMessage;
  bool _bannerIsError = true;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.resendCooldownSeconds;
    _startCooldownTimer();
  }

  void _startCooldownTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = widget.resendCooldownSeconds);
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
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _onOtpChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index].unfocus();
      _focusNodes[index + 1].requestFocus();
    }
  }

  String _getOtp() {
    return _otpControllers.map((controller) => controller.text).join();
  }

  void _handleVerify() async {
    setState(() => _bannerMessage = null);
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
      });

      final result = await ref
          .read(authProvider.notifier)
          .verifyOtp(
            widget.phoneNumber,
            _getOtp(),
            role: widget.role,
            fullName: widget.fullName,
            password: widget.password,
            gender: widget.gender,
            dateOfBirth: widget.dateOfBirth,
          );

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
                result['message']?.toString() ?? 'Failed to verify OTP';
            _bannerIsError = true;
          });
        }
      }
    }
  }

  Future<void> _handleResend() async {
    if (_secondsLeft > 0 || _resendLoading) return;
    setState(() {
      _bannerMessage = null;
      _resendLoading = true;
    });

    final future =
        widget.resendOtp ?? () => AuthService().sendOtp(widget.phoneNumber);
    final result = await future();

    if (mounted) {
      setState(() {
        _resendLoading = false;
      });

      if (result['success'] == true) {
        _startCooldownTimer();
        setState(() {
          _bannerMessage = result['message']?.toString() ?? 'New code sent.';
          _bannerIsError = false;
        });
      } else {
        setState(() {
          _bannerMessage =
              result['message']?.toString() ?? 'Failed to resend OTP';
          _bannerIsError = true;
        });
      }
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
            child: Padding(
              padding: EdgeInsets.all(AppSizes.padding.w),
              child: Column(
                children: [
                  SizedBox(height: 24.h),
                  Text(
                    'Verify OTP',
                    style: TextStyle(
                      fontSize: 28.sp,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: AppSizes.spacingSmall.h),
                  Text(
                    'Enter the 6-digit code sent to ${widget.phoneNumber}',
                    textAlign: TextAlign.center,
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
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (index) {
                          return SizedBox(
                            width: 45.w,
                            height: 52.w,
                            child: TextFormField(
                              controller: _otpControllers[index],
                              focusNode: _focusNodes[index],
                              textAlign: TextAlign.center,
                              maxLength: 1,
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return '';
                                }
                                if (!RegExp(r'^\d$').hasMatch(value)) {
                                  return '';
                                }
                                return null;
                              },
                              onChanged: (value) => _onOtpChanged(index, value),
                              decoration: InputDecoration(
                                counterText: '',
                                filled: true,
                                fillColor: AppTheme.surfaceWhite,
                                contentPadding: EdgeInsets.zero,
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
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.radius.r,
                                  ),
                                  borderSide: const BorderSide(
                                    color: AppTheme.error,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  SizedBox(height: AppSizes.spacingMedium.h),
                  TextButton(
                    onPressed:
                        (_isLoading || _secondsLeft > 0 || _resendLoading)
                        ? null
                        : _handleResend,
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
                  SizedBox(height: AppSizes.spacingLarge.h),
                  SizedBox(
                    width: double.infinity,
                    height: 50.h,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleVerify,
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
                      child: _isLoading
                          ? SizedBox(
                              width: 20.w,
                              height: 20.w,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text('Verify', style: TextStyle(fontSize: 16.sp)),
                    ),
                  ),
                  SizedBox(height: 80.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
