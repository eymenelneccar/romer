import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../controllers/admin_controller.dart';
import '../../data/admin_repository.dart';
import '../../../../core/error_view.dart';
import '../../../../core/user_facing_exception.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final Set<String> _updatingUserIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(adminUsersProvider);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة المستخدمين'),
      ),
      body: usersAsync.when(
        data: (users) {
          if (users.isEmpty) {
            return const Center(child: Text('لا يوجد مستخدمون'));
          }

          return ListView.separated(
            padding: EdgeInsets.all(16.w),
            itemCount: users.length,
            separatorBuilder: (_, __) => SizedBox(height: 10.h),
            itemBuilder: (context, index) {
              final u = users[index];
              final id = u['id']?.toString();
              final name = u['name']?.toString().trim();
              final email = u['email']?.toString().trim();
              final phone = u['phone']?.toString().trim();

              final currentRole =
                  (u['role']?.toString().trim().isNotEmpty == true)
                      ? u['role']!.toString().trim()
                      : 'driver';
              const baseRoles = ['driver', 'restaurant', 'admin'];
              final roles = baseRoles.contains(currentRole)
                  ? baseRoles
                  : [...baseRoles, currentRole];

              final isSelf = currentUserId != null && id == currentUserId;
              final isUpdating = id != null && _updatingUserIds.contains(id);

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  side: BorderSide(color: Colors.grey[200]!),
                ),
                child: Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            Theme.of(context).primaryColor.withOpacity(0.08),
                        child: Icon(Icons.person,
                            color: Theme.of(context).primaryColor),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name?.isNotEmpty == true ? name! : 'مستخدم',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            if (email?.isNotEmpty == true) Text(email!),
                            if (phone?.isNotEmpty == true) Text(phone!),
                            if (isSelf) const Text('هذا الحساب الحالي'),
                          ],
                        ),
                      ),
                      SizedBox(width: 12.w),
                      SizedBox(
                        width: 140.w,
                        child: DropdownButtonFormField<String>(
                          value: currentRole,
                          items: roles
                              .map(
                                (r) => DropdownMenuItem<String>(
                                  value: r,
                                  child: Text(_roleLabel(r)),
                                ),
                              )
                              .toList(),
                          onChanged: (isSelf || isUpdating || id == null)
                              ? null
                              : (newRole) async {
                                  if (newRole == null ||
                                      newRole == currentRole) {
                                    return;
                                  }
                                  setState(() => _updatingUserIds.add(id));
                                  try {
                                    await ref
                                        .read(adminRepositoryProvider)
                                        .updateUserRole(
                                            userId: id, role: newRole);
                                    ref.invalidate(adminUsersProvider);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text('تم تحديث الدور')),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content:
                                                Text('فشل تحديث الدور: ${uiErrorMessage(e)}')),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(
                                          () => _updatingUserIds.remove(id));
                                    }
                                  }
                                },
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12.w, vertical: 10.h),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10.r)),
                          ),
                        ),
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
          title: 'تعذر تحميل المستخدمين',
          error: err,
          onRetry: () => ref.invalidate(adminUsersProvider),
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'أدمن';
      case 'restaurant':
        return 'مطعم';
      case 'driver':
      default:
        return 'سائق';
    }
  }
}
