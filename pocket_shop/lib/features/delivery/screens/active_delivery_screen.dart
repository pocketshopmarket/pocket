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
import '../../../widgets/qr_scanner_sheet.dart';

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
  final List<_OfflineLocation> _locationQueue = [];
  bool _stepsLoading = false;
  String? _stepsError;
  List<_DirectionStep> _directionSteps = const [];
  int _currentStepIndex = 0;
  List<_RouteOption> _routeOptions = const [];
  int _selectedRouteIndex = 0;
  static final Distance _distance = Distance();
  bool _panelHidden = false;
  bool _followLocked = true;
  bool _offRoute = false;

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
    if (!['accepted', 'picked_up', 'in_transit'].contains(status)) return;

    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      final svc = ref.read(deliveryServiceProvider);

      // Flush queued offline pings before the live one
      if (_locationQueue.isNotEmpty) {
        final queued = List<_OfflineLocation>.from(_locationQueue);
        _locationQueue.clear();
        for (final q in queued) {
          try {
            await svc.updateLocation(
              assignmentId: q.assignmentId,
              lat: q.lat,
              lng: q.lng,
            );
          } catch (_) {
            _locationQueue.insert(0, q);
            return; // still offline — try again next tick
          }
        }
      }

      await svc.updateLocation(
        assignmentId: id,
        lat: pos.latitude,
        lng: pos.longitude,
        speed: pos.speed,
        accuracy: pos.accuracy,
      );
    } catch (_) {
      // Queue the last known position for the next successful push (cap at 5)
      final pos = _liveLatLng;
      if (pos != null && _locationQueue.length < 5) {
        _locationQueue.add(_OfflineLocation(id, pos.latitude, pos.longitude));
      }
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
        simulateQr: false,
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
            const SnackBar(
              content: Text('Delivery complete! Great job.'),
              backgroundColor: AppTheme.success,
              duration: Duration(seconds: 2),
            ),
          );
          await Future.delayed(const Duration(milliseconds: 1800));
          if (mounted) context.go('/delivery/home');
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

  Future<void> _verifyPickupQrAndContinue() async {
    final a = _assignment;
    if (a == null) return;
    final id = _parseId(a['id']);
    if (id == null) return;

    final scanned = await QrScannerSheet.scan(
      context,
      title: 'Scan seller QR',
      instruction: 'Point the camera at the seller\'s identity QR code to confirm pickup.',
    );
    if (scanned == null || scanned.isEmpty) return;

    setState(() => _busy = true);
    try {
      final svc = ref.read(deliveryServiceProvider);
      final result = await svc.verifyIdentityQR(
        assignmentId: id,
        step: 'pickup',
        qrData: scanned,
      );
      if (!mounted) return;
      final verified = result['verified'] == true || result['success'] == true;
      if (!verified && result.isNotEmpty) {
        setState(() => _busy = false);
        final errMsg = result['error']?.toString() ??
            result['message']?.toString() ??
            'Could not verify seller QR. Try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errMsg), backgroundColor: AppTheme.error),
        );
        return;
      }
      setState(() => _busy = false);
      if (!mounted) return;
      await _showScanSuccess(
        icon: Icons.store_rounded,
        color: AppTheme.primaryCyan,
        title: 'Pickup confirmed!',
        subtitle: 'Seller QR verified. The order is now with you.',
        action: 'Continue',
      );
      if (!mounted) return;
      await _setStatus('picked_up');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e is DioException
          ? ref.read(deliveryServiceProvider).extractErrorMessage(e)
          : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg ?? 'Could not verify pickup QR'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _verifyDropoffTokenDialog() async {
    final a = _assignment;
    if (a == null) return;
    final id = _parseId(a['id']);
    if (id == null) return;

    final scanned = await QrScannerSheet.scan(
      context,
      title: 'Scan buyer QR',
      instruction: 'Point the camera at the buyer\'s identity QR code to confirm delivery.',
    );
    if (scanned == null || scanned.isEmpty) return;

    setState(() => _busy = true);
    try {
      final svc = ref.read(deliveryServiceProvider);
      final result = await svc.verifyIdentityQR(
        assignmentId: id,
        step: 'dropoff',
        qrData: scanned,
      );
      if (!mounted) return;
      final verified = result['verified'] == true || result['success'] == true;
      if (!verified && result.isNotEmpty) {
        setState(() => _busy = false);
        final errMsg = result['error']?.toString() ??
            result['message']?.toString() ??
            'Could not verify buyer QR. Try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errMsg), backgroundColor: AppTheme.error),
        );
        return;
      }
      setState(() => _busy = false);
      if (!mounted) return;
      await _showScanSuccess(
        icon: Icons.check_circle_rounded,
        color: AppTheme.success,
        title: 'Delivery confirmed!',
        subtitle: 'Buyer QR verified. Order marked as delivered.',
        action: 'Done',
      );
      if (!mounted) return;
      await _setStatus('delivered');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e is DioException
          ? ref.read(deliveryServiceProvider).extractErrorMessage(e)
          : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg ?? 'Could not verify dropoff QR'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _showScanSuccess({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String action,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 42, color: color),
            ),
            const SizedBox(height: 18),
            Text(title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.5)),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(action, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _nextActionLabel(String status) {
    switch (status) {
      case 'accepted':
        return 'Scan seller pickup QR';
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
                  instruction: '$act$where',
                  distanceMeters: dist,
                  maneuverType: type,
                  maneuverModifier: modifier,
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
    _checkOffRoute();
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

  IconData _maneuverIcon(String? type, String? modifier) {
    final t = (type ?? '').trim();
    final m = (modifier ?? '').trim();
    if (t == 'depart') return Icons.my_location_rounded;
    if (t == 'arrive') return Icons.flag_rounded;
    if (t == 'roundabout' || t == 'rotary') return Icons.rotate_right_rounded;
    if (t == 'merge') return Icons.merge_rounded;
    if (t == 'fork') {
      return (m == 'left' || m == 'slight left')
          ? Icons.fork_left_rounded
          : Icons.fork_right_rounded;
    }
    if (t == 'turn') {
      switch (m) {
        case 'left':
          return Icons.turn_left_rounded;
        case 'right':
          return Icons.turn_right_rounded;
        case 'sharp left':
          return Icons.turn_sharp_left_rounded;
        case 'sharp right':
          return Icons.turn_sharp_right_rounded;
        case 'slight left':
          return Icons.turn_slight_left_rounded;
        case 'slight right':
          return Icons.turn_slight_right_rounded;
        case 'uturn':
          return Icons.u_turn_left_rounded;
      }
    }
    return Icons.straight_rounded;
  }

  void _checkOffRoute() {
    if (_liveLatLng == null || _routeOptions.isEmpty) {
      if (_offRoute) setState(() => _offRoute = false);
      return;
    }
    final pts = _selectedRouteIndex < _routeOptions.length
        ? _routeOptions[_selectedRouteIndex].points
        : <LatLng>[];
    if (pts.isEmpty) {
      if (_offRoute) setState(() => _offRoute = false);
      return;
    }
    var minDist = double.infinity;
    for (final p in pts) {
      final d = _distance.as(LengthUnit.Meter, _liveLatLng!, p);
      if (d < minDist) {
        minDist = d;
        if (minDist < 50) break;
      }
    }
    final nowOff = minDist > 100;
    if (nowOff != _offRoute) {
      setState(() => _offRoute = nowOff);
      if (nowOff) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _offRoute) _loadInAppDirections(_assignment);
        });
      }
    }
  }

  Widget _stepRow(_DirectionStep s, bool isCurrent) {
    final distLabel =
        s.distanceMeters > 0 ? 'In ${_fmtDistance(s.distanceMeters)}' : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _maneuverIcon(s.maneuverType, s.maneuverModifier),
          size: 16,
          color: isCurrent ? AppTheme.darkCyan : AppTheme.textSecondary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (distLabel != null)
                Text(
                  distLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color:
                        isCurrent ? AppTheme.primaryCyan : AppTheme.textSecondary,
                  ),
                ),
              Text(
                s.instruction,
                style: TextStyle(
                  fontSize: 12,
                  color: isCurrent ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontWeight:
                      isCurrent ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
                        child: Icon(
                          _maneuverIcon(
                            _directionSteps[i].maneuverType,
                            _directionSteps[i].maneuverModifier,
                          ),
                          size: 13,
                          color: isCurrent ? Colors.white : AppTheme.darkCyan,
                        ),
                      ),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_directionSteps[i].distanceMeters > 0)
                            Text(
                              'In ${_fmtDistance(_directionSteps[i].distanceMeters)}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.darkCyan,
                              ),
                            ),
                          Text(
                            _directionSteps[i].instruction,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  isCurrent ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
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
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryCyan.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delivery_dining_rounded,
                          size: 52,
                          color: AppTheme.primaryCyan,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'No active delivery',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'You have no delivery in progress.\nHead to the home tab to find nearby orders.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.5),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => context.go('/delivery/home'),
                          icon: const Icon(Icons.search_rounded),
                          label: const Text('Find available orders'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryCyan,
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
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

    final nextManeuverStep =
        _directionSteps.isNotEmpty && _currentStepIndex < _directionSteps.length
            ? _directionSteps[_currentStepIndex]
            : null;
    final alternativeRoutes = [
      for (var i = 0; i < _routeOptions.length; i++)
        if (i != _selectedRouteIndex && _routeOptions[i].points.isNotEmpty)
          _routeOptions[i].points,
    ];
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
      if (nextManeuverStep?.maneuverPoint != null)
        MapMarker(
          point: nextManeuverStep!.maneuverPoint!,
          icon: _maneuverIcon(
            nextManeuverStep.maneuverType,
            nextManeuverStep.maneuverModifier,
          ),
          color: AppTheme.warning,
          size: 18,
        ),
    ];

    final status = a['status']?.toString() ?? '';
    final orderNo = a['order_number']?.toString() ?? '';
    final buyerPhone = a['buyer_phone']?.toString() ?? '';
    final sellerPhone = a['seller_phone']?.toString() ?? '';
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
            alternativeRoutes: alternativeRoutes,
            markers: markers,
            expandVertically: true,
            clipBorderRadius: BorderRadius.zero,
            showZoomControls: true,
            followTarget: _followLocked ? you : null,
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
        if (_offRoute)
          Positioned(
            top: 70,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Off route — recalculating...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          top: 170,
          right: 10,
          child: FloatingActionButton.small(
            heroTag: 'follow_lock',
            onPressed: () => setState(() => _followLocked = !_followLocked),
            backgroundColor: _followLocked
                ? AppTheme.primaryCyan.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.9),
            foregroundColor: _followLocked ? Colors.white : AppTheme.textSecondary,
            child: Icon(
              _followLocked ? Icons.gps_fixed : Icons.gps_not_fixed,
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 10,
          child: IgnorePointer(
            ignoring: _panelHidden,
            child: AnimatedSlide(
              offset: _panelHidden ? const Offset(0, 1.5) : Offset.zero,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.65,
                ),
                child: Container(
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
            child: SingleChildScrollView(
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryCyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _humanStatus(status),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.darkCyan,
                    ),
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
                if (buyerPhone.isNotEmpty || sellerPhone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (buyerPhone.isNotEmpty)
                        TextButton.icon(
                          onPressed: () async {
                            final uri = Uri(scheme: 'tel', path: buyerPhone);
                            if (await canLaunchUrl(uri)) await launchUrl(uri);
                          },
                          icon: const Icon(Icons.call_outlined, size: 16),
                          label: const Text('Call buyer'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      if (sellerPhone.isNotEmpty)
                        TextButton.icon(
                          onPressed: () async {
                            final uri = Uri(scheme: 'tel', path: sellerPhone);
                            if (await canLaunchUrl(uri)) await launchUrl(uri);
                          },
                          icon: const Icon(Icons.call_outlined, size: 16),
                          label: const Text('Call seller'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
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
                      for (var i = _currentStepIndex;
                          i < _directionSteps.length &&
                              i < _currentStepIndex + 2;
                          i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _stepRow(
                            _directionSteps[i],
                            i == _currentStepIndex,
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
                if (_directionSteps.isNotEmpty || nextNavTarget != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (_directionSteps.isNotEmpty)
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _openStepsSheet,
                            icon: const Icon(Icons.route_rounded, size: 16),
                            label: Text('In-app ($nextNavLabel)'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 38),
                            ),
                          ),
                        ),
                      if (_directionSteps.isNotEmpty && nextNavTarget != null)
                        const SizedBox(width: 8),
                      if (nextNavTarget != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _openDirections(nextNavTarget, you),
                            icon: const Icon(Icons.map_outlined, size: 16),
                            label: const Text('Google Maps'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 38),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (status == 'in_transit' || status == 'picked_up') ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _verifyDropoffTokenDialog,
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                      label: const Text('Verify dropoff QR from buyer'),
                    ),
                  ),
                ],
                if (next != null && nextLabel != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy
                          ? null
                          : () {
                              if (status == 'accepted' && next == 'picked_up') {
                                _verifyPickupQrAndContinue();
                                return;
                              }
                              _setStatus(next);
                            },
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
              ),
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

  String _humanStatus(String status) {
    switch (status) {
      case 'accepted':
        return 'Accepted — head to pickup';
      case 'picked_up':
        return 'Picked up — heading to customer';
      case 'in_transit':
        return 'In transit';
      case 'delivered':
        return 'Delivered';
      default:
        return status.replaceAll('_', ' ');
    }
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

class _OfflineLocation {
  final int assignmentId;
  final double lat;
  final double lng;
  const _OfflineLocation(this.assignmentId, this.lat, this.lng);
}

class _DirectionStep {
  final String instruction;
  final double distanceMeters;
  final String? maneuverType;
  final String? maneuverModifier;
  final LatLng? maneuverPoint;

  const _DirectionStep({
    required this.instruction,
    this.distanceMeters = 0,
    this.maneuverType,
    this.maneuverModifier,
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
