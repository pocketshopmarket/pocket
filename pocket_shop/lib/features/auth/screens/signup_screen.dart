import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/validators.dart';
import '../../../../services/auth_service.dart';
import '../auth_navigation.dart';
import '../widgets/auth_action_button.dart';
import '../widgets/auth_message_banner.dart';

class SignupScreen extends ConsumerStatefulWidget {
  final String role;

  const SignupScreen({super.key, required this.role});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final PageController _pageController = PageController();
  final GlobalKey<FormState> _step1FormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _step2FormKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String? _gender;
  String? _genderError;
  DateTime? _dateOfBirth;
  int _pageIndex = 0;
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  String? _sendOtpBannerMessage;
  bool _sendOtpBannerIsError = true;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _formatDateIso(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final lastAllowed = DateTime(now.year - 16, now.month, now.day);
    final initial = _dateOfBirth ?? DateTime(lastAllowed.year - 10);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(lastAllowed) ? lastAllowed : initial,
      firstDate: DateTime(1900),
      lastDate: lastAllowed,
      helpText: 'Date of birth',
    );
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
    }
  }

  void _goToStep(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _onNextFromStep1() {
    if (_gender == null || _gender!.isEmpty) {
      setState(() => _genderError = 'Please select your gender');
    } else {
      setState(() => _genderError = null);
    }
    if (!(_step1FormKey.currentState?.validate() ?? false)) return;
    if (_gender == null || _gender!.isEmpty) return;
    _goToStep(1);
  }

  Future<void> _sendOtpAndContinue() async {
    if (!(_step2FormKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _sendOtpBannerMessage = null;
    });

    final authService = AuthService();
    final result = await authService.sendOtp(_phoneController.text);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      final dob = _dateOfBirth;
      GoRouter.of(context).push(
        '/otp',
        extra: {
          'phone': _phoneController.text,
          'role': widget.role,
          'name': _nameController.text.trim(),
          'password': _passwordController.text,
          'gender': _gender,
          if (dob != null) 'date_of_birth': _formatDateIso(dob),
        },
      );
    } else {
      setState(() {
        _sendOtpBannerMessage =
            result['message']?.toString() ?? 'Failed to send OTP';
        _sendOtpBannerIsError = true;
      });
    }
  }

  String? _validateDateOfBirth(DateTime? _) {
    if (_dateOfBirth == null) {
      return 'Please select your date of birth';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDelivery = widget.role == 'delivery';
    final isSeller = widget.role == 'seller';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;
        if (_pageIndex == 1) {
          _goToStep(0);
        } else {
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
            onPressed: () {
              if (_pageIndex == 1) {
                _goToStep(0);
              } else {
                AuthNavigation.popOrGo(context);
              }
            },
          ),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSizes.padding.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create account',
                      style: TextStyle(
                        fontSize: 28.sp,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      'Step ${_pageIndex + 1} of 2 · ${widget.role}',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    SizedBox(height: 16.h),
                    _StepProgressIndicator(pageIndex: _pageIndex),
                  ],
                ),
              ),
              SizedBox(height: 16.h),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _pageIndex = i),
                  children: [
                    _buildStepAboutYou(),
                    _buildStepAccount(
                      isDelivery: isDelivery,
                      isSeller: isSeller,
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

  Widget _buildStepAboutYou() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.padding.w),
      child: Form(
        key: _step1FormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'About you',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: AppSizes.spacingMedium.h),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              validator: (v) => Validators.validateRequired(v, 'Full name'),
              decoration: InputDecoration(
                labelText: 'Full name',
                hintText: 'Enter your full name',
                filled: true,
                fillColor: AppTheme.surfaceWhite,
              ),
            ),
            SizedBox(height: AppSizes.spacingMedium.h),
            Text(
              'Gender',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: 8.h),
            Semantics(
              label: 'Gender, select Male or Female',
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(value: 'male', label: Text('Male')),
                  ButtonSegment<String>(value: 'female', label: Text('Female')),
                ],
                emptySelectionAllowed: true,
                selected: _gender != null ? {_gender!} : <String>{},
                onSelectionChanged: (Set<String> selection) {
                  setState(() {
                    _gender = selection.isEmpty ? null : selection.first;
                    _genderError = null;
                  });
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            if (_genderError != null) ...[
              SizedBox(height: 6.h),
              Text(
                _genderError!,
                style: TextStyle(color: AppTheme.error, fontSize: 12.sp),
              ),
            ],
            SizedBox(height: AppSizes.spacingMedium.h),
            FormField<DateTime>(
              validator: _validateDateOfBirth,
              builder: (state) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () async {
                        await _pickDateOfBirth();
                        state.didChange(_dateOfBirth);
                      },
                      borderRadius: BorderRadius.circular(AppSizes.radius.r),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Date of birth',
                          filled: true,
                          fillColor: AppTheme.surfaceWhite,
                          errorText: state.errorText,
                          suffixIcon: const Icon(Icons.calendar_today_outlined),
                        ),
                        child: Text(
                          _dateOfBirth != null
                              ? _formatDateIso(_dateOfBirth!)
                              : 'Tap to select (must be 16+)',
                          style: TextStyle(
                            fontSize: 16.sp,
                            color: _dateOfBirth != null
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: AppSizes.spacingLarge.h),
            SizedBox(
              height: 46.h,
              child: AuthActionButton(
                label: 'Continue',
                onPressed: _onNextFromStep1,
                isLoading: false,
              ),
            ),
            SizedBox(height: 24.h),
          ],
        ),
      ),
    );
  }

  Widget _buildStepAccount({required bool isDelivery, required bool isSeller}) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.padding.w),
      child: Form(
        key: _step2FormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Account',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            if (_sendOtpBannerMessage != null) ...[
              SizedBox(height: AppSizes.spacingMedium.h),
              AuthMessageBanner(
                message: _sendOtpBannerMessage!,
                isError: _sendOtpBannerIsError,
                onDismiss: () => setState(() => _sendOtpBannerMessage = null),
              ),
            ],
            SizedBox(height: AppSizes.spacingMedium.h),
            TextFormField(
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
            SizedBox(height: AppSizes.spacingMedium.h),
            TextFormField(
              controller: _passwordController,
              obscureText: !_isPasswordVisible,
              validator: Validators.validatePasswordLength,
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'At least 6 characters',
                filled: true,
                fillColor: AppTheme.surfaceWhite,
                suffixIcon: IconButton(
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: () =>
                      setState(() => _isPasswordVisible = !_isPasswordVisible),
                ),
              ),
            ),
            SizedBox(height: AppSizes.spacingMedium.h),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: !_isConfirmPasswordVisible,
              validator: (v) =>
                  Validators.validatePasswordMatch(_passwordController.text, v),
              decoration: InputDecoration(
                labelText: 'Confirm password',
                filled: true,
                fillColor: AppTheme.surfaceWhite,
                suffixIcon: IconButton(
                  icon: Icon(
                    _isConfirmPasswordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: () => setState(
                    () =>
                        _isConfirmPasswordVisible = !_isConfirmPasswordVisible,
                  ),
                ),
              ),
            ),
            if (isDelivery || isSeller) ...[
              SizedBox(height: AppSizes.spacingMedium.h),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: AppTheme.divider),
                  color: Colors.white,
                ),
                child: Text(
                  isDelivery
                      ? 'After signup, delivery verification requires driver license images (front and back).'
                      : 'Complete shop details and verification after signup before you can sell.',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
            SizedBox(height: AppSizes.spacingLarge.h),
            const _TermsAndPrivacyNotice(),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => _goToStep(0),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textPrimary,
                      side: const BorderSide(color: AppTheme.divider),
                      minimumSize: Size.fromHeight(44.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSizes.radius.r),
                      ),
                    ),
                    child: const Text('Back'),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 44.h,
                    child: AuthActionButton(
                      label: 'Send code',
                      onPressed: _sendOtpAndContinue,
                      isLoading: _isLoading,
                      loadingLabel: 'Preparing verification...',
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 32.h),
          ],
        ),
      ),
    );
  }
}

