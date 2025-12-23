import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../../auth/data/auth_repository.dart';
import '../../data/driver_repository.dart';

final driverControllerProvider =
    StateNotifierProvider<DriverController, AsyncValue<DriverState>>((ref) {
  final driverRepo = ref.read(driverRepositoryProvider);
  final authRepo = ref.read(authRepositoryProvider);
  return DriverController(driverRepo, authRepo);
});

class DriverState {
  final bool isOnline;
  final LatLng? currentLocation;

  DriverState({this.isOnline = false, this.currentLocation});

  DriverState copyWith({bool? isOnline, LatLng? currentLocation}) {
    return DriverState(
      isOnline: isOnline ?? this.isOnline,
      currentLocation: currentLocation ?? this.currentLocation,
    );
  }
}

class DriverController extends StateNotifier<AsyncValue<DriverState>> {
  final DriverRepository _driverRepository;
  final AuthRepository _authRepository;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<List<Map<String, dynamic>>>? _slotsSubscription;
  Timer? _availabilityTimer;
  bool _lastSentAvailability = true;
  List<Map<String, dynamic>> _cachedSlots = const <Map<String, dynamic>>[];

  DriverController(this._driverRepository, this._authRepository)
      : super(AsyncValue.data(DriverState(isOnline: false)));

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

  Future<void> _applyScheduleAvailability(String userId,
      {DateTime? now}) async {
    try {
      final isAvailableNow =
          _isWithinSchedule(_cachedSlots, now ?? DateTime.now());
      if (isAvailableNow == _lastSentAvailability) return;
      _lastSentAvailability = isAvailableNow;
      await _driverRepository.setAvailability(userId, isAvailableNow);
    } catch (_) {}
  }

  void _startAvailabilityTimer(String userId) {
    _availabilityTimer?.cancel();
    _availabilityTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _applyScheduleAvailability(userId),
    );
  }

  void _startSlotsListener(String userId) {
    _slotsSubscription?.cancel();
    _slotsSubscription =
        _driverRepository.getAvailabilitySlotsStream(userId).listen((slots) {
      _cachedSlots = slots;
      _applyScheduleAvailability(userId);
    }, onError: (_, __) {});
  }

  Future<void> toggleOnlineStatus(bool isOnline) async {
    final user = _authRepository.currentUser;
    if (user == null) return;

    final previousState = state.valueOrNull ?? DriverState(isOnline: false);
    state = const AsyncValue.loading();
    try {
      if (isOnline) {
        // Request permissions and start tracking
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          final requested = await Geolocator.requestPermission();
          if (requested == LocationPermission.denied) {
            throw Exception('Location permission denied');
          }
        }

        // Get initial location
        final position = await Geolocator.getCurrentPosition();
        final latLng = LatLng(position.latitude, position.longitude);

        final slots = await _driverRepository.getAvailabilitySlots(user.id);
        _cachedSlots = slots;
        final isAvailableNow = _isWithinSchedule(_cachedSlots, DateTime.now());
        _lastSentAvailability = isAvailableNow;

        // Update server
        await _driverRepository.updateLocation(
          userId: user.id,
          lat: latLng.latitude,
          lng: latLng.longitude,
          isAvailable: isAvailableNow,
        );

        state = AsyncValue.data(
            DriverState(isOnline: true, currentLocation: latLng));

        // Start listening to updates
        _startSlotsListener(user.id);
        _startAvailabilityTimer(user.id);
        _startLocationUpdates(user.id);
      } else {
        // Go offline
        _availabilityTimer?.cancel();
        _availabilityTimer = null;
        await _slotsSubscription?.cancel();
        _slotsSubscription = null;
        _cachedSlots = const <Map<String, dynamic>>[];
        await _positionStream?.cancel();
        _positionStream = null;

        await _driverRepository.setAvailability(user.id, false);

        state = AsyncValue.data(previousState.copyWith(isOnline: false));
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void _startLocationUpdates(String userId) {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen((position) {
      final latLng = LatLng(position.latitude, position.longitude);

      // Update local state
      final current = state.valueOrNull;
      state = AsyncValue.data((current ?? DriverState(isOnline: true))
          .copyWith(currentLocation: latLng));

      final isAvailableNow = _isWithinSchedule(_cachedSlots, DateTime.now());
      if (isAvailableNow != _lastSentAvailability) {
        _lastSentAvailability = isAvailableNow;
        _driverRepository
            .setAvailability(userId, isAvailableNow)
            .catchError((_, __) {});
      }

      // Update server (fire and forget to avoid blocking UI)
      _driverRepository
          .updateLocation(
        userId: userId,
        lat: latLng.latitude,
        lng: latLng.longitude,
        isAvailable: isAvailableNow,
      )
          .catchError((e, st) async {
        await _positionStream?.cancel();
        _positionStream = null;
        state = AsyncValue.error(e, st is StackTrace ? st : StackTrace.current);
      });
    }, onError: (e, st) async {
      await _positionStream?.cancel();
      _positionStream = null;
      state = AsyncValue.error(e, st);
    });
  }

  // --- Order Actions ---

  Future<void> acceptOrder(int orderId) async {
    final user = _authRepository.currentUser;
    if (user == null) return;

    try {
      await _driverRepository.acceptOrder(orderId);
    } catch (e) {
      // Handle error (e.g. order taken)
      rethrow;
    }
  }

  Future<void> pickupOrder(int orderId) async {
    await _driverRepository.pickupOrder(orderId);
  }

  Future<void> deliverOrder(int orderId) async {
    await _driverRepository.completeOrder(orderId);
  }

  @override
  void dispose() {
    _availabilityTimer?.cancel();
    _slotsSubscription?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }
}

class DriverStats {
  final int totalOrders;
  final int deliveredOrders;
  final int cancelledOrders;
  final double acceptanceRate;

  const DriverStats({
    required this.totalOrders,
    required this.deliveredOrders,
    required this.cancelledOrders,
    required this.acceptanceRate,
  });
}

// Provider for Available Orders
final availableOrdersProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(driverRepositoryProvider).getAvailableOrdersStream();
});

