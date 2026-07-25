import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';

/// Shared by the buyer/seller/delivery profile screens so account deletion
/// behaves identically everywhere — two explicit confirmations (irreversible
/// action), then calls the backend and returns to the phone/login screen.
Future<void> showDeleteAccountFlow(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete your account?'),
      content: const Text(
        'This permanently deletes your Pocket Shop account. Your name, '
        'phone number, and photos are removed and cannot be recovered. '
        'Past orders are kept for legal and accounting records, but will '
        'no longer show your personal details.\n\nThis cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: AppTheme.error),
          child: const Text('Delete My Account'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;

  final doubleConfirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Are you absolutely sure?'),
      content: const Text('This is your last chance to cancel.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep My Account'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
          child: const Text('Delete Permanently'),
        ),
      ],
    ),
  );
  if (doubleConfirmed != true) return;
  if (!context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  final success = await ref.read(authProvider.notifier).deleteAccount();

  if (!context.mounted) return;
  Navigator.pop(context); // close the loading spinner

  if (success) {
    context.go('/phone');
  } else {
    final error = ref.read(authProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Could not delete your account. Please try again.'),
        backgroundColor: AppTheme.error,
      ),
    );
  }
}
