import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../../../../core/user_facing_exception.dart';
import '../../../auth/data/auth_repository.dart';
import '../../data/driver_repository.dart';
import '../controllers/driver_controller.dart';
import 'driver_drawer.dart';

class _OsrmStep {
  final LatLng location;
  final String instruction;
  final double distance;
  final double duration;

  const _OsrmStep({
    required this.location,
    required this.instruction,
    required this.distance,
    required this.duration,
  });
}

class _OsrmRouteData {
  final List<LatLng> points;
  final double distance;
  final double duration;
  final List<_OsrmStep> steps;

  const _OsrmRouteData({
    required this.points,
    required this.distance,
    required this.duration,
    required this.steps,
  });
}

class DriverMapScreen extends ConsumerStatefulWidget {
  const DriverMapScreen({super.key});

  @override
  ConsumerState<DriverMapScreen> createState() => _DriverMapScreenState();
}

class _DriverMapScreenState extends ConsumerState<DriverMapScreen> {
  final MapController _mapController = MapController();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const LatLng _kDefaultCenter = LatLng(24.7136, 46.6753);
  static const double _kDefaultZoom = 14.4746;
  static const double _kSheetHeight = 260;
  static const String _kOsrmProfile = 'driving';
  static const String _kGoogleTravelMode = 'bicycling';

  ProviderSubscription<AsyncValue<DriverState>>? _driverStateSubscription;
  ProviderSubscription<AsyncValue<List<Map<String, dynamic>>>>?
      _availableOrdersSubscription;
  ProviderSubscription<AsyncValue<Map<String, dynamic>?>>?
      _activeOrderSubscription;
  bool _isMapReady = false;
  LatLng? _pendingMoveCenter;
  double? _pendingMoveZoom;
  LatLng _lastCenter = _kDefaultCenter;
  double _lastZoom = _kDefaultZoom;
  bool _hasTileLoadError = false;
  int? _lastNotifiedOrderId;
  final Map<int, int> _lastNotifiedResendCount = <int, int>{};
  int? _incomingSheetOrderId;
  int? _lastHandledActiveOrderId;
  String? _lastHandledActiveOrderStatus;

  List<LatLng> _pickupRoutePoints = <LatLng>[];
  List<LatLng> _dropoffRoutePoints = <LatLng>[];
  List<_OsrmRouteData> _pickupRoutes = <_OsrmRouteData>[];
  List<_OsrmRouteData> _dropoffRoutes = <_OsrmRouteData>[];
  int _selectedPickupRouteIndex = 0;
  int _selectedDropoffRouteIndex = 0;
  String? _pickupNextInstruction;
  String? _dropoffNextInstruction;
  LatLng? _lastPickupFrom;
  LatLng? _lastPickupTo;
  LatLng? _lastDropoffFrom;
  LatLng? _lastDropoffTo;
  DateTime? _lastPickupFetchAt;
  DateTime? _lastDropoffFetchAt;
  bool _isFetchingPickupRoute = false;
  bool _isFetchingDropoffRoute = false;
  bool _pickupRouteFetchFailed = false;
  bool _dropoffRouteFetchFailed = false;
  Map<String, dynamic>? _optimisticOrderOverride;
  DateTime? _optimisticOrderOverrideUntil;
  final Map<int, LatLng> _resolvedBranchLocations = <int, LatLng>{};
  final Map<int, LatLng> _resolvedCustomerLocations = <int, LatLng>{};
  final Map<int, DateTime> _branchGeocodeAttemptAt = <int, DateTime>{};
  final Map<int, DateTime> _customerGeocodeAttemptAt = <int, DateTime>{};
  bool _isGeocodingBranch = false;
  bool _isGeocodingCustomer = false;
  DateTime? _lastGeocodeAt;

  bool _isWithinSchedule(List<Map<String, dynamic>> slots, DateTime now) {
    final activeSlots = slots.where((s) => s['is_active'] == true).toList();
    if (activeSlots.isEmpty) return true;

    final dayOfWeek = now.weekday % 7;
    final nowMin = (now.hour * 60) + now.minute;

    for (final s in activeSlots) {
      if ((s['day_of_week'] as num?)?.toInt() != dayOfWeek) continue;
      final startMin = (s['start_min'] as num?)?.toInt();
      final endMin = (s['end_min'] as num?)?.toInt();
      if (startMin == null || endMin == null) continue;
      if (nowMin >= startMin && nowMin < endMin) return true;
    }
    return false;
  }

