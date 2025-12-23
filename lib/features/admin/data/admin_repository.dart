import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(Supabase.instance.client);
});

class AdminRepository {
  final SupabaseClient _supabase;

  AdminRepository(this._supabase);

  Future<Map<String, dynamic>> settleDriverWallet(
      {required String driverId}) async {
    final res = await _supabase.rpc(
      'admin_settle_driver_wallet',
      params: {'p_driver_id': driverId},
    );

    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    if (res is List && res.isNotEmpty && res.first is Map) {
      return Map<String, dynamic>.from(res.first as Map);
    }

    throw Exception('Unexpected response from admin_settle_driver_wallet');
  }

  // Stream of all online drivers with their locations and status
  // Joining with profiles to get names
  Stream<List<Map<String, dynamic>>> getAllDriversStream() {
    return _supabase
        .from('drivers_profiles')
        .stream(primaryKey: ['id'])
        .order('updated_at', ascending: false)
        .asyncMap((drivers) async {
          // Manually join profiles because Supabase Stream doesn't support joins directly yet easily
          // For efficiency in a real app, we might handle this differently (e.g. view or fetching profiles once)
          // Here we will just fetch profile names for the drivers

          if (drivers.isEmpty) return [];

          final driverIds = drivers.map((d) => d['id']).toList();
          final driverIdStrings = <String>[
            for (final id in driverIds)
              if (id != null) id.toString(),
          ];

          final deliveredByDriver = <String, int>{};
          final naemiShareByDriver = <String, double>{};

          List<List<T>> chunk<T>(List<T> list, int size) {
            final out = <List<T>>[];
            for (var i = 0; i < list.length; i += size) {
              out.add(list.sublist(
                  i, (i + size) > list.length ? list.length : (i + size)));
            }
            return out;
          }

          for (final ids in chunk(driverIdStrings, 100)) {
            final deliveredRows = await _supabase
                .from('orders')
                .select('driver_id')
                .inFilter('driver_id', ids)
                .eq('status', 'delivered');

            for (final r in deliveredRows) {
              final id = r['driver_id']?.toString();
              if (id == null || id.isEmpty) continue;
              deliveredByDriver[id] = (deliveredByDriver[id] ?? 0) + 1;
            }

            final walletRows = await _supabase
                .from('wallet_transactions')
                .select('driver_id, naemi_percentage')
                .inFilter('driver_id', ids)
                .eq('type', 'delivery_fee');

            for (final r in walletRows) {
              final id = r['driver_id']?.toString();
              if (id == null || id.isEmpty) continue;
              final naemi = (r['naemi_percentage'] as num?)?.toDouble() ?? 0.0;
              naemiShareByDriver[id] = (naemiShareByDriver[id] ?? 0.0) + naemi;
            }
          }

          final profiles = await _supabase
              .from('profiles')
              .select('id, name, phone')
              .inFilter('id', driverIds);

          final profilesMap = {for (var p in profiles) p['id']: p};

          return drivers.map((driver) {
            final profile = profilesMap[driver['id']];
            final id = driver['id']?.toString();
            final deliveredCount =
                id == null ? 0 : (deliveredByDriver[id] ?? 0);
            final naemiShare =
                id == null ? 0.0 : (naemiShareByDriver[id] ?? 0.0);
            return {
              ...driver,
              'name': profile?['name'] ?? 'Unknown Driver',
              'phone': profile?['phone'] ?? '',
              'delivered_orders_count': deliveredCount,
              'naemi_share_total': naemiShare,
            };
          }).toList();
        });
  }

