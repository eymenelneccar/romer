import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../../../../router.dart';
import '../../data/auth_repository.dart';
import '../controllers/auth_controller.dart';
import '../../../../core/error_view.dart';
import '../../../../core/user_facing_exception.dart';

class ApprovalStatusScreen extends ConsumerStatefulWidget {
  const ApprovalStatusScreen({super.key});

  @override
  ConsumerState<ApprovalStatusScreen> createState() =>
      _ApprovalStatusScreenState();
}

class _ApprovalStatusScreenState extends ConsumerState<ApprovalStatusScreen> {
  bool _uploadingAvatar = false;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('حالة الطلب'),
      ),
      body: profileAsync.when(
        data: (profile) {
          final status = profile?['approval_status']?.toString() ?? 'pending';
          final isApproved =
              profile?['is_approved'] == true || status == 'approved';
          final role = profile?['role']?.toString() ?? 'driver';
          final requestedRole = profile?['requested_role']?.toString() ?? role;
          final avatarUrl = profile?['avatar_url']?.toString().trim();

          String message() {
            if (isApproved) return 'تمت الموافقة على حسابك. يمكنك المتابعة.';
            if (status == 'rejected') return 'تم رفض الطلب. راجع الأدمن.';
            return 'تم تقديم الطلب. انتظر موافقة الأدمن.';
          }

          String homeForRole(String r) {
            if (r == 'admin') return '/admin';
            if (r == 'restaurant') return '/restaurant';
            return '/driver';
          }

          return Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    side: BorderSide(color: Colors.grey[200]!),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: CircleAvatar(
                            radius: 44.r,
                            backgroundColor: Colors.grey[100],
                            backgroundImage: (avatarUrl?.isNotEmpty == true)
                                ? NetworkImage(avatarUrl!)
                                : null,
                            child: (avatarUrl?.isNotEmpty == true)
                                ? null
                                : Icon(Icons.person_outline,
                                    color: Colors.grey[700]),
                          ),
                        ),
                        SizedBox(height: 10.h),
                        Text(
                          message(),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        SizedBox(height: 10.h),
                        Text('النوع المطلوب: ${_roleLabel(requestedRole)}'),
                        if (!isApproved)
                          Text('الحالة: ${_statusLabel(status)}'),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 14.h),
                SizedBox(
                  height: 48.h,
                  child: OutlinedButton(
                    onPressed: _uploadingAvatar
                        ? null
                        : () async {
                            setState(() => _uploadingAvatar = true);
                            try {
                              final picker = ImagePicker();
                              final picked = await picker.pickImage(
                                source: ImageSource.gallery,
                                imageQuality: 80,
                                maxWidth: 1000,
                              );
                              if (picked == null) return;

                              final Uint8List bytes =
                                  await picked.readAsBytes();
                              final repo = ref.read(authRepositoryProvider);
                              final url = await repo.uploadCurrentUserAvatar(
                                bytes: bytes,
                                fileName: picked.name,
                              );
                              await repo.updateCurrentUserAvatarUrl(url);
                              ref
                                  .read(routerProfileCacheProvider.notifier)
                                  .state = null;
                              ref.invalidate(userProfileProvider);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'تعذر رفع الصورة: ${uiErrorMessage(e)}')),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _uploadingAvatar = false);
                              }
                            }
                          },
                    child: _uploadingAvatar
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('تحديث الصورة'),
                  ),
                ),
                SizedBox(height: 10.h),
                SizedBox(
                  height: 48.h,
                  child: ElevatedButton(
                    onPressed: () async {
                      ref.read(routerProfileCacheProvider.notifier).state =
                          null;
                      await ref
                          .read(authRepositoryProvider)
                          .getOrCreateCurrentUserProfile();
                      ref.invalidate(userProfileProvider);
                    },
                    child: const Text('تحديث الحالة'),
                  ),
                ),
                SizedBox(height: 10.h),
                if (isApproved)
                  SizedBox(
                    height: 48.h,
                    child: OutlinedButton(
                      onPressed: () {
                        ref.read(routerProfileCacheProvider.notifier).state =
                            null;
                        context.go(homeForRole(role));
                      },
                      child: const Text('الدخول'),
                    ),
                  ),
                const Spacer(),
                SizedBox(
                  height: 48.h,
                  child: OutlinedButton(
                    onPressed: () async {
                      await ref.read(authControllerProvider.notifier).signOut();
                      ref.read(routerProfileCacheProvider.notifier).state =
                          null;
                      if (context.mounted) context.go('/login');
                    },
                    child: const Text('تسجيل الخروج'),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorView(
          title: 'تعذر تحميل حالة الطلب',
          error: err,
          onRetry: () => ref.invalidate(userProfileProvider),
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'مقبول';
      case 'rejected':
        return 'مرفوض';
      case 'pending':
      default:
        return 'بانتظار الموافقة';
    }
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
