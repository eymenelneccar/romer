import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/admin_controller.dart';
import '../../data/admin_repository.dart';
import '../../../../core/error_view.dart';
import '../../../../core/user_facing_exception.dart';

class AdminZonesScreen extends ConsumerWidget {
  const AdminZonesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonesAsync = ref.watch(adminZonesProvider);
    final restaurantsAsync = ref.watch(adminRestaurantsProvider);
    final pricingAsync = ref.watch(adminRestaurantZonePricingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة المناطق'),
      ),
      body: restaurantsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorView(
          title: 'تعذر تحميل المطاعم',
          error: err,
          onRetry: () => ref.invalidate(adminRestaurantsProvider),
        ),
        data: (restaurants) {
          return zonesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => ErrorView(
              title: 'تعذر تحميل المناطق',
              error: err,
              onRetry: () => ref.invalidate(adminZonesProvider),
            ),
            data: (zones) {
              return pricingAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => ErrorView(
                  title: 'تعذر تحميل تسعير المناطق',
                  error: err,
                  onRetry: () =>
                      ref.invalidate(adminRestaurantZonePricingProvider),
                ),
                data: (pricing) {
                  if (restaurants.isEmpty) {
                    return const Center(child: Text('لا يوجد مطاعم'));
                  }

                  final zonesById = <int, Map<String, dynamic>>{};
                  for (final z in zones) {
                    final zid = (z['id'] as num?)?.toInt();
                    if (zid == null) continue;
                    zonesById[zid] = z;
                  }

                  final pricingByRestaurant =
                      <String, List<Map<String, dynamic>>>{};
                  for (final p in pricing) {
                    final rid = p['restaurant_id']?.toString();
                    if (rid == null) continue;
                    pricingByRestaurant.putIfAbsent(rid, () => []).add(p);
                  }

                  return ListView.separated(
                    padding: EdgeInsets.all(16.w),
                    itemCount: restaurants.length,
                    separatorBuilder: (_, __) => SizedBox(height: 10.h),
                    itemBuilder: (context, index) {
                      final r = restaurants[index];
                      final restaurantId = r['id']?.toString();
                      final restaurantName = r['name']?.toString().trim();
                      final email = r['email']?.toString().trim();

                      final list = restaurantId == null
                          ? <Map<String, dynamic>>[]
                          : (pricingByRestaurant[restaurantId] ?? []);
                      list.sort((a, b) {
                        final aZone = (a['zone_id'] as num?)?.toInt() ?? 0;
                        final bZone = (b['zone_id'] as num?)?.toInt() ?? 0;
                        return aZone.compareTo(bZone);
                      });

                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          side: BorderSide(color: Colors.grey[200]!),
                        ),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.symmetric(
                              horizontal: 12.w, vertical: 4.h),
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context)
                                .primaryColor
                                .withOpacity(0.08),
                            child: Icon(Icons.store_outlined,
                                color: Theme.of(context).primaryColor),
                          ),
                          title: Text(restaurantName?.isNotEmpty == true
                              ? restaurantName!
                              : 'مطعم'),
                          subtitle:
                              email?.isNotEmpty == true ? Text(email!) : null,
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 10.h),
                              child: SizedBox(
                                width: double.infinity,
                                height: 44.h,
                                child: ElevatedButton.icon(
                                  onPressed: restaurantId == null
                                      ? null
                                      : () => _showAddZonePriceDialog(
                                            context,
                                            ref,
                                            restaurantId: restaurantId,
                                            zones: zones,
                                          ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('إضافة المنطقة وسعرها'),
                                ),
                              ),
                            ),
                            if (list.isEmpty)
                              Padding(
                                padding: EdgeInsets.only(bottom: 12.h),
                                child: Text(
                                  'لا توجد مناطق لهذا المطعم',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              )
                            else
                              Padding(
                                padding:
                                    EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h),
                                child: Column(
                                  children: list.map((p) {
                                    final zoneId =
                                        (p['zone_id'] as num?)?.toInt();
                                    final fee = (p['delivery_fee'] as num?)
                                            ?.toDouble() ??
                                        0.0;
                                    final zoneName = zoneId == null
                                        ? null
                                        : zonesById[zoneId]?['name']
                                            ?.toString()
                                            .trim();
                                    return Container(
                                      margin: EdgeInsets.only(bottom: 8.h),
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 12.w, vertical: 10.h),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[50],
                                        borderRadius:
                                            BorderRadius.circular(10.r),
                                        border: Border.all(
                                            color: Colors.grey[200]!),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                                zoneName?.isNotEmpty == true
                                                    ? zoneName!
                                                    : 'منطقة'),
                                          ),
                                          Text(
                                            '${fee.toStringAsFixed(fee.truncateToDouble() == fee ? 0 : 2)} د.ع',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showAddZonePriceDialog(
    BuildContext context,
    WidgetRef ref, {
    required String restaurantId,
    required List<Map<String, dynamic>> zones,
  }) async {
    final zoneNameController = TextEditingController();
    final feeController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('إضافة المنطقة وسعرها'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: zoneNameController,
                decoration: const InputDecoration(
                  labelText: 'اسم المنطقة',
                  prefixIcon: Icon(Icons.map_outlined),
                ),
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: feeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'سعر التوصيل',
                  suffixText: 'د.ع',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final zoneName = zoneNameController.text.trim();
                if (zoneName.isEmpty) return;

                final fee = double.tryParse(feeController.text.trim());
                if (fee == null) return;

                try {
                  await ref.read(adminRepositoryProvider).createZoneAndSetPrice(
                        restaurantId: restaurantId,
                        zoneName: zoneName,
                        deliveryFee: fee,
                      );
                  ref.invalidate(adminRestaurantZonePricingProvider);
                  ref.invalidate(adminZonesProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم حفظ المنطقة والسعر')),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('فشل الحفظ: ${uiErrorMessage(e)}')),
                    );
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
  }
}