// Provider for Active Order (The one the driver is currently working on)
final activeOrderProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final user = ref.read(authRepositoryProvider).currentUser;
  if (user == null) return const Stream.empty();
  return ref.read(driverRepositoryProvider).getActiveOrderStream(user.id);
});

final driverAvailabilitySlotsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, userId) {
  return ref.read(driverRepositoryProvider).getAvailabilitySlotsStream(userId);
});

final driverProfileProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final user = ref.read(authRepositoryProvider).currentUser;
  if (user == null) return const Stream<Map<String, dynamic>?>.empty();
  return ref
      .read(driverRepositoryProvider)
      .getDriverProfileStream(user.id)
      .map((event) => event);
});

final walletTransactionsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.read(authRepositoryProvider).currentUser;
  if (user == null) return const Stream<List<Map<String, dynamic>>>.empty();
  return ref
      .read(driverRepositoryProvider)
      .getWalletTransactionsStream(user.id);
});

final orderHistoryProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.read(authRepositoryProvider).currentUser;
  if (user == null) return const Stream<List<Map<String, dynamic>>>.empty();
  return ref.read(driverRepositoryProvider).getOrderHistoryStream(user.id);
});

final driverStatsProvider = Provider<AsyncValue<DriverStats>>((ref) {
  final history = ref.watch(orderHistoryProvider);
  return history.whenData((orders) {
    var delivered = 0;
    var cancelled = 0;

    for (final o in orders) {
      final status = o['status'];
      if (status == 'delivered') delivered++;
      if (status == 'cancelled') cancelled++;
    }

    final total = delivered + cancelled;
    final acceptanceRate = total == 0 ? 0.0 : delivered / total;

    return DriverStats(
      totalOrders: total,
      deliveredOrders: delivered,
      cancelledOrders: cancelled,
      acceptanceRate: acceptanceRate,
    );
  });
});
