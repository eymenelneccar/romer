import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../controllers/admin_controller.dart';
import '../../data/admin_repository.dart';
import '../../../../core/error_view.dart';
import '../../../../core/user_facing_exception.dart';

class AdminNewMembersScreen extends ConsumerStatefulWidget {
  const AdminNewMembersScreen({super.key});

  @override
  ConsumerState<AdminNewMembersScreen> createState() =>
      _AdminNewMembersScreenState();
}

class _AdminNewMembersScreenState extends ConsumerState<AdminNewMembersScreen> {
  final Set<String> _processing = <String>{};

  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(adminPendingMembersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('أعضاء جدد')),
      body: pendingAsync.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('لا يوجد طلبات انتظار'));
          }

          return ListView.separated(
            padding: EdgeInsets.all(16.w),
            itemCount: list.length,
            separatorBuilder: (_, __) => SizedBox(height: 10.h),
            itemBuilder: (context, index) {
              final u = list[index];
              final id = u['id']?.toString();
              final name = u['name']?.toString().trim();
              final phone = u['phone']?.toString().trim();
              final email = u['email']?.toString().trim();
              final requestedRole = u['requested_role']?.toString().trim();
              final avatarUrl = u['avatar_url']?.toString().trim();

              final isBusy = id != null && _processing.contains(id);

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  side: BorderSide(color: Colors.grey[200]!),
                ),
                child: Padding(
                  padding: EdgeInsets.all(12.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Theme.of(context)
                                .primaryColor
                                .withOpacity(0.08),
                            backgroundImage: (avatarUrl?.isNotEmpty == true)
                                ? NetworkImage(avatarUrl!)
                                : null,
                            child: (avatarUrl?.isNotEmpty == true)
                                ? null
                                : Icon(Icons.person,
                                    color: Theme.of(context).primaryColor),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name?.isNotEmpty == true ? name! : 'عضو جديد',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                if (requestedRole?.isNotEmpty == true)
                                  Text(
                                      'النوع المطلوب: ${_roleLabel(requestedRole!)}'),
                                if (phone?.isNotEmpty == true) Text(phone!),
                                if (email?.isNotEmpty == true) Text(email!),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: (id == null || isBusy)
                                  ? null
                                  : () async {
                                      setState(() => _processing.add(id));
                                      try {
                                        await ref
                                            .read(adminRepositoryProvider)
                                            .rejectMembership(userId: id);
                                        ref.invalidate(
                                            adminPendingMembersProvider);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text('تم الرفض')),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    'فشل الرفض: ${uiErrorMessage(e)}')),
                                          );
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(
                                              () => _processing.remove(id));
                                        }
                                      }
                                    },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                              ),
                              child: isBusy
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Text('رفض'),
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: (id == null || isBusy)
                                  ? null
                                  : () async {
                                      setState(() => _processing.add(id));
                                      try {
                                        await ref
                                            .read(adminRepositoryProvider)
                                            .approveMembership(userId: id);
                                        ref.invalidate(
                                            adminPendingMembersProvider);
                                        ref.invalidate(adminUsersProvider);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text('تمت الموافقة')),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content:
                                                    Text(
                                                        'فشل الموافقة: ${uiErrorMessage(e)}')),
                                          );
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(
                                              () => _processing.remove(id));
                                        }
                                      }
                                    },
                              child: isBusy
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Text('قبول'),
                            ),
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
          title: 'تعذر تحميل طلبات الأعضاء الجدد',
          error: err,
          onRetry: () => ref.invalidate(adminPendingMembersProvider),
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'restaurant':
        return 'مطعم';
      case 'driver':
      default:
        return 'سائق دراجة';
    }
  }
}
