import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/delivery_provider.dart';

class DeliveryOffersScreen extends ConsumerStatefulWidget {
  const DeliveryOffersScreen({super.key});

  @override
  ConsumerState<DeliveryOffersScreen> createState() =>
      _DeliveryOffersScreenState();
}

class _DeliveryOffersScreenState extends ConsumerState<DeliveryOffersScreen> {
  List<Map<String, dynamic>> _offers = [];
  bool _loading = true;
  String? _error;
  bool _accepting = false;
  double _lat = 0;
  double _lng = 0;

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
      final offers = await ref.read(deliveryServiceProvider).fetchOffers();
      if (mounted) {
        setState(() {
          _offers = offers;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is DioException
          ? ref.read(deliveryServiceProvider).extractErrorMessage(e)
          : e.toString();
      setState(() {
        _loading = false;
        _error = msg ?? 'Could not load offers';
      });
    }
  }

  Future<void> _acceptOffer(Map<String, dynamic> offer) async {
    final orderIdRaw = offer['order'];
    if (orderIdRaw == null) return;
    final orderId = (orderIdRaw as num).toInt();
    final offerIdRaw = offer['id'];
    final offerId = offerIdRaw is num ? offerIdRaw.toInt() : null;

    setState(() => _accepting = true);

    // Ensure we have location
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.denied &&
          perm != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition();
        _lat = pos.latitude;
        _lng = pos.longitude;
      }
    } catch (_) {}

    if (_lat == 0 && _lng == 0) {
      if (mounted) {
        setState(() => _accepting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enable location to accept a delivery')),
        );
      }
      return;
    }

    try {
      final svc = ref.read(deliveryServiceProvider);
      await svc.acceptOrder(
        orderId: orderId,
        lat: _lat,
        lng: _lng,
        offerId: offerId,
      );
      if (mounted) {
        setState(() => _accepting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery accepted')),
        );
        context.go('/delivery/active');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _accepting = false);
      final msg = e is DioException
          ? ref.read(deliveryServiceProvider).extractErrorMessage(e)
          : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg ?? 'Accept failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Delivery offers'),
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
        child: RefreshIndicator(
          color: AppTheme.primaryCyan,
          onRefresh: _load,
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryCyan),
                )
              : _error != null
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(_error!, style: const TextStyle(color: AppTheme.error)),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ],
                )
              : _offers.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: const [
                    SizedBox(height: 48),
                    Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.inbox_rounded,
                            size: 52,
                            color: AppTheme.textSecondary,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No delivery offers',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Offers appear here when the system selects you for a nearby order.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    ..._offers.map(
                      (o) => _OfferCard(
                        offer: o,
                        accepting: _accepting,
                        onAccept: () => _acceptOffer(o),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
        ),
      ),
    );
  }
}

class _OfferCard extends StatefulWidget {
  final Map<String, dynamic> offer;
  final bool accepting;
  final VoidCallback onAccept;

  const _OfferCard({
    required this.offer,
    required this.accepting,
    required this.onAccept,
  });

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _computeRemaining();
    if (widget.offer['status'] == 'pending') {
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _computeRemaining(),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _computeRemaining() {
    final raw = widget.offer['expires_at'];
    if (raw == null) {
      if (mounted) setState(() => _remaining = Duration.zero);
      return;
    }
    try {
      final expiry = DateTime.parse(raw.toString()).toLocal();
      final diff = expiry.difference(DateTime.now());
      if (mounted) {
        setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
      }
    } catch (_) {}
  }

  bool get _isExpired =>
      widget.offer['status'] == 'pending' && _remaining == Duration.zero;

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final orderNumber = offer['order_number']?.toString() ?? '';
    final address = offer['delivery_address']?.toString() ?? '';
    final distRaw = offer['rider_distance_km'];
    final dist = distRaw != null ? (distRaw as num).toStringAsFixed(1) : null;
    final status = offer['status']?.toString() ?? '';
    final orderStatus = offer['order_status']?.toString() ?? '';
    final isPending = status == 'pending' && !_isExpired;
    final canAccept = isPending && orderStatus == 'out_for_delivery';

    final statusColor = switch (status) {
      'accepted' => AppTheme.success,
      'expired' => AppTheme.error,
      'taken' => AppTheme.textSecondary,
      'declined' => AppTheme.error,
      _ => _isExpired ? AppTheme.error : AppTheme.primaryCyan,
    };
    final statusLabel = switch (status) {
      'accepted' => 'Accepted',
      'expired' => 'Expired',
      'taken' => 'Taken',
      'declined' => 'Declined',
      _ => _isExpired ? 'Expired' : 'Pending',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isPending
                ? AppTheme.primaryCyan.withValues(alpha: 0.4)
                : AppTheme.divider,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    orderNumber,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if (address.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (dist != null)
                  _chip(
                    Icons.near_me_rounded,
                    '$dist km to pickup',
                    AppTheme.darkCyan,
                  ),
                if (isPending && _remaining.inSeconds > 0)
                  _chip(
                    Icons.timer_rounded,
                    _fmtDuration(_remaining),
                    AppTheme.warning,
                  ),
                if (_isExpired)
                  _chip(
                    Icons.timer_off_rounded,
                    'Offer expired',
                    AppTheme.error,
                  ),
              ],
            ),
            if (canAccept) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: widget.accepting ? null : widget.onAccept,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  child: widget.accepting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Accept delivery'),
                ),
              ),
            ] else if (isPending && orderStatus != 'out_for_delivery') ...[
              const SizedBox(height: 10),
              Text(
                'Order is still being prepared — accept once it is out for delivery.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppTheme.darkCyan.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
