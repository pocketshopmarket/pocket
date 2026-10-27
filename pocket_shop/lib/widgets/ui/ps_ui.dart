import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Status shown as a solid dot + colored text — no pill fill.
class PsStatusLabel extends StatelessWidget {
  const PsStatusLabel({super.key, required this.label, required this.color, this.fontSize = 12.5});

  final String label;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTheme.body(fontSize: fontSize, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}

/// Small outlined tag (shop type, quality, variant).
class PsTag extends StatelessWidget {
  const PsTag({super.key, required this.label, this.color = AppTheme.darkCyan});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: AppTheme.body(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// Solid rounded square with a white icon.
class PsIconBadge extends StatelessWidget {
  const PsIconBadge({
    super.key,
    required this.icon,
    this.color = AppTheme.primaryCyan,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: size * 0.48),
    );
  }
}

class PsSectionHeader extends StatelessWidget {
  const PsSectionHeader({super.key, required this.title, this.actionLabel, this.onAction, this.trailing});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: AppTheme.display(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        ?trailing,
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Text(
                actionLabel!,
                style: AppTheme.body(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.darkCyan),
              ),
            ),
          ),
      ],
    );
  }
}

/// Dashboard number tile. An [accent] marks it as needing attention with a
/// colored border and number instead of a pastel fill.
class PsStatTile extends StatelessWidget {
  const PsStatTile({super.key, required this.label, required this.value, this.accent, this.onTap});

  final String label;
  final String value;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final a = accent;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: a ?? AppTheme.divider, width: a != null ? 1.4 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: a ?? AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: AppTheme.display(fontSize: 24, color: a ?? AppTheme.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Flat ink hero card used for greetings and status banners.
class PsHeroCard extends StatelessWidget {
  const PsHeroCard({super.key, required this.child, this.padding = const EdgeInsets.all(18)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.textPrimary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

/// Friendly empty / error state with an optional action.
class PsEmptyState extends StatelessWidget {
  const PsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.divider),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 28, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTheme.display(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTheme.body(fontSize: 13.5, color: AppTheme.textSecondary, height: 1.45),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
