import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Same asset as before; web uses the bundle only.
class PocketShopLogo extends StatelessWidget {
  const PocketShopLogo({super.key, required this.size});

  final double size;

  static const String assetPath = 'assets/images/pocket_shopper_buyers_logo.jpg';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Icon(
        Icons.storefront_rounded,
        size: size * 0.55,
        color: AppTheme.primaryCyan,
      ),
    );
  }
}
