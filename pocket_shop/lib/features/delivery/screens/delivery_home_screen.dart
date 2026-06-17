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
      setState(() {
        _locationNote = 'Turn on location for distance estimates.';
        _lat = 0;
        _lng = 0;
      });
      return;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      setState(() {
        _locationNote = 'Location permission denied — distances may be hidden.';
        _lat = 0;
        _lng = 0;
      });
      return;
    }

    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      _lat = pos.latitude;
      _lng = pos.longitude;
      _locationNote = null;
    });
  }

  Future<void> _setOnlineStatus(bool value) async {
    setState(() {
      _online = value;
      _updatingOnline = true;
    });
    try {
      await ApiService().put(
        AppConstants.profileEndpoint,
        data: {'is_available': value},
      );
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
    if (value) {
      _refresh();
    } else {
      setState(() => _orders = []);
    }
  }

  Future<void> _refresh() async {
    if (!_online) return;

    setState(() {
      _loading = true;
    });

    await _ensureLocation();
    if (!mounted) return;

    try {
      final svc = ref.read(deliveryServiceProvider);
      final list = await svc.fetchAvailableOrders(lat: _lat, lng: _lng);
      if (mounted) {
        setState(() {
          _orders = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _orders = [];
        });
        final msg = e is DioException
            ? ref.read(deliveryServiceProvider).extractErrorMessage(e)
            : e.toString();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg ?? 'Could not load orders')));
      }
    }
  }

  Future<void> _accept(Map<String, dynamic> order) async {
    final rawId = order['id'];
    final id = rawId is int
        ? rawId
        : rawId is num
        ? rawId.toInt()
        : null;
    if (id == null) return;

    final st = order['status']?.toString() ?? '';
    if (st != 'out_for_delivery') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            st == 'preparing'
                ? 'Seller is still preparing this order. Accept when it is marked out for delivery.'
                : 'Wait until the seller marks this order out for delivery before accepting.',
          ),
        ),
      );
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
      final svc = ref.read(deliveryServiceProvider);
      await svc.acceptOrder(orderId: id, lat: _lat, lng: _lng);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Delivery accepted')));
        context.go('/delivery/active');
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is DioException
          ? ref.read(deliveryServiceProvider).extractErrorMessage(e)
          : e.toString();
      final active = e is DioException && e.response?.data is Map
          ? (e.response?.data as Map)['active_assignment']
          : null;
      final activeLine =
          active is Map && active['order_number'] != null && active['status'] != null
          ? ' Current active: ${active['order_number']} (${active['status']}).'
          : '';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text('${msg ?? 'Accept failed'}$activeLine')),
      );
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
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeaderCard(),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => context.push('/delivery/offers'),
                icon: const Icon(Icons.inbox_rounded, size: 17),
                label: const Text('View my delivery offers'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 42),
                  foregroundColor: AppTheme.darkCyan,
                  side: BorderSide(color: AppTheme.primaryCyan.withValues(alpha: 0.5)),
                ),
              ),
              if (_locationNote != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.warning.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    _locationNote!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text(
                    'Nearby deliveries',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryCyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_orders.length} order${_orders.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.darkCyan,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'You can accept only when order status is ready.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 14),
              _pickupMapCard(),
              const SizedBox(height: 14),
              if (!_online)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Center(
                    child: Text(
                      'Go online to see available orders',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                )
              else if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryCyan,
                    ),
                  ),
                )
              else if (_orders.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(
                    child: Text(
                      'No orders available right now',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                )
              else
                ..._orders.map((o) => _orderCard(o)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> o) {
    final number = o['order_number']?.toString() ?? '';
    final addr = o['delivery_address']?.toString() ?? '';
    final price = o['total_price']?.toString() ?? '';
    final dist = o['distance_from_rider'];
    final eta = o['estimated_time'];
    final status = o['status']?.toString() ?? '';
    final canAccept = status == 'out_for_delivery';

    String subtitle = addr;
    if (dist != null) {
      final km = (dist as num).toStringAsFixed(1);
      final etaPart = eta != null ? ' · ~$eta min' : '';
      subtitle += '\n$km km to pickup$etaPart';
    }

    final statusLabel = _statusChipLabel(status);
    final statusColor = canAccept ? AppTheme.success : AppTheme.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.divider),
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
                    number,
                    style: const TextStyle(
                      fontSize: 22,
                      letterSpacing: 0.2,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.35,
              ),
            ),
            if (!canAccept) ...[
              const SizedBox(height: 8),
              Text(
                _statusHint(status),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppTheme.darkCyan.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (price.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'ZMW $price',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.darkCyan,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canAccept ? () => _accept(o) : null,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                child: Text(canAccept ? 'Accept delivery' : 'Not ready yet'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickupMapCard() {
    final markers = _orders
        .map(_pickupMarkerFromOrder)
        .whereType<MapMarker>()
        .toList();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pickup map',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            markers.isEmpty
                ? 'No pickup points to show yet.'
                : '${markers.length} pickup point(s) available',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 170,
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

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delivery board',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'See nearby orders and accept quickly.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFD1D5DB)),
                    ),
                  ],
                ),
              ),
              const NotificationBell(),
              const SizedBox(width: 4),
              _updatingOnline
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryCyan,
                      ),
                    )
                  : Switch(
                      value: _online,
                      activeThumbColor: AppTheme.primaryCyan,
                      onChanged: _setOnlineStatus,
                    ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _miniStatChip(
                label: 'Mode',
                value: _online ? 'Online' : 'Offline',
              ),
              const SizedBox(width: 8),
              _miniStatChip(label: 'Available', value: '${_orders.length}'),
              const SizedBox(width: 8),
              _miniStatChip(
                label: 'Location',
                value: (_lat != 0 || _lng != 0) ? 'Ready' : 'Off',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStatChip({required String label, required String value}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFFC7CED8)),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusChipLabel(String status) {
    switch (status) {
      case 'out_for_delivery':
        return 'Ready';
      case 'preparing':
        return 'Preparing';
      case 'accepted':
        return 'Accepted';
      case 'pending':
        return 'Pending';
      default:
        return status.isEmpty ? '—' : status;
    }
  }

  String _statusHint(String status) {
    switch (status) {
      case 'pending':
        return 'Waiting for the seller to accept this order from the buyer.';
      case 'accepted':
        return 'Seller accepted this order. They still need to move it to preparing, then out for delivery.';
      case 'preparing':
        return 'Being prepared at the store. You can accept once it is marked out for delivery.';
      default:
        return 'You can accept only when the order is out for delivery.';
    }
  }
}
