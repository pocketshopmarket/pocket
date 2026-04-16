import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Reliable back navigation for GoRouter (especially on desktop/web where
/// [AppBar] may not imply a leading button when [canPop] is false).
class AuthNavigation {
  AuthNavigation._();

  /// Pops the current route if possible; otherwise [context.go] to [fallback].
  static void popOrGo(BuildContext context, [String fallback = '/phone']) {
    if (!context.mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(fallback);
    }
  }

  /// Pop only when the stack allows (e.g. modal sub-routes while logged in).
  static void tryPop(BuildContext context) {
    if (!context.mounted) return;
    if (context.canPop()) {
      context.pop();
    }
  }
}
