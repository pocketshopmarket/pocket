import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/auth_service.dart';
import '../auth_navigation.dart';
import '../widgets/auth_message_banner.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _o = false;
  bool _n = false;
  bool _c = false;
  String? _bannerMessage;
  bool _bannerIsError = true;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _bannerMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    final result = await AuthService().changePassword(
      oldPassword: _oldController.text,
      newPassword: _newController.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result['success'] == true) {
      setState(() {
        _bannerMessage = result['message']?.toString() ?? 'Password changed.';
        _bannerIsError = false;
      });
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      // Sign out all sessions (tokens already blacklisted on server).
      await AuthService().logout();
      ref.read(authProvider.notifier).handlePasswordChanged();
      GoRouter.of(context).go('/phone');
    } else {
      setState(() {
        _bannerMessage =
            result['message']?.toString() ?? 'Could not change password.';
        _bannerIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Change password'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.textPrimary,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => AuthNavigation.tryPop(context),
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
                if (_bannerMessage != null)
                  AuthMessageBanner(
                    message: _bannerMessage!,
                    isError: _bannerIsError,
                    onDismiss: () => setState(() => _bannerMessage = null),
                  ),
                TextFormField(
                  controller: _oldController,
                  obscureText: !_o,
                  validator: (v) =>
                      Validators.validateRequired(v, 'Current password'),
                  decoration: InputDecoration(
                    labelText: 'Current password',
                    filled: true,
                    suffixIcon: IconButton(
                      icon: Icon(_o ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _o = !_o),
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
                TextFormField(
                  controller: _newController,
                  obscureText: !_n,
                  validator: Validators.validatePasswordLength,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    hintText: 'At least 6 characters',
                    filled: true,
                    suffixIcon: IconButton(
                      icon: Icon(_n ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _n = !_n),
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
                TextFormField(
                  controller: _confirmController,
                  obscureText: !_c,
                  validator: (v) =>
                      Validators.validatePasswordMatch(_newController.text, v),
                  decoration: InputDecoration(
                    labelText: 'Confirm new password',
                    filled: true,
                    suffixIcon: IconButton(
                      icon: Icon(_c ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _c = !_c),
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
                        borderRadius: BorderRadius.circular(AppSizes.radius.r),
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
                        : Text('Save', style: TextStyle(fontSize: 16.sp)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
