import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Provides aggressive local caching for map tiles using [CachedNetworkImageProvider].
/// Once a tile is loaded, it is saved locally and can be displayed instantly
/// and offline on future visits.
class CachedTileProvider extends TileProvider {
  CachedTileProvider() : super();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedNetworkImageProvider(
      getTileUrl(coordinates, options),
      headers: const {
        'User-Agent': 'com.pocket.pocketshop',
      },
    );
  }
}

/// OpenStreetMap tiles + optional route polyline + markers (lng,lat from API → LatLng).
///
/// Use [followTarget] to keep the camera centered on a moving point (device GPS or
/// polled rider position). Use [refitBoundsWhenDataChanges] for an overview when
/// there is no follow target.
class OsmRouteMap extends StatefulWidget {
  final List<LatLng> routePoints;

  /// Optional GPS trail (e.g. recent tracking points), drawn under the main route.
  final List<LatLng> trailPoints;
  final List<MapMarker> markers;
  final double height;

  /// When true, fills parent (e.g. [Expanded]); [height] is ignored for layout.
  final bool expandVertically;

  /// Clip for the map tile; use [BorderRadius.zero] when filling the screen.
  final BorderRadius clipBorderRadius;

  /// When set, the map pans to follow this position when it moves (≥ [followMinMoveMeters]).
  final LatLng? followTarget;

  /// Minimum movement before a follow pan (reduces jitter).
  final double followMinMoveMeters;

  /// Zoom while following (after first fix).
  final double followZoom;

  /// When true and [followTarget] is null, fit route + trail + markers when they change.
  final bool refitBoundsWhenDataChanges;
  final bool showZoomControls;

  const OsmRouteMap({
    super.key,
    this.routePoints = const [],
    this.trailPoints = const [],
    this.markers = const [],
    this.height = 220,
    this.expandVertically = false,
    this.clipBorderRadius = const BorderRadius.all(Radius.circular(14)),
    this.followTarget,
    this.followMinMoveMeters = 8,
    this.followZoom = 16,
    this.refitBoundsWhenDataChanges = true,
    this.showZoomControls = false,
  });

  static List<LatLng> coordsFromJson(dynamic raw) {
    if (raw is! List) return [];
    final out = <LatLng>[];
    for (final e in raw) {
      if (e is List && e.length >= 2) {
        final lng = (e[0] as num).toDouble();
        final lat = (e[1] as num).toDouble();
        out.add(LatLng(lat, lng));
      }
    }
    return out;
  }

  static LatLng? pointFromJson(dynamic raw) {
    if (raw is Map) {
      final lat = raw['lat'];
      final lng = raw['lng'];
      if (lat != null && lng != null) {
        return LatLng((lat as num).toDouble(), (lng as num).toDouble());
      }
    }
    return null;
  }

  @override
  State<OsmRouteMap> createState() => _OsmRouteMapState();
}

class _OsmRouteMapState extends State<OsmRouteMap> {
  final MapController _controller = MapController();
  static const LatLng _fallback = LatLng(-15.3875, 28.3228);
  static final Distance _distance = Distance();

  bool _mapReady = false;
  LatLng? _lastFollow;
  int _lastDataSig = 0;
  bool _didOverviewFit = false;

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    final cam = _controller.camera;
    final next = (cam.zoom + delta).clamp(3.0, 19.5);
    _controller.move(cam.center, next);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<LatLng> _allPoints() {
    return <LatLng>[
      ...widget.routePoints,
      ...widget.trailPoints,
      ...widget.markers.map((m) => m.point),
    ].where((p) => p.latitude.isFinite && p.longitude.isFinite).toList();
  }

  int _dataSignatureFor(OsmRouteMap w) {
    var h = w.routePoints.length.hashCode;
    h ^= w.trailPoints.length.hashCode * 17;
    h ^= w.markers.length.hashCode * 31;
    if (w.routePoints.isNotEmpty) {
      final p = w.routePoints.last;
      h ^= p.latitude.hashCode ^ p.longitude.hashCode;
    }
    if (w.trailPoints.isNotEmpty) {
      final p = w.trailPoints.last;
      h ^= p.latitude.hashCode ^ p.longitude.hashCode;
    }
    for (final m in w.markers) {
      h ^= m.point.latitude.hashCode * 3;
      h ^= m.point.longitude.hashCode * 5;
    }
    return h;
  }