  Stream<List<Map<String, dynamic>>> getAllProfilesStream() {
    return _supabase
        .from('profiles')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => List<Map<String, dynamic>>.from(data));
  }

  Future<void> updateUserRole(
      {required String userId, required String role}) async {
    final res = await _supabase.rpc(
      'admin_set_user_role',
      params: {'p_user_id': userId, 'p_role': role},
    );

    String? updatedRole;
    if (res is List && res.isNotEmpty) {
      updatedRole = (res.first as Map<String, dynamic>)['role']?.toString();
    } else if (res is Map) {
      updatedRole = res['role']?.toString();
    }

    if (updatedRole == null) {
      throw Exception(
          'لم يتم تحديث الدور. تأكد من تطبيق migration الخاصة بالأدمن.');
    }
    if (updatedRole != role) {
      throw Exception('تم رفض تحديث الدور إلى القيمة المطلوبة.');
    }
  }

  Stream<List<Map<String, dynamic>>> getRestaurantZonePricingStream() {
    return _supabase
        .from('restaurant_zone_pricing')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => List<Map<String, dynamic>>.from(data));
  }

  Future<void> upsertRestaurantZonePricing({
    required String restaurantId,
    required int zoneId,
    required double deliveryFee,
  }) async {
    await _supabase.from('restaurant_zone_pricing').upsert(
      {
        'restaurant_id': restaurantId,
        'zone_id': zoneId,
        'delivery_fee': deliveryFee,
      },
      onConflict: 'restaurant_id,zone_id',
    );
  }

  Future<void> createZoneAndSetPrice({
    required String restaurantId,
    required String zoneName,
    required double deliveryFee,
  }) async {
    await _supabase.rpc(
      'admin_create_zone_and_set_price',
      params: {
        'p_restaurant_id': restaurantId,
        'p_zone_name': zoneName,
        'p_delivery_fee': deliveryFee,
      },
    );
  }

  // Stream of all active orders (not delivered/cancelled)
  Stream<List<Map<String, dynamic>>> getActiveOrdersStream() {
    final nowUtc = DateTime.now().toUtc();
    final cutoff = nowUtc.subtract(const Duration(hours: 24));
    final activeStatuses = <String>[
      'pending',
      'pending_repost',
      'accepted',
      'picked_up',
    ];

    List<List<T>> chunk<T>(List<T> list, int size) {
      final out = <List<T>>[];
      for (var i = 0; i < list.length; i += size) {
        out.add(list.sublist(
            i, (i + size) > list.length ? list.length : (i + size)));
      }
      return out;
    }

    return _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .inFilter('status', activeStatuses)
        .order('created_at', ascending: false)
        .map((data) => List<Map<String, dynamic>>.from(data))
        .map((orders) {
          return orders.where((o) {
            final raw = o['created_at'];
            DateTime? createdAt;
            if (raw is DateTime) {
              createdAt = raw;
            } else if (raw is String) {
              createdAt = DateTime.tryParse(raw);
            }
            if (createdAt == null) return true;
            return createdAt.toUtc().isAfter(cutoff);
          }).toList();
        })
        .asyncMap((orders) async {
          if (orders.isEmpty) return orders;

          final branchIds = orders
              .map((o) => (o['branch_id'] as num?)?.toInt())
              .whereType<int>()
              .toSet()
              .toList();
          final driverIds = orders
              .map((o) => o['driver_id']?.toString())
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList();

          final branchById = <int, Map<String, dynamic>>{};
          for (final ids in chunk(branchIds, 100)) {
            final rows = await _supabase
                .from('branches')
                .select('id, restaurant_name, address, restaurant_id')
                .inFilter('id', ids);
            for (final r in rows) {
              final id = (r['id'] as num?)?.toInt();
              if (id == null) continue;
              branchById[id] = Map<String, dynamic>.from(r);
            }
          }

          final driverById = <String, Map<String, dynamic>>{};
          for (final ids in chunk(driverIds, 100)) {
            final rows = await _supabase
                .from('profiles')
                .select('id, name, phone')
                .inFilter('id', ids);
            for (final r in rows) {
              final id = r['id']?.toString();
              if (id == null || id.isEmpty) continue;
              driverById[id] = Map<String, dynamic>.from(r);
            }
          }

          return orders.map((o) {
            final branchId = (o['branch_id'] as num?)?.toInt();
            final branch = branchId == null ? null : branchById[branchId];
            final driverId = o['driver_id']?.toString();
            final driver = (driverId == null || driverId.isEmpty)
                ? null
                : driverById[driverId];

            final restaurantName = branch?['restaurant_name']?.toString();
            final branchAddress = branch?['address']?.toString();
            final driverName = driver?['name']?.toString();
            final driverPhone = driver?['phone']?.toString();

            return {
              ...o,
              if (restaurantName != null && restaurantName.isNotEmpty)
                'restaurant_name': restaurantName,
              if (branchId != null) 'branch_name': 'فرع #$branchId',
              if (branchAddress != null && branchAddress.isNotEmpty)
                'branch_address': branchAddress,
              if (driverName != null && driverName.isNotEmpty)
                'driver_name': driverName,
              if (driverPhone != null && driverPhone.isNotEmpty)
                'driver_phone': driverPhone,
            };
          }).toList();
        });
  }

  Stream<List<Map<String, dynamic>>> getRestaurantsStream() {
    final activeStatuses = <String>[
      'pending',
      'pending_repost',
      'accepted',
      'picked_up',
    ];

    return _supabase
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('role', 'restaurant')
        .order('created_at', ascending: false)
        .asyncMap((data) async {
          final restaurants = List<Map<String, dynamic>>.from(data);
          if (restaurants.isEmpty) return restaurants;

          final restaurantIds = restaurants
              .map((r) => r['id']?.toString())
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toList();
          if (restaurantIds.isEmpty) return restaurants;

          List<List<T>> chunk<T>(List<T> list, int size) {
            final out = <List<T>>[];
            for (var i = 0; i < list.length; i += size) {
              out.add(list.sublist(
                  i, (i + size) > list.length ? list.length : (i + size)));
            }
            return out;
          }

          final branchToRestaurant = <int, String>{};
          for (final ids in chunk(restaurantIds, 100)) {
            final rows = await _supabase
                .from('branches')
                .select('id, restaurant_id')
                .inFilter('restaurant_id', ids);
            for (final r in rows) {
              final branchId = (r['id'] as num?)?.toInt();
              final rid = r['restaurant_id']?.toString();
              if (branchId == null || rid == null || rid.isEmpty) continue;
              branchToRestaurant[branchId] = rid;
            }
          }

          if (branchToRestaurant.isEmpty) {
            return restaurants
                .map((r) => {...r, 'outgoing_orders_count': 0})
                .toList();
          }

          final activeByRestaurant = <String, int>{};
          final branchIds = branchToRestaurant.keys.toList();

          for (final ids in chunk(branchIds, 100)) {
            final rows = await _supabase
                .from('orders')
                .select('branch_id')
                .inFilter('branch_id', ids)
                .inFilter('status', activeStatuses);

            for (final o in rows) {
              final branchId = (o['branch_id'] as num?)?.toInt();
              if (branchId == null) continue;

              final rid = branchToRestaurant[branchId];
              if (rid == null) continue;
              activeByRestaurant[rid] = (activeByRestaurant[rid] ?? 0) + 1;
            }
          }

          return restaurants.map((r) {
            final id = r['id']?.toString();
            final count = id == null ? 0 : (activeByRestaurant[id] ?? 0);
            return {
              ...r,
              'outgoing_orders_count': count,
            };
          }).toList();
        });
  }

  Stream<List<Map<String, dynamic>>> getZonesStream() {
    return _supabase
        .from('zones')
        .stream(primaryKey: ['id'])
        .order('id', ascending: true)
        .map((data) => List<Map<String, dynamic>>.from(data));
  }

  Stream<List<Map<String, dynamic>>> getPendingMembersStream() {
    return _supabase
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('approval_status', 'pending')
        .order('approval_requested_at', ascending: false)
        .map((data) => List<Map<String, dynamic>>.from(data));
  }

  Future<void> approveMembership({required String userId}) async {
    await _supabase
        .rpc('admin_approve_membership', params: {'p_user_id': userId});
  }

  Future<void> rejectMembership({required String userId}) async {
    await _supabase
        .rpc('admin_reject_membership', params: {'p_user_id': userId});
  }
}
