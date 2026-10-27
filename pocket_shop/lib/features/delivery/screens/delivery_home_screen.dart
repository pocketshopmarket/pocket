import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/location_helper.dart';
import '../../../providers/delivery_provider.dart';
import '../../../services/api_service.dart';
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
  bool _online = true;
  bool _updatingOnline = false;
  bool _loading = false;
  String? _locationNote;
  List<Map<String, dynamic>> _orders = [];
  double _lat = 0;
  double _lng = 0;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _ensureLocation() async {
    final result = await LocationHelper.getCurrentPositionOrFallback();
    switch (result.status) {
      case LocationStatus.servicesDisabled:
        setState(() { _locationNote = 'Turn on location for distance estimates.'; _lat = 0; _lng = 0; });
        return;
      case LocationStatus.permissionDenied:
        setState(() { _locationNote = 'Location permission denied — distances may be hidden.'; _lat = 0; _lng = 0; });
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
    setState(() { _online = value; _updatingOnline = true; });
    try {
      await ApiService().put(AppConstants.profileEndpoint, data: {'is_available': value});
    } catch (_) {
      if (mounted) {
        setState(() => _online = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update status. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingOnline = false);
    }
    if (value) { _refresh(); } else { setState(() => _orders = []); }
  }

  Future<void> _refresh() async {
    if (!_online) return;
    setState(() => _loading = true);
    await _ensureLocation();
    if (!mounted) return;
    try {
      final list = await ref.read(deliveryServiceProvider).fetchAvailableOrders(lat: _lat, lng: _lng);
      if (mounted) setState(() { _orders = list; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _loading = false; _orders = []; });
        final msg = e is DioException ? ref.read(deliveryServiceProvider).extractErrorMessage(e) : null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg ?? "Couldn't load deliveries. Pull down to try again.")));
      }
    }
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

    try {
      await ref.read(deliveryServiceProvider).acceptOrder(orderId: id, lat: _lat, lng: _lng);
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
                trailing: _online && _orders.isNotEmpty
                    ? Text(
                        '${_orders.length} available',
                        style: AppTheme.body(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondary),
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              if (_online && _orders.isNotEmpty) ...[
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
                        color: _online ? AppTheme.success : AppTheme.placeholder,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _online ? "You're online" : "You're offline",
                      style: AppTheme.display(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _online
                      ? 'Looking for deliveries near you'
                      : 'Go online to see deliveries near you',
                  style: AppTheme.body(fontSize: 13, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _updatingOnline
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
                    value: _online,
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
                    Text('My delivery offers', style: AppTheme.body(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(
                      'Deliveries sellers sent to you directly',
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
    if (!_online) {
      return PsEmptyState(
        icon: Icons.power_settings_new_rounded,
        title: 'Taking a break?',
        message: "Flip the switch when you're ready and nearby deliveries will show up here.",
        actionLabel: 'Go online',
        onAction: () => _setOnlineStatus(true),
      );
    }

    if (_loading && _orders.isEmpty) {
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
        message: 'New deliveries appear here as soon as sellers have them ready. We check every 30 seconds.',
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
    final canAccept = status == 'out_for_delivery';

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
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          if (!canAccept) ...[
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
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: canAccept ? () => _accept(o) : null,
              child: Text(canAccept ? 'Accept' : 'Not ready yet'),
            ),
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
