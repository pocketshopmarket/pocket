import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/delivery_provider.dart';
import '../../../services/api_service.dart';
import '../../../widgets/notification_bell.dart';
import '../../../widgets/osm_route_map.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _ensureLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      setState(() { _locationNote = 'Turn on location for distance estimates.'; _lat = 0; _lng = 0; });
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
      setState(() { _locationNote = 'Location permission denied — distances may be hidden.'; _lat = 0; _lng = 0; });
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    setState(() { _lat = pos.latitude; _lng = pos.longitude; _locationNote = null; });
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
        final msg = e is DioException ? ref.read(deliveryServiceProvider).extractErrorMessage(e) : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg ?? 'Could not load orders')));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery accepted')));
        context.go('/delivery/active');
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is DioException ? ref.read(deliveryServiceProvider).extractErrorMessage(e) : e.toString();
      final active = e is DioException && e.response?.data is Map ? (e.response?.data as Map)['active_assignment'] : null;
      final activeLine = active is Map && active['order_number'] != null
          ? ' Active: ${active['order_number']} (${active['status']}).' : '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${msg ?? 'Accept failed'}$activeLine')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryCyan,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              _buildHeader(),
              if (_locationNote != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_off_rounded, size: 15, color: AppTheme.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_locationNote!, style: TextStyle(fontSize: 12, color: AppTheme.warning)),
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/delivery/offers'),
                  icon: const Icon(Icons.inbox_rounded, size: 16),
                  label: const Text('My delivery offers'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    foregroundColor: AppTheme.darkCyan,
                    side: BorderSide(color: AppTheme.primaryCyan.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text(
                      'Nearby orders',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                    ),
                    const Spacer(),
                    if (_orders.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryCyan.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_orders.length} available',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.darkCyan),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_orders.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _pickupMapCard(),
                ),
                const SizedBox(height: 12),
              ],
              _buildBody(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_online) {
      return _emptyState(
        icon: Icons.wifi_off_rounded,
        iconColor: AppTheme.textSecondary,
        title: "You're offline",
        subtitle: 'Toggle online to start receiving nearby delivery orders.',
        action: FilledButton.icon(
          onPressed: () => _setOnlineStatus(true),
          icon: const Icon(Icons.toggle_on_rounded),
          label: const Text('Go online'),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryCyan),
        ),
      );
    }

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(color: AppTheme.primaryCyan)),
      );
    }

    if (_orders.isEmpty) {
      return _emptyState(
        icon: Icons.delivery_dining_rounded,
        iconColor: AppTheme.primaryCyan,
        title: 'No orders nearby',
        subtitle: 'Pull down to refresh. New orders appear here as sellers prepare them.',
        action: OutlinedButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.darkCyan),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: _orders.map(_orderCard).toList()),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 44, color: iconColor),
          ),
          const SizedBox(height: 20),
          Text(title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.5)),
          if (action != null) ...[
            const SizedBox(height: 24),
            action,
          ],
        ],
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> o) {
    final number = o['order_number']?.toString() ?? '';
    final addr = o['delivery_address']?.toString() ?? '';
    final price = o['total_price']?.toString() ?? '';
    final deliveryFee = o['delivery_fee']?.toString() ?? '';
    final dist = o['distance_from_rider'];
    final eta = o['estimated_time'];
    final status = o['status']?.toString() ?? '';
    final sellerName = o['seller_name']?.toString() ?? '';
    final itemsSummary = o['items_summary']?.toString() ?? '';
    final canAccept = status == 'out_for_delivery';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: canAccept
                ? AppTheme.primaryCyan.withValues(alpha: 0.5)
                : AppTheme.divider,
            width: canAccept ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (canAccept ? AppTheme.primaryCyan : Colors.black).withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Top row — order number + status badge
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          number,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                        ),
                        if (sellerName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.storefront_rounded, size: 12, color: AppTheme.darkCyan),
                              const SizedBox(width: 4),
                              Text(sellerName,
                                  style: const TextStyle(fontSize: 12, color: AppTheme.darkCyan, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  _statusBadge(status, canAccept),
                ],
              ),
            ),
            if (itemsSummary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.inventory_2_rounded, size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(itemsSummary,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.3)),
                    ),
                  ],
                ),
              ),
            // Address
            if (addr.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_rounded, size: 15, color: AppTheme.textSecondary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(addr,
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.35)),
                    ),
                  ],
                ),
              ),
            // Info chips
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  if (dist != null) ...[
                    _infoChip(Icons.near_me_rounded, '${(dist as num).toStringAsFixed(1)} km', AppTheme.darkCyan),
                    const SizedBox(width: 8),
                  ],
                  if (eta != null)
                    _infoChip(Icons.access_time_rounded, '~$eta min', AppTheme.accentOrange),
                  const Spacer(),
                  if (price.isNotEmpty)
                    Text(
                      'ZMW $price',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                    ),
                ],
              ),
            ),
            if (deliveryFee.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: [
                    const Spacer(),
                    Text(
                      'Your fee: ZMW $deliveryFee',
                      style: const TextStyle(fontSize: 12, color: AppTheme.darkCyan, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            // Status hint
            if (!canAccept)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.lightCyan.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _statusHint(status),
                    style: const TextStyle(fontSize: 12, color: AppTheme.darkCyan, height: 1.4),
                  ),
                ),
              ),
            // Accept button
            Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canAccept ? () => _accept(o) : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    backgroundColor: canAccept ? AppTheme.primaryCyan : null,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    canAccept ? 'Accept delivery' : 'Not ready yet',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status, bool canAccept) {
    final color = canAccept ? AppTheme.success : AppTheme.textSecondary;
    final label = switch (status) {
      'out_for_delivery' => 'Ready',
      'preparing' => 'Preparing',
      'accepted' => 'Accepted',
      'pending' => 'Pending',
      _ => status.isEmpty ? '—' : status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _pickupMapCard() {
    final markers = _orders.map(_pickupMarkerFromOrder).whereType<MapMarker>().toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.map_rounded, size: 15, color: AppTheme.darkCyan),
              const SizedBox(width: 6),
              const Text('Pickup map', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              const Spacer(),
              Text(
                '${markers.length} point${markers.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: OsmRouteMap(
              markers: markers,
              showZoomControls: true,
              refitBoundsWhenDataChanges: true,
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

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A4A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Delivery board',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 3),
                    Text(
                      _online ? 'You are online — watching for orders' : 'You are offline',
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.65)),
                    ),
                  ],
                ),
              ),
              const NotificationBell(),
              const SizedBox(width: 8),
              _updatingOnline
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryCyan))
                  : GestureDetector(
                      onTap: () => _setOnlineStatus(!_online),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _online
                              ? AppTheme.primaryCyan.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _online
                                ? AppTheme.primaryCyan.withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _online ? AppTheme.primaryCyan : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _online ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _online ? AppTheme.primaryCyan : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _statChip(label: 'Orders', value: '${_orders.length}'),
              const SizedBox(width: 8),
              _statChip(label: 'Location', value: (_lat != 0 || _lng != 0) ? 'Ready' : 'Off'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.55))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }

  String _statusHint(String status) {
    return switch (status) {
      'pending' => 'Waiting for seller to accept the order from the buyer.',
      'accepted' => 'Seller accepted — waiting to start preparing.',
      'preparing' => 'Being prepared. Accept once marked out for delivery.',
      _ => 'Accept only when the order is out for delivery.',
    };
  }
}
