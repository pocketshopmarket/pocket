import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/delivery_provider.dart';
import '../../../../providers/payment_methods_provider.dart';
import 'add_payment_method_screen.dart';

class BuyerProfileScreen extends ConsumerStatefulWidget {
  const BuyerProfileScreen({super.key});

  @override
  ConsumerState<BuyerProfileScreen> createState() => _BuyerProfileScreenState();
}

class _BuyerProfileScreenState extends ConsumerState<BuyerProfileScreen> {
  bool _isUploadingPhoto = false;
  bool _isSavingProfile = false;

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 800,
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _isUploadingPhoto = true);
    try {
      final authService = ref.read(authServiceProvider);
      final result = await authService.uploadProfilePhoto(picked.path);
      if (!mounted) return;
      if (result['success'] == true) {
        await ref.read(authProvider.notifier).refreshUser();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Could not upload photo')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not upload photo')),
      );
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  void _confirmDelete(dynamic method) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove method?'),
        content: Text(
          'Delete ${method.providerLabel} · ${method.phoneNumber} from your payment methods?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(paymentMethodsProvider.notifier).deleteMethod(method.id);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  static const List<_PaymentProviderOption> _providerOptions = [
    _PaymentProviderOption(
      label: 'MTN',
      logoAsset: 'mtn.png',
      accentColor: Color(0xFFF2D23B),
    ),
    _PaymentProviderOption(
      label: 'Airtel',
      logoAsset: 'airtel.png',
      accentColor: Color(0xFFE51E2A),
    ),
    _PaymentProviderOption(
      label: 'Zamtel',
      logoAsset: 'zamtel.png',
      accentColor: Color(0xFF008543),
    ),
  ];

  _PaymentProviderOption _providerVisual(String provider) {
    final normalized = provider.toLowerCase();
    if (normalized.contains('airtel')) return _providerOptions[1];
    if (normalized.contains('zamtel')) return _providerOptions[2];
    return _providerOptions[0];
  }

  Widget _providerLogo(String provider, {double size = 28}) {
    final visual = _providerVisual(provider);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        visual.logoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          return Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: visual.accentColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              visual.label[0],
              style: TextStyle(
                color: visual.accentColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(paymentMethodsProvider.notifier).load();
    });
  }

  Future<void> _showAddPaymentFlow(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => const AddPaymentMethodScreen(),
      ),
    );
    if (mounted) ref.read(paymentMethodsProvider.notifier).load();
  }

  Future<void> _editField({
    required String title,
    required String current,
    required String hint,
    required Future<Map<String, dynamic>> Function(String value) onSave,
    int maxLines = 1,
    bool showLocationButton = false,
  }) async {
    final controller = TextEditingController(text: current);
    final formKey = GlobalKey<FormState>();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        bool locating = false;
        bool locationDetected = false;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
          Future<void> useCurrentLocation() async {
            setModalState(() {
              locating = true;
              locationDetected = false;
            });
            try {
              final serviceEnabled = await Geolocator.isLocationServiceEnabled();
              if (!serviceEnabled) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Location services are off. Enter your address manually.'),
                  ));
                }
                return;
              }
              var permission = await Geolocator.checkPermission();
              if (permission == LocationPermission.denied) {
                permission = await Geolocator.requestPermission();
              }
              if (permission == LocationPermission.denied ||
                  permission == LocationPermission.deniedForever) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Location permission denied. Enter your address manually.'),
                  ));
                }
                return;
              }
              final pos = await Geolocator.getCurrentPosition();
              String resolved =
                  '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
              try {
                final reverse = await ref
                    .read(deliveryServiceProvider)
                    .reverseGeocode(lat: pos.latitude, lng: pos.longitude);
                final display = reverse?['display_name']?.toString().trim();
                if (display != null && display.isNotEmpty) resolved = display;
              } catch (_) {}
              controller.text = resolved;
              setModalState(() => locationDetected = true);
            } catch (_) {
            } finally {
              setModalState(() => locating = false);
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: controller,
                    maxLines: maxLines,
                    autofocus: !showLocationButton,
                    onChanged: (_) {
                      if (locationDetected) {
                        setModalState(() => locationDetected = false);
                      }
                    },
                    decoration: InputDecoration(hintText: hint),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  if (showLocationButton) ...[
                    const SizedBox(height: 10),
                    if (locating)
                      Row(
                        children: const [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.primaryCyan),
                          ),
                          SizedBox(width: 8),
                          Text('Finding your location…',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.primaryCyan)),
                        ],
                      )
                    else if (locationDetected)
                      Row(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              size: 16, color: AppTheme.success),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text('Location found',
                                style: TextStyle(
                                    fontSize: 13, color: AppTheme.success)),
                          ),
                          TextButton(
                            onPressed: useCurrentLocation,
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            child: const Text('Not accurate? Re-detect',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary)),
                          ),
                        ],
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: useCurrentLocation,
                          icon: const Icon(Icons.my_location_rounded,
                              size: 18, color: AppTheme.primaryCyan),
                          label: const Text('Use current location',
                              style: TextStyle(color: AppTheme.primaryCyan)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.primaryCyan),
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      onPressed: () {
                        if (formKey.currentState!.validate()) {
                          Navigator.of(ctx).pop(true);
                        }
                      },
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryCyan),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        );
      },
    );

    if (confirmed != true || !mounted) return;
    setState(() => _isSavingProfile = true);
    try {
      final result = await onSave(controller.text.trim());
      if (!mounted) return;
      if (result['success'] == true) {
        await ref.read(authProvider.notifier).refreshUser();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Could not save')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final authNotifier = ref.read(authProvider.notifier);
    final cartItems = ref.watch(cartProvider).totalItems;
    final paymentMethods = ref.watch(paymentMethodsProvider);

    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceWhite,
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryCyan),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppTheme.primaryCyan,
                          backgroundImage: user.profilePhoto != null
                              ? CachedNetworkImageProvider(user.profilePhoto!)
                              : null,
                          child: user.profilePhoto == null
                              ? const Icon(Icons.person, color: Colors.white, size: 28)
                              : null,
                        ),
                        if (_isUploadingPhoto)
                          const Positioned.fill(
                            child: CircleAvatar(
                              radius: 32,
                              backgroundColor: Colors.black45,
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        else
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                color: AppTheme.primaryCyan,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          user.phoneNumber,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFD1D5DB),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Account details',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
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
              child: _isSavingProfile
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            color: AppTheme.primaryCyan, strokeWidth: 2),
                      ),
                    )
                  : Column(
                      children: [
                        _EditableTile(
                          icon: Icons.person_outline_rounded,
                          label: 'Name',
                          value: user.displayName,
                          onTap: () => _editField(
                            title: 'Edit name',
                            current: user.displayName,
                            hint: 'Your full name',
                            onSave: (v) => ref
                                .read(authServiceProvider)
                                .updateProfile(fullName: v),
                          ),
                        ),
                        const Divider(height: 1),
                        _EditableTile(
                          icon: Icons.location_on_outlined,
                          label: 'Default delivery address',
                          value: user.buyerProfile?.defaultAddress?.isNotEmpty == true
                              ? user.buyerProfile!.defaultAddress!
                              : 'Not set',
                          onTap: () => _editField(
                            title: 'Default delivery address',
                            current: user.buyerProfile?.defaultAddress ?? '',
                            hint: 'e.g. Plot 12, Cairo Road, Lusaka',
                            maxLines: 2,
                            showLocationButton: true,
                            onSave: (v) => ref
                                .read(authServiceProvider)
                                .updateProfile(defaultAddress: v),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Payments',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
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
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Payment Methods',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _showAddPaymentFlow(context),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (paymentMethods.isEmpty)
                    const Text(
                      'No payment methods added yet.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    )
                  else
                    ...paymentMethods.map((method) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            _providerLogo(method.providerLabel),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    method.providerLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        method.phoneNumber,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        method.isVerified ? Icons.verified : Icons.error_outline,
                                        size: 14,
                                        color: method.isVerified ? AppTheme.success : AppTheme.warning,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(paymentMethodsProvider.notifier)
                                      .setDefault(method.id);
                                } catch (e) {
                                  if (!context.mounted) return;
                                  final err = ref
                                      .read(paymentMethodsProvider.notifier)
                                      .extractError(e);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        err ?? 'Could not set default',
                                      ),
                                    ),
                                  );
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 34),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                              child: Text(method.isDefault ? 'Default' : 'Set'),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: () => _confirmDelete(method),
                              icon: const Icon(Icons.delete_outline, color: AppTheme.error, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Orders & activity',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
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
                  const Text(
                    'My orders',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ActionTile(
                    icon: Icons.receipt_long_outlined,
                    title: 'My Orders',
                    onTap: () => context.push('/buyer/orders'),
                  ),
                  const SizedBox(height: 8),
                  _ActionTile(
                    icon: Icons.assignment_return_outlined,
                    title: 'Refund requests',
                    onTap: () => context.push('/refund-requests'),
                  ),
                  const SizedBox(height: 8),
                  _ActionTile(
                    icon: Icons.cancel_outlined,
                    title: 'Cancellation requests',
                    onTap: () => context.push('/cancellation-requests'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
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
                children: [
                  _ActionTile(
                    icon: Icons.shopping_basket_outlined,
                    title: 'My Cart ($cartItems items)',
                    onTap: () => context.go('/buyer/cart'),
                  ),
                  const SizedBox(height: 8),
                  _ActionTile(
                    icon: Icons.local_shipping_outlined,
                    title: 'Track Order',
                    onTap: () => context.push('/buyer/orders'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
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
              child: _ActionTile(
                icon: Icons.lock_outline_rounded,
                title: 'Change password',
                onTap: () => context.push('/change-password'),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await authNotifier.logout();
                  if (context.mounted) {
                    context.go('/phone');
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.textPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _EditableTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _EditableTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined, size: 16, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _PaymentProviderOption {
  final String label;
  final String logoAsset;
  final Color accentColor;

  const _PaymentProviderOption({
    required this.label,
    required this.logoAsset,
    required this.accentColor,
  });
}
