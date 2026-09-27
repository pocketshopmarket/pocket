import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart' as android;

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

  // If the card window doesn't finish loading a new page for a while (the
  // classic symptom of a stuck 3-D Secure bank verification step), offer the
  // "open in browser" escape hatch instead of leaving the buyer stuck on a
  // spinner with no way out.
  Timer? _stallTimer;
  bool _showBrowserFallback = false;
  static const _stallTimeout = Duration(seconds: 20);

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
          onNavigationRequest: (request) {
            _resetStallTimer();
            return NavigationDecision.navigate;
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _showBrowserFallback = false;
            });
            _resetStallTimer();
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
    _allowThirdPartyCookiesOnAndroid();
    _resetStallTimer();
  }

  @override
  void dispose() {
    _stallTimer?.cancel();
    super.dispose();
  }

  /// Bank verification pages commonly need a cookie set on their own domain
  /// to be sent back on the redirect that follows. Android WebView has
  /// third-party cookies switched off per-instance by default (since
  /// Android 5), which shows up as exactly this symptom: the verification
  /// step loads but never completes. iOS's WKWebView doesn't have this
  /// restriction, so there is nothing to do there.
  Future<void> _allowThirdPartyCookiesOnAndroid() async {
    final platformController = _controller.platform;
    if (platformController is! android.AndroidWebViewController) return;
    final cookieManager = WebViewCookieManager().platform;
    if (cookieManager is android.AndroidWebViewCookieManager) {
      await cookieManager.setAcceptThirdPartyCookies(platformController, true);
    }
  }

  void _resetStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer(_stallTimeout, () {
      if (mounted) setState(() => _showBrowserFallback = true);
    });
  }

  Future<void> _openInBrowser() async {
    _stallTimer?.cancel();
    final uri = Uri.parse(widget.checkoutUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open your browser. Please try again.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finish paying in your browser'),
        content: const Text(
          'Complete your card payment in the browser tab that just opened. Once done, come back here '
          'and tap Continue — we\'ll pick up from there.',
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Continue')),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop(CardCheckoutResult.pending);
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
            if (_showBrowserFallback && _loadError == null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Taking a while?',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Some banks\' verification pages work better in your browser.',
                          style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _openInBrowser,
                            icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                            label: const Text('Open in browser instead'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
