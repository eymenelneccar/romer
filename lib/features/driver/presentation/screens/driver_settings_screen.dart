import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/driver_repository.dart';
import '../controllers/driver_controller.dart';
import '../../../../core/error_view.dart';
import '../../../../core/user_facing_exception.dart';

class DriverSettingsScreen extends ConsumerWidget {
  const DriverSettingsScreen({super.key});

  String _dayLabel(int dayOfWeek) {
    switch (dayOfWeek) {
      case 0:
        return 'الأحد';
      case 1:
        return 'الاثنين';
      case 2:
        return 'الثلاثاء';
      case 3:
        return 'الأربعاء';
      case 4:
        return 'الخميس';
      case 5:
        return 'الجمعة';
      case 6:
        return 'السبت';
      default:
        return 'غير معروف';
    }
  }

  String _formatMinutes(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  int _toMinutes(TimeOfDay t) => (t.hour * 60) + t.minute;

  TimeOfDay _fromMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return TimeOfDay(hour: h, minute: m);
  }

  Future<void> _openSlotEditor(
    BuildContext context,
    WidgetRef ref, {
    required String userId,
    required List<Map<String, dynamic>> allSlots,
    Map<String, dynamic>? slot,
  }) async {
    final slotId = (slot?['id'] as num?)?.toInt();
    int dayOfWeek =
        (slot?['day_of_week'] as num?)?.toInt() ?? DateTime.now().weekday % 7;
    int startMin = (slot?['start_min'] as num?)?.toInt() ?? 9 * 60;
    int endMin = (slot?['end_min'] as num?)?.toInt() ?? 17 * 60;
    bool isActive = slot == null ? true : slot['is_active'] == true;
    bool isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(
                  left: 16.w,
                  right: 16.w,
                  top: 16.h,
                  bottom: bottomInset + 16.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    slotId == null ? 'إضافة وقت نشاط' : 'تعديل وقت نشاط',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 14.h),
                  DropdownButtonFormField<int>(
                    value: dayOfWeek,
                    decoration: const InputDecoration(labelText: 'اليوم'),
                    items: List.generate(
                      7,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(_dayLabel(i)),
                      ),
                    ),
                    onChanged: isSaving
                        ? null
                        : (v) =>
                            setSheetState(() => dayOfWeek = v ?? dayOfWeek),
                  ),
                  SizedBox(height: 12.h),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule),
                    title: const Text('من'),
                    trailing: Text(_formatMinutes(startMin)),
                    onTap: isSaving
                        ? null
                        : () async {
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime: _fromMinutes(startMin),
                            );
                            if (picked == null) return;
                            setSheetState(() => startMin = _toMinutes(picked));
                          },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule),
                    title: const Text('إلى'),
                    trailing: Text(_formatMinutes(endMin)),
                    onTap: isSaving
                        ? null
                        : () async {
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime: _fromMinutes(endMin),
                            );
                            if (picked == null) return;
                            setSheetState(() => endMin = _toMinutes(picked));
                          },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isActive,
                    onChanged: isSaving
                        ? null
                        : (v) => setSheetState(() => isActive = v),
                    title: const Text('مفعّل'),
                  ),
                  SizedBox(height: 12.h),
                  ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (endMin <= startMin) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'وقت النهاية يجب أن يكون بعد وقت البداية')),
                              );
                              return;
                            }
                            if (isActive) {
                              final sameDay = allSlots
                                  .where((s) =>
                                      (s['day_of_week'] as num?)?.toInt() ==
                                          dayOfWeek &&
                                      s['is_active'] == true &&
                                      ((s['id'] as num?)?.toInt() != slotId))
                                  .toList();
                              for (final s in sameDay) {
                                final sStart =
                                    (s['start_min'] as num?)?.toInt();
                                final sEnd = (s['end_min'] as num?)?.toInt();
                                if (sStart == null || sEnd == null) continue;
                                final overlaps =
                                    startMin < sEnd && endMin > sStart;
                                if (overlaps) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'تداخل في أوقات النشاط. عدّل الأوقات لتجنب التداخل.')),
                                  );
                                  return;
                                }
                              }
                            }
                            setSheetState(() => isSaving = true);
                            try {
                              final repo = ref.read(driverRepositoryProvider);
                              if (slotId == null) {
                                await repo.createAvailabilitySlot(
                                  userId: userId,
                                  dayOfWeek: dayOfWeek,
                                  startMin: startMin,
                                  endMin: endMin,
                                  isActive: isActive,
                                );
                              } else {
                                await repo.updateAvailabilitySlot(
                                  slotId: slotId,
                                  dayOfWeek: dayOfWeek,
                                  startMin: startMin,
                                  endMin: endMin,
                                  isActive: isActive,
                                );
                              }
                              ref.invalidate(
                                  driverAvailabilitySlotsProvider(userId));
                              if (ctx.mounted) Navigator.pop(ctx);
                            } catch (e) {
                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                    content:
                                        Text('تعذر الحفظ: ${uiErrorMessage(e)}')),
                              );
                              setSheetState(() => isSaving = false);
                            }
                          },
                    child: isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('حفظ'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.w),
        child: profileAsync.when(
          data: (profile) {
            final name = profile?['name']?.toString();
            final email = profile?['email']?.toString();
            final phone = profile?['phone']?.toString();
            final userId = profile?['id']?.toString();
            final slotsAsync = userId == null
                ? null
                : ref.watch(driverAvailabilitySlotsProvider(userId));

            return ListView(
              children: [
                Card(
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
                        Text(
                          name?.isNotEmpty == true ? name! : 'السائق',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        SizedBox(height: 6.h),
                        if (email?.isNotEmpty == true) Text(email!),
                        if (phone?.isNotEmpty == true) Text(phone!),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                Card(
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
                            Expanded(
                              child: Text(
                                'أوقات النشاط',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: userId == null
                                  ? null
                                  : () => _openSlotEditor(
                                        context,
                                        ref,
                                        userId: userId,
                                        allSlots:
                                            slotsAsync?.valueOrNull ?? const [],
                                      ),
                              icon: const Icon(Icons.add),
                              label: const Text('إضافة'),
                            ),
                          ],
                        ),
                        SizedBox(height: 10.h),
                        if (userId == null)
                          const Text('تعذر تحميل بيانات المستخدم.')
                        else
                          slotsAsync!.when(
                            data: (slots) {
                              if (slots.isEmpty) {
                                return const Text(
                                    'لم يتم تحديد أوقات نشاط بعد.');
                              }

                              return Column(
                                children: [
                                  for (final slot in slots)
                                    Padding(
                                      padding: EdgeInsets.only(bottom: 8.h),
                                      child: Material(
                                        color: Colors.grey[50],
                                        borderRadius:
                                            BorderRadius.circular(10.r),
                                        child: ListTile(
                                          title: Text(_dayLabel(
                                              (slot['day_of_week'] as num)
                                                  .toInt())),
                                          subtitle: Text(
                                            '${_formatMinutes((slot['start_min'] as num).toInt())} - ${_formatMinutes((slot['end_min'] as num).toInt())}',
                                          ),
                                          leading: Switch(
                                            value: slot['is_active'] == true,
                                            onChanged: (v) async {
                                              final slotId =
                                                  (slot['id'] as num).toInt();
                                              try {
                                                await ref
                                                    .read(
                                                        driverRepositoryProvider)
                                                    .updateAvailabilitySlot(
                                                      slotId: slotId,
                                                      dayOfWeek:
                                                          (slot['day_of_week']
                                                                  as num)
                                                              .toInt(),
                                                      startMin:
                                                          (slot['start_min']
                                                                  as num)
                                                              .toInt(),
                                                      endMin: (slot['end_min']
                                                              as num)
                                                          .toInt(),
                                                      isActive: v,
                                                    );
                                                ref.invalidate(
                                                    driverAvailabilitySlotsProvider(
                                                        userId));
                                              } catch (e) {
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                      content: Text(
                                                          'تعذر التحديث: ${uiErrorMessage(e)}')),
                                                );
                                              }
                                            },
                                          ),
                                          trailing: IconButton(
                                            icon: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.red),
                                            onPressed: () async {
                                              final slotId =
                                                  (slot['id'] as num).toInt();
                                              try {
                                                await ref
                                                    .read(
                                                        driverRepositoryProvider)
                                                    .deleteAvailabilitySlot(
                                                        slotId);
                                                ref.invalidate(
                                                    driverAvailabilitySlotsProvider(
                                                        userId));
                                              } catch (e) {
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                      content: Text(
                                                          'تعذر الحذف: ${uiErrorMessage(e)}')),
                                                );
                                              }
                                            },
                                          ),
                                          onTap: () => _openSlotEditor(
                                            context,
                                            ref,
                                            userId: userId,
                                            allSlots: slots,
                                            slot: slot,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                            loading: () => const Center(
                                child: CircularProgressIndicator()),
                            error: (err, _) => ErrorView(
                              title: 'تعذر تحميل أوقات النشاط',
                              error: err,
                              onRetry: () => ref.invalidate(
                                  driverAvailabilitySlotsProvider(userId)),
                              compact: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet),
                  title: const Text('المحفظة'),
                  onTap: () => context.push('/driver/wallet'),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('تسجيل الخروج'),
                  textColor: Colors.red,
                  onTap: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => ErrorView(
            title: 'تعذر تحميل الإعدادات',
            error: err,
            onRetry: () => ref.invalidate(userProfileProvider),
          ),
        ),
      ),
    );
  }
}
