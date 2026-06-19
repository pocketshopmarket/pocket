import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../widgets/osm_route_map.dart';
import '../../../../widgets/qr_identity_sheet.dart';

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
  final double? deliveryLat;
  final double? deliveryLng;
  final double? sellerLat;
  final double? sellerLng;
  final String? sellerPhone;
  final List<String>? orderItems;

  const OrderTrackingScreen({
    super.key,
    this.orderNumber,
    this.deliveryLat,
    this.deliveryLng,
    this.sellerLat,
    this.sellerLng,
    this.sellerPhone,
    this.orderItems,
  });

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
        } else if (e is DioException &&
            (e.type == DioExceptionType.connectionError ||
                e.type == DioExceptionType.unknown)) {
          _error = "Can't connect to the server. Please check your internet connection.";
        } else if (e is DioException &&
            (e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.receiveTimeout)) {
          _error = 'Request timed out. Please try again.';
        } else {
          _error = 'Something went wrong. Please try again.';
        }
      });
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/buyer/orders'),
        ),
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
      final sellerPin = widget.sellerLat != null && widget.sellerLng != null
          ? LatLng(widget.sellerLat!, widget.sellerLng!)
          : null;
      final dropPin = widget.deliveryLat != null && widget.deliveryLng != null
          ? LatLng(widget.deliveryLat!, widget.deliveryLng!)
          : null;
      final hasCoords = sellerPin != null || dropPin != null;

      return _mapAndSheet(
        mapLayer: hasCoords
            ? OsmRouteMap(
                expandVertically: true,
                clipBorderRadius: BorderRadius.zero,
                routePoints: const [],
                trailPoints: const [],
                markers: [
                  if (sellerPin != null)
                    MapMarker(
                      point: sellerPin,
                      icon: Icons.store,
                      color: AppTheme.darkCyan,
                    ),
                  if (dropPin != null)
                    MapMarker(
                      point: dropPin,
                      icon: Icons.home,
                      color: AppTheme.success,
                    ),
                ],
                showZoomControls: true,
              )
            : _mapPlaceholder(loading: false),
        sheetBody: (c) => _sheetNotStarted(c),
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

  Widget _sheetNotStarted(ScrollController scrollController) {
    return CustomScrollView(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _sheetDragHandle()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Waiting for rider',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your order is being prepared. Live tracking will appear here automatically once a rider is assigned.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary.withValues(alpha: 0.9),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                _pill(
                  icon: Icons.refresh_rounded,
                  text: 'Checking every 15s',
                  color: AppTheme.primaryCyan,
                ),
                if (widget.orderItems != null && widget.orderItems!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildItemsSummary(widget.orderItems!),
                ],
                if ((widget.sellerPhone ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final uri = Uri(scheme: 'tel', path: widget.sellerPhone);
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                      },
                      icon: const Icon(Icons.call_outlined),
                      label: const Text('Call seller'),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
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
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => QrIdentitySheet.show(context),
                          borderRadius: BorderRadius.circular(14),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryCyan.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.qr_code_rounded,
                                    color: AppTheme.primaryCyan,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Show my QR code',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Rider scans this to confirm drop-off',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.white38,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    if ((assignment['delivery_person_phone']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final uri = Uri(
                              scheme: 'tel',
                              path: assignment['delivery_person_phone'].toString(),
                            );
                            if (await canLaunchUrl(uri)) await launchUrl(uri);
                          },
                          icon: const Icon(Icons.call_outlined),
                          label: const Text('Call rider'),
                        ),
                      ),
                    ],
                    if ((widget.sellerPhone ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final uri = Uri(scheme: 'tel', path: widget.sellerPhone);
                            if (await canLaunchUrl(uri)) await launchUrl(uri);
                          },
                          icon: const Icon(Icons.storefront_outlined),
                          label: const Text('Call seller'),
                        ),
                      ),
                    ],
                    if (widget.orderItems != null && widget.orderItems!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildItemsSummary(widget.orderItems!),
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
        chip('Pickup', AppTheme.darkCyan, Icons.store),
        chip('Drop-off', AppTheme.success, Icons.home),
        chip(
          riderLive ? 'Rider' : 'Rider (pending)',
          AppTheme.primaryCyan,
          Icons.delivery_dining,
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

  Widget _buildItemsSummary(List<String> items) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.softSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Items',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 5, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
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
