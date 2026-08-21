import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';

/// Shown wherever a guest (no account) attempts something account-based —
/// checkout, viewing their profile, writing a review. Product browsing
/// itself must never show this (Apple Guideline 5.1.1): only actions that
/// genuinely require an account should.
///
/// Presentational only — pass [onSignIn] to control what happens next. Use
/// [SignInPrompt.showSheet] to present it as a modal bottom sheet with
/// standard sheet chrome (see [SellerSuggestionsSheet] for the same
/// pattern), or embed [SignInPrompt] directly for an inline empty state
/// (e.g. a whole screen body).
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({
    super.key,
    this.title = 'Sign in required',
    required this.message,
    this.buttonLabel = 'Sign In',
    required this.onSignIn,
    this.showRoleSwitchLink = false,
  });

  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onSignIn;

  /// Shows a secondary "Want to sell or deliver instead?" link to
  /// /role-selection. Only the Profile-tab usage enables this — it's the
  /// natural "I'm here, what do I do" moment; checkout/review already carry
  /// clear buyer intent and don't need it.
  final bool showRoleSwitchLink;

  /// Presents [SignInPrompt] as a modal bottom sheet. Handles closing the
  /// sheet itself before navigating, so callers never manage dismissal.
  static Future<void> showSheet(
    BuildContext context, {
    String title = 'Sign in required',
    required String message,
    String buttonLabel = 'Sign In',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SignInPrompt(
                  title: title,
                  message: message,
                  buttonLabel: buttonLabel,
                  onSignIn: () {
                    Navigator.of(sheetContext).pop();
                    sheetContext.go('/phone');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppTheme.primaryCyan.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.person_outline_rounded,
            color: AppTheme.primaryCyan,
            size: 28,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onSignIn,
            child: Text(buttonLabel),
          ),
        ),
        if (showRoleSwitchLink) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => context.push('/role-selection'),
            child: const Text('Want to sell or deliver instead?'),
          ),
        ],
      ],
    );
  }
}
