import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';
import '../../../widgets/qr_identity_sheet.dart';

class DeliveryProfileScreen extends ConsumerStatefulWidget {
  const DeliveryProfileScreen({super.key});

  @override
  ConsumerState<DeliveryProfileScreen> createState() =>
      _DeliveryProfileScreenState();
}

class _DeliveryProfileScreenState extends ConsumerState<DeliveryProfileScreen> {
  final _licenseController = TextEditingController();
  final _provinceController = TextEditingController();
  final _townController = TextEditingController();
  final _areaController = TextEditingController();

  Map<String, dynamic>? _payload;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String _vehicleType = 'motorcycle';
  String? _licenseFrontPath;
  String? _licenseBackPath;
  String? _livePhotoPath;
  String? _profilePhotoPath;
  bool _resubmitRequested = false;
  bool _isAvailable = true;
  bool _updatingAvailability = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _licenseController.dispose();
    _provinceController.dispose();
    _townController.dispose();
    _areaController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(authServiceProvider).getCurrentUser();
      if (!mounted) return;
      final profile = data?['profile'] as Map<String, dynamic>?;
      if (profile != null) {
        _vehicleType = profile['vehicle_type']?.toString() ?? 'motorcycle';
        _licenseController.text = profile['license_number']?.toString() ?? '';
        _provinceController.text = profile['province']?.toString() ?? '';
        _townController.text = profile['town']?.toString() ?? '';
        _areaController.text = profile['area']?.toString() ?? '';
        _isAvailable = profile['is_available'] == true;
      }
      setState(() {
        _payload = data;
        _loading = false;
        _resubmitRequested = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ref.read(authServiceProvider).extractFriendlyMessage(
          e,
          defaultMessage: 'Could not load your delivery profile. Please try again.',
        );
      });
    }
  }

  Future<String?> _pickImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      preferredCameraDevice: CameraDevice.rear,
    );
    return image?.path;
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

  Future<void> _submitVerification() async {
    final missing = <String>[];
    if (_licenseController.text.trim().isEmpty) missing.add('license number');
    if (_provinceController.text.trim().isEmpty) missing.add('province');
    if (_townController.text.trim().isEmpty) missing.add('town/city');
    if (_areaController.text.trim().isEmpty) missing.add('area');
    if (_licenseFrontPath == null) missing.add('license front image');
    if (_licenseBackPath == null) missing.add('license back image');
    if (_livePhotoPath == null) missing.add('live verification photo');
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Missing: ${missing.join(', ')}')),
      );
      return;
    }

    setState(() => _submitting = true);
    final result = await ref.read(authServiceProvider).submitDeliveryVerification(
          vehicleType: _vehicleType,
          licenseNumber: _licenseController.text.trim(),
          licenseFrontPath: _licenseFrontPath!,
          licenseBackPath: _licenseBackPath!,
          province: _provinceController.text.trim(),
          town: _townController.text.trim(),
          area: _areaController.text.trim(),
          livePhotoPath: _livePhotoPath!,
          profilePhotoPath: _profilePhotoPath,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result['message']?.toString() ?? 'Submitted')),
    );
    if (result['success'] == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Account'),
        actions: [
          IconButton(
            tooltip: 'My QR code',
            onPressed: () => QrIdentitySheet.show(context),
            icon: const Icon(Icons.qr_code_rounded),
          ),
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
                : _buildContent(context),
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

  Widget _buildContent(BuildContext context) {
    final user = _payload?['user'] as Map<String, dynamic>? ?? {};
    final profile = _payload?['profile'] as Map<String, dynamic>?;
    final name = user['full_name']?.toString() ?? '-';
    final phone = user['phone_number']?.toString() ?? '-';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _profileHeader(name: name, phone: phone, profile: profile),
        const SizedBox(height: 24),
        const Text(
          'Delivery profile',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        if (profile == null)
          const Text(
            'No delivery profile returned. Pull to refresh or contact support.',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          )
        else ...[
          _tile('Vehicle', _prettyVehicle(profile['vehicle_type']?.toString()),
              icon: Icons.two_wheeler_outlined),
          _tile('License', profile['license_number']?.toString() ?? '-',
              icon: Icons.badge_outlined),
          _tile('Service area', _serviceArea(profile),
              icon: Icons.location_city_outlined),
          _tile(
            'Verification',
            profile['is_approved'] == true
                ? 'Approved'
                : (profile['verification_status']?.toString() ?? 'Pending'),
            icon: Icons.verified_outlined,
            emphasized: profile['is_approved'] == true,
          ),
          _availabilityTile(),
        ],
        const SizedBox(height: 14),
        _verificationPanel(profile),
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => context.push('/delivery/payout-methods'),
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('Manage payout methods'),
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

  String _serviceArea(Map<String, dynamic> profile) {
    final parts = [
      profile['province']?.toString() ?? '',
      profile['town']?.toString() ?? '',
      profile['area']?.toString() ?? '',
    ].where((v) => v.trim().isNotEmpty).toList();
    return parts.isEmpty ? '-' : parts.join(', ');
  }

  String _fmtDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

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

  Widget _verificationPanel(Map<String, dynamic>? profile) {
    final rawStatus = profile?['is_approved'] == true
        ? 'approved'
        : (profile?['verification_status']?.toString() ?? 'not_started');
    final reason = profile?['verification_rejection_reason']?.toString() ?? '';
    final submittedAt = profile?['submitted_at'] != null
        ? DateTime.tryParse(profile!['submitted_at'].toString())
        : null;
    final reviewedAt = profile?['reviewed_at'] != null
        ? DateTime.tryParse(profile!['reviewed_at'].toString())
        : null;
    final isApproved = rawStatus == 'approved';

    return Container(
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
              const Icon(Icons.assignment_ind_outlined, color: AppTheme.darkCyan),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Rider verification',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              _coloredStatusChip(rawStatus),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'License, vehicle type, service area, and a live selfie.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppTheme.textSecondary.withValues(alpha: 0.95),
            ),
          ),
          if (submittedAt != null || reviewedAt != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (submittedAt != null)
                  Expanded(
                    child: Text(
                      'Submitted: ${_fmtDate(submittedAt)}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ),
                if (reviewedAt != null)
                  Expanded(
                    child: Text(
                      'Reviewed: ${_fmtDate(reviewedAt)}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary),
                      textAlign: TextAlign.end,
                    ),
                  ),
              ],
            ),
          ],
          if (isApproved) ...[
            const SizedBox(height: 10),
            _statusBox(
              'Verification approved. You can now accept delivery offers.',
              AppTheme.success,
              Icons.check_circle_outline_rounded,
            ),
            const SizedBox(height: 8),
            if (_resubmitRequested) ...[
              _statusBox(
                'Submitting new details will reset your status to pending review until staff approve again.',
                AppTheme.warning,
                Icons.info_outline_rounded,
              ),
              const SizedBox(height: 10),
              ..._verificationFormFields(),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _submitting ? null : _submitVerification,
                child: Text(_submitting ? 'Submitting...' : 'Submit update'),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => setState(() => _resubmitRequested = false),
                child: const Text('Cancel'),
              ),
            ] else
              TextButton.icon(
                onPressed: () => setState(() => _resubmitRequested = true),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Request profile update'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                ),
              ),
          ] else if (rawStatus == 'submitted') ...[
            const SizedBox(height: 10),
            _statusBox(
              'Documents submitted. You will be notified once reviewed.',
              AppTheme.warning,
              Icons.hourglass_empty_rounded,
            ),
          ] else ...[
            if (rawStatus == 'rejected' && reason.isNotEmpty) ...[
              const SizedBox(height: 10),
              _statusBox(reason, AppTheme.error, Icons.info_outline_rounded),
            ],
            const SizedBox(height: 12),
            ..._verificationFormFields(),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _submitting ? null : _submitVerification,
              child: Text(_submitting ? 'Submitting...' : 'Submit verification'),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _verificationFormFields() {
    return [
      DropdownButtonFormField<String>(
        initialValue: _vehicleType,
        items: const [
          DropdownMenuItem(value: 'bicycle', child: Text('Bicycle')),
          DropdownMenuItem(value: 'motorcycle', child: Text('Motorcycle')),
          DropdownMenuItem(value: 'car', child: Text('Car')),
          DropdownMenuItem(value: 'van', child: Text('Van')),
        ],
        onChanged: (v) => setState(() => _vehicleType = v ?? 'motorcycle'),
        decoration: const InputDecoration(labelText: 'Vehicle type'),
      ),
      const SizedBox(height: 10),
      _textField(_licenseController, 'Driver license number'),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.photo_camera_outlined, size: 18, color: Colors.amber.shade800),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Place your license on a flat surface in good light and take a clear photo. All text must be readable — blurry or dark photos will be rejected.',
                style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _fileButton(
              label: _fileLabel(_licenseFrontPath, 'License front'),
              onPressed: () async {
                final path = await _pickImage();
                if (path != null) setState(() => _licenseFrontPath = path);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _fileButton(
              label: _fileLabel(_licenseBackPath, 'License back'),
              onPressed: () async {
                final path = await _pickImage();
                if (path != null) setState(() => _licenseBackPath = path);
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      _textField(_provinceController, 'Province'),
      const SizedBox(height: 10),
      _textField(_townController, 'Town / city'),
      const SizedBox(height: 10),
      _textField(_areaController, 'Area / compound'),
      const SizedBox(height: 10),
      _fileButton(
        label: _fileLabel(_livePhotoPath, 'Live verification photo'),
        onPressed: () async {
          final path = await _captureLivePhoto();
          if (path != null) setState(() => _livePhotoPath = path);
        },
      ),
      const SizedBox(height: 10),
      _fileButton(
        label: _fileLabel(_profilePhotoPath, 'Profile photo (optional)'),
        onPressed: () async {
          final path = await _pickImage();
          if (path != null) setState(() => _profilePhotoPath = path);
        },
      ),
    ];
  }

  Widget _availabilityTile() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.bolt_outlined, size: 18, color: AppTheme.primaryCyan),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Available for jobs',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ),
            if (_updatingAvailability)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primaryCyan,
                ),
              )
            else
              Switch.adaptive(
                value: _isAvailable,
                activeThumbColor: AppTheme.primaryCyan,
                onChanged: _updateAvailability,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateAvailability(bool value) async {
    setState(() {
      _isAvailable = value;
      _updatingAvailability = true;
    });
    try {
      await ApiService().put(
        AppConstants.profileEndpoint,
        data: {'is_available': value},
      );
    } catch (_) {
      if (mounted) {
        setState(() => _isAvailable = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update availability. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingAvailability = false);
    }
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

  String _prettyVehicle(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    return raw[0].toUpperCase() + raw.substring(1);
  }

  Widget _profileHeader({
    required String name,
    required String phone,
    required Map<String, dynamic>? profile,
  }) {
    final approved = profile?['is_approved'] == true;
    final available = profile?['is_available'] == true;

    return Container(
      padding: const EdgeInsets.all(14),
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
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phone,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFD1D5DB),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _headerChip(
                label: approved ? 'Verified' : 'Pending',
                color: approved ? AppTheme.success : AppTheme.warning,
              ),
              const SizedBox(width: 8),
              _headerChip(
                label: available ? 'Available' : 'Offline',
                color:
                    available ? AppTheme.primaryCyan : AppTheme.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _tile(
    String label,
    String value, {
    required IconData icon,
    bool emphasized = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppTheme.primaryCyan),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: emphasized ? AppTheme.darkCyan : AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
