import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/delivery_provider.dart';
import '../../../widgets/osm_route_map.dart';

class ActiveDeliveryScreen extends ConsumerStatefulWidget {
  const ActiveDeliveryScreen({super.key});

  @override
  ConsumerState<ActiveDeliveryScreen> createState() =>
      _ActiveDeliveryScreenState();
}

class _ActiveDeliveryScreenState extends ConsumerState<ActiveDeliveryScreen> {
  Map<String, dynamic>? _assignment;
  bool _loading = true;
  String? _error;
  bool _busy = false;
  Timer? _locationTimer;
  StreamSubscription<Position>? _positionSub;
  LatLng? _liveLatLng;
  bool _stepsLoading = false;
  String? _stepsError;
  List<_DirectionStep> _directionSteps = const [];
  int _currentStepIndex = 0;
  List<_RouteOption> _routeOptions = const [];
  int _selectedRouteIndex = 0;
  static final Distance _distance = Distance();
  bool _panelHidden = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _startLocationLoop();
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  void _bindLivePositionStream() {
    _positionSub?.cancel();
    _positionSub = null;
    if (!mounted) return;
    setState(() => _liveLatLng = null);

    final a = _assignment;
    if (a == null) return;
    final status = a['status']?.toString() ?? '';
    if (!['accepted', 'picked_up', 'in_transit'].contains(status)) {
      return;
    }

    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 8,
          ),
        ).listen((pos) {
          if (!mounted) return;
          setState(() {
            _liveLatLng = LatLng(pos.latitude, pos.longitude);
          });
          _syncCurrentStepFromLocation();
        }, onError: (_) {});
  }

  void _startLocationLoop() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _pushLocationIfPossible();
    });
  }

  int? _parseId(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  Future<void> _pushLocationIfPossible() async {
    final a = _assignment;
    if (a == null) return;
    final id = _parseId(a['id']);
    if (id == null) return;

    final status = a['status']?.toString() ?? '';
    if (!['accepted', 'picked_up', 'in_transit'].contains(status)) {
      return;
    }

    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      await ref
          .read(deliveryServiceProvider)
          .updateLocation(
            assignmentId: id,
            lat: pos.latitude,
            lng: pos.longitude,
            speed: pos.speed,
            accuracy: pos.accuracy,
          );
    } catch (_) {
      // Non-fatal; next tick will retry
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final svc = ref.read(deliveryServiceProvider);
      final a = await svc.fetchActiveAssignment();
      if (mounted) {
        setState(() {
          _assignment = a;
          _loading = false;
        });
        await _loadInAppDirections(a);
        _bindLivePositionStream();
        if (a != null) {
          _pushLocationIfPossible();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e is DioException
              ? ref.read(deliveryServiceProvider).extractErrorMessage(e)
              : e.toString();
        });
      }
    }
  }

  Future<void> _openDirections(LatLng? dest, LatLng? origin) async {
    if (dest == null) return;
    final q = StringBuffer('https://www.google.com/maps/dir/?api=1')
      ..write('&destination=${dest.latitude},${dest.longitude}')
      ..write('&travelmode=driving')
      ..write('&dir_action=navigate');
    if (origin != null) {
      q.write('&origin=${origin.latitude},${origin.longitude}');
    }
    final uri = Uri.parse(q.toString());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    final fallback = Uri.parse(
      'google.navigation:q=${dest.latitude},${dest.longitude}',
    );
    if (await canLaunchUrl(fallback)) {
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  LatLng? _loc(dynamic raw) {
    if (raw is Map) {
      final la = raw['lat'];
      final ln = raw['lng'];
      if (la != null && ln != null) {
        return LatLng((la as num).toDouble(), (ln as num).toDouble());
      }
    }
    return null;
  }

  Future<void> _setStatus(String next) async {
    final a = _assignment;
    if (a == null) return;
    final id = _parseId(a['id']);
    if (id == null) return;

    setState(() => _busy = true);
    try {
      final svc = ref.read(deliveryServiceProvider);
      final messenger = ScaffoldMessenger.of(context);
      final updated = await svc.updateAssignmentStatus(
        assignmentId: id,
        status: next,
        simulateQr: next == 'picked_up' || next == 'delivered',
      );
      if (mounted) {
        setState(() {
          _assignment = updated;
          _busy = false;
        });
        await _loadInAppDirections(updated);
        _bindLivePositionStream();
        if (next == 'delivered') {
          messenger.showSnackBar(
            const SnackBar(content: Text('Marked delivered')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        final msg = e is DioException
            ? ref.read(deliveryServiceProvider).extractErrorMessage(e)
            : e.toString();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg ?? 'Update failed')));
      }
    }
  }

  String? _nextActionLabel(String status) {
    switch (status) {
      case 'accepted':
        return 'Mark picked up';
      case 'picked_up':
        return 'Start trip (in transit)';
      case 'in_transit':
        return 'Mark delivered';
      default:
        return null;
    }
  }

  Future<void> _loadInAppDirections(Map<String, dynamic>? a) async {
    if (a == null) {
      if (!mounted) return;
      setState(() {
        _directionSteps = const [];
        _currentStepIndex = 0;
        _routeOptions = const [];
        _selectedRouteIndex = 0;
        _stepsLoading = false;
        _stepsError = null;
      });
      return;
    }

    final status = a['status']?.toString() ?? '';
    final pickup = _loc(a['pickup_location']);
    final drop = _loc(a['delivery_location']);
    final current = _liveLatLng ?? _loc(a['current_location']);

    LatLng? start;
    LatLng? end;
    if (status == 'accepted') {
      start = current ?? pickup;
      end = pickup;
    } else if (status == 'picked_up' || status == 'in_transit') {
      start = current ?? pickup;
      end = drop;
    } else {
      start = pickup;
      end = drop;
    }
    if (start == null || end == null) {
      if (!mounted) return;
      setState(() {
        _directionSteps = const [];
        _currentStepIndex = 0;
        _routeOptions = const [];
        _selectedRouteIndex = 0;
        _stepsLoading = false;
        _stepsError = null;
      });
      return;
    }

    setState(() {
      _stepsLoading = true;
      _stepsError = null;
    });
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://router.project-osrm.org',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );
      final response = await dio.get(
        '/route/v1/driving/'
        '${start.longitude},${start.latitude};${end.longitude},${end.latitude}',
        queryParameters: {
          'overview': 'full',
          'steps': 'true',
          'alternatives': 'true',
          'geometries': 'geojson',
        },
      );
      final data = response.data;
      final routes = (data is Map) ? data['routes'] : null;
      if (routes is! List || routes.isEmpty) {
        throw Exception('No route steps found.');
      }
      final builtOptions = <_RouteOption>[];
      for (final r in routes) {
        if (r is! Map) continue;
        final distanceM = (r['distance'] as num?)?.toDouble() ?? 0;
        final durationS = (r['duration'] as num?)?.toDouble() ?? 0;
        final geom = r['geometry'];
        final points = <LatLng>[];
        if (geom is Map) {
          final coords = geom['coordinates'];
          if (coords is List) {
            for (final c in coords) {
              if (c is List && c.length >= 2) {
                final lng = (c[0] as num?)?.toDouble();
                final lat = (c[1] as num?)?.toDouble();
                if (lat != null && lng != null) {
                  points.add(LatLng(lat, lng));
                }
              }
            }
          }
        }

        final legs = r['legs'];
        final out = <_DirectionStep>[];
        if (legs is List) {
          for (final leg in legs) {
            if (leg is! Map) continue;
            final steps = leg['steps'];
            if (steps is! List) continue;
            for (final s in steps) {
              if (s is! Map) continue;
              final maneuver = s['maneuver'];
              final type = maneuver is Map ? maneuver['type']?.toString() : '';
              final modifier =
                  maneuver is Map ? maneuver['modifier']?.toString() : '';
              final road = (s['name']?.toString() ?? '').trim();
              final dist = (s['distance'] as num?)?.toDouble() ?? 0;
              final act = _stepAction(type, modifier);
              final where = road.isEmpty ? '' : ' onto $road';
              LatLng? maneuverPoint;
              if (maneuver is Map) {
                final loc = maneuver['location'];
                if (loc is List && loc.length >= 2) {
                  final lng = (loc[0] as num?)?.toDouble();
                  final lat = (loc[1] as num?)?.toDouble();
                  if (lat != null && lng != null) {
                    maneuverPoint = LatLng(lat, lng);
                  }
                }
              }
              out.add(
                _DirectionStep(
                  instruction: '$act$where (${_fmtDistance(dist)})',
                  maneuverPoint: maneuverPoint,
                ),
              );
            }
          }
        }

        builtOptions.add(
          _RouteOption(
            distanceKm: distanceM / 1000,
            durationMin: (durationS / 60).round(),
            points: points,
            steps: out,
          ),
        );
      }
      if (builtOptions.isEmpty) {
        throw Exception('No usable route options.');
      }
      if (!mounted) return;
      setState(() {
        _routeOptions = builtOptions;
        _selectedRouteIndex = 0;
        _directionSteps = builtOptions.first.steps;
        _currentStepIndex = 0;
        _stepsLoading = false;
      });
      _syncCurrentStepFromLocation();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stepsLoading = false;
        _directionSteps = const [];
        _currentStepIndex = 0;
        _routeOptions = const [];
        _selectedRouteIndex = 0;
        _stepsError = 'Could not load in-app directions.';
      });
    }
  }

  void _selectRouteOption(int index) {
    if (index < 0 || index >= _routeOptions.length) return;
    setState(() {
      _selectedRouteIndex = index;
      _directionSteps = _routeOptions[index].steps;
      _currentStepIndex = 0;
    });
    _syncCurrentStepFromLocation();
  }

  void _syncCurrentStepFromLocation() {
    if (!mounted || _directionSteps.isEmpty || _liveLatLng == null) return;
    var bestIdx = _currentStepIndex;
    var bestDist = double.infinity;
    for (var i = _currentStepIndex; i < _directionSteps.length; i++) {
      final p = _directionSteps[i].maneuverPoint;
      if (p == null) continue;
      final d = _distance.as(LengthUnit.Meter, _liveLatLng!, p);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    if (bestIdx != _currentStepIndex) {
      setState(() => _currentStepIndex = bestIdx);
    }
  }

  String _stepAction(String? type, String? modifier) {
    final t = (type ?? '').trim();
    final m = (modifier ?? '').trim();
    if (t == 'depart') return 'Start';
    if (t == 'arrive') return 'Arrive';
    if (t == 'turn') {
      if (m.isNotEmpty) return 'Turn $m';
      return 'Turn';
    }
    if (t == 'roundabout') return 'Enter roundabout';
    if (t == 'new name') return 'Continue';
    if (t == 'merge') return 'Merge';
    return t.isEmpty ? 'Continue' : 'Continue';
  }

  String _fmtDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  void _openStepsSheet() {
    if (_directionSteps.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            const Text(
              'In-app directions',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Step ${_currentStepIndex + 1} of ${_directionSteps.length}',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemBuilder: (_, i) {
                  final isCurrent = i == _currentStepIndex;
                  return Container(
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? AppTheme.lightCyan.withValues(alpha: 0.35)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor:
                            isCurrent ? AppTheme.primaryCyan : AppTheme.lightCyan,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isCurrent
                                ? Colors.white
                                : AppTheme.darkCyan,
                          ),
                        ),
                      ),
                      title: Text(
                        _directionSteps[i].instruction,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      trailing: isCurrent
                          ? const Text(
                              'Next',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.darkCyan,
                              ),
                            )
                          : null,
                    ),
                  );
                },
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemCount: _directionSteps.length,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _nextStatus(String status) {
    switch (status) {
      case 'accepted':
        return 'picked_up';
      case 'picked_up':
        return 'in_transit';
      case 'in_transit':
        return 'delivered';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryCyan),
              )
            : _error != null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.error),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              )
            : _assignment == null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.local_shipping_outlined,
                      size: 48,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No active delivery',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Accept an order from Home to start.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => context.go('/delivery/home'),
                      child: const Text('View available orders'),
                    ),
                  ],
                ),
              )
            : _buildActiveBody(_assignment!),
      ),
    );
  }

  Widget _buildActiveBody(Map<String, dynamic> a) {
    final pickup = _loc(a['pickup_location']);
    final drop = _loc(a['delivery_location']);
    final serverCurrent = _loc(a['current_location']);
    final you = _liveLatLng ?? serverCurrent;
    final routeRaw = a['route_coordinates'];
    final serverRoutePoints = OsmRouteMap.coordsFromJson(routeRaw);
    final routePoints = _routeOptions.isNotEmpty &&
            _selectedRouteIndex < _routeOptions.length &&
            _routeOptions[_selectedRouteIndex].points.isNotEmpty
        ? _routeOptions[_selectedRouteIndex].points
        : serverRoutePoints;

    final markers = <MapMarker>[
      if (pickup != null)
        MapMarker(point: pickup, icon: Icons.store, color: AppTheme.darkCyan),
      if (drop != null)
        MapMarker(point: drop, icon: Icons.home, color: AppTheme.success),
      if (you != null)
        MapMarker(
          point: you,
          icon: Icons.navigation,
          color: AppTheme.primaryCyan,
        ),
    ];

    final status = a['status']?.toString() ?? '';
    final orderNo = a['order_number']?.toString() ?? '';
    final buyerPhone = a['buyer_phone']?.toString() ?? '';
    final addr = a['delivery_address']?.toString() ?? '';
    final distM = a['route_distance_m'];
    final durS = a['route_duration_s'];
    final routeSource = a['route_source']?.toString();
    final routeConfidence =
        double.tryParse((a['route_confidence'] ?? '').toString());
    final etaMinutes =
        int.tryParse((a['estimated_duration'] ?? '').toString());

    String? routeMeta;
    if (distM != null && durS != null) {
      final km = (distM as num) / 1000;
      final min = ((durS as num) / 60).round();
      routeMeta =
          'Route ~${km.toStringAsFixed(1)} km · ~$min min (OSRM estimate)';
    }

    final nextLabel = _nextActionLabel(status);
    final next = _nextStatus(status);
    final nextNavTarget = status == 'accepted' ? pickup : drop;
    final nextNavLabel = status == 'accepted'
        ? 'pickup'
        : 'drop-off';

    return Stack(
      children: [
        Positioned.fill(
          child: OsmRouteMap(
            key: ValueKey(_parseId(a['id']) ?? 0),
            routePoints: routePoints,
            markers: markers,
            expandVertically: true,
            clipBorderRadius: BorderRadius.zero,
            showZoomControls: true,
            followTarget: you,
            refitBoundsWhenDataChanges: _liveLatLng == null,
            followMinMoveMeters: 6,
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Active delivery',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _load,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                ),
                icon: const Icon(Icons.refresh),
                color: Colors.white,
              ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 10,
          child: _panelHidden
              ? const SizedBox.shrink()
              : Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (routeMeta != null)
                  Text(
                    routeMeta,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                if (etaMinutes != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _etaLabel(etaMinutes, routeConfidence),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: routeConfidence != null && routeConfidence < 0.55
                          ? AppTheme.warning
                          : AppTheme.darkCyan,
                    ),
                  ),
                ],
                if (routeSource != null || routeConfidence != null) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (routeSource != null)
                        _infoChip(
                          _sourceLabel(routeSource),
                          AppTheme.darkCyan,
                          Icons.route_rounded,
                        ),
                      if (routeConfidence != null)
                        _infoChip(
                          _confidenceLabel(routeConfidence),
                          _confidenceColor(routeConfidence),
                          Icons.verified_rounded,
                        ),
                    ],
                  ),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        orderNo,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Hide panel',
                      onPressed: () =>
                          setState(() => _panelHidden = true),
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                      ),
                    ),
                  ],
                ),
                if (_routeOptions.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _routeOptions.length && i < 3; i++)
                        _routeChip(i, _routeOptions[i]),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Status: $status',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.darkCyan,
                  ),
                ),
                if (addr.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Deliver to: $addr',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
                if (buyerPhone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Customer: $buyerPhone',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (pickup != null)
                      OutlinedButton.icon(
                        onPressed: () => _openDirections(pickup, you),
                        icon: const Icon(Icons.directions, size: 17),
                        label: const Text('Pickup'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    if (drop != null)
                      OutlinedButton.icon(
                        onPressed: () => _openDirections(drop, you),
                        icon: const Icon(Icons.place_outlined, size: 17),
                        label: const Text('Drop-off'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_stepsLoading)
                  const LinearProgressIndicator(color: AppTheme.primaryCyan)
                else if (_stepsError != null)
                  Text(
                    _stepsError!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.warning,
                    ),
                  )
                else if (_directionSteps.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'In-app directions',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Step ${_currentStepIndex + 1}/${_directionSteps.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.darkCyan,
                        ),
                      ),
                      const SizedBox(height: 2),
                      ..._directionSteps
                          .skip(_currentStepIndex)
                          .take(2)
                          .map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '• ${s.instruction}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      if (_directionSteps.length - _currentStepIndex > 2)
                        Text(
                          '+ ${_directionSteps.length - _currentStepIndex - 2} more steps',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      TextButton(
                        onPressed: _openStepsSheet,
                        child: const Text('View full in-app directions'),
                      ),
                    ],
                  ),
                if (_directionSteps.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openStepsSheet,
                      icon: const Icon(Icons.route_rounded, size: 18),
                      label: Text('Start in-app guidance to $nextNavLabel'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                    ),
                  ),
                ],
                if (nextNavTarget != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openDirections(nextNavTarget, you),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text('Fallback: Open Google Maps ($nextNavLabel)'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 38),
                      ),
                    ),
                  ),
                ],
                if (next != null && nextLabel != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : () => _setStatus(next),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 42),
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(nextLabel),
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  _liveLatLng != null
                      ? 'Live: map follows your GPS.'
                      : 'Waiting for GPS...',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_panelHidden)
          Positioned(
            right: 14,
            bottom: 18,
            child: FloatingActionButton.small(
              heroTag: 'expand_active_panel',
              onPressed: () => setState(() => _panelHidden = false),
              backgroundColor: Colors.white.withValues(alpha: 0.92),
              foregroundColor: AppTheme.textPrimary,
              child: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
          ),
      ],
    );
  }

  Widget _routeChip(int index, _RouteOption route) {
    final selected = index == _selectedRouteIndex;
    return InkWell(
      onTap: () => _selectRouteOption(index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryCyan.withValues(alpha: 0.18)
              : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.primaryCyan : AppTheme.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_car_filled_rounded,
              size: 14,
              color: selected ? AppTheme.darkCyan : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              '${route.durationMin} min',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? AppTheme.darkCyan : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${route.distanceKm.toStringAsFixed(1)} km',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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

  String _confidenceLabel(double score) {
    if (score >= 0.8) return 'High confidence';
    if (score >= 0.55) return 'Moderate confidence';
    return 'Low confidence';
  }

  Color _confidenceColor(double score) {
    if (score >= 0.8) return AppTheme.success;
    if (score >= 0.55) return AppTheme.warning;
    return AppTheme.error;
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

class _DirectionStep {
  final String instruction;
  final LatLng? maneuverPoint;

  const _DirectionStep({
    required this.instruction,
    this.maneuverPoint,
  });
}

class _RouteOption {
  final double distanceKm;
  final int durationMin;
  final List<LatLng> points;
  final List<_DirectionStep> steps;

  const _RouteOption({
    required this.distanceKm,
    required this.durationMin,
    required this.points,
    required this.steps,
  });
}
