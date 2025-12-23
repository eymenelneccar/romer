import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/restaurant_repository.dart';

final restaurantControllerProvider =
    StateNotifierProvider<RestaurantController, AsyncValue<void>>((ref) {
  return RestaurantController(ref.read(restaurantRepositoryProvider));
});

class RestaurantController extends StateNotifier<AsyncValue<void>> {
  final RestaurantRepository _repository;

  RestaurantController(this._repository) : super(const AsyncValue.data(null));

  Future<void> submitOrder({
    required String customerName,
    required String phone,
    required String address,
    required double price,
    required double deliveryFee,
    int? branchId,
    double? customerLat,
    double? customerLng,
  }) async {
    state = const AsyncValue.loading();
    try {
      final customerDetails = {
        'name': customerName,
        'phone': phone,
        'address': address,
      };

      await _repository.createOrder(
        customerDetails: customerDetails,
        price: price,
        deliveryFee: deliveryFee,
        branchId: branchId,
        customerLat: customerLat,
        customerLng: customerLng,
      );

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final restaurantOrdersProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(restaurantRepositoryProvider).getOrdersStream();
});

final restaurantBranchesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.read(restaurantRepositoryProvider).getMyBranches();
});

final restaurantZonePricingProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(restaurantRepositoryProvider).getMyZonePricingStream();
});
