import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/location_helper.dart';
import '../../../providers/delivery_provider.dart';
import '../../../services/firebase_init.dart';
import '../../../widgets/notification_bell.dart';
import '../../../widgets/osm_route_map.dart';
import '../../../widgets/shimmer_loading.dart';
import '../../../widgets/ui/ps_ui.dart';

class DeliveryHomeScreen extends ConsumerStatefulWidget {
  const DeliveryHomeScreen({super.key});

  @override
  ConsumerState<DeliveryHomeScreen> createState() => _DeliveryHomeScreenState();
}

class _DeliveryHomeScreenState extends ConsumerState<DeliveryHomeScreen> {
  /// null until the server tells us (it can set riders offline after missed offers).
  bool? _online;
  bool _updatingOnline = false;
  bool _loading = false;
  String? _locationNote;
  List<Map<String, dynamic>> _orders = [];
  double _lat = 0;
  double _lng = 0;
  Timer? _autoRefreshTimer;
  Timer? _countdownTimer;
  // Offer countdowns run from when the list was fetched, using the server's
  // seconds-left, so a phone with the wrong clock still counts down correctly.
  DateTime _fetchedAt = DateTime.now();
  final Set<int> _busyOrderIds = {};
  bool _refreshSoon = false;

  bool get _isOnline => _online == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickOffers());
    riderJobsSignal.addListener(_refresh);
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _countdownTimer?.cancel();
    riderJobsSignal.removeListener(_refresh);
    super.dispose();
  }

  int _secondsLeft(Map<String, dynamic> o) {
    final total = (o['offer_seconds_left'] as num?)?.toInt() ?? 0;
    final left = total - DateTime.now().difference(_fetchedAt).inSeconds;
    return left < 0 ? 0 : left;
  }

  void _tickOffers() {
    if (!mounted) return;
    final offers = _orders.where((o) => o['is_offer'] == true).toList();
    if (offers.isEmpty) return;
    setState(() {});
    // An offer just ran out: ask again shortly to see what happens next.
    if (!_refreshSoon && offers.any((o) => _secondsLeft(o) == 0)) {
      _refreshSoon = true;
      Future.delayed(const Duration(seconds: 2), () {
        _refreshSoon = false;
        _refresh();
      });
    }
  }

  Future<void> _ensureLocation() async {
    final result = await LocationHelper.getCurrentPositionOrFallback();
    if (!mounted) return;
    switch (result.status) {
      case LocationStatus.servicesDisabled:
        setState(() { _locationNote = "Turn on location. You won't get deliveries while it's off."; _lat = 0; _lng = 0; });
        return;
      case LocationStatus.permissionDenied:
        setState(() { _locationNote = 'Allow location so we can send you deliveries nearby.'; _lat = 0; _lng = 0; });
        return;
      case LocationStatus.error:
        setState(() { _locationNote = 'Could not determine your location.'; _lat = 0; _lng = 0; });
        return;
      case LocationStatus.success:
        setState(() { _lat = result.lat!; _lng = result.lng!; _locationNote = null; });
        return;
    }
  }

  Future<void> _setOnlineStatus(bool value) async {
    setState(() => _updatingOnline = true);
    if (value) {
      await _ensureLocation();
      if (!mounted) return;
      if (_lat == 0 && _lng == 0) {
        setState(() => _updatingOnline = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Turn on your location to go online. We only send deliveries to riders we can see nearby.'),
        ));
        return;
      }
    }
    final svc = ref.read(deliveryServiceProvider);
    try {
      final online = await svc.setOnline(online: value, lat: _lat, lng: _lng);
      if (!mounted) return;
      setState(() {
        _online = online;
        if (!online) _orders = [];
      });
    } catch (e) {
      if (mounted) {
        final msg = e is DioException ? svc.extractErrorMessage(e) : null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg ?? 'Could not update status. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingOnline = false);
    }
    if (_isOnline) _refresh();
  }

  /// Checks in with the server (keeps our location fresh and learns if we are
  /// still online), then loads offers and open deliveries.
  Future<void> _refresh() async {
    if (!mounted || _updatingOnline) return;
    setState(() => _loading = true);
    if (_online != false) await _ensureLocation();
    if (!mounted) return;
    final svc = ref.read(deliveryServiceProvider);
    try {
      final online = await svc.checkIn(lat: _lat, lng: _lng);
      if (!online) {
        if (mounted) setState(() { _online = false; _orders = []; _loading = false; });
        return;
      }
      final list = await svc.fetchAvailableOrders(lat: _lat, lng: _lng);
      if (mounted) {
        setState(() {
          _online = true;
          _orders = list;
          _fetchedAt = DateTime.now();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        final msg = e is DioException ? svc.extractErrorMessage(e) : null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg ?? "Couldn't load deliveries. Pull down to try again.")));
      }
    }
  }

  Future<void> _decline(Map<String, dynamic> order) async {
    final offerId = (order['offer_id'] as num?)?.toInt();
    final orderId = (order['id'] as num?)?.toInt();
    if (offerId == null || orderId == null) return;
    setState(() => _busyOrderIds.add(orderId));
    try {
      await ref.read(deliveryServiceProvider).declineOffer(offerId);
    } catch (_) {
      // Nothing to fix: the offer runs out on its own anyway.
    }
    if (!mounted) return;
    setState(() {
      _busyOrderIds.remove(orderId);
      _orders.removeWhere((o) => o['id'] == order['id']);
    });
    _refresh();
  }

  Future<void> _accept(Map<String, dynamic> order) async {
    final rawId = order['id'];
    final id = rawId is int ? rawId : rawId is num ? rawId.toInt() : null;
    if (id == null) return;

    final st = order['status']?.toString() ?? '';
    if (st != 'out_for_delivery') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(st == 'preparing'
            ? 'Seller is still preparing this order.'
            : 'Wait until the seller marks this order out for delivery.'),
      ));
      return;
    }

    await _ensureLocation();
    if (!mounted) return;
    if (_lat == 0 && _lng == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enable location to accept a delivery.')),
      );
      return;
    }

    setState(() => _busyOrderIds.add(id));
    try {
      await ref.read(deliveryServiceProvider).acceptOrder(
        orderId: id,
        lat: _lat,
        lng: _lng,
        offerId: (order['offer_id'] as num?)?.toInt(),
      );
      if (mounted) {
        ref.read(activeDeliveryReloadTriggerProvider.notifier).state++;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery accepted')));
        context.go('/delivery/active');
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is DioException ? ref.read(deliveryServiceProvider).extractErrorMessage(e) : null;
      final active = e is DioException && e.response?.data is Map ? (e.response?.data as Map)['active_assignment'] : null;
      final activeLine = active is Map && active['order_number'] != null
          ? ' Active: ${active['order_number']} (${active['status']}).' : '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${msg ?? "Couldn't accept this delivery. Please try again."}$activeLine')));
      _refresh();
    } finally {
      if (mounted) setState(() => _busyOrderIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryCyan,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Row(
                children: [
                  Expanded(child: Text('Deliveries', style: AppTheme.display(fontSize: 26))),
                  SizedBox.square(
                    dimension: 42,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: const NotificationBell(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _statusCard(),
              if (_locationNote != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.location_off_rounded, size: 16, color: AppTheme.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _locationNote!,
                        style: AppTheme.body(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.warning),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              _offersRow(),
              const SizedBox(height: 24),
              PsSectionHeader(
                title: 'Nearby deliveries',
                trailing: _isOnline && _orders.isNotEmpty
                    ? Text(
                        '${_orders.length} available',
                        style: AppTheme.body(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondary),
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              if (_isOnline && _orders.isNotEmpty) ...[
                _pickupMapCard(),
                const SizedBox(height: 12),
              ],
              _buildBody(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCard() {
    return PsHeroCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: _isOnline ? AppTheme.success : AppTheme.placeholder,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _online == null ? 'Checking…' : (_isOnline ? "You're online" : "You're offline"),
                      style: AppTheme.display(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _isOnline
                      ? 'We send you deliveries near you. Keep location on.'
                      : 'Go online with location on to get deliveries',
                  style: AppTheme.body(fontSize: 13, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _updatingOnline || _online == null
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  ),
                )
              : Transform.scale(
                  scale: 1.15,
                  child: Switch(
                    value: _isOnline,
                    onChanged: _setOnlineStatus,
                    trackColor: WidgetStateProperty.resolveWith(
                      (s) => s.contains(WidgetState.selected) ? AppTheme.success : const Color(0xFF3A3A52),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _offersRow() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => context.push('/delivery/offers'),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              const PsIconBadge(icon: Icons.inbox_rounded, size: 36, color: AppTheme.textPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Offer history', style: AppTheme.body(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(
                      'Offers sent to you and what happened',
                      style: AppTheme.body(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_online == false) {
      return PsEmptyState(
        icon: Icons.power_settings_new_rounded,
        title: 'Taking a break?',
        message: "Flip the switch when you're ready and nearby deliveries will show up here.",
        actionLabel: 'Go online',
        onAction: () => _setOnlineStatus(true),
      );
    }

    if ((_loading || _online == null) && _orders.isEmpty) {
      return AppShimmer(
        child: Column(
          children: List.generate(
            2,
            (_) => Container(
              height: 150,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      );
    }

    if (_orders.isEmpty) {
      return PsEmptyState(
        icon: Icons.delivery_dining_rounded,
        title: 'All quiet for now',
        message: "When a shop near you has an order ready, we'll send it to you. Keep the app open and location on.",
        actionLabel: 'Check again',
        onAction: _refresh,
      );
    }

    return Column(children: _orders.map(_orderCard).toList());
  }

  Widget _orderCard(Map<String, dynamic> o) {
    final number = o['order_number']?.toString() ?? '';
    final addr = o['delivery_address']?.toString() ?? '';
    final price = o['total_price']?.toString() ?? '';
    final deliveryFee = double.tryParse(o['delivery_fee']?.toString() ?? '');
    final dist = o['distance_from_rider'];
    final eta = o['estimated_time'];
    final status = o['status']?.toString() ?? '';
    final sellerName = o['seller_name']?.toString() ?? '';
    final itemsSummary = o['items_summary']?.toString() ?? '';
    final isOffer = o['is_offer'] == true;
    final secondsLeft = isOffer ? _secondsLeft(o) : 0;
    final busy = _busyOrderIds.contains((o['id'] as num?)?.toInt());
    final canAccept = status == 'out_for_delivery' && (!isOffer || secondsLeft > 0) && !busy;

    final route = [
      if (addr.isNotEmpty) addr,
      if (dist is num) '${dist.toStringAsFixed(1)} km',
    ].join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOffer ? AppTheme.textPrimary : AppTheme.divider,
          width: isOffer ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isOffer) ...[
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: AppTheme.accentOrange, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Offered to you',
                    style: AppTheme.body(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  secondsLeft > 0 ? '${secondsLeft}s left' : "Time's up",
                  style: AppTheme.body(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: secondsLeft > 10 ? AppTheme.textPrimary : AppTheme.error,
                  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sellerName.isNotEmpty ? sellerName : number,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    if (route.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '→ $route',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(fontSize: 13, color: AppTheme.textSecondary, height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (deliveryFee != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'ZMW ${deliveryFee.toStringAsFixed(deliveryFee.truncateToDouble() == deliveryFee ? 0 : 2)}',
                      style: AppTheme.display(fontSize: 19, color: AppTheme.accentOrange),
                    ),
                    Text(
                      'you earn',
                      style: AppTheme.body(fontSize: 11.5, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PsStatusLabel(
                label: _statusLabel(status),
                color: canAccept ? AppTheme.success : AppTheme.textSecondary,
                fontSize: 12,
              ),
              if (eta != null) _meta(Icons.schedule_rounded, '~$eta min'),
              if (number.isNotEmpty && sellerName.isNotEmpty) _meta(Icons.tag_rounded, number),
              if (price.isNotEmpty) _meta(Icons.receipt_long_outlined, 'Order ZMW $price'),
            ],
          ),
          if (itemsSummary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              itemsSummary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.35),
            ),
          ],
          if (status != 'out_for_delivery') ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 15, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _statusHint(status),
                    style: AppTheme.body(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.35),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (isOffer && secondsLeft > 0) ...[
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: busy ? null : () => _decline(o),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: const BorderSide(color: AppTheme.divider),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('No thanks'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: canAccept ? () => _accept(o) : null,
                    child: Text(
                      status != 'out_for_delivery'
                          ? 'Not ready yet'
                          : (isOffer && secondsLeft == 0 ? "Time's up" : 'Accept'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(text, style: AppTheme.body(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
      ],
    );
  }

  String _statusLabel(String status) => switch (status) {
        'out_for_delivery' => 'Ready for pickup',
        'preparing' => 'Preparing',
        'accepted' => 'Accepted',
        'pending' => 'Pending',
        _ => status.isEmpty ? '—' : status,
      };

  Widget _pickupMapCard() {
    final markers = _orders.map(_pickupMarkerFromOrder).whereType<MapMarker>().toList();
    if (markers.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Pickup points', style: AppTheme.body(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(
                '${markers.length} shop${markers.length == 1 ? '' : 's'}',
                style: AppTheme.body(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 160,
              child: OsmRouteMap(
                markers: markers,
                showZoomControls: true,
                refitBoundsWhenDataChanges: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  MapMarker? _pickupMarkerFromOrder(Map<String, dynamic> o) {
    final raw = o['pickup_location'];
    if (raw is! Map) return null;
    final lat = raw['lat'];
    final lng = raw['lng'];
    if (lat is! num || lng is! num) return null;
    return MapMarker(
      point: LatLng(lat.toDouble(), lng.toDouble()),
      icon: Icons.circle,
      color: AppTheme.darkCyan,
      size: 8,
      useBadge: false,
    );
  }

  String _statusHint(String status) {
    return switch (status) {
      'pending' => 'Waiting for the seller to accept the order.',
      'accepted' => 'Seller accepted — they will start preparing soon.',
      'preparing' => 'Being packed. You can accept once it is ready for pickup.',
      _ => 'You can accept once the order is ready for pickup.',
    };
  }
}
