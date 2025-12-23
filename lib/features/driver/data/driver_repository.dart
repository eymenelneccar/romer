import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/user_facing_exception.dart';

final driverRepositoryProvider = Provider<DriverRepository>((ref) {
  return DriverRepository(Supabase.instance.client);
});

class DriverRepository {
  final SupabaseClient _supabase;

  DriverRepository(this._supabase);

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    if (kReleaseMode) return;
    developer.log(message,
        name: 'naemi_team', error: error, stackTrace: stackTrace);
  }

  // Update driver location and status
  Future<void> updateLocation({
    required String userId,
    required double lat,
    required double lng,
    required bool isAvailable,
  }) async {
    // Check if profile exists first
    final exists = await _supabase
        .from('drivers_profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (exists == null) {
      // Create profile if not exists
      await _supabase.from('drivers_profiles').insert({
        'id': userId,
        'current_lat': lat,
        'current_lng': lng,
        'is_available': isAvailable,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } else {
      // Update existing
      await _supabase.from('drivers_profiles').update({
        'current_lat': lat,
        'current_lng': lng,
        'is_available': isAvailable,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    }
  }

  // Toggle availability
  Future<void> setAvailability(String userId, bool isAvailable) async {
    try {
      final exists = await _supabase
          .from('drivers_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (exists == null) {
        await _supabase.from('drivers_profiles').insert({
          'id': userId,
          'is_available': isAvailable,
          'updated_at': DateTime.now().toIso8601String(),
        });
        return;
      }

      await _supabase.from('drivers_profiles').update({
        'is_available': isAvailable,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    } catch (e, st) {
      _log(
        'setAvailability failed. userId=$userId isAvailable=$isAvailable',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  // Get driver wallet balance
  Stream<Map<String, dynamic>?> getDriverProfileStream(String userId) {
    return _supabase
        .from('drivers_profiles')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .map((event) => event.isEmpty ? null : event.first);
  }

  Stream<List<Map<String, dynamic>>> getAvailabilitySlotsStream(String userId) {
    return _supabase
        .from('driver_availability_slots')
        .stream(primaryKey: ['id'])
        .eq('driver_id', userId)
        .order('day_of_week', ascending: true)
        .order('start_min', ascending: true)
        .map((data) => List<Map<String, dynamic>>.from(data));
  }

  Future<List<Map<String, dynamic>>> getAvailabilitySlots(String userId) async {
    final data = await _supabase
        .from('driver_availability_slots')
        .select()
        .eq('driver_id', userId)
        .order('day_of_week', ascending: true)
        .order('start_min', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  bool _overlaps(int aStart, int aEnd, int bStart, int bEnd) {
    return aStart < bEnd && aEnd > bStart;
  }

  Future<void> _ensureNoActiveOverlap({
    required String userId,
    required int dayOfWeek,
    required int startMin,
    required int endMin,
    required bool isActive,
    int? excludeSlotId,
  }) async {
    if (!isActive) return;

    final rows = await _supabase
        .from('driver_availability_slots')
        .select('id, start_min, end_min, is_active')
        .eq('driver_id', userId)
        .eq('day_of_week', dayOfWeek)
        .order('start_min', ascending: true);

    for (final r in rows) {
      final id = (r['id'] as num?)?.toInt();
      if (excludeSlotId != null && id == excludeSlotId) continue;
      if (r['is_active'] != true) continue;
      final s = (r['start_min'] as num).toInt();
      final e = (r['end_min'] as num).toInt();
      if (_overlaps(startMin, endMin, s, e)) {
        throw const PostgrestException(
            message: 'تداخل في أوقات النشاط. عدّل الأوقات لتجنب التداخل.');
      }
    }
  }

  Future<void> createAvailabilitySlot({
    required String userId,
    required int dayOfWeek,
    required int startMin,
    required int endMin,
    bool isActive = true,
  }) async {
    try {
      await _ensureNoActiveOverlap(
        userId: userId,
        dayOfWeek: dayOfWeek,
        startMin: startMin,
        endMin: endMin,
        isActive: isActive,
      );
      await _supabase.from('driver_availability_slots').insert({
        'driver_id': userId,
        'day_of_week': dayOfWeek,
        'start_min': startMin,
        'end_min': endMin,
        'is_active': isActive,
      });
    } catch (e, st) {
      _log(
        'createAvailabilitySlot failed. userId=$userId dayOfWeek=$dayOfWeek startMin=$startMin endMin=$endMin',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  Future<void> updateAvailabilitySlot({
    required int slotId,
    required int dayOfWeek,
    required int startMin,
    required int endMin,
    required bool isActive,
  }) async {
    try {
      final current = await _supabase
          .from('driver_availability_slots')
          .select('driver_id')
          .eq('id', slotId)
          .maybeSingle();
      if (current == null) {
        throw const UserFacingException(
            'تعذر التحديث: وقت النشاط غير موجود أو لا تملك صلاحية تعديله.');
      }
      final userId = current['driver_id']?.toString();
      if (userId != null && userId.isNotEmpty) {
        await _ensureNoActiveOverlap(
          userId: userId,
          dayOfWeek: dayOfWeek,
          startMin: startMin,
          endMin: endMin,
          isActive: isActive,
          excludeSlotId: slotId,
        );
      }
      await _supabase.from('driver_availability_slots').update({
        'day_of_week': dayOfWeek,
        'start_min': startMin,
        'end_min': endMin,
        'is_active': isActive,
      }).eq('id', slotId);
    } catch (e, st) {
      _log(
        'updateAvailabilitySlot failed. slotId=$slotId',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  Future<void> deleteAvailabilitySlot(int slotId) async {
    try {
      await _supabase
          .from('driver_availability_slots')
          .delete()
          .eq('id', slotId);
    } catch (e, st) {
      _log(
        'deleteAvailabilitySlot failed. slotId=$slotId',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  Future<void> deactivateAllAvailabilitySlots(String userId) async {
    try {
      await _supabase
          .from('driver_availability_slots')
          .update({'is_active': false})
          .eq('driver_id', userId)
          .eq('is_active', true);
    } catch (e, st) {
      _log(
        'deactivateAllAvailabilitySlots failed. userId=$userId',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  Stream<List<Map<String, dynamic>>> getWalletTransactionsStream(
      String userId) {
    return _supabase
        .from('wallet_transactions')
        .stream(primaryKey: ['id'])
        .eq('driver_id', userId)
        .order('created_at', ascending: false)
        .map((data) => List<Map<String, dynamic>>.from(data));
  }

  Stream<List<Map<String, dynamic>>> getOrderHistoryStream(String driverId) {
    return _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('driver_id', driverId)
        .order('created_at', ascending: false)
        .map((data) => List<Map<String, dynamic>>.from(data))
        .map(
          (orders) => orders
              .where((o) =>
                  o['status'] == 'delivered' || o['status'] == 'cancelled')
              .toList(),
        );
  }

  // --- Dispatch Logic ---

  // Stream of available orders (pending)
  Stream<List<Map<String, dynamic>>> getAvailableOrdersStream() {
    return _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => List<Map<String, dynamic>>.from(data))
        .map((orders) => orders
            .where((o) =>
                o['status'] == 'pending' || o['status'] == 'pending_repost')
            .toList())
        .handleError((e, st) {
          _log('getAvailableOrdersStream failed.', error: e, stackTrace: st);
        })
        .asyncMap((orders) async {
          if (orders.isEmpty) return orders;

          final orderIds = orders
              .map((o) => o['id'])
              .whereType<num>()
              .map((n) => n.toInt())
              .toList();
          if (orderIds.isEmpty) return orders;

          List<dynamic> rows;
          try {
            rows = await _supabase
                .from('driver_orders_with_branch')
                .select(
                    'order_id, branch_id, branch_name, lat, lng, restaurant_name, branch_address')
                .inFilter('order_id', orderIds);
          } catch (e, st) {
            _log('getAvailableOrdersStream failed (join view fetch).',
                error: e, stackTrace: st);
            return orders;
          }

          final byOrderId = <int, Map<String, dynamic>>{
            for (final r in rows)
              (r['order_id'] as num).toInt(): Map<String, dynamic>.from(r),
          };

          return orders.map((o) {
            final id = (o['id'] as num?)?.toInt();
            final branch = id != null ? byOrderId[id] : null;
            return {
              ...o,
              if (branch != null) ...branch,
            };
          }).toList();
        });
  }

  // Stream of active order for specific driver
  Stream<Map<String, dynamic>?> getActiveOrderStream(String driverId) {
    return _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('driver_id', driverId)
        .order('created_at', ascending: false)
        .map((data) => List<Map<String, dynamic>>.from(data))
        .map((orders) {
          for (final o in orders) {
            final status = o['status'];
            if (status != 'delivered' && status != 'cancelled') return o;
          }
          return null;
        })
        .asyncMap((order) async {
          if (order == null) return null;
          final id = (order['id'] as num?)?.toInt();
          if (id == null) return order;

          final branch = await _supabase
              .from('driver_orders_with_branch')
              .select(
                  'order_id, branch_id, branch_name, lat, lng, restaurant_name, branch_address')
              .eq('order_id', id)
              .maybeSingle();

          if (branch == null) return order;

          return {
            ...order,
            ...Map<String, dynamic>.from(branch),
          };
        });
  }

  // Accept an order
  Future<void> acceptOrder(int orderId) async {
    dynamic accepted;
    try {
      accepted = await _supabase.rpc(
        'accept_order',
        params: {'p_order_id': orderId},
      );
    } catch (e, st) {
      _log('accept_order failed (rpc error). orderId=$orderId',
          error: e, stackTrace: st);
      rethrow;
    }

    if (accepted == 'success') return;
    if (accepted == 'already_taken') {
      _log('accept_order failed. orderId=$orderId result=already_taken');
      throw const UserFacingException('تم أخذ الطلب من سائق آخر!');
    }

    _log('accept_order failed. orderId=$orderId result=$accepted');
    throw Exception('Unable to accept order');
  }

  Future<void> pickupOrder(int orderId) async {
    dynamic result;
    try {
      result = await _supabase.rpc(
        'pickup_order',
        params: {'p_order_id': orderId},
      );
    } catch (e, st) {
      _log('pickup_order failed (rpc error). orderId=$orderId',
          error: e, stackTrace: st);
      rethrow;
    }

    if (result == 'success') return;

    _log('pickup_order failed. orderId=$orderId result=$result');
    throw Exception('Unable to pickup order');
  }

  // Complete order (delivered) and handle wallet
  Future<void> completeOrder(int orderId) async {
    dynamic completed;
    try {
      completed = await _supabase.rpc(
        'complete_order',
        params: {'p_order_id': orderId},
      );
    } catch (e, st) {
      _log('complete_order failed (rpc error). orderId=$orderId',
          error: e, stackTrace: st);
      rethrow;
    }

    if (completed != true) {
      _log('complete_order failed. orderId=$orderId result=$completed');
      throw Exception('Unable to complete order');
    }
  }
}
