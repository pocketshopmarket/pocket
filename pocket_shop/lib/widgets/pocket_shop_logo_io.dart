import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// App logo (`assets/images/pocket_shopper_buyers_logo.jpg`). On Windows, after
/// hot restart the asset manifest can break while files under
/// `data/flutter_assets/` remain; load that path so the logo still shows.
class PocketShopLogo extends StatelessWidget {
  const PocketShopLogo({super.key, required this.size});

  final double size;

  static const String assetPath = 'assets/images/pocket_shopper_buyers_logo.jpg';

  static String? _windowsBundledFilePath() {
    if (!Platform.isWindows) return null;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final rel = assetPath.replaceAll('/', Platform.pathSeparator);
      final candidates = [
        '$exeDir${Platform.pathSeparator}data${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}$rel',
        '$exeDir${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}$rel',
      ];
      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final path = _windowsBundledFilePath();
      if (path != null) {
        return Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(),
        );
      }
    }

    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _fallback(),
    );
  }

  Widget _fallback() {
    return Icon(
      Icons.storefront_rounded,
      size: size * 0.55,
      color: AppTheme.primaryCyan,
    );
  }
}
