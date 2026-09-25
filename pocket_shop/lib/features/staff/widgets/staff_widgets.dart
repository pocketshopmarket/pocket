import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Shared building blocks for the staff money screens. Payouts, earnings
/// claims and refunds used to each carry their own copy of these, and the
/// copies had drifted apart (different wording, different rules about proof
/// screenshots, different error handling). Keep them in one place.

class StaffInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;

  const StaffInfoRow({super.key, required this.label, required this.value, this.copyable = false});

  @override
  Widget build(BuildContext context) {
    final text = Text(
      value,
      style: TextStyle(
        fontSize: 13,
        fontWeight: copyable ? FontWeight.w600 : FontWeight.normal,
        decoration: copyable ? TextDecoration.underline : null,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
          Expanded(
            child: copyable
                ? GestureDetector(
                    onTap: () => copyToClipboard(context, value),
                    child: Row(
                      children: [
                        Flexible(child: text),
                        const SizedBox(width: 6),
                        Icon(Icons.copy_rounded, size: 14, color: Theme.of(context).colorScheme.primary),
                      ],
                    ),
                  )
                : text,
          ),
        ],
      ),
    );
  }
}

Future<void> copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $text'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class StaffProofThumbnail extends StatelessWidget {
  final String url;
  final String title;
  const StaffProofThumbnail({super.key, required this.url, this.title = 'Payment receipt'});

  void _viewFull(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title)),
          body: Center(
            child: InteractiveViewer(child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _viewFull(context),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: url,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              placeholder: (_, _) => const SizedBox(
                width: 64,
                height: 64,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              errorWidget: (_, _, _) =>
                  const SizedBox(width: 64, height: 64, child: Icon(Icons.broken_image_outlined)),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$title attached — tap to view',
            style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class StaffEmptyCenter extends StatelessWidget {
  final String label;
  const StaffEmptyCenter({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
          const SizedBox(height: 8),
          Text(label),
        ],
      ),
    );
  }
}

class StaffRetryCenter extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const StaffRetryCenter({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class StaffBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  const StaffBadge({super.key, required this.label, required this.background, required this.foreground});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class StaffCallout extends StatelessWidget {
  final String text;
  final MaterialColor color;
  final IconData icon;
  const StaffCallout({super.key, required this.text, this.color = Colors.red, this.icon = Icons.warning_amber_rounded});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color.shade800, fontSize: 12, height: 1.4))),
        ],
      ),
    );
  }
}

/// What a staff member entered when confirming money was sent by hand.
class ManualSendProof {
  final String notes;
  final String proofImagePath;
  const ManualSendProof({required this.notes, required this.proofImagePath});
}

/// Confirm that money was sent by hand. A screenshot is ALWAYS required — the
/// refund screen already insisted on it while the payout and claims screens
/// made it optional, which left manual payouts with no audit trail.
Future<ManualSendProof?> askManualSendProof(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
}) {
  return showDialog<ManualSendProof>(
    context: context,
    builder: (_) => _ManualSendDialog(title: title, message: message, confirmLabel: confirmLabel),
  );
}

class _ManualSendDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmLabel;
  const _ManualSendDialog({required this.title, required this.message, required this.confirmLabel});

  @override
  State<_ManualSendDialog> createState() => _ManualSendDialogState();
}

class _ManualSendDialogState extends State<_ManualSendDialog> {
  // Owned by the dialog, so they're fresh every time and disposed with it
  // (the old code kept the picked image on the card and leaked the controller).
  final TextEditingController _notes = TextEditingController();
  String? _proofPath;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Reference / Notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
                if (picked != null) setState(() => _proofPath = picked.path);
              },
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: Text(_proofPath != null ? 'Screenshot attached ✓' : 'Attach payment screenshot'),
            ),
            if (_proofPath == null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'A screenshot is required before you can confirm.',
                  style: TextStyle(fontSize: 11, color: Colors.red),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _proofPath == null
              ? null
              : () => Navigator.pop(context, ManualSendProof(notes: _notes.text.trim(), proofImagePath: _proofPath!)),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Plain yes/no confirmation. Returns true on confirm.
Future<bool> askStaffConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Colors.red.shade600) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

/// "Fri 2 Oct" for a refund promise, plus whether it has already passed.
({String label, bool overdue}) staffDueLabel(String? iso) {
  if (iso == null || iso.isEmpty) return (label: '', overdue: false);
  final due = DateTime.tryParse(iso)?.toLocal();
  if (due == null) return (label: '', overdue: false);
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return (
    label: '${days[due.weekday - 1]} ${due.day} ${months[due.month - 1]}',
    overdue: due.isBefore(DateTime.now()),
  );
}
