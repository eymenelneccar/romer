import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/user_facing_exception.dart';

final restaurantRepositoryProvider = Provider<RestaurantRepository>((ref) {
  return RestaurantRepository(Supabase.instance.client);
});

class RestaurantRepository {
  final SupabaseClient _supabase;

  RestaurantRepository(this._supabase);

  Future<List<Map<String, dynamic>>> getMyBranches() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const UserFacingException(
          'تعذر التحقق من تسجيل الدخول. الرجاء تسجيل الدخول مرة أخرى.');
    }

    final rows = await _supabase
        .from('branches')
        .select('id, restaurant_name')
        .eq('restaurant_id', user.id)
        .order('id', ascending: true);

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<int> _getMyBranchId() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const UserFacingException(
          'تعذر التحقق من تسجيل الدخول. الرجاء تسجيل الدخول مرة أخرى.');
    }

    final branch = await _supabase
        .from('branches')
        .select('id')
        .eq('restaurant_id', user.id)
        .order('id', ascending: true)
        .limit(1)
        .maybeSingle();

    final branchId = (branch?['id'] as num?)?.toInt();
    if (branchId == null) {
      throw const UserFacingException(
          'بيانات المطعم غير مكتملة حالياً. الرجاء التواصل مع الأدمن.');
    }

    return branchId;
  }

  // Create a new order
  Future<void> createOrder({
    required Map<String, dynamic> customerDetails,
    required double price,
    required double deliveryFee,
    int? branchId,
    double? customerLat,
    double? customerLng,
  }) async {
    final resolvedBranchId = branchId ?? await _getMyBranchId();

    try {
      final order = <String, dynamic>{
        'customer_details': customerDetails,
        'price': price,
        'delivery_fee': deliveryFee,
        'branch_id': resolvedBranchId,
        'status': 'pending',
      };

      if (customerLat != null && customerLng != null) {
        order['customer_lat'] = customerLat;
        order['customer_lng'] = customerLng;
      }

      await _supabase.from('orders').insert(order);
    } on PostgrestException catch (e) {
      final code = e.code ?? '';
      if (code == '42501') {
        throw const UserFacingException(
            'صلاحياتك لا تسمح بإرسال الطلب. انتظر موافقة الأدمن أو تواصل معه.');
      }
      if (code == '23503') {
        throw const UserFacingException(
            'تعذر إرسال الطلب بسبب إعدادات المطعم. تواصل مع الأدمن.');
      }
      if (code == '23502') {
        throw const UserFacingException('تعذر إرسال الطلب. تواصل مع الأدمن.');
      }
      throw UserFacingException('تعذر إرسال الطلب: ${e.message}');
    }
  }

  Future<void> resendOrder(int orderId) async {
    try {
      await _supabase.rpc(
        'restaurant_resend_order',
        params: {'p_order_id': orderId},
      );
    } on PostgrestException catch (e) {
      final raw = e.message;
      if (raw.contains('Order not found')) {
        throw const UserFacingException('الطلب غير موجود.');
      }
      if (raw.contains('Order is not pending')) {
        throw const UserFacingException(
            'لا يمكن إعادة الإرسال لأن الطلب ليس معلقاً.');
      }
      if (raw.contains('Order already accepted')) {
        throw const UserFacingException(
            'لا يمكن إعادة الإرسال لأن الطلب تم قبوله.');
      }
      if (raw.contains('Restaurant not approved')) {
        throw const UserFacingException('حساب المطعم غير مفعّل بعد.');
      }
      if (raw.contains('Only restaurants can resend orders')) {
        throw const UserFacingException('ليس لديك صلاحية لإعادة إرسال الطلب.');
      }
      throw UserFacingException('تعذر إعادة إرسال الطلب: ${e.message}');
    } catch (e) {
      throw const UserFacingException('تعذر إعادة إرسال الطلب.');
    }
  }

  // Get real-time stream of orders for the restaurant
  Stream<List<Map<String, dynamic>>> getOrdersStream() {
    return _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .asyncMap((data) async {
          final orders = List<Map<String, dynamic>>.from(data);
          if (orders.isEmpty) return orders;

          final driverIds = orders
              .map((o) => o['driver_id']?.toString().trim())
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList();
          if (driverIds.isEmpty) return orders;

          final profiles = await _supabase
              .from('profiles')
              .select('id, name, phone')
              .inFilter('id', driverIds);

          final byId = <String, Map<String, dynamic>>{};
          for (final p in profiles) {
            final id = p['id']?.toString().trim();
            if (id == null || id.isEmpty) continue;
            byId[id] = Map<String, dynamic>.from(p);
          }

          return orders.map((o) {
            final driverId = o['driver_id']?.toString().trim();
            final p = (driverId != null && driverId.isNotEmpty)
                ? byId[driverId]
                : null;
            final driverName = p?['name']?.toString().trim();
            final driverPhone = p?['phone']?.toString().trim();
            return {
              ...o,
              if (driverName != null && driverName.isNotEmpty)
                'driver_name': driverName,
              if (driverPhone != null && driverPhone.isNotEmpty)
                'driver_phone': driverPhone,
            };
          }).toList();
        });
  }

  Stream<List<Map<String, dynamic>>> getMyZonePricingStream() {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return Stream.value(<Map<String, dynamic>>[]);
    }

    return _supabase
        .from('restaurant_zone_pricing')
        .stream(primaryKey: ['id'])
        .eq('restaurant_id', user.id)
        .order('created_at', ascending: false)
        .asyncMap((rows) async {
          if (rows.isEmpty) return <Map<String, dynamic>>[];

          final zoneIds = rows
              .map((r) => (r['zone_id'] as num?)?.toInt())
              .whereType<int>()
              .toList();

          final zones = await _supabase
              .from('zones')
              .select('id, name')
              .inFilter('id', zoneIds);
          final zonesMap = <int, String>{};
          for (final z in zones) {
            final id = (z['id'] as num?)?.toInt();
            final name = z['name']?.toString().trim();
            if (id != null && name != null && name.isNotEmpty) {
              zonesMap[id] = name;
            }
          }

          return rows.map((r) {
            final zid = (r['zone_id'] as num?)?.toInt();
            final fee = (r['delivery_fee'] as num?)?.toDouble() ?? 0.0;
            return {
              'zone_id': zid,
              'zone_name': zid == null ? null : zonesMap[zid],
              'delivery_fee': fee,
            };
          }).toList();
        });
  }
}
