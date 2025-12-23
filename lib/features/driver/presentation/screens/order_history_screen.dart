import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../controllers/driver_controller.dart';
import '../../../../core/error_view.dart';

class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(orderHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الطلبات'),
      ),
      body: historyAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('لا يوجد سجل حتى الآن'));
          }

          final dateFormat = DateFormat('d MMM yyyy - hh:mm a');

          return ListView.separated(
            padding: EdgeInsets.all(16.w),
            itemCount: orders.length,
            separatorBuilder: (_, __) => SizedBox(height: 10.h),
            itemBuilder: (context, index) {
              final order = orders[index];
              final id = (order['id'] as num?)?.toInt();
              final status = order['status']?.toString();
              final fee = (order['delivery_fee'] as num?)?.toDouble() ?? 0.0;
              final createdAtRaw = order['created_at']?.toString();
              final createdAt =
                  createdAtRaw != null ? DateTime.tryParse(createdAtRaw) : null;
              final dateText = createdAt != null
                  ? dateFormat.format(createdAt.toLocal())
                  : '';

              final statusColor = switch (status) {
                'delivered' => Colors.green,
                'cancelled' => Colors.red,
                _ => Colors.grey,
              };

              final statusText = switch (status) {
                'delivered' => 'تم التوصيل',
                'cancelled' => 'ملغي',
                _ => status ?? '',
              };

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  side: BorderSide(color: Colors.grey[200]!),
                ),
                child: Padding(
                  padding: EdgeInsets.all(14.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            id != null ? 'طلب #$id' : 'طلب',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10.w, vertical: 4.h),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20.r),
                              border: Border.all(color: statusColor),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12.sp,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (dateText.isNotEmpty) ...[
                        SizedBox(height: 6.h),
                        Text(dateText,
                            style: TextStyle(color: Colors.grey[700])),
                      ],
                      SizedBox(height: 10.h),
                      Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined,
                              size: 18),
                          SizedBox(width: 6.w),
                          Text(
                            '${fee.toStringAsFixed(2)} د.ع',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorView(
          title: 'تعذر تحميل سجل الطلبات',
          error: err,
          onRetry: () => ref.invalidate(orderHistoryProvider),
        ),
      ),
    );
  }
}