  void _syncCamera() {
    if (!mounted || !_mapReady) return;

    final follow = widget.followTarget;
    if (follow != null && follow.latitude.isFinite && follow.longitude.isFinite) {
      _didOverviewFit = false;
      if (_lastFollow == null) {
        _lastFollow = follow;
        _controller.move(follow, widget.followZoom);
        return;
      }
      final moved = _distance.as(LengthUnit.Meter, _lastFollow!, follow);
      if (moved >= widget.followMinMoveMeters) {
        _lastFollow = follow;
        final z = _controller.camera.zoom;
        _controller.move(follow, z < 14 ? widget.followZoom : z);
      }
      return;
    }

    _lastFollow = null;

    final sig = _dataSignatureFor(widget);
    final dataChanged = sig != _lastDataSig;
    _lastDataSig = sig;

    final pts = _allPoints();
    if (pts.isEmpty) {
      _controller.move(_fallback, 13);
      return;
    }
    if (pts.length == 1) {
      _controller.move(pts.first, 14);
      _didOverviewFit = true;
      return;
    }
    final shouldRefit =
        (widget.refitBoundsWhenDataChanges && dataChanged) || !_didOverviewFit;
    if (shouldRefit) {
      final bounds = LatLngBounds.fromPoints(pts);
      if ((bounds.north - bounds.south).abs() < 0.0001 &&
          (bounds.east - bounds.west).abs() < 0.0001) {
        _controller.move(bounds.center, 14);
      } else {
        _controller.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(28),
          ),
        );
      }
      _didOverviewFit = true;
    }
  }

  @override
  void didUpdateWidget(OsmRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.followTarget != widget.followTarget ||
        _dataSignatureFor(oldWidget) != _dataSignatureFor(widget)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncCamera());
    }
  }

  @override
  Widget build(BuildContext context) {
    final map = FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: _fallback,
        initialZoom: 13,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
        onMapReady: () {
          if (!mounted) return;
          setState(() => _mapReady = true);
          WidgetsBinding.instance.addPostFrameCallback((_) => _syncCamera());
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          retinaMode: MediaQuery.of(context).devicePixelRatio > 1.0,
          userAgentPackageName: 'com.pocket.pocketshop',
          tileProvider: CachedTileProvider(),
        ),
        if (widget.trailPoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.trailPoints,
                strokeWidth: 4,
                color: const Color(0xFFA3AED0),
              ),
            ],
          ),
        if (widget.routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.routePoints,
                strokeWidth: 5,
                color: const Color(0xFF2563EB),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final m in widget.markers)
              if (m.point.latitude.isFinite && m.point.longitude.isFinite)
                Marker(
                point: m.point,
                width: m.useBadge ? 36 : 16,
                height: m.useBadge ? 36 : 16,
                alignment: Alignment.bottomCenter,
                child: m.useBadge
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: m.color.withValues(alpha: 0.55),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1A000000),
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(m.icon, color: m.color, size: m.size),
                      )
                    : Icon(m.icon, color: m.color, size: m.size),
              ),
          ],
        ),
      ],
    );

    final withControls = widget.showZoomControls
        ? Stack(
            children: [
              Positioned.fill(child: map),
              Positioned(
                right: 10,
                top: 82,
                child: Column(
                  children: [
                    _zoomBtn(
                      icon: Icons.add,
                      onTap: _mapReady ? () => _zoomBy(1.0) : null,
                    ),
                    const SizedBox(height: 6),
                    _zoomBtn(
                      icon: Icons.remove,
                      onTap: _mapReady ? () => _zoomBy(-1.0) : null,
                    ),
                  ],
                ),
              ),
            ],
          )
        : map;

    final sized = widget.expandVertically
        ? SizedBox.expand(child: withControls)
        : SizedBox(
            height: widget.height,
            width: double.infinity,
            child: withControls,
          );

    return ClipRRect(borderRadius: widget.clipBorderRadius, child: sized);
  }

  Widget _zoomBtn({required IconData icon, required VoidCallback? onTap}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      elevation: 2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 18,
            color: onTap == null ? const Color(0xFF9CA3AF) : Colors.black87,
          ),
        ),
      ),
    );
  }
}

class MapMarker {
  final LatLng point;
  final IconData icon;
  final Color color;
  final double size;
  final bool useBadge;

  const MapMarker({
    required this.point,
    this.icon = Icons.place,
    this.color = Colors.red,
    this.size = 22,
    this.useBadge = true,
  });
}
