import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/admin_controller.dart';
import '../../../../core/error_view.dart';

class AdminRestaurantsScreen extends ConsumerWidget {
  const AdminRestaurantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurantsAsync = ref.watch(adminRestaurantsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة المطاعم'),
      ),
      body: restaurantsAsync.when(
        data: (restaurants) {
          if (restaurants.isEmpty) {
            return const Center(child: Text('لا توجد حسابات مطاعم'));
          }

          return ListView.separated(
            padding: EdgeInsets.all(16.w),
            itemCount: restaurants.length,
            separatorBuilder: (_, __) => SizedBox(height: 10.h),
            itemBuilder: (context, index) {
              final r = restaurants[index];
              final name = r['name']?.toString().trim();
              final email = r['email']?.toString().trim();
              final phone = r['phone']?.toString().trim();
              final outgoingCount =
                  (r['outgoing_orders_count'] as num?)?.toInt() ?? 0;

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  side: BorderSide(color: Colors.grey[200]!),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).primaryColor.withOpacity(0.08),
                    child: Icon(Icons.store,
                        color: Theme.of(context).primaryColor),
                  ),
                  title: Text(name?.isNotEmpty == true ? name! : 'مطعم'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (email?.isNotEmpty == true) Text(email!),
                      if (phone?.isNotEmpty == true) Text(phone!),
                      Text('طلبات طالعة: $outgoingCount'),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorView(
          title: 'تعذر تحميل المطاعم',
          error: err,
          onRetry: () => ref.invalidate(adminRestaurantsProvider),
        ),
      ),
    );
  }
}
