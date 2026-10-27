import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/validators.dart';
import '../../../../models/category.dart';
import '../../../../providers/category_provider.dart';
import '../../../../services/auth_service.dart';
import '../auth_navigation.dart';
import '../widgets/auth_action_button.dart';
import '../widgets/auth_message_banner.dart';
import '../widgets/phone_number_field.dart';

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
  DateTime? _dateOfBirth;
  // Only asked once the buyer is computed 18+; defaults to shown (matches the
  // server default) so an unanswered-but-visible toggle doesn't surprise them.
  bool _showAlcoholProducts = true;
  // Buyer-only. Null means "no preference" — skipping the question is fine,
  // the home screen just won't default to a filtered view for them.
  int? _preferredCategoryId;
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

  bool get _isAdult {
    final dob = _dateOfBirth;
    if (dob == null) return false;
    final now = DateTime.now();
    var age = now.year - dob.year;
    final hadBirthdayThisYear =
        now.month > dob.month || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthdayThisYear) age -= 1;
    return age >= 18;
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
    if (!(_step1FormKey.currentState?.validate() ?? false)) return;
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
          if (_isAdult) 'show_alcohol_products': _showAlcoholProducts,
          if (widget.role == 'buyer' && _preferredCategoryId != null)
            'preferred_category': _preferredCategoryId,
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

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
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
                      style: AppTheme.display(fontSize: 24.sp),
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      'Step ${_pageIndex + 1} of 2 · Creating your ${widget.role} account',
                      style: AppTheme.body(fontSize: 13.5.sp, color: AppTheme.textSecondary),
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
              style: AppTheme.display(fontSize: 18.sp, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: AppSizes.spacingMedium.h),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              validator: (v) => Validators.validateRequired(v, 'Full name'),
              style: AppTheme.body(fontSize: 14.5.sp),
              decoration: _fieldDecoration(
                label: 'Full name',
                hint: 'Enter your full name',
              ),
            ),
            SizedBox(height: AppSizes.spacingMedium.h),
            Text(
              'Gender',
              style: AppTheme.body(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppTheme.textSecondary),
            ),
            SizedBox(height: 8.h),
            Semantics(
              label: 'Gender, select Male, Female, or Prefer not to say',
              child: Column(
                children: [
                  _GenderTile(
                    label: 'Male',
                    icon: Icons.male_rounded,
                    selected: _gender == 'male',
                    onTap: () => setState(
                      () => _gender = _gender == 'male' ? null : 'male',
                    ),
                  ),
                  SizedBox(height: 8.h),
                  _GenderTile(
                    label: 'Female',
                    icon: Icons.female_rounded,
                    selected: _gender == 'female',
                    onTap: () => setState(
                      () => _gender = _gender == 'female' ? null : 'female',
                    ),
                  ),
                  SizedBox(height: 8.h),
                  _GenderTile(
                    label: 'Prefer not to say',
                    icon: Icons.visibility_off_outlined,
                    selected: _gender == 'prefer_not_to_say',
                    onTap: () => setState(
                      () => _gender = _gender == 'prefer_not_to_say'
                          ? null
                          : 'prefer_not_to_say',
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Used to personalize your experience — optional.',
              style: TextStyle(
                fontSize: 12.sp,
                color: AppTheme.textSecondary,
              ),
            ),
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
                      borderRadius: BorderRadius.circular(16.r),
                      child: InputDecorator(
                        decoration: _fieldDecoration(
                          label: 'Date of birth',
                          suffixIcon: const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary),
                        ).copyWith(errorText: state.errorText),
                        child: Text(
                          _dateOfBirth != null
                              ? _formatDateIso(_dateOfBirth!)
                              : 'Tap to select (must be 16+)',
                          style: AppTheme.body(
                            fontSize: 14.5.sp,
                            color: _dateOfBirth != null ? AppTheme.textPrimary : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_isAdult) ...[
              SizedBox(height: AppSizes.spacingMedium.h),
              Container(
                padding: EdgeInsets.all(14.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'See alcohol products?',
                      style: AppTheme.display(fontSize: 14.sp, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'You can change this later in your profile.',
                      style: AppTheme.body(fontSize: 12.sp, color: AppTheme.textSecondary),
                    ),
                    SizedBox(height: 8.h),
                    Semantics(
                      label: 'See alcohol products, select Yes or No',
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(value: true, label: Text('Yes')),
                          ButtonSegment<bool>(value: false, label: Text('No')),
                        ],
                        showSelectedIcon: false,
                        selected: {_showAlcoholProducts},
                        onSelectionChanged: (selection) {
                          setState(() => _showAlcoholProducts = selection.first);
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.sp)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (widget.role == 'buyer') ...[
              SizedBox(height: AppSizes.spacingMedium.h),
              Container(
                padding: EdgeInsets.all(14.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What do you love to shop for?',
                      style: AppTheme.display(fontSize: 14.sp, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Optional — we\'ll show you that first. You can change it anytime.',
                      style: AppTheme.body(fontSize: 12.sp, color: AppTheme.textSecondary),
                    ),
                    SizedBox(height: 8.h),
                    Consumer(
                      builder: (context, ref, _) {
                        final categories = ref.watch(topLevelCategoriesProvider);
                        if (categories.isEmpty) return const SizedBox.shrink();
                        return Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: categories.map((Category c) {
                            final selected = _preferredCategoryId == c.id;
                            return ChoiceChip(
                              label: Text(c.name),
                              selected: selected,
                              onSelected: (_) {
                                setState(() {
                                  _preferredCategoryId = selected ? null : c.id;
                                });
                              },
                              labelStyle: AppTheme.body(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w600,
                                color: selected ? Colors.white : AppTheme.textPrimary,
                              ),
                              selectedColor: AppTheme.primaryCyan,
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: AppTheme.divider),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: AppSizes.spacingLarge.h),
            SizedBox(
              height: 52.h,
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
              style: AppTheme.display(fontSize: 18.sp, fontWeight: FontWeight.w700),
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
            PhoneNumberField(
              controller: _phoneController,
              label: 'Phone number',
              validator: Validators.validatePhoneNumber,
            ),
            SizedBox(height: AppSizes.spacingMedium.h),
            TextFormField(
              controller: _passwordController,
              obscureText: !_isPasswordVisible,
              validator: Validators.validatePasswordLength,
              style: AppTheme.body(fontSize: 14.5.sp),
              decoration: _fieldDecoration(
                label: 'Password',
                hint: 'At least 6 characters',
                suffixIcon: IconButton(
                  icon: Icon(
                    _isPasswordVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
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
              style: AppTheme.body(fontSize: 14.5.sp),
              decoration: _fieldDecoration(
                label: 'Confirm password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _isConfirmPasswordVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
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
                padding: EdgeInsets.all(14.w),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16.r),
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
                      minimumSize: Size.fromHeight(52.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                    ),
                    child: const Text('Back'),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 52.h,
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

class _GenderTile extends StatelessWidget {
  const _GenderTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14.r),
      child: Container(
        height: 52.h,
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: selected ? AppTheme.primaryCyan : AppTheme.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32.w,
              height: 32.w,
              decoration: BoxDecoration(
                color: selected ? AppTheme.primaryCyan : AppTheme.surfaceWhite,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 17.sp,
                color: selected ? Colors.white : AppTheme.textSecondary,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                label,
                style: AppTheme.body(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                ),
              ),
            ),
            Container(
              width: 20.w,
              height: 20.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppTheme.primaryCyan : Colors.transparent,
                border: selected ? null : Border.all(color: AppTheme.divider, width: 2),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                  : null,
            ),
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
        _bar(filled: true),
        SizedBox(width: 6.w),
        _bar(filled: pageIndex >= 1),
      ],
    );
  }

  Widget _bar({required bool filled}) {
    return Expanded(
      child: Container(
        height: 4.h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: filled ? AppTheme.primaryCyan : AppTheme.divider,
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
