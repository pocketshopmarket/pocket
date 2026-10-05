import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/auth_service.dart';

/// A dismissible nudge for buyers who have no date of birth on file — mainly
/// accounts created before the signup form required one. Without it, a few
/// products (anything age-restricted, like alcohol) stay invisible to them
/// with no explanation, since the app can't tell they're an adult.
///
/// Framed around unlocking products, not as an age checkpoint — buyers can
/// dismiss it and keep browsing normally; restricted items just stay hidden
/// until they answer. Dismissal is remembered locally so it doesn't nag on
/// every app open.
class BirthdayNudgeCard extends ConsumerStatefulWidget {
  const BirthdayNudgeCard({super.key});

  @override
  ConsumerState<BirthdayNudgeCard> createState() => _BirthdayNudgeCardState();
}

class _BirthdayNudgeCardState extends ConsumerState<BirthdayNudgeCard> {
  bool _dismissed = true; // starts hidden until we've checked local storage
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  String _prefsKey(int userId) => 'birthday_nudge_dismissed_$userId';

  Future<void> _loadDismissed() async {
    final user = ref.read(userProvider);
    if (user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getBool(_prefsKey(user.id)) ?? false;
      if (mounted) setState(() => _dismissed = dismissed);
    } catch (_) {
      if (mounted) setState(() => _dismissed = false);
    }
  }

  Future<void> _dismiss() async {
    final user = ref.read(userProvider);
    setState(() => _dismissed = true);
    if (user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey(user.id), true);
    } catch (_) {}
  }

  Future<void> _pickAndSave() async {
    final now = DateTime.now();
    final lastAllowed = DateTime(now.year - 16, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(lastAllowed.year - 10),
      firstDate: DateTime(1900),
      lastDate: lastAllowed,
      helpText: 'Date of birth',
    );
    if (picked == null || !mounted) return;

    setState(() => _saving = true);
    final iso = '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    final result = await AuthService().updateProfile(dateOfBirth: iso);
    if (!mounted) return;
    setState(() => _saving = false);
    // Captured now, before any further awaits, so using it below never
    // touches `context` across an async gap.
    final messenger = ScaffoldMessenger.of(context);

    if (result['success'] == true) {
      await ref.read(authProvider.notifier).refreshUser();
      if (!mounted) return;
      await _dismiss();
      messenger.showSnackBar(
        const SnackBar(content: Text('Thanks! More products may now be visible.'), backgroundColor: AppTheme.success),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Could not save. Please try again.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final show = !_dismissed &&
        user != null &&
        user.role == 'buyer' &&
        (user.dateOfBirth == null || user.dateOfBirth!.isEmpty);
    if (!show) return const SizedBox.shrink();

    return Container(
      // No horizontal margin: the parent ListView already applies its own
      // outer padding, so this sits flush with the search bar beneath it.
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryCyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryCyan.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.cake_outlined, color: AppTheme.darkCyan, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A few products are waiting for you',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Add your date of birth to see everything available near you, '
                  'including age-restricted items like alcohol.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      height: 34,
                      child: FilledButton(
                        onPressed: _saving ? null : _pickAndSave,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Add date of birth'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _saving ? null : _dismiss,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Not now'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _saving ? null : _dismiss,
            icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textSecondary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}