  Future<void> _openExternalNavigation(
      {double? lat, double? lng, String? address}) async {
    if (kIsWeb) return;
    Uri? uri;
    if (lat != null && lng != null) {
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=$_kGoogleTravelMode');
    } else if (address != null && address.trim().isNotEmpty) {
      uri = Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': address.trim(),
        'travelmode': _kGoogleTravelMode
      });
    }
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _sanitizePhone(String phone) {
    final raw = phone.trim();
    if (raw.isEmpty) return '';

    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final c = raw[i];
      if ((c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) || c == '+') {
        buffer.write(c);
      }
    }

    var cleaned = buffer.toString();
    if (cleaned.startsWith('00')) cleaned = '+${cleaned.substring(2)}';
    if (cleaned == '+') return '';
    return cleaned;
  }

  String _phoneForWaMe(String phone) {
    var p = _sanitizePhone(phone);
    if (p.isEmpty) return '';
    if (p.startsWith('+')) p = p.substring(1);
    return p;
  }

  Future<void> _openPhoneDialer(String phone) async {
    if (kIsWeb) return;
    final p = _sanitizePhone(phone);
    if (p.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: p);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openWhatsApp(String phone) async {
    if (kIsWeb) return;
    final p = _phoneForWaMe(phone);
    if (p.isEmpty) return;

    final appUri = Uri.parse('whatsapp://send?phone=$p');
    if (await canLaunchUrl(appUri)) {
      await launchUrl(appUri, mode: LaunchMode.externalApplication);
      return;
    }

    final webUri = Uri.parse('https://wa.me/$p');
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  double? _doubleFromDynamic(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final cleaned = value.trim();
      if (cleaned.isEmpty) return null;
      final normalized = cleaned.replaceAll(',', '.');
      return double.tryParse(normalized);
    }
    return null;
  }

  LatLng? _latLngFromOrder(
    Map<String, dynamic> order, {
    required List<String> latKeys,
    required List<String> lngKeys,
  }) {
    double? lat;
    for (final k in latKeys) {
      lat = _doubleFromDynamic(order[k]);
      if (lat != null) break;
    }
    double? lng;
    for (final k in lngKeys) {
      lng = _doubleFromDynamic(order[k]);
      if (lng != null) break;
    }
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  String? _trimString(Object? value) {
    if (value == null) return null;
    return value.toString().trim();
  }

  int _resendCountFromOrder(Map<String, dynamic> order) {
    final customer = _mapFromDynamic(order['customer_details']);
    return (customer['resend_count'] as num?)?.toInt() ?? 0;
  }

  Map<String, dynamic> _mapFromDynamic(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  String? _branchQueryFromOrder(Map<String, dynamic> order) {
    final addr = _trimString(order['branch_address']);
    if (addr != null && addr.isNotEmpty) return addr;
    final restaurant = _trimString(order['restaurant_name']);
    final branch = _trimString(order['branch_name']);
    final parts = <String>[
      if (restaurant != null && restaurant.isNotEmpty) restaurant,
      if (branch != null && branch.isNotEmpty) branch,
    ];
    if (parts.isEmpty) return null;
    final q = parts.join(' ');
    return q.isEmpty ? null : q;
  }

  String? _customerQueryFromOrder(Map<String, dynamic> order) {
    final customer = _mapFromDynamic(order['customer_details']);
    final addr = _trimString(customer['address']);
    if (addr != null && addr.isNotEmpty) return addr;
    return null;
  }

  Future<LatLng?> _geocodeAddress(String address) async {
    final q = address.trim();
    if (q.isEmpty) return null;
    if (_lastGeocodeAt != null) {
      final elapsed = DateTime.now().difference(_lastGeocodeAt!);
      if (elapsed.inMilliseconds < 900) {
        await Future<void>.delayed(
            Duration(milliseconds: 900 - elapsed.inMilliseconds));
      }
    }
    _lastGeocodeAt = DateTime.now();

    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      <String, String>{'format': 'jsonv2', 'limit': '1', 'q': q},
    );
    try {
      final response = await http.get(
        uri,
        headers: const <String, String>{
          'User-Agent': 'naemi_team (flutter)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) return null;
      final first = decoded.first;
      if (first is! Map) return null;
      final lat = _doubleFromDynamic(first['lat']);
      final lon = _doubleFromDynamic(first['lon']);
      if (lat == null || lon == null) return null;
      return LatLng(lat, lon);
    } catch (_) {
      return null;
    }
  }

  Future<void> _maybeResolveBranchLocation({
    required int orderId,
    required String? address,
    required LatLng? driverLocation,
    required bool focus,
  }) async {
    if (_resolvedBranchLocations.containsKey(orderId)) return;
    final lastAttempt = _branchGeocodeAttemptAt[orderId];
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt).inSeconds < 20) return;
    final addr = address?.trim() ?? '';
    if (addr.isEmpty) return;
    if (_isGeocodingBranch) return;
    _isGeocodingBranch = true;
    _branchGeocodeAttemptAt[orderId] = DateTime.now();
    try {
      final loc = await _geocodeAddress(addr);
      if (!mounted) return;
      if (loc == null) return;
      setState(() {
        _resolvedBranchLocations[orderId] = loc;
      });
      if (focus) _moveTo(loc, zoom: 16);
      if (driverLocation != null) {
        unawaited(_maybeRefreshPickupRoute(driverLocation, loc));
        _updatePickupGuidance(driverLocation);
      }
    } finally {
      _isGeocodingBranch = false;
    }
  }

  Future<void> _maybeResolveCustomerLocation({
    required int orderId,
    required String? address,
    required LatLng? driverLocation,
    required bool focus,
  }) async {
    if (_resolvedCustomerLocations.containsKey(orderId)) return;
    final lastAttempt = _customerGeocodeAttemptAt[orderId];
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt).inSeconds < 20) return;
    final addr = address?.trim() ?? '';
    if (addr.isEmpty) return;
    if (_isGeocodingCustomer) return;
    _isGeocodingCustomer = true;
    _customerGeocodeAttemptAt[orderId] = DateTime.now();
    try {
      final loc = await _geocodeAddress(addr);
      if (!mounted) return;
      if (loc == null) return;
      setState(() {
        _resolvedCustomerLocations[orderId] = loc;
      });
      if (focus) _moveTo(loc, zoom: 16);
      if (driverLocation != null) {
        unawaited(_maybeRefreshDropoffRoute(driverLocation, loc));
        _updateDropoffGuidance(driverLocation);
      }
    } finally {
      _isGeocodingCustomer = false;
    }
  }

  double _metersBetween(LatLng a, LatLng b) {
    return const Distance().as(LengthUnit.Meter, a, b);
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      final km = meters / 1000.0;
      return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} كم';
    }
    return '${meters.round()} م';
  }

  String _formatDuration(double seconds) {
    final totalMinutes = (seconds / 60).round();
    if (totalMinutes < 60) return '$totalMinutes د';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return m == 0 ? '$h س' : '$h س $m د';
  }

  double _distanceToPolylineMeters(LatLng point, List<LatLng> polylinePoints) {
    if (polylinePoints.isEmpty) return double.infinity;
    final step =
        (polylinePoints.length / 120).ceil().clamp(1, polylinePoints.length);
    var best = double.infinity;
    for (var i = 0; i < polylinePoints.length; i += step) {
      final d = _metersBetween(point, polylinePoints[i]);
      if (d < best) best = d;
    }
    return best;
  }

  String _buildArabicInstruction({
    required String? type,
    required String? modifier,
    required String? name,
  }) {
    final t = type ?? '';
    final m = modifier ?? '';
    String base;
    if (t == 'depart') {
      base = 'انطلق';
    } else if (t == 'arrive') {
      base = 'وصلت إلى وجهتك';
    } else if (t == 'roundabout') {
      base = 'ادخل الدوار';
    } else if (t == 'exit roundabout') {
      base = 'اخرج من الدوار';
    } else if (t == 'merge') {
      base = 'اندماج';
    } else if (t == 'on ramp') {
      base = 'ادخل المخرج';
    } else if (t == 'off ramp') {
      base = 'اخرج من المخرج';
    } else if (t == 'fork') {
      if (m == 'left') {
        base = 'اتجه يساراً';
      } else if (m == 'right') {
        base = 'اتجه يميناً';
      } else {
        base = 'اتبع التفرع';
      }
    } else if (t == 'turn' || t == 'end of road') {
      if (m == 'left') {
        base = 'انعطف يساراً';
      } else if (m == 'right') {
        base = 'انعطف يميناً';
      } else if (m == 'slight left') {
        base = 'انعطف يساراً قليلاً';
      } else if (m == 'slight right') {
        base = 'انعطف يميناً قليلاً';
      } else if (m == 'sharp left') {
        base = 'انعطف يساراً بشكل حاد';
      } else if (m == 'sharp right') {
        base = 'انعطف يميناً بشكل حاد';
      } else if (m == 'straight') {
        base = 'تابع للأمام';
      } else if (m == 'uturn') {
        base = 'قم بالالتفاف';
      } else {
        base = 'تابع السير';
      }
    } else {
      base = 'تابع السير';
    }

    final road = (name ?? '').trim();
    if (road.isEmpty) return base;
    if (t == 'arrive') return base;
    return '$base باتجاه $road';
  }

  int _statusRank(String? status) {
    switch (status) {
      case 'pending':
      case 'pending_repost':
        return 0;
      case 'accepted':
        return 1;
      case 'picked_up':
        return 2;
      case 'delivered':
        return 3;
      default:
        return 0;
    }
  }

  void _setOptimisticOrderOverride(Map<String, dynamic> order, String status) {
    final next = Map<String, dynamic>.from(order);
    next['status'] = status;
    setState(() {
      _optimisticOrderOverride = next;
      _optimisticOrderOverrideUntil =
          DateTime.now().add(const Duration(seconds: 20));
    });
  }

  void _scheduleRouteRefresh({
    required bool showPickupRoute,
    required bool showDropoffRoute,
    required LatLng? driverLocation,
    required LatLng? branchLocation,
    required LatLng? customerLocation,
    required int? orderId,
    required String? branchAddress,
    required String? customerAddress,
  }) {
    if (kIsWeb) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (showPickupRoute &&
          driverLocation != null &&
          branchLocation == null &&
          orderId != null) {
        unawaited(
          _maybeResolveBranchLocation(
            orderId: orderId,
            address: branchAddress,
            driverLocation: driverLocation,
            focus: true,
          ),
        );
      }
      if (showPickupRoute && driverLocation != null && branchLocation != null) {
        _maybeRefreshPickupRoute(driverLocation, branchLocation);
        _updatePickupGuidance(driverLocation);
      } else if (_pickupRoutePoints.isNotEmpty) {
        setState(() {
          _pickupRoutePoints = <LatLng>[];
          _pickupRoutes = <_OsrmRouteData>[];
          _selectedPickupRouteIndex = 0;
          _pickupNextInstruction = null;
        });
      }

      if (showDropoffRoute &&
          driverLocation != null &&
          customerLocation == null &&
          orderId != null) {
        unawaited(
          _maybeResolveCustomerLocation(
            orderId: orderId,
            address: customerAddress,
            driverLocation: driverLocation,
            focus: true,
          ),
        );
      }
      if (showDropoffRoute &&
          driverLocation != null &&
          customerLocation != null) {
        _maybeRefreshDropoffRoute(driverLocation, customerLocation);
        _updateDropoffGuidance(driverLocation);
      } else if (_dropoffRoutePoints.isNotEmpty) {
        setState(() {
          _dropoffRoutePoints = <LatLng>[];
          _dropoffRoutes = <_OsrmRouteData>[];
          _selectedDropoffRouteIndex = 0;
          _dropoffNextInstruction = null;
        });
      }
    });
  }

  void _updatePickupGuidance(LatLng driverLocation) {
    final routes = _pickupRoutes;
    if (routes.isEmpty) return;
    final selectedIndex = _selectedPickupRouteIndex.clamp(0, routes.length - 1);
    final steps = routes[selectedIndex].steps;
    if (steps.isEmpty) return;

    var passed = -1;
    for (var i = 0; i < steps.length; i++) {
      if (_metersBetween(driverLocation, steps[i].location) <= 25) {
        passed = i;
      }
    }

    final nextIndex = (passed + 1).clamp(0, steps.length - 1);
    final next = steps[nextIndex];
    final dist = _metersBetween(driverLocation, next.location);
    final text = 'بعد ${_formatDistance(dist)}: ${next.instruction}';

    if (_pickupNextInstruction != text) {
      setState(() {
        _pickupNextInstruction = text;
      });
    }
  }

  void _updateDropoffGuidance(LatLng driverLocation) {
    final routes = _dropoffRoutes;
    if (routes.isEmpty) return;
    final selectedIndex =
        _selectedDropoffRouteIndex.clamp(0, routes.length - 1);
    final steps = routes[selectedIndex].steps;
    if (steps.isEmpty) return;

    var passed = -1;
    for (var i = 0; i < steps.length; i++) {
      if (_metersBetween(driverLocation, steps[i].location) <= 25) {
        passed = i;
      }
    }

    final nextIndex = (passed + 1).clamp(0, steps.length - 1);
    final next = steps[nextIndex];
    final dist = _metersBetween(driverLocation, next.location);
    final text = 'بعد ${_formatDistance(dist)}: ${next.instruction}';

    if (_dropoffNextInstruction != text) {
      setState(() {
        _dropoffNextInstruction = text;
      });
    }
  }

  Widget _buildRouteAlternatives({
    required List<_OsrmRouteData> routes,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
  }) {
    if (routes.length <= 1) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < routes.length; i++)
            Padding(
              padding: EdgeInsetsDirectional.only(end: 10.w),
              child: ChoiceChip(
                selected: i == selectedIndex,
                onSelected: (_) => onSelected(i),
                label: Text(
                  '${_formatDuration(routes[i].duration)} • ${_formatDistance(routes[i].distance)}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: i == selectedIndex ? Colors.white : Colors.black87,
                  ),
                ),
                selectedColor: Colors.black,
                backgroundColor: Colors.grey[100],
                side: BorderSide(color: Colors.grey[300]!),
                showCheckmark: false,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _maybeRefreshPickupRoute(LatLng from, LatLng to) async {
    if (_isFetchingPickupRoute) return;

    final now = DateTime.now();
    final lastAt = _lastPickupFetchAt;
    final lastFrom = _lastPickupFrom;
    final lastTo = _lastPickupTo;

    final withinTimeWindow =
        lastAt != null && now.difference(lastAt).inSeconds < 10;
    final sameFrom = lastFrom != null && _metersBetween(lastFrom, from) < 30;
    final sameTo = lastTo != null && _metersBetween(lastTo, to) < 5;
    final offRoute = _pickupRoutePoints.isNotEmpty &&
        _distanceToPolylineMeters(from, _pickupRoutePoints) > 80;
    final allowForcedRefresh =
        offRoute && (lastAt == null || now.difference(lastAt).inSeconds >= 5);

    if (!allowForcedRefresh) {
      if (_pickupRoutePoints.isNotEmpty && sameFrom && sameTo) return;
      if (withinTimeWindow && sameFrom && sameTo) return;
    }

    _isFetchingPickupRoute = true;
    _pickupRouteFetchFailed = false;
    _lastPickupFetchAt = now;
    _lastPickupFrom = from;
    _lastPickupTo = to;

    try {
      final routes = await _fetchOsrmRoutes(from, to);
      if (!mounted) return;
      if (routes.isNotEmpty) {
        var bestIndex = 0;
        var bestDuration = routes.first.duration;
        for (var i = 1; i < routes.length; i++) {
          final d = routes[i].duration;
          if (d < bestDuration) {
            bestDuration = d;
            bestIndex = i;
          }
        }

        final preservedIndex = _selectedPickupRouteIndex;
        final nextSelected =
            preservedIndex >= 0 && preservedIndex < routes.length
                ? preservedIndex
                : bestIndex;

        setState(() {
          _pickupRoutes = routes;
          _selectedPickupRouteIndex = nextSelected;
          _pickupRoutePoints = routes[nextSelected].points;
        });
      } else {
        if (_pickupRoutePoints.isEmpty) {
          setState(() => _pickupRouteFetchFailed = true);
        }
      }
    } finally {
      _isFetchingPickupRoute = false;
    }
  }

  Future<void> _maybeRefreshDropoffRoute(LatLng from, LatLng to) async {
    if (_isFetchingDropoffRoute) return;

    final now = DateTime.now();
    final lastAt = _lastDropoffFetchAt;
    final lastFrom = _lastDropoffFrom;
    final lastTo = _lastDropoffTo;

    final withinTimeWindow =
        lastAt != null && now.difference(lastAt).inSeconds < 10;
    final sameFrom = lastFrom != null && _metersBetween(lastFrom, from) < 30;
    final sameTo = lastTo != null && _metersBetween(lastTo, to) < 5;
    final offRoute = _dropoffRoutePoints.isNotEmpty &&
        _distanceToPolylineMeters(from, _dropoffRoutePoints) > 80;
    final allowForcedRefresh =
        offRoute && (lastAt == null || now.difference(lastAt).inSeconds >= 5);

    if (!allowForcedRefresh) {
      if (_dropoffRoutePoints.isNotEmpty && sameFrom && sameTo) return;
      if (withinTimeWindow && sameFrom && sameTo) return;
    }

    _isFetchingDropoffRoute = true;
    _dropoffRouteFetchFailed = false;
    _lastDropoffFetchAt = now;
    _lastDropoffFrom = from;
    _lastDropoffTo = to;

    try {
      final routes = await _fetchOsrmRoutes(from, to);
      if (!mounted) return;
      if (routes.isNotEmpty) {
        var bestIndex = 0;
        var bestDuration = routes.first.duration;
        for (var i = 1; i < routes.length; i++) {
          final d = routes[i].duration;
          if (d < bestDuration) {
            bestDuration = d;
            bestIndex = i;
          }
        }

        final preservedIndex = _selectedDropoffRouteIndex;
        final nextSelected =
            preservedIndex >= 0 && preservedIndex < routes.length
                ? preservedIndex
                : bestIndex;

        setState(() {
          _dropoffRoutes = routes;
          _selectedDropoffRouteIndex = nextSelected;
          _dropoffRoutePoints = routes[nextSelected].points;
        });
      } else {
        if (_dropoffRoutePoints.isEmpty) {
          setState(() => _dropoffRouteFetchFailed = true);
        }
      }
    } finally {
      _isFetchingDropoffRoute = false;
    }
  }

  Future<List<_OsrmRouteData>> _fetchOsrmRoutes(LatLng from, LatLng to) async {
    if (kIsWeb) return const <_OsrmRouteData>[];

    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/$_kOsrmProfile/${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=full&geometries=geojson&alternatives=true&steps=true',
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const <_OsrmRouteData>[];

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const <_OsrmRouteData>[];

      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) return const <_OsrmRouteData>[];

      final parsedRoutes = <_OsrmRouteData>[];

      for (final r in routes) {
        if (r is! Map) continue;
        final geometry = r['geometry'];
        if (geometry is! Map) continue;

        final coords = geometry['coordinates'];
        if (coords is! List) continue;

        final points = <LatLng>[];
        for (final c in coords) {
          if (c is! List || c.length < 2) continue;
          final lon = (c[0] as num?)?.toDouble();
          final lat = (c[1] as num?)?.toDouble();
          if (lat == null || lon == null) continue;
          points.add(LatLng(lat, lon));
        }

        if (points.length < 2) continue;

        final distance = (r['distance'] as num?)?.toDouble() ?? 0.0;
        final duration = (r['duration'] as num?)?.toDouble() ?? 0.0;

        final steps = <_OsrmStep>[];
        final legs = r['legs'];
        if (legs is List && legs.isNotEmpty) {
          final leg0 = legs.first;
          if (leg0 is Map) {
            final rawSteps = leg0['steps'];
            if (rawSteps is List) {
              for (final s in rawSteps) {
                if (s is! Map) continue;
                final maneuver = s['maneuver'];
                if (maneuver is! Map) continue;
                final loc = maneuver['location'];
                if (loc is! List || loc.length < 2) continue;
                final lon = (loc[0] as num?)?.toDouble();
                final lat = (loc[1] as num?)?.toDouble();
                if (lat == null || lon == null) continue;

                final type = maneuver['type']?.toString();
                final modifier = maneuver['modifier']?.toString();
                final name = s['name']?.toString();

                steps.add(
                  _OsrmStep(
                    location: LatLng(lat, lon),
                    instruction: _buildArabicInstruction(
                        type: type, modifier: modifier, name: name),
                    distance: (s['distance'] as num?)?.toDouble() ?? 0.0,
                    duration: (s['duration'] as num?)?.toDouble() ?? 0.0,
                  ),
                );
              }
            }
          }
        }

        parsedRoutes.add(
          _OsrmRouteData(
            points: points,
            distance: distance,
            duration: duration,
            steps: steps,
          ),
        );
      }

      return parsedRoutes;
    } catch (_) {
      return const <_OsrmRouteData>[];
    }
  }

  @override
  void initState() {
    super.initState();
    _initLocalNotifications();
    _driverStateSubscription =
        ref.listenManual(driverControllerProvider, (prev, next) {
      final prevLocation = prev?.value?.currentLocation;
      final nextLocation = next.value?.currentLocation;
      final wentOnline = (prev?.value?.isOnline ?? false) == false &&
          (next.value?.isOnline ?? false) == true;

      if ((wentOnline || prevLocation == null) && nextLocation != null) {
        _moveTo(nextLocation, zoom: 16);
      }
    });
    _activeOrderSubscription =
        ref.listenManual(activeOrderProvider, (prev, next) {
      final order = next.valueOrNull;
      if (order == null) {
        if (!mounted) return;
        setState(() {
          _optimisticOrderOverride = null;
          _optimisticOrderOverrideUntil = null;
          _pickupRoutePoints = <LatLng>[];
          _dropoffRoutePoints = <LatLng>[];
          _pickupRoutes = <_OsrmRouteData>[];
          _dropoffRoutes = <_OsrmRouteData>[];
          _selectedPickupRouteIndex = 0;
          _selectedDropoffRouteIndex = 0;
          _pickupNextInstruction = null;
          _dropoffNextInstruction = null;
          _pickupRouteFetchFailed = false;
          _dropoffRouteFetchFailed = false;
          _lastHandledActiveOrderId = null;
          _lastHandledActiveOrderStatus = null;
        });
        return;
      }

      final id = (order['id'] as num?)?.toInt();
      if (id == null) return;
      final status = order['status']?.toString();

      final optimistic = _optimisticOrderOverride;
      if (optimistic != null) {
        final optimisticId = (optimistic['id'] as num?)?.toInt();
        final optimisticStatus = optimistic['status']?.toString();
        if (optimisticId == null || optimisticId != id) {
          if (mounted) {
            setState(() {
              _optimisticOrderOverride = null;
              _optimisticOrderOverrideUntil = null;
            });
          }
        } else if (optimisticStatus != null && optimisticStatus == status) {
          if (mounted) {
            setState(() {
              _optimisticOrderOverride = null;
              _optimisticOrderOverrideUntil = null;
            });
          }
        }
      }

      final branchLocation = _latLngFromOrder(
        order,
        latKeys: const [
          'lat',
          'branch_lat',
          'branchLatitude',
          'branch_latitude'
        ],
        lngKeys: const [
          'lng',
          'branch_lng',
          'branchLongitude',
          'branch_longitude'
        ],
      );

      final customerLocation = _latLngFromOrder(
        order,
        latKeys: const [
          'customer_lat',
          'customerLatitude',
          'customer_latitude'
        ],
        lngKeys: const [
          'customer_lng',
          'customerLongitude',
          'customer_longitude'
        ],
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (_lastHandledActiveOrderId != id) {
          setState(() {
            _pickupRoutePoints = <LatLng>[];
            _dropoffRoutePoints = <LatLng>[];
            _pickupRoutes = <_OsrmRouteData>[];
            _dropoffRoutes = <_OsrmRouteData>[];
            _selectedPickupRouteIndex = 0;
            _selectedDropoffRouteIndex = 0;
            _pickupNextInstruction = null;
            _dropoffNextInstruction = null;
            _pickupRouteFetchFailed = false;
            _dropoffRouteFetchFailed = false;
            _lastHandledActiveOrderId = id;
            _lastHandledActiveOrderStatus = status;
          });
        } else if (_lastHandledActiveOrderStatus != status) {
          _lastHandledActiveOrderStatus = status;
        }

        final driverLocation =
            ref.read(driverControllerProvider).valueOrNull?.currentLocation;
        if (status == 'picked_up') {
          if (customerLocation != null) {
            _moveTo(customerLocation, zoom: 16);
          }
          if (driverLocation != null && customerLocation != null) {
            unawaited(
                _maybeRefreshDropoffRoute(driverLocation, customerLocation));
            _updateDropoffGuidance(driverLocation);
          }
        } else {
          if (branchLocation != null) {
            _moveTo(branchLocation, zoom: 16);
          }
          if (driverLocation != null && branchLocation != null) {
            unawaited(_maybeRefreshPickupRoute(driverLocation, branchLocation));
            _updatePickupGuidance(driverLocation);
          }
        }
      });
    });
    _availableOrdersSubscription =
        ref.listenManual(availableOrdersProvider, (prev, next) {
      final userId = ref.read(authRepositoryProvider).currentUser?.id;
      if (userId == null) return;

      if (prev != null) {
        final prevOrders = prev.valueOrNull ?? const <Map<String, dynamic>>[];
        final prevResendById = <int, int>{
          for (final o in prevOrders)
            if ((o['id'] as num?)?.toInt() != null)
              (o['id'] as num).toInt(): _resendCountFromOrder(o),
        };

        final orders = next.valueOrNull;
        if (orders != null && orders.isNotEmpty) {
          for (final o in orders) {
            final id = (o['id'] as num?)?.toInt();
            if (id == null) continue;
            final nextCount = _resendCountFromOrder(o);
            final prevCount = prevResendById[id] ?? 0;
            if (nextCount <= 0 || nextCount <= prevCount) continue;

            final lastNotifiedCount = _lastNotifiedResendCount[id] ?? 0;
            if (nextCount <= lastNotifiedCount) continue;
            _lastNotifiedResendCount[id] = nextCount;

            unawaited(_showResentOrderNotification(o));

            final activeOrder = ref.read(activeOrderProvider).valueOrNull;
            if (activeOrder == null && _incomingSheetOrderId == null) {
              unawaited(_showIncomingOrderSheet(o, title: 'طلب معاد إرساله'));
            }
          }
        }
      }

      final isOnline =
          ref.read(driverControllerProvider).valueOrNull?.isOnline ?? false;
      if (!isOnline) return;

      final isAvailable =
          ref.read(driverProfileProvider).valueOrNull?['is_available'] == true;
      if (!isAvailable) return;

      final activeOrder = ref.read(activeOrderProvider).valueOrNull;
      if (activeOrder != null) return;

      if (prev == null) return;
      if (_incomingSheetOrderId != null) return;

      final orders = next.valueOrNull;
      if (orders == null || orders.isEmpty) return;

      final prevOrders = prev.valueOrNull ?? const <Map<String, dynamic>>[];
      final prevIds = prevOrders
          .map((o) => (o['id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();

      final newOrders = orders.where((o) {
        final id = (o['id'] as num?)?.toInt();
        if (id == null) return false;
        return !prevIds.contains(id);
      }).toList();

      if (newOrders.isEmpty) return;
      final newest = newOrders.first;
      final newId = (newest['id'] as num?)?.toInt();
      if (newId == null) return;
      if (_lastNotifiedOrderId == newId) return;
      _lastNotifiedOrderId = newId;

      _showNewOrderNotification(newest);
      _showIncomingOrderSheet(newest);
    });
  }

  @override
  void dispose() {
    _driverStateSubscription?.close();
    _availableOrdersSubscription?.close();
    _activeOrderSubscription?.close();
    super.dispose();
  }

  Future<void> _initLocalNotifications() async {
    if (kIsWeb) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _localNotifications.initialize(settings);

    final iosPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  Future<void> _showNewOrderNotification(Map<String, dynamic> order) async {
    if (kIsWeb) return;
    final id = (order['id'] as num?)?.toInt() ?? 0;
    final restaurantName = _trimString(order['restaurant_name']);
    final customer = _mapFromDynamic(order['customer_details']);
    final address = _trimString(customer['address']);

    const title = 'طلب جديد';
    final parts = <String>[
      if (restaurantName != null && restaurantName.isNotEmpty) restaurantName,
      if (address != null && address.isNotEmpty) address,
    ];
    final body = parts.isEmpty ? 'يوجد طلب توصيل جديد' : parts.join(' - ');

    const androidDetails = AndroidNotificationDetails(
      'orders',
      'Orders',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(
        presentAlert: true, presentBadge: true, presentSound: true);
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _localNotifications.show(id, title, body, details);
  }

  Future<void> _showResentOrderNotification(Map<String, dynamic> order) async {
    final id = (order['id'] as num?)?.toInt() ?? 0;
    final restaurantName = _trimString(order['restaurant_name']);
    final customer = _mapFromDynamic(order['customer_details']);
    final address = _trimString(customer['address']);

    const title = 'طلب معاد إرساله';
    final parts = <String>[
      if (restaurantName != null && restaurantName.isNotEmpty) restaurantName,
      if (address != null && address.isNotEmpty) address,
    ];
    final body =
        parts.isEmpty ? 'يوجد طلب توصيل معاد إرساله' : parts.join(' - ');

    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title: $body')),
      );
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'orders',
      'Orders',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(
        presentAlert: true, presentBadge: true, presentSound: true);
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _localNotifications.show(id + 1000000, title, body, details);
  }

  Future<void> _showIncomingOrderSheet(Map<String, dynamic> order,
      {String title = 'طلب جديد وصل الآن'}) async {
    if (!mounted) return;
    final id = (order['id'] as num?)?.toInt();
    if (id == null) return;
    if (_incomingSheetOrderId == id) return;
    _incomingSheetOrderId = id;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) {
        final customer = _mapFromDynamic(order['customer_details']);
        final restaurantName = order['restaurant_name']?.toString();
        final branchAddress = order['branch_address']?.toString();
        final pickupTitle = (restaurantName != null &&
                restaurantName.isNotEmpty)
            ? restaurantName
            : 'المطعم';
        final dropoffAddress = customer['address']?.toString();
        final deliveryFee = (order['delivery_fee'] as num?)?.toDouble();

        return SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: EdgeInsets.only(
                left: 16.w,
                right: 16.w,
                top: 14.h,
                bottom: 18.h + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                              fontSize: 16.sp, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.notifications_active),
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),
                  Container(
                    padding: EdgeInsets.all(14.w),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(pickupTitle,
                            style: TextStyle(
                                fontSize: 14.sp, fontWeight: FontWeight.w600)),
                        if (branchAddress != null &&
                            branchAddress.trim().isNotEmpty) ...[
                          SizedBox(height: 4.h),
                          Text(
                            branchAddress,
                            style: TextStyle(
                                color: Colors.grey[700], fontSize: 12.sp),
                          ),
                        ],
                        SizedBox(height: 6.h),
                        Text(
                          (dropoffAddress == null || dropoffAddress.isEmpty)
                              ? '—'
                              : dropoffAddress,
                          style: TextStyle(
                              color: Colors.grey[700], fontSize: 12.sp),
                        ),
                        SizedBox(height: 10.h),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                deliveryFee == null
                                    ? '—'
                                    : '${deliveryFee.toStringAsFixed(2)} د.ع',
                                style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 10.w, vertical: 6.h),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: const Text('توصيل'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 46.h,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final branchLocation = _latLngFromOrder(
                                order,
                                latKeys: const [
                                  'lat',
                                  'branch_lat',
                                  'branchLatitude',
                                  'branch_latitude'
                                ],
                                lngKeys: const [
                                  'lng',
                                  'branch_lng',
                                  'branchLongitude',
                                  'branch_longitude'
                                ],
                              );
                              final branchLat = branchLocation?.latitude;
                              final branchLng = branchLocation?.longitude;
                              final driverLocation = ref
                                  .read(driverControllerProvider)
                                  .valueOrNull
                                  ?.currentLocation;
                              final messenger = ScaffoldMessenger.of(context);

                              Navigator.pop(ctx);
                              try {
                                await ref
                                    .read(driverControllerProvider.notifier)
                                    .acceptOrder(id);
                              } catch (e) {
                                final message = e is UserFacingException
                                    ? e.toString()
                                    : 'تعذر قبول الطلب';
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(Icons.warning_amber_rounded,
                                            color: Colors.amber),
                                        SizedBox(width: 10.w),
                                        Expanded(child: Text(message)),
                                      ],
                                    ),
                                  ),
                                );
                                return;
                              }

                              if (!mounted) return;
                              _setOptimisticOrderOverride(order, 'accepted');
                              if (branchLocation != null) {
                                _moveTo(branchLocation, zoom: 16);
                              } else {
                                final q = _branchQueryFromOrder(order);
                                unawaited(
                                  _maybeResolveBranchLocation(
                                    orderId: id,
                                    address: q,
                                    driverLocation: driverLocation,
                                    focus: true,
                                  ),
                                );
                              }

                              if (driverLocation != null &&
                                  branchLocation != null) {
                                unawaited(_maybeRefreshPickupRoute(
                                    driverLocation, branchLocation));
                                _updatePickupGuidance(driverLocation);
                              }

                              messenger.showSnackBar(
                                SnackBar(
                                  content: const Text(
                                      'تم قبول الطلب وتحديد طريق المطعم'),
                                  action: ((branchLat != null &&
                                              branchLng != null) ||
                                          ((_branchQueryFromOrder(order) ?? '')
                                              .isNotEmpty))
                                      ? SnackBarAction(
                                          label: 'خرائط Google',
                                          onPressed: () async {
                                            final q =
                                                _branchQueryFromOrder(order);
                                            await _openExternalNavigation(
                                              lat: branchLat,
                                              lng: branchLng,
                                              address: q,
                                            );
                                          },
                                        )
                                      : null,
                                ),
                              );
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('قبول الطلب'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14.r)),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: SizedBox(
                          height: 46.h,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم رفض الطلب')),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black87,
                              side: BorderSide(color: Colors.grey[300]!),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14.r)),
                            ),
                            child: const Text('رفض'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (mounted) _incomingSheetOrderId = null;
  }

  void _moveTo(LatLng center, {double? zoom}) {
    if (!_isMapReady) {
      _pendingMoveCenter = center;
      _pendingMoveZoom = zoom;
      _lastCenter = center;
      if (zoom != null) _lastZoom = zoom;
      if (mounted) setState(() {});
      return;
    }
    final targetZoom = zoom ?? _mapController.camera.zoom;
    _mapController.move(center, targetZoom);
  }

  Future<void> _showTripCompletedDialog(BuildContext context,
      {required double? earnings}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          insetPadding: EdgeInsets.symmetric(horizontal: 22.w, vertical: 24.h),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22.r)),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 18.h),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52.w,
                    height: 52.w,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.check, color: Colors.green, size: 28),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    'تم إنهاء الرحلة!',
                    style:
                        TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    'تم توصيل العميل بنجاح',
                    style: TextStyle(color: Colors.grey[700], fontSize: 13.sp),
                  ),
                  SizedBox(height: 14.h),
                  Container(
                    width: double.infinity,
                    padding:
                        EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'الأرباح من الرحلة',
                          style: TextStyle(
                              color: Colors.grey[700], fontSize: 12.sp),
                        ),
                        SizedBox(height: 6.h),
                        Text(
                          earnings == null
                              ? '—'
                              : '${earnings.toStringAsFixed(2)} د.ع',
                          style: TextStyle(
                              fontSize: 22.sp, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 14.h),
                  SizedBox(
                    width: double.infinity,
                    height: 46.h,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.r)),
                      ),
                      child: const Text('العودة الرئيسية'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final driverState = ref.watch(driverControllerProvider);
    final driverProfile = ref.watch(driverProfileProvider);
    final activeOrder = ref.watch(activeOrderProvider);
    final driverStats = ref.watch(driverStatsProvider);

    // Determine if driver has an active order
    Map<String, dynamic>? currentActiveOrder = activeOrder.value;
    final optimistic = _optimisticOrderOverride;
    final optimisticUntil = _optimisticOrderOverrideUntil;
    if (optimistic != null &&
        optimisticUntil != null &&
        DateTime.now().isBefore(optimisticUntil)) {
      final optimisticId = (optimistic['id'] as num?)?.toInt();
      final activeId = (currentActiveOrder?['id'] as num?)?.toInt();
      final optimisticStatus = optimistic['status']?.toString();
      final activeStatus = currentActiveOrder?['status']?.toString();
      final canOverride = activeId == null ||
          (optimisticId != null && optimisticId == activeId);
      if (canOverride &&
          _statusRank(optimisticStatus) >= _statusRank(activeStatus)) {
        currentActiveOrder = optimistic;
      }
    }
    final currentOrderId = (currentActiveOrder?['id'] as num?)?.toInt();
    final branchAddress = currentActiveOrder == null
        ? null
        : _branchQueryFromOrder(currentActiveOrder);
    final customerAddress = currentActiveOrder == null
        ? null
        : _customerQueryFromOrder(currentActiveOrder);

    LatLng? branchLocation = currentActiveOrder == null
        ? null
        : _latLngFromOrder(
            currentActiveOrder,
            latKeys: const [
              'lat',
              'branch_lat',
              'branchLatitude',
              'branch_latitude'
            ],
            lngKeys: const [
              'lng',
              'branch_lng',
              'branchLongitude',
              'branch_longitude'
            ],
          );
    if (branchLocation == null && currentOrderId != null) {
      branchLocation = _resolvedBranchLocations[currentOrderId];
    }

    final isOnline = driverState.value?.isOnline ?? false;
    final walletBalance =
        (driverProfile.valueOrNull?['wallet_balance'] as num?)?.toDouble() ??
            0.0;
    final hasActiveOrder = currentActiveOrder != null;
    final activeStatus = currentActiveOrder?['status']?.toString();
    final showPickupRoute = hasActiveOrder && activeStatus != 'picked_up';
    LatLng? customerLocation = currentActiveOrder == null
        ? null
        : _latLngFromOrder(
            currentActiveOrder,
            latKeys: const [
              'customer_lat',
              'customerLatitude',
              'customer_latitude'
            ],
            lngKeys: const [
              'customer_lng',
              'customerLongitude',
              'customer_longitude'
            ],
          );
    if (customerLocation == null && currentOrderId != null) {
      customerLocation = _resolvedCustomerLocations[currentOrderId];
    }
    final showDropoffRoute = hasActiveOrder && activeStatus == 'picked_up';
    final driverLocation = driverState.value?.currentLocation;
    final guidanceText = showDropoffRoute
        ? _dropoffNextInstruction
        : (showPickupRoute ? _pickupNextInstruction : null);

    _scheduleRouteRefresh(
      showPickupRoute: showPickupRoute,
      showDropoffRoute: showDropoffRoute,
      driverLocation: driverLocation,
      branchLocation: branchLocation,
      customerLocation: customerLocation,
      orderId: currentOrderId,
      branchAddress: branchAddress,
      customerAddress: customerAddress,
    );

    return Scaffold(
      drawer: const DriverDrawer(),
      body: Stack(
        children: [
          if (!kIsWeb)
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _lastCenter,
                initialZoom: _lastZoom,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onMapReady: () {
                  _isMapReady = true;
                  _lastCenter = _mapController.camera.center;
                  _lastZoom = _mapController.camera.zoom;
                  final pending = _pendingMoveCenter;
                  if (pending != null) {
                    final pendingZoom = _pendingMoveZoom;
                    _pendingMoveCenter = null;
                    _pendingMoveZoom = null;
                    _moveTo(pending, zoom: pendingZoom ?? 16);
                    return;
                  }
                  final driverLocation = driverState.value?.currentLocation;
                  if (driverLocation != null) {
                    _moveTo(driverLocation, zoom: _lastZoom);
                  }
                },
                onPositionChanged: (position, _) {
                  _lastCenter = position.center;
                  _lastZoom = position.zoom;
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.naemi_team',
                  errorTileCallback: (_, __, ___) {
                    if (_hasTileLoadError) return;
                    setState(() => _hasTileLoadError = true);
                  },
                ),
                if (showPickupRoute &&
                    driverLocation != null &&
                    branchLocation != null)
                  if (_pickupRoutePoints.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _pickupRoutePoints,
                          strokeWidth: 5,
                          color: Colors.blue,
                        ),
                      ],
                    )
                  else if (_pickupRouteFetchFailed)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: <LatLng>[driverLocation, branchLocation],
                          strokeWidth: 5,
                          color: Colors.blue,
                        ),
                      ],
                    ),
                if (showDropoffRoute &&
                    driverLocation != null &&
                    customerLocation != null)
                  if (_dropoffRoutePoints.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _dropoffRoutePoints,
                          strokeWidth: 5,
                          color: Colors.blue,
                        ),
                      ],
                    )
                  else if (_dropoffRouteFetchFailed)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: <LatLng>[driverLocation, customerLocation],
                          strokeWidth: 5,
                          color: Colors.blue,
                        ),
                      ],
                    ),
                MarkerLayer(
                  markers: [
                    if (driverState.value?.currentLocation != null)
                      Marker(
                        point: driverState.value!.currentLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.navigation,
                            color: Colors.purple, size: 40),
                      ),
                    if (branchLocation != null)
                      Marker(
                        point: branchLocation,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.store_mall_directory,
                            color: Colors.orange, size: 40),
                      ),
                    if (customerLocation != null && activeStatus == 'picked_up')
                      Marker(
                        point: customerLocation,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_pin,
                            color: Colors.redAccent, size: 40),
                      ),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            )
          else
            Container(
              color: Colors.grey[100],
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24.w),
                  child: const Text(
                    'الخريطة غير متاحة على الويب حالياً',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          if (currentActiveOrder != null)
            _buildActiveOrderUI(context, currentActiveOrder,
                mapEnabled: !kIsWeb),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                child: Row(
                  children: [
                    Builder(
                      builder: (ctx) {
                        return Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => Scaffold.of(ctx).openDrawer(),
                            child: Padding(
                              padding: EdgeInsets.all(10.w),
                              child:
                                  const Icon(Icons.menu, color: Colors.black87),
                            ),
                          ),
                        );
                      },
                    ),
                    Expanded(
                      child: Center(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 14.w, vertical: 10.h),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(18.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                walletBalance.toStringAsFixed(2),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16.sp,
                                ),
                              ),
                              SizedBox(width: 8.w),
                              Text(
                                'د.ع',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.95),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: (driverState.value?.currentLocation == null)
                            ? null
                            : () => _moveTo(driverState.value!.currentLocation!,
                                zoom: 16),
                        child: Padding(
                          padding: EdgeInsets.all(10.w),
                          child:
                              const Icon(Icons.near_me, color: Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (guidanceText != null && guidanceText.trim().isNotEmpty)
            Positioned(
              top: 72.h,
              left: 14.w,
              right: 14.w,
              child: SafeArea(
                top: false,
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34.w,
                        height: 34.w,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Icon(Icons.navigation,
                            color: Colors.white, size: 18.sp),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Text(
                          guidanceText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.sp, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (currentActiveOrder == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  height: _kSheetHeight.h,
                  padding:
                      EdgeInsets.symmetric(horizontal: 18.w, vertical: 14.h),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(30.r)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Material(
                            color: Colors.grey[100],
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => context.push('/driver/slots'),
                              child: Padding(
                                padding: EdgeInsets.all(10.w),
                                child: const Icon(Icons.tune,
                                    color: Colors.black87),
                              ),
                            ),
                          ),
                          SizedBox(width: 10.w),
                          const Spacer(),
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  isOnline ? 'أنت متصل' : 'أنت غير متصل',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontSize: 18.sp,
                                      fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  isOnline
                                      ? 'اضغط لإيقاف استقبال الطلبات'
                                      : 'اضغط لتبدأ لاستقبال الطلبات',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 18.h),
                      Expanded(
                        child: Center(
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: driverState.isLoading
                                ? null
                                : () async {
                                    HapticFeedback.mediumImpact();
                                    if (!isOnline) {
                                      final userId = ref
                                          .read(authRepositoryProvider)
                                          .currentUser
                                          ?.id;
                                      if (userId != null) {
                                        try {
                                          final slots = await ref
                                              .read(driverRepositoryProvider)
                                              .getAvailabilitySlots(userId);
                                          final hasAnyActive = slots.any(
                                              (s) => s['is_active'] == true);
                                          if (hasAnyActive &&
                                              !_isWithinSchedule(
                                                  slots, DateTime.now())) {
                                            if (!context.mounted) return;
                                            context.push('/driver/slots');
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'أنت خارج وقت النشاط المحدد. أوقف الجدولة أو عدّلها ثم اضغط ابدأ.'),
                                              ),
                                            );
                                            return;
                                          }
                                        } catch (_) {}
                                      }
                                    }
                                    ref
                                        .read(driverControllerProvider.notifier)
                                        .toggleOnlineStatus(!isOnline);
                                  },
                            child: Container(
                              width: 84.w,
                              height: 84.w,
                              decoration: const BoxDecoration(
                                color: Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: isOnline
                                      ? Colors.orange
                                      : const Color(0xFF1B2330),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: driverState.isLoading
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white),
                                        )
                                      : Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.power_settings_new,
                                                color: Colors.white),
                                            SizedBox(height: 4.h),
                                            Text(
                                              isOnline ? 'إيقاف' : 'ابدأ',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12.sp,
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
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                driverStats.when(
                                  data: (s) => Text(
                                    s.totalOrders.toString(),
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.sp),
                                  ),
                                  loading: () => Text(
                                    '—',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.sp),
                                  ),
                                  error: (_, __) => Text(
                                    '—',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.sp),
                                  ),
                                ),
                                SizedBox(height: 2.h),
                                Text('طلبات',
                                    style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12.sp)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                driverStats.when(
                                  data: (s) => Text(
                                    '${(s.acceptanceRate * 100).round()}%',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.sp),
                                  ),
                                  loading: () => Text(
                                    '—',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.sp),
                                  ),
                                  error: (_, __) => Text(
                                    '—',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.sp),
                                  ),
                                ),
                                SizedBox(height: 2.h),
                                Text('القبول',
                                    style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12.sp)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!kIsWeb && _hasTileLoadError)
            Positioned(
              top: 56.h,
              left: 16.w,
              right: 16.w,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: const Text(
                    'تعذر تحميل الخريطة. تأكد من اتصال الإنترنت.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActiveOrderUI(
    BuildContext context,
    Map<String, dynamic> order, {
    required bool mapEnabled,
  }) {
    final status = order['status'];
    final customer = _mapFromDynamic(order['customer_details']);
    final isPickedUp = status == 'picked_up';
    final orderId = (order['id'] as num?)?.toInt();
    final customerName = customer['name']?.toString();
    final customerPhone = customer['phone']?.toString();
    final customerAddress = customer['address']?.toString();
    LatLng? customerLocation = _latLngFromOrder(
      order,
      latKeys: const ['customer_lat', 'customerLatitude', 'customer_latitude'],
      lngKeys: const [
        'customer_lng',
        'customerLongitude',
        'customer_longitude'
      ],
    );
    if (customerLocation == null && orderId != null) {
      customerLocation = _resolvedCustomerLocations[orderId];
    }
    final customerLat = customerLocation?.latitude;
    final customerLng = customerLocation?.longitude;

    final orderPrice = (order['price'] as num?)?.toDouble();
    final deliveryFee = (order['delivery_fee'] as num?)?.toDouble();
    final totalPrice = (orderPrice != null && deliveryFee != null)
        ? (orderPrice + deliveryFee)
        : null;
    String formatIqd(double v) =>
        v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

    final restaurantName = order['restaurant_name']?.toString();
    final branchName = order['branch_name']?.toString();
    final branchAddress = order['branch_address']?.toString();
    final pickupTitle = (restaurantName != null && restaurantName.isNotEmpty)
        ? '$restaurantName${(branchName != null && branchName.isNotEmpty) ? ' - $branchName' : ''}'
        : 'المطعم';

    LatLng? branchLocation = _latLngFromOrder(
      order,
      latKeys: const ['lat', 'branch_lat', 'branchLatitude', 'branch_latitude'],
      lngKeys: const [
        'lng',
        'branch_lng',
        'branchLongitude',
        'branch_longitude'
      ],
    );
    if (branchLocation == null && orderId != null) {
      branchLocation = _resolvedBranchLocations[orderId];
    }
    final branchLat = branchLocation?.latitude;
    final branchLng = branchLocation?.longitude;

    final driverLocation =
        ref.read(driverControllerProvider).valueOrNull?.currentLocation;
    final pickupKm = (driverLocation != null && branchLocation != null)
        ? const Distance()
            .as(LengthUnit.Kilometer, driverLocation, branchLocation)
        : null;
    final routes = isPickedUp ? _dropoffRoutes : _pickupRoutes;
    final selectedRouteIndex = routes.isEmpty
        ? 0
        : (isPickedUp ? _selectedDropoffRouteIndex : _selectedPickupRouteIndex)
            .clamp(0, routes.length - 1);

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.all(18.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30.r)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (totalPrice ?? deliveryFee ?? orderPrice) == null
                              ? '—'
                              : '${formatIqd((totalPrice ?? deliveryFee ?? orderPrice)!)} د.ع',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18.sp),
                        ),
                        SizedBox(height: 4.h),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10.w, vertical: 6.h),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Text(
                            totalPrice != null
                                ? 'المجموع'
                                : (deliveryFee != null ? 'توصيل' : 'وجبة'),
                            style: TextStyle(
                                fontSize: 12.sp, color: Colors.black87),
                          ),
                        ),
                        if (orderPrice != null || deliveryFee != null) ...[
                          SizedBox(height: 6.h),
                          if (orderPrice != null)
                            Text(
                              'سعر الوجبة: ${formatIqd(orderPrice)} د.ع',
                              style: TextStyle(
                                  color: Colors.grey[700], fontSize: 12.sp),
                            ),
                          if (deliveryFee != null)
                            Text(
                              'سعر التوصيل: ${formatIqd(deliveryFee)} د.ع',
                              style: TextStyle(
                                  color: Colors.grey[700], fontSize: 12.sp),
                            ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          (customerName != null && customerName.isNotEmpty)
                              ? customerName
                              : 'العميل',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16.sp),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          'الدفع نقداً',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 12.sp),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Container(
                    padding: EdgeInsets.all(2.w),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.green, width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 18.r,
                      backgroundColor: Colors.grey[200],
                      child: const Icon(Icons.person, color: Colors.black54),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              if (routes.isNotEmpty)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _buildRouteAlternatives(
                    routes: routes,
                    selectedIndex: selectedRouteIndex,
                    onSelected: (i) {
                      setState(() {
                        if (isPickedUp) {
                          _selectedDropoffRouteIndex = i;
                          _dropoffRoutePoints = _dropoffRoutes[i].points;
                        } else {
                          _selectedPickupRouteIndex = i;
                          _pickupRoutePoints = _pickupRoutes[i].points;
                        }
                      });
                      final currentDriver = driverLocation;
                      if (currentDriver != null) {
                        if (isPickedUp) {
                          _updateDropoffGuidance(currentDriver);
                        } else {
                          _updatePickupGuidance(currentDriver);
                        }
                      }
                    },
                  ),
                ),
              if (routes.length > 1) SizedBox(height: 12.h),
              InkWell(
                borderRadius: BorderRadius.circular(18.r),
                onTap: !mapEnabled
                    ? null
                    : () async {
                        final address = isPickedUp
                            ? customerAddress
                            : ((branchAddress != null &&
                                    branchAddress.isNotEmpty)
                                ? branchAddress
                                : pickupTitle);
                        if (isPickedUp) {
                          await _openExternalNavigation(
                            lat: customerLat,
                            lng: customerLng,
                            address: address,
                          );
                          return;
                        }
                        await _openExternalNavigation(
                          lat: branchLat,
                          lng: branchLng,
                          address: address,
                        );
                      },
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(18.r),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8.w),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child:
                            const Icon(Icons.navigation, color: Colors.white),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isPickedUp
                                  ? 'اتجه نحو العميل'
                                  : 'اتجه نحو موقع الاستلام',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.sp),
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              isPickedUp
                                  ? ((customerAddress != null &&
                                          customerAddress.isNotEmpty)
                                      ? customerAddress
                                      : '—')
                                  : ((branchAddress != null &&
                                          branchAddress.isNotEmpty)
                                      ? branchAddress
                                      : pickupTitle),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.95),
                                  fontSize: 12.sp),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 10.w),
                      InkWell(
                        onTap: () async {
                          final target =
                              isPickedUp ? customerLocation : branchLocation;
                          if (target == null) return;
                          final address = isPickedUp
                              ? ((customerAddress != null &&
                                      customerAddress.isNotEmpty)
                                  ? customerAddress
                                  : '—')
                              : ((branchAddress != null &&
                                      branchAddress.isNotEmpty)
                                  ? branchAddress
                                  : pickupTitle);
                          await _openExternalNavigation(
                            lat: target.latitude,
                            lng: target.longitude,
                            address: address,
                          );
                        },
                        child: Padding(
                          padding: EdgeInsets.all(6.w),
                          child: const Icon(Icons.open_in_new,
                              color: Colors.white, size: 18),
                        ),
                      ),
                      SizedBox(width: 6.w),
                      if (!isPickedUp && pickupKm != null)
                        Text(
                          '${(pickupKm * 1000).round()} م',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16.sp),
                        ),
                      SizedBox(width: 6.w),
                      const Icon(Icons.arrow_forward_ios,
                          color: Colors.white, size: 16),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 14.h),
              SizedBox(
                width: double.infinity,
                height: 48.h,
                child: ElevatedButton(
                  onPressed: orderId == null
                      ? null
                      : () async {
                          HapticFeedback.mediumImpact();
                          try {
                            if (isPickedUp) {
                              await ref
                                  .read(driverControllerProvider.notifier)
                                  .deliverOrder(orderId);
                              if (!context.mounted) return;
                              await _showTripCompletedDialog(context,
                                  earnings: deliveryFee);
                            } else {
                              await ref
                                  .read(driverControllerProvider.notifier)
                                  .pickupOrder(orderId);
                              if (!context.mounted) return;
                              _setOptimisticOrderOverride(order, 'picked_up');

                              final driverNow = ref
                                  .read(driverControllerProvider)
                                  .valueOrNull
                                  ?.currentLocation;
                              if (customerLocation != null) {
                                _moveTo(customerLocation, zoom: 16);
                              }
                              if (driverNow != null &&
                                  customerLocation != null) {
                                unawaited(_maybeRefreshDropoffRoute(
                                    driverNow, customerLocation));
                                _updateDropoffGuidance(driverNow);
                              }

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                      'تم استلام الطلب وتحديد طريق العميل'),
                                  action: (customerLat != null &&
                                          customerLng != null)
                                      ? SnackBarAction(
                                          label: 'خرائط Google',
                                          onPressed: () async {
                                            await _openExternalNavigation(
                                              lat: customerLat,
                                              lng: customerLng,
                                              address: customerAddress,
                                            );
                                          },
                                        )
                                      : null,
                                ),
                              );
                            }
                          } catch (_) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('تعذر تنفيذ العملية')),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPickedUp
                        ? Colors.black
                        : Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18.r)),
                  ),
                  child:
                      Text(isPickedUp ? 'تم تسليم الطلبية' : 'تم استلام الطلب'),
                ),
              ),
              SizedBox(height: 12.h),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16.r),
                      onTap: () async {
                        if (customerPhone == null || customerPhone.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('لا يوجد رقم هاتف')),
                          );
                          return;
                        }
                        await _openWhatsApp(customerPhone);
                      },
                      child: Container(
                        height: 46.h,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.chat_bubble_outline,
                                color: Colors.blue),
                            SizedBox(width: 10.w),
                            const Text('واتساب'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16.r),
                      onTap: () async {
                        if (customerPhone == null || customerPhone.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('لا يوجد رقم هاتف')),
                          );
                          return;
                        }
                        await _openPhoneDialer(customerPhone);
                      },
                      child: Container(
                        height: 46.h,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.call,
                                color: Theme.of(context).primaryColor),
                            SizedBox(width: 10.w),
                            const Text('اتصال'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
