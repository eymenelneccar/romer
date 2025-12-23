import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/admin_repository.dart';

final adminDriversProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(adminRepositoryProvider).getAllDriversStream();
});

final adminOrdersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(adminRepositoryProvider).getActiveOrdersStream();
});

final adminRestaurantsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(adminRepositoryProvider).getRestaurantsStream();
});

final adminZonesProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(adminRepositoryProvider).getZonesStream();
});

final adminRestaurantZonePricingProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(adminRepositoryProvider).getRestaurantZonePricingStream();
});

final adminUsersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(adminRepositoryProvider).getAllProfilesStream();
});

final adminPendingMembersProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(adminRepositoryProvider).getPendingMembersStream();
});

// Derived statistics
final onlineDriversCountProvider = Provider<AsyncValue<int>>((ref) {
  final drivers = ref.watch(adminDriversProvider);
  return drivers
      .whenData((list) => list.where((d) => d['is_available'] == true).length);
});

final activeOrdersCountProvider = Provider<AsyncValue<int>>((ref) {
  final orders = ref.watch(adminOrdersProvider);
  return orders.whenData((list) => list.length);
});

final pendingMembersCountProvider = Provider<AsyncValue<int>>((ref) {
  final pending = ref.watch(adminPendingMembersProvider);
  return pending.whenData((list) => list.length);
});