class _StepProgressIndicator extends StatelessWidget {
  const _StepProgressIndicator({required this.pageIndex});

  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _dot(filled: true, label: '1'),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6.w),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4.r),
                    child: LinearProgressIndicator(
                      value: pageIndex >= 1 ? 1.0 : 0.0,
                      minHeight: 4.h,
                      backgroundColor: AppTheme.divider,
                      color: AppTheme.primaryCyan,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _dot(filled: pageIndex >= 1, label: '2'),
      ],
    );
  }

  Widget _dot({required bool filled, required String label}) {
    return Container(
      width: 28.w,
      height: 28.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? AppTheme.primaryCyan : AppTheme.divider,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _TermsAndPrivacyNotice extends StatelessWidget {
  const _TermsAndPrivacyNotice();

  static final Uri _termsUri = Uri.parse('https://mypocketshop.store/terms/');
  static final Uri _privacyUri = Uri.parse('https://mypocketshop.store/privacy/');

  Future<void> _open(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle(
      fontSize: 12.sp,
      color: AppTheme.primaryCyan,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );
    return Text.rich(
      TextSpan(
        text: 'By creating an account you agree to our ',
        style: TextStyle(fontSize: 12.sp, color: AppTheme.textSecondary, height: 1.4),
        children: [
          TextSpan(
            text: 'Terms of Service',
            style: linkStyle,
            recognizer: TapGestureRecognizer()..onTap = () => _open(_termsUri),
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: linkStyle,
            recognizer: TapGestureRecognizer()..onTap = () => _open(_privacyUri),
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
