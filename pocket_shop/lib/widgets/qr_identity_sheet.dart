import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../services/api_service.dart';

/// Bottom sheet that shows the logged-in user's persistent identity QR code.
/// The QR encodes "pocket:UUID" — riders scan this at pickup (seller) and
/// dropoff (buyer) to confirm identity.
class QrIdentitySheet extends StatefulWidget {
  const QrIdentitySheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QrIdentitySheet(),
    );
  }

  @override
  State<QrIdentitySheet> createState() => _QrIdentitySheetState();
}

class _QrIdentitySheetState extends State<QrIdentitySheet> {
  String? _qrData;
  String? _name;
  String? _role;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ApiService();
      final response = await api.get(AppConstants.myQREndpoint);
      final data = response.data;
      if (mounted) {
        setState(() {
          _qrData = data['qr_data']?.toString();
          _name = data['name']?.toString() ?? '';
          _role = data['role']?.toString() ?? '';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load QR code. Please try again.';
          _loading = false;
        });
      }
    }
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'seller':
        return AppTheme.accentBlue;
      case 'delivery':
        return AppTheme.success;
      case 'buyer':
      default:
        return AppTheme.primaryCyan;
    }
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'seller':
        return 'Seller';
      case 'delivery':
        return 'Rider';
      case 'buyer':
        return 'Buyer';
      default:
        return role ?? '';
    }
  }

  String _roleInstruction(String? role) {
    switch (role) {
      case 'seller':
        return 'Show this to the rider when they arrive to collect your order';
      case 'buyer':
        return 'Show this to your rider at drop-off';
      case 'delivery':
        return 'Scan seller QR at pickup, buyer QR at drop-off';
      default:
        return 'Show this QR to verify your identity';
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleColor = _roleColor(_role);
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: CircularProgressIndicator(color: AppTheme.primaryCyan),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _error = null;
                      });
                      _load();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: roleColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _roleLabel(_role),
                    style: TextStyle(
                      color: roleColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _name ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: roleColor.withValues(alpha: 0.25),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: QrImageView(
                data: _qrData ?? '',
                version: QrVersions.auto,
                size: 220,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppTheme.textPrimary,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _roleInstruction(_role),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'This QR is unique to your account',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
