import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../widgets/osm_route_map.dart';

/// Parsed tracking API payload for map + bottom sheet (Phase 1 layout).
class _TrackingPayload {
  const _TrackingPayload({
    required this.order,
    required this.assignment,
    required this.points,
    required this.orderNumber,
    required this.status,
    required this.routeCoords,
    required this.trail,
    required this.markers,
    required this.rider,
    required this.locationUpdatedLabel,
    required this.etaMinutes,
    required this.routeSource,
    required this.routeConfidence,
  });

  final Map<String, dynamic> order;
  final Map<String, dynamic>? assignment;
  final List<dynamic> points;
  final String orderNumber;
  final String status;
  final List<LatLng> routeCoords;
  final List<LatLng> trail;
  final List<MapMarker> markers;
  final LatLng? rider;
  final String? locationUpdatedLabel;
  final int? etaMinutes;
  final String? routeSource;
  final double? routeConfidence;
}

class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String? orderNumber;

  const OrderTrackingScreen({super.key, this.orderNumber});

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _sheetHidden = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        final on = widget.orderNumber?.trim();
        if (on != null && on.isNotEmpty && mounted) {
          _load(silent: true);
        }
      });
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final on = widget.orderNumber?.trim();
    if (on == null || on.isEmpty) {
      setState(() {
        _loading = false;
        _error = null;
        _data = null;
      });
      return;
    }

    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final svc = ref.read(orderServiceProvider);
      final data = await svc.trackDelivery(on);
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (silent) {
        return;
      }
      setState(() {
        _loading = false;
        if (e is DioException && e.response?.statusCode == 404) {
          _error = 'not_started';
        } else {
          _error = e.toString();
        }
      });
    }
  }
  Future<void> _showDropoffToken(int assignmentId) async {
    setState(() => _loading = true);
    try {
      final svc = ref.read(orderServiceProvider);
      final payload = await svc.generateBuyerDropoffToken(assignmentId);
      if (!mounted) return;
      setState(() => _loading = false);
      final token = (payload['token'] ?? '').toString();
      showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: AppTheme.surfaceWhite,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.qr_code_rounded,
                  size: 48,
                  color: AppTheme.primaryCyan,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your delivery QR code',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Show this to the rider when they arrive to confirm delivery.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                if (token.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                    ),
                    child: QrImageView(
                      data: token,
                      version: QrVersions.auto,
                      size: 180.0,
                    ),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'Or provide this code manually:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.lightCyan.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    token.isEmpty ? 'Token not available' : token,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      letterSpacing: 2.0,
                      color: AppTheme.darkCyan,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final msg = e is DioException ? ref.read(orderServiceProvider).extractErrorMessage(e) : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg ?? 'Could not generate token')),
      );
    }
  }


  bool get _hasOrder =>
      widget.orderNumber != null && widget.orderNumber!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final showMapChrome =
        _hasOrder && _error == null && _data != null;

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Track delivery'),
        elevation: showMapChrome ? 0 : 1,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (_hasOrder)
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : () => _load(),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: !_hasOrder
          ? _buildNoOrderBody()
          : _buildOrderBody(context),
    );
  }

  Widget _buildNoOrderBody() {
    return SafeArea(
      child: RefreshIndicator(
        color: AppTheme.primaryCyan,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            _emptyState(
              icon: Icons.local_shipping_outlined,
              title: 'No order selected',
              subtitle:
                  'Open an order from My orders and tap Track delivery.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderBody(BuildContext context) {
    if (_loading && _data == null) {
      return _mapAndSheet(
        mapLayer: _mapPlaceholder(loading: true),
        sheetBody: (c) => _sheetLoading(c),
      );
    }
    if (_error == 'not_started') {
      return SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryCyan,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              _emptyState(
                icon: Icons.schedule_outlined,
                title: 'Delivery not started',
                subtitle:
                    'Your order is being prepared. Tracking will appear when a rider is assigned.',
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryCyan,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: AppTheme.error,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _load(),
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryCyan,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_data != null) {
      final payload = _parsePayload(context, _data!);
      if (payload == null) {
        return const Center(child: Text('Invalid tracking data'));
      }
      return _mapAndSheet(
        mapLayer: OsmRouteMap(
          key: ValueKey(payload.orderNumber),
          expandVertically: true,
          clipBorderRadius: BorderRadius.zero,
          routePoints: payload.routeCoords,
          trailPoints: payload.trail,
          markers: payload.markers,
          followTarget: payload.rider,
          followMinMoveMeters: 12,
          refitBoundsWhenDataChanges: payload.rider == null,
          showZoomControls: true,
        ),
        sheetBody: (c) => _sheetTrackingContent(context, c, payload),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _mapPlaceholder({required bool loading}) {
    return ColoredBox(
      color: const Color(0xFFEAF1FF),
      child: Center(
        child: loading
            ? const CircularProgressIndicator(color: AppTheme.primaryCyan)
            : Icon(
                Icons.map_outlined,
                size: 56,
                color: AppTheme.textSecondary.withValues(alpha: 0.4),
              ),
      ),
    );
  }

  Widget _mapAndSheet({
    required Widget mapLayer,
    required Widget Function(ScrollController scrollController) sheetBody,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: mapLayer),
        if (!_sheetHidden)
          DraggableScrollableSheet(
            initialChildSize: 0.48,
            minChildSize: 0.20,
            maxChildSize: 0.92,
            snap: true,
            snapSizes: const [0.20, 0.48, 0.65, 0.92],
            builder: (context, scrollController) {
              return Material(
                elevation: 12,
                shadowColor: Colors.black26,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                color: Colors.white.withValues(alpha: 0.88),
                clipBehavior: Clip.antiAlias,
                child: sheetBody(scrollController),
              );
            },
          ),
        if (_sheetHidden)
          Positioned(
            right: 14,
            bottom: 18,
            child: FloatingActionButton.small(
              heroTag: 'expand_tracking_panel',
              onPressed: () => setState(() => _sheetHidden = false),
              backgroundColor: Colors.white.withValues(alpha: 0.92),
              foregroundColor: AppTheme.textPrimary,
              child: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
          ),
      ],
    );
  }

  Widget _sheetLoading(ScrollController scrollController) {
    return CustomScrollView(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _sheetDragHandle()),
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.primaryCyan),
                  SizedBox(height: 16),
                  Text(
                    'Loading live map…',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sheetDragHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppTheme.textSecondary.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _sheetTrackingContent(
    BuildContext context,
    ScrollController scrollController,
    _TrackingPayload p,
  ) {
    final assignment = p.assignment;
    final confidenceLabel = _confidenceLabel(p.routeConfidence);
    final confidenceColor = _confidenceColor(p.routeConfidence);

    return RefreshIndicator(
      color: AppTheme.primaryCyan,
      onRefresh: _load,
      child: CustomScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _sheetDragHandle()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      p.orderNumber,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Minimise panel',
                    onPressed: () => setState(() => _sheetHidden = true),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.textSecondary,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _labelStatus(p.status),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _labelOrderStatusRaw(p.status),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.darkCyan.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (p.etaMinutes != null)
                        _pill(
                          icon: Icons.schedule_rounded,
                          text: _etaLabel(
                            p.etaMinutes!,
                            p.routeConfidence,
                          ),
                          color: AppTheme.accentBlue,
                        ),
                      if (confidenceLabel != null)
                        _pill(
                          icon: Icons.verified_rounded,
                          text: confidenceLabel,
                          color: confidenceColor,
                        ),
                      if (p.routeSource != null)
                        _pill(
                          icon: Icons.route_rounded,
                          text: _sourceLabel(p.routeSource!),
                          color: AppTheme.darkCyan,
                        ),
                    ],
                  ),
                  if (assignment != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _labelAssignmentStatus(
                        assignment['status']?.toString() ?? '',
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (assignment['status'] == 'in_transit' || assignment['status'] == 'picked_up') ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _showDropoffToken(int.parse(assignment['id'].toString())),
                          icon: const Icon(Icons.qr_code_2_rounded),
                          label: const Text('Show delivery QR code'),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          if (assignment != null &&
              (assignment['delivery_address']?.toString() ?? '').isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Deliver to',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      assignment['delivery_address'].toString(),
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (assignment != null &&
              (assignment['buyer_phone']?.toString() ?? '').isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.phone_outlined,
                      size: 18,
                      color: AppTheme.textSecondary.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Phone on order: ${assignment['buyer_phone']}',
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: _mapLegendRow(p.rider != null),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.rider != null
                        ? 'Map refreshes about every 15s while you stay on this screen. Drag the sheet for more detail.'
                        : 'Waiting for rider GPS — the map will follow when updates arrive.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  if (p.locationUpdatedLabel != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Rider position last reported at ${p.locationUpdatedLabel} (your time)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (p.points.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'No GPS trail points yet.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '${p.points.length} recent GPS point(s) on trail',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _mapLegendRow(bool riderLive) {
    Widget chip(String label, Color color, IconData icon) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('Pickup', AppTheme.darkCyan, Icons.store_rounded),
        chip('Drop-off', AppTheme.success, Icons.home_rounded),
        chip(
          riderLive ? 'Rider' : 'Rider (pending)',
          AppTheme.primaryCyan,
          Icons.delivery_dining_rounded,
        ),
      ],
    );
  }

  Widget _pill({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  _TrackingPayload? _parsePayload(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final order = data['order'] as Map<String, dynamic>? ?? {};
    final assignmentRaw = data['assignment'];
    Map<String, dynamic>? assignment;
    if (assignmentRaw is Map<String, dynamic>) {
      assignment = assignmentRaw;
    } else if (assignmentRaw is Map) {
      assignment = Map<String, dynamic>.from(assignmentRaw);
    }

    final points = data['tracking_points'] as List<dynamic>? ?? [];
    final status = order['status']?.toString() ?? '';
    final orderNumber = order['order_number']?.toString() ?? '';
    if (orderNumber.isEmpty) return null;

    final pickup =
        assignment != null ? _coordFromLoc(assignment['pickup_location']) : null;
    final drop =
        assignment != null ? _coordFromLoc(assignment['delivery_location']) : null;
    final rider =
        assignment != null ? _coordFromLoc(assignment['current_location']) : null;

    final routeCoords = assignment != null
        ? OsmRouteMap.coordsFromJson(assignment['route_coordinates'])
        : <LatLng>[];

    final trail = _trailFromTracking(points);

    final locationUpdatedLabel = assignment != null
        ? _formatLocationUpdated(context, assignment['location_updated_at'])
        : null;
    final etaMinutes = assignment != null
        ? int.tryParse((assignment['estimated_duration'] ?? '').toString())
        : null;
    final routeSource = assignment != null
        ? assignment['route_source']?.toString()
        : null;
    final routeConfidence = assignment != null
        ? double.tryParse((assignment['route_confidence'] ?? '').toString())
        : null;

    final markers = <MapMarker>[
      if (pickup != null)
        MapMarker(
          point: pickup,
          icon: Icons.store,
          color: AppTheme.darkCyan,
        ),
      if (drop != null)
        MapMarker(
          point: drop,
          icon: Icons.home,
          color: AppTheme.success,
        ),
      if (rider != null)
        MapMarker(
          point: rider,
          icon: Icons.delivery_dining,
          color: AppTheme.primaryCyan,
        ),
    ];

    return _TrackingPayload(
      order: order,
      assignment: assignment,
      points: points,
      orderNumber: orderNumber,
      status: status,
      routeCoords: routeCoords,
      trail: trail,
      markers: markers,
      rider: rider,
      locationUpdatedLabel: locationUpdatedLabel,
      etaMinutes: etaMinutes,
      routeSource: routeSource,
      routeConfidence: routeConfidence,
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(
            icon,
            size: 52,
            color: AppTheme.textSecondary.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  LatLng? _coordFromLoc(dynamic raw) {
    if (raw is Map) {
      final la = raw['lat'];
      final ln = raw['lng'];
      if (la != null && ln != null) {
        final lat = double.tryParse(la.toString());
        final lng = double.tryParse(ln.toString());
        if (lat != null && lng != null) {
          return LatLng(lat, lng);
        }
      }
    }
    return null;
  }

  String? _formatLocationUpdated(BuildContext context, dynamic raw) {
    if (raw == null) return null;
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return TimeOfDay.fromDateTime(dt).format(context);
    } catch (_) {
      return null;
    }
  }

  List<LatLng> _trailFromTracking(List<dynamic> pointsNewestFirst) {
    final out = <LatLng>[];
    for (final p in pointsNewestFirst.reversed) {
      if (p is Map) {
        final la = p['latitude'];
        final lo = p['longitude'];
        if (la != null && lo != null) {
          final lat = double.tryParse(la.toString());
          final lng = double.tryParse(lo.toString());
          if (lat != null && lng != null) {
            out.add(LatLng(lat, lng));
          }
        }
      }
    }
    return out;
  }

  String _labelAssignmentStatus(String s) {
    switch (s) {
      case 'accepted':
        return 'Rider accepted — heading to pickup';
      case 'picked_up':
        return 'Picked up from store';
      case 'in_transit':
        return 'On the way to you';
      case 'delivered':
        return 'Delivered';
      default:
        return s.isEmpty ? 'Delivery update' : s;
    }
  }

  /// Short headline for the large title (buyer-friendly).
  String _labelStatus(String s) {
    switch (s) {
      case 'out_for_delivery':
        return 'On the way';
      case 'delivered':
        return 'Delivered';
      case 'pending':
        return 'Order received';
      default:
        return s.isEmpty ? 'Tracking' : s;
    }
  }

  String _labelOrderStatusRaw(String s) {
    switch (s) {
      case 'out_for_delivery':
        return 'Out for delivery';
      case 'delivered':
        return 'Delivered';
      case 'pending':
        return 'Pending';
      default:
        return s.isEmpty ? '—' : s;
    }
  }

  String? _confidenceLabel(double? score) {
    if (score == null) return null;
    if (score >= 0.8) return 'High confidence';
    if (score >= 0.55) return 'Moderate confidence';
    return 'Low confidence';
  }

  Color _confidenceColor(double? score) {
    if (score == null) return AppTheme.textSecondary;
    if (score >= 0.8) return AppTheme.success;
    if (score >= 0.55) return AppTheme.warning;
    return AppTheme.error;
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'osrm':
        return 'Road route';
      case 'haversine_fallback':
        return 'Fallback route';
      default:
        return source;
    }
  }

  String _etaLabel(int minutes, double? confidence) {
    final range = _etaRange(minutes, confidence);
    if (range == null) return '~$minutes min ETA';
    return 'ETA ${range.$1}-${range.$2} min';
  }

  (int, int)? _etaRange(int minutes, double? confidence) {
    if (confidence == null) return null;
    double spread;
    if (confidence >= 0.8) {
      return null;
    } else if (confidence >= 0.55) {
      spread = 0.18;
    } else {
      spread = 0.3;
    }
    final delta = (minutes * spread).ceil();
    final minEta = (minutes - delta).clamp(1, 10000);
    final maxEta = (minutes + delta + 2).clamp(minEta + 1, 10000);
    return (minEta, maxEta);
  }
}
