import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_theme.dart';

/// How the card window ended, as far as the page itself could tell. This is
/// only a hint — the server confirms the payment with Lenco, and the
/// payment-pending screen shows the real outcome — so every result leads to
/// the same next step.
enum CardCheckoutResult { success, pending, closed }

/// Hosts the Lenco card window inside the app. The page is served by our own
/// server (it carries the public key and the order details), so the buyer
/// never leaves Pocket Shop and card details never touch our servers.
class CardCheckoutScreen extends StatefulWidget {
  final String checkoutUrl;
  const CardCheckoutScreen({super.key, required this.checkoutUrl});

  @override
  State<CardCheckoutScreen> createState() => _CardCheckoutScreenState();
}

class _CardCheckoutScreenState extends State<CardCheckoutScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _loadError;
  CardCheckoutResult? _result;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      // The hosted page reports what happened through this channel.
      ..addJavaScriptChannel('PocketPay', onMessageReceived: _onPageMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            // Ignore sub-resource noise; only a failed main page matters.
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _loading = false;
                _loadError = 'Could not open the secure payment window. Check your connection and try again.';
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  void _onPageMessage(JavaScriptMessage message) {
    final result = switch (message.message) {
      'success' => CardCheckoutResult.success,
      'pending' => CardCheckoutResult.pending,
      'closed' => CardCheckoutResult.closed,
      _ => null,
    };
    if (result == null || !mounted) return;
    _result = result;
    // A finished payment moves on by itself; a closed window stays put so the
    // buyer can use the page's "Try again" button.
    if (result != CardCheckoutResult.closed) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _leave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave card payment?'),
        content: const Text(
          "If you've already paid, we'll still confirm it. Otherwise your order stays unpaid "
          'and you can pay again from your orders.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
        ],
      ),
    );
    if (leave == true && mounted) {
      Navigator.of(context).pop(_result ?? CardCheckoutResult.closed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Secure card payment'),
          leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: _leave),
        ),
        body: Stack(
          children: [
            if (_loadError == null)
              WebViewWidget(controller: _controller)
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 48, color: AppTheme.textSecondary),
                      const SizedBox(height: 12),
                      Text(_loadError!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _loadError = null;
                            _loading = true;
                          });
                          _controller.loadRequest(Uri.parse(widget.checkoutUrl));
                        },
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_loading && _loadError == null)
              const Center(child: CircularProgressIndicator(color: AppTheme.primaryCyan)),
          ],
        ),
      ),
    );
  }
}
