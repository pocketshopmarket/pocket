import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/delivery_provider.dart';

/// Shop summary + account actions for sellers (parity with buyer/delivery).
class SellerProfileScreen extends ConsumerStatefulWidget {
  const SellerProfileScreen({super.key});

  @override
  ConsumerState<SellerProfileScreen> createState() =>
      _SellerProfileScreenState();
}

class _SellerProfileScreenState extends ConsumerState<SellerProfileScreen> {
  final _shopNameController = TextEditingController();
  final _shopLocationController = TextEditingController();
  final _nrcController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _businessRegController = TextEditingController();

  Map<String, dynamic>? _payload;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _nrcFrontPath;
  String? _nrcBackPath;
  String? _businessLicensePath;
  String? _livePhotoPath;

  Timer? _shopLocationDebounce;
  List<Map<String, dynamic>> _shopLocationSuggestions = [];
  bool _shopLocationSearching = false;

  @override
  void dispose() {
    _shopNameController.dispose();
    _shopLocationController.dispose();
    _nrcController.dispose();
    _businessNameController.dispose();
    _businessRegController.dispose();
    _shopLocationDebounce?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(authProvider.notifier).refreshUser();
      if (!mounted) return;
      setState(() {
        _payload = data;
        _loading = false;
        _error = data == null ? 'Could not load profile' : null;
      });
      final profile = data?['profile'] as Map<String, dynamic>?;
      if (profile != null) {
        _shopNameController.text = profile['shop_name']?.toString() ?? '';
        _shopLocationController.text =
            profile['shop_location']?.toString() ?? '';
        _nrcController.text = profile['nrc_number']?.toString() ?? '';
        _businessNameController.text =
            profile['business_name']?.toString() ?? '';
        _businessRegController.text =
            profile['business_registration_number']?.toString() ?? '';
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ref.read(authServiceProvider).extractFriendlyMessage(
          e,
          defaultMessage: 'Could not load your seller profile. Please try again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Shop & account'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.textPrimary,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryCyan),
              )
            : _error != null
            ? _errorBody()
            : _content(context),
      ),
    );
  }

  Widget _errorBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null) return null;
    final file = result.files.single;
    if (file.path != null) return file.path;
    if (file.bytes != null) {
      final tmp = await File(
        '${Directory.systemTemp.path}/${file.name}',
      ).writeAsBytes(file.bytes!);
      return tmp.path;
    }
    return null;
  }

  Future<String?> _captureLivePhoto() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.front,
    );
    return image?.path;
  }

  String _fileLabel(String? path, String fallback) {
    if (path == null || path.isEmpty) return fallback;
    return path.split(RegExp(r'[\\/]')).last;
  }

  Future<void> _submitVerification(String tier) async {
    final missing = <String>[];
    if (_shopNameController.text.trim().isEmpty) missing.add('shop name');
    if (_shopLocationController.text.trim().isEmpty) {
      missing.add('shop location');
    }
    if (_nrcController.text.trim().isEmpty) missing.add('NRC number');
    if (_nrcFrontPath == null) missing.add('NRC front image');
    if (_nrcBackPath == null) missing.add('NRC back image');
    if (_livePhotoPath == null) missing.add('live verification photo');
    if (tier == 'tier2' && _businessLicensePath == null) {
      missing.add('business license');
    }
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Missing: ${missing.join(', ')}')),
      );
      return;
    }

    setState(() => _submitting = true);
    final result = await ref.read(authServiceProvider).submitSellerVerification(
          tier: tier,
          shopName: _shopNameController.text.trim(),
          shopLocation: _shopLocationController.text.trim(),
          nrcNumber: _nrcController.text.trim(),
          nrcFrontPath: _nrcFrontPath!,
          nrcBackPath: _nrcBackPath!,
          livePhotoPath: _livePhotoPath!,
          businessLicensePath: _businessLicensePath,
          businessName: _businessNameController.text,
          businessRegistrationNumber: _businessRegController.text,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result['message']?.toString() ?? 'Submitted')),
    );
    if (result['success'] == true) await _load();
  }

  Widget _content(BuildContext context) {
    final user = _payload?['user'] as Map<String, dynamic>? ?? {};
    final profile = _payload?['profile'] as Map<String, dynamic>?;

    final name = user['full_name']?.toString() ?? '-';
    final phone = user['phone_number']?.toString() ?? '-';
    final shopName = profile?['shop_name']?.toString() ?? '-';
    final shopLoc = profile?['shop_location']?.toString() ?? '-';
    final approved = profile?['is_approved'] == true;
    final tier1 = profile?['tier1_status']?.toString() ?? 'not_started';
    final tier2 = profile?['tier2_status']?.toString() ?? 'not_started';
    final submittedAt = profile?['submitted_at'] != null
        ? DateTime.tryParse(profile!['submitted_at'].toString())
        : null;
    final reviewedAt = profile?['reviewed_at'] != null
        ? DateTime.tryParse(profile!['reviewed_at'].toString())
        : null;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shopName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    approved
                        ? Icons.verified_outlined
                        : Icons.schedule_outlined,
                    size: 18,
                    color: approved ? AppTheme.success : AppTheme.warning,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    approved ? 'Shop verified' : 'Verification pending',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: approved ? AppTheme.success : AppTheme.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _pillInfo(label: 'Owner', value: name),
                  const SizedBox(width: 8),
                  _pillInfo(label: 'Phone', value: phone),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _verificationPanel(
          tier1Status: tier1,
          tier2Status: tier2,
          approved: approved,
          reason: profile?['verification_rejection_reason']?.toString() ?? '',
          submittedAt: submittedAt,
          reviewedAt: reviewedAt,
        ),
        const SizedBox(height: 20),
        const Text(
          'Owner',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                phone,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Shop location',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            shopLoc,
            style: const TextStyle(
              fontSize: 15,
              height: 1.4,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        if (profile == null) ...[
          const SizedBox(height: 16),
          const Text(
            'No shop profile in response. Open this tab again after admin setup.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ],
        if (!approved) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.warning.withValues(alpha: 0.35),
              ),
            ),
            child: const Text(
              'Until your shop is approved, you can list products and view orders, '
              'but you cannot advance order status in the app.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => context.push('/seller/payout'),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Claim earnings'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.success,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => context.push('/seller/payout-methods'),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Manage payment methods'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/change-password'),
            icon: const Icon(Icons.lock_outline_rounded),
            label: const Text('Change password'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/phone');
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Log out'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _pillInfo({required String label, required String value}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFFD1D5DB)),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _verificationPanel({
    required String tier1Status,
    required String tier2Status,
    required bool approved,
    required String reason,
    DateTime? submittedAt,
    DateTime? reviewedAt,
  }) {
    final tier1Approved = approved || tier1Status == 'approved';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Tier 1 ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_user_outlined, color: AppTheme.darkCyan),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Seller verification — Tier 1',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  _coloredStatusChip(tier1Approved ? 'approved' : tier1Status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'NRC number, NRC images, shop details, and a live selfie.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppTheme.textSecondary.withValues(alpha: 0.95),
                ),
              ),
              if (submittedAt != null || reviewedAt != null) ...[
                const SizedBox(height: 8),
                _datesRow(submittedAt, reviewedAt),
              ],
              if (tier1Approved) ...[
                const SizedBox(height: 10),
                _statusBox(
                  'Tier 1 approved. You can accept orders and call buyers.',
                  AppTheme.success,
                  Icons.check_circle_outline_rounded,
                ),
              ] else if (tier1Status == 'submitted') ...[
                const SizedBox(height: 10),
                _statusBox(
                  'Documents submitted. You will be notified once reviewed.',
                  AppTheme.warning,
                  Icons.hourglass_empty_rounded,
                ),
              ] else ...[
                if (tier1Status == 'rejected' && reason.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _statusBox(reason, AppTheme.error, Icons.info_outline_rounded),
                ],
                const SizedBox(height: 12),
                _textField(_shopNameController, 'Shop name'),
                const SizedBox(height: 10),
                _shopLocationField(),
                const SizedBox(height: 10),
                _textField(_nrcController, 'NRC number'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _fileButton(
                        label: _fileLabel(_nrcFrontPath, 'NRC front'),
                        onPressed: () async {
                          final path = await _pickImage();
                          if (path != null) setState(() => _nrcFrontPath = path);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _fileButton(
                        label: _fileLabel(_nrcBackPath, 'NRC back'),
                        onPressed: () async {
                          final path = await _pickImage();
                          if (path != null) setState(() => _nrcBackPath = path);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _fileButton(
                  label: _fileLabel(_livePhotoPath, 'Live verification photo'),
                  onPressed: () async {
                    final path = await _captureLivePhoto();
                    if (path != null) setState(() => _livePhotoPath = path);
                  },
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _submitting ? null : () => _submitVerification('tier1'),
                  child: Text(_submitting ? 'Submitting...' : 'Submit Tier 1'),
                ),
              ],
            ],
          ),
        ),

        // ── Tier 2 (only unlocked after Tier 1 approved) ────────────
        if (tier1Approved) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.business_outlined, color: AppTheme.darkCyan),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Business verification — Tier 2',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    _coloredStatusChip(tier2Status),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Optional. Add your business license for a Tier 2 badge and higher buyer trust.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppTheme.textSecondary.withValues(alpha: 0.95),
                  ),
                ),
                if (tier2Status == 'approved') ...[
                  const SizedBox(height: 10),
                  _statusBox(
                    'Business verified. Tier 2 badge active.',
                    AppTheme.success,
                    Icons.check_circle_outline_rounded,
                  ),
                ] else if (tier2Status == 'submitted') ...[
                  const SizedBox(height: 10),
                  _statusBox(
                    'Business documents under review.',
                    AppTheme.warning,
                    Icons.hourglass_empty_rounded,
                  ),
                ] else ...[
                  if (tier2Status == 'rejected' && reason.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _statusBox(reason, AppTheme.error, Icons.info_outline_rounded),
                  ],
                  const SizedBox(height: 12),
                  _textField(_businessNameController, 'Business name'),
                  const SizedBox(height: 10),
                  _textField(_businessRegController, 'Business registration number'),
                  const SizedBox(height: 10),
                  _fileButton(
                    label: _fileLabel(_businessLicensePath, 'Business license'),
                    onPressed: () async {
                      final path = await _pickImage();
                      if (path != null) setState(() => _businessLicensePath = path);
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _submitting ? null : () => _submitVerification('tier2'),
                    child: Text(_submitting ? 'Submitting...' : 'Submit Tier 2'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _shopLocationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _shopLocationController,
          decoration: InputDecoration(
            labelText: 'Shop location',
            filled: true,
            fillColor: AppTheme.surfaceWhite,
            suffixIcon: _shopLocationSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryCyan,
                      ),
                    ),
                  )
                : null,
          ),
          onChanged: (value) {
            _shopLocationDebounce?.cancel();
            final query = value.trim();
            if (query.length < 3) {
              setState(() {
                _shopLocationSuggestions = [];
                _shopLocationSearching = false;
              });
              return;
            }
            setState(() => _shopLocationSearching = true);
            _shopLocationDebounce = Timer(
              const Duration(milliseconds: 350),
              () async {
                try {
                  final results = await ref
                      .read(deliveryServiceProvider)
                      .searchAddressSuggestions(query, limit: 5);
                  if (mounted) {
                    setState(() {
                      _shopLocationSuggestions = results;
                      _shopLocationSearching = false;
                    });
                  }
                } catch (_) {
                  if (mounted) {
                    setState(() {
                      _shopLocationSuggestions = [];
                      _shopLocationSearching = false;
                    });
                  }
                }
              },
            );
          },
        ),
        if (_shopLocationSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _shopLocationSuggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final row = _shopLocationSuggestions[i];
                final name = row['display_name']?.toString() ?? '';
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.location_on_outlined,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                  title: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  onTap: () => setState(() {
                    _shopLocationController.text = name;
                    _shopLocationSuggestions = [];
                  }),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _textField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppTheme.surfaceWhite,
      ),
    );
  }

  Widget _fileButton({required String label, required VoidCallback onPressed}) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.upload_file_outlined),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }

  String _fmtDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  Widget _datesRow(DateTime? submittedAt, DateTime? reviewedAt) {
    return Row(
      children: [
        if (submittedAt != null)
          Expanded(
            child: Text(
              'Submitted: ${_fmtDate(submittedAt)}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        if (reviewedAt != null)
          Expanded(
            child: Text(
              'Reviewed: ${_fmtDate(reviewedAt)}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              textAlign: TextAlign.end,
            ),
          ),
      ],
    );
  }

  Widget _statusBox(String message, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coloredStatusChip(String raw) {
    final label = raw.replaceAll('_', ' ');
    final Color fg;
    final Color bg;
    switch (raw) {
      case 'approved':
        fg = AppTheme.success;
        bg = AppTheme.success.withValues(alpha: 0.12);
      case 'submitted':
        fg = AppTheme.warning;
        bg = AppTheme.warning.withValues(alpha: 0.12);
      case 'rejected':
        fg = AppTheme.error;
        bg = AppTheme.error.withValues(alpha: 0.1);
      default:
        fg = AppTheme.textSecondary;
        bg = AppTheme.textSecondary.withValues(alpha: 0.1);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}
