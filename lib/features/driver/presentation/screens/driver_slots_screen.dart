import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../../../auth/data/auth_repository.dart';
import '../../data/driver_repository.dart';
import '../controllers/driver_controller.dart';
import '../../../../core/error_view.dart';
import '../../../../core/user_facing_exception.dart';

class DriverSlotsScreen extends ConsumerStatefulWidget {
  const DriverSlotsScreen({super.key});

  @override
  ConsumerState<DriverSlotsScreen> createState() => _DriverSlotsScreenState();
}

class _DriverSlotsScreenState extends ConsumerState<DriverSlotsScreen> {
  DateTime _selectedDate = DateTime.now();

  int _dayOfWeek(DateTime date) => date.weekday % 7;

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

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<DateTime> _weekDays(DateTime anchor) {
    final start = anchor.subtract(Duration(days: anchor.weekday - 1));
    return List.generate(7, (i) => start.add(Duration(days: i)));
  }

  String _weekdayShort(DateTime date) {
    const labels = ['اث', 'ثل', 'أر', 'خم', 'جم', 'سب', 'أح'];
    final i = (date.weekday - 1).clamp(0, 6);
    return labels[i];
  }

  bool _overlaps(int aStart, int aEnd, int bStart, int bEnd) {
    return aStart < bEnd && aEnd > bStart;
  }

  bool _isAvailableNow(List<Map<String, dynamic>> slots, DateTime now) {
    final activeSlots = slots.where((s) => s['is_active'] == true).toList();
    if (activeSlots.isEmpty) return true;
    final dayOfWeek = now.weekday % 7;
    final nowMin = (now.hour * 60) + now.minute;
    for (final s in activeSlots) {
      if ((s['day_of_week'] as num?)?.toInt() != dayOfWeek) continue;
      final startMin = (s['start_min'] as num?)?.toInt();
      final endMin = (s['end_min'] as num?)?.toInt();
      if (startMin == null || endMin == null) continue;
      if (nowMin >= startMin && nowMin < endMin) return true;
    }
    return false;
  }

  int? _nextStartToday(List<Map<String, dynamic>> slots, DateTime now) {
    final activeSlots = slots.where((s) => s['is_active'] == true).toList();
    if (activeSlots.isEmpty) return null;
    final dayOfWeek = now.weekday % 7;
    final nowMin = (now.hour * 60) + now.minute;
    final starts = <int>[];
    for (final s in activeSlots) {
      if ((s['day_of_week'] as num?)?.toInt() != dayOfWeek) continue;
      final startMin = (s['start_min'] as num?)?.toInt();
      final endMin = (s['end_min'] as num?)?.toInt();
      if (startMin == null || endMin == null) continue;
      if (nowMin < startMin) starts.add(startMin);
    }
    if (starts.isEmpty) return null;
    starts.sort();
    return starts.first;
  }

  int? _currentEndToday(List<Map<String, dynamic>> slots, DateTime now) {
    final activeSlots = slots.where((s) => s['is_active'] == true).toList();
    if (activeSlots.isEmpty) return null;
    final dayOfWeek = now.weekday % 7;
    final nowMin = (now.hour * 60) + now.minute;
    for (final s in activeSlots) {
      if ((s['day_of_week'] as num?)?.toInt() != dayOfWeek) continue;
      final startMin = (s['start_min'] as num?)?.toInt();
      final endMin = (s['end_min'] as num?)?.toInt();
      if (startMin == null || endMin == null) continue;
      if (nowMin >= startMin && nowMin < endMin) return endMin;
    }
    return null;
  }

  int _sumDayMinutes(List<Map<String, dynamic>> slots, int dayOfWeek) {
    var total = 0;
    for (final s in slots) {
      if ((s['day_of_week'] as num?)?.toInt() != dayOfWeek) continue;
      if (s['is_active'] != true) continue;
      final startMin = (s['start_min'] as num?)?.toInt();
      final endMin = (s['end_min'] as num?)?.toInt();
      if (startMin == null || endMin == null) continue;
      if (endMin > startMin) total += (endMin - startMin);
    }
    return total;
  }

  Future<void> _openSlotEditor({
    required BuildContext context,
    required String userId,
    required List<Map<String, dynamic>> allSlots,
    Map<String, dynamic>? slot,
    required int initialDayOfWeek,
  }) async {
    final slotId = (slot?['id'] as num?)?.toInt();
    int dayOfWeek = (slot?['day_of_week'] as num?)?.toInt() ?? initialDayOfWeek;
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
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('الاثنين')),
                      DropdownMenuItem(value: 2, child: Text('الثلاثاء')),
                      DropdownMenuItem(value: 3, child: Text('الأربعاء')),
                      DropdownMenuItem(value: 4, child: Text('الخميس')),
                      DropdownMenuItem(value: 5, child: Text('الجمعة')),
                      DropdownMenuItem(value: 6, child: Text('السبت')),
                      DropdownMenuItem(value: 0, child: Text('الأحد')),
                    ],
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
                              ScaffoldMessenger.of(ctx).showSnackBar(
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
                                if (_overlaps(startMin, endMin, sStart, sEnd)) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
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
                                    content: Text(
                                        'تعذر الحفظ: ${uiErrorMessage(e)}')),
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
  Widget build(BuildContext context) {
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    final slotsAsync = userId == null
        ? null
        : ref.watch(driverAvailabilitySlotsProvider(userId));
    final hasAnyActiveSlots = (slotsAsync?.valueOrNull ?? const [])
        .any((s) => s['is_active'] == true);
    final dateLabel = DateFormat('MMMM yyyy', 'ar').format(_selectedDate);
    final days = _weekDays(_selectedDate);
    final selectedDayOfWeek = _dayOfWeek(_selectedDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('أوقات النشاط'),
        actions: [
          if (userId != null && hasAnyActiveSlots)
            TextButton(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) {
                    return AlertDialog(
                      title: const Text('إيقاف الجدولة'),
                      content:
                          const Text('سيتم تعطيل جميع أوقات النشاط المفعّلة.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('إلغاء'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('إيقاف'),
                        ),
                      ],
                    );
                  },
                );
                if (confirmed != true) return;
                try {
                  await ref
                      .read(driverRepositoryProvider)
                      .deactivateAllAvailabilitySlots(userId);
                  ref.invalidate(driverAvailabilitySlotsProvider(userId));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'تم إيقاف الجدولة. يمكنك الآن الضغط على ابدأ.')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'تعذر إيقاف الجدولة: ${uiErrorMessage(e)}')),
                  );
                }
              },
              child: const Text('إيقاف الجدولة'),
            ),
          TextButton(
            onPressed: () => setState(() => _selectedDate = DateTime.now()),
            child: const Text('اليوم'),
          ),
        ],
      ),
      floatingActionButton: userId == null
          ? null
          : FloatingActionButton(
              onPressed: () => _openSlotEditor(
                context: context,
                userId: userId,
                allSlots: ref
                        .read(driverAvailabilitySlotsProvider(userId))
                        .valueOrNull ??
                    const [],
                initialDayOfWeek: selectedDayOfWeek,
              ),
              child: const Icon(Icons.add),
            ),
      body: userId == null
          ? const Center(child: Text('تعذر تحميل المستخدم.'))
          : Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12.h),
                  SizedBox(
                    height: 66.h,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: days.length,
                      separatorBuilder: (_, __) => SizedBox(width: 10.w),
                      itemBuilder: (context, index) {
                        final d = days[index];
                        final isSelected = _isSameDate(d, _selectedDate);
                        return InkWell(
                          onTap: () => setState(() => _selectedDate = d),
                          borderRadius: BorderRadius.circular(14.r),
                          child: Container(
                            width: 56.w,
                            padding: EdgeInsets.symmetric(vertical: 10.h),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(14.r),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _weekdayShort(d),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  '${d.day}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(height: 14.h),
                  Expanded(
                    child: ref
                        .watch(driverAvailabilitySlotsProvider(userId))
                        .when(
                          data: (slots) {
                            final now = DateTime.now();
                            final isToday = _isSameDate(_selectedDate, now);
                            final nowMin = (now.hour * 60) + now.minute;
                            final hasAnyActive =
                                slots.any((s) => s['is_active'] == true);
                            final availableNow = _isAvailableNow(slots, now);
                            final currentEnd =
                                isToday ? _currentEndToday(slots, now) : null;
                            final nextStart =
                                isToday ? _nextStartToday(slots, now) : null;

                            final daySlots = slots
                                .where((s) =>
                                    (s['day_of_week'] as num).toInt() ==
                                    selectedDayOfWeek)
                                .toList()
                              ..sort((a, b) {
                                final aa = (a['start_min'] as num).toInt();
                                final bb = (b['start_min'] as num).toInt();
                                return aa.compareTo(bb);
                              });
                            final totalDayMin =
                                _sumDayMinutes(slots, selectedDayOfWeek);
                            final totalDayH = totalDayMin ~/ 60;
                            final totalDayM = totalDayMin % 60;
                            final totalDayLabel = totalDayMin == 0
                                ? '—'
                                : (totalDayH > 0
                                    ? '$totalDayHس $totalDayMد'
                                    : '$totalDayMد');

                            return Column(
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.all(14.w),
                                  decoration: BoxDecoration(
                                    color: (!hasAnyActive || availableNow)
                                        ? Colors.green[50]
                                        : Colors.orange[50],
                                    borderRadius: BorderRadius.circular(14.r),
                                    border: Border.all(
                                      color: ((!hasAnyActive || availableNow)
                                          ? Colors.green
                                          : Colors.orange)[200]!,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        !hasAnyActive
                                            ? 'أوقات النشاط غير محددة'
                                            : (availableNow
                                                ? 'ضمن وقت النشاط الآن'
                                                : 'خارج وقت النشاط الآن'),
                                        style: TextStyle(
                                          color: Colors.grey[900],
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.sp,
                                        ),
                                      ),
                                      SizedBox(height: 6.h),
                                      Text(
                                        !hasAnyActive
                                            ? 'عند عدم تحديد أوقات مفعّلة، ستكون متاحاً طوال الوقت.'
                                            : (availableNow
                                                ? 'ستصلك الطلبات عند تشغيل وضع الاتصال.'
                                                : 'لن تصلك الطلبات حتى تدخل ضمن وقت نشاط مفعّل.'),
                                        style: TextStyle(
                                            color: Colors.grey[800],
                                            fontWeight: FontWeight.w600),
                                      ),
                                      if (isToday && hasAnyActive) ...[
                                        SizedBox(height: 10.h),
                                        if (availableNow && currentEnd != null)
                                          Text(
                                            'ينتهي وقت النشاط الحالي: ${_formatMinutes(currentEnd)}',
                                            style: TextStyle(
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w600),
                                          ),
                                        if (!availableNow && nextStart != null)
                                          Text(
                                            'أقرب وقت نشاط اليوم: ${_formatMinutes(nextStart)}',
                                            style: TextStyle(
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w600),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                                SizedBox(height: 12.h),
                                Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.all(14.w),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14.r),
                                    border:
                                        Border.all(color: Colors.grey[200]!),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'ملخص اليوم',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13.sp,
                                                color: Colors.grey[900],
                                              ),
                                            ),
                                            SizedBox(height: 6.h),
                                            Text(
                                              'مجموع الساعات المفعّلة: $totalDayLabel',
                                              style: TextStyle(
                                                  color: Colors.grey[700],
                                                  fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 10.w, vertical: 8.h),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[100],
                                          borderRadius:
                                              BorderRadius.circular(12.r),
                                        ),
                                        child: Text(
                                          isToday
                                              ? 'اليوم'
                                              : _weekdayShort(_selectedDate),
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12.sp),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 12.h),
                                Expanded(
                                  child: daySlots.isEmpty
                                      ? Center(
                                          child: Text(
                                            'لا توجد أوقات نشاط لهذا اليوم.\nاضغط + لإضافة وقت.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                color: Colors.grey[700]),
                                          ),
                                        )
                                      : ListView.separated(
                                          itemCount: daySlots.length,
                                          separatorBuilder: (_, __) =>
                                              SizedBox(height: 10.h),
                                          itemBuilder: (context, index) {
                                            final slot = daySlots[index];
                                            final slotId =
                                                (slot['id'] as num).toInt();
                                            final slotDayOfWeek =
                                                (slot['day_of_week'] as num)
                                                    .toInt();
                                            final startMin =
                                                (slot['start_min'] as num)
                                                    .toInt();
                                            final endMin =
                                                (slot['end_min'] as num)
                                                    .toInt();
                                            final isActive =
                                                slot['is_active'] == true;

                                            final isNow = isToday &&
                                                isActive &&
                                                nowMin >= startMin &&
                                                nowMin < endMin;
                                            final label = isNow
                                                ? 'الآن - ${_formatMinutes(endMin)}'
                                                : '${_formatMinutes(startMin)} - ${_formatMinutes(endMin)}';

                                            final minutes = isNow
                                                ? (endMin - nowMin)
                                                : (endMin - startMin);
                                            final h = minutes ~/ 60;
                                            final m = minutes % 60;
                                            final durationLabel =
                                                h > 0 ? '($hس $mد)' : '($mد)';

                                            return Material(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(14.r),
                                              child: ListTile(
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          14.r),
                                                  side: BorderSide(
                                                      color: Colors.grey[200]!),
                                                ),
                                                title: Text(
                                                  '$label $durationLabel',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                                subtitle: Text(isActive
                                                    ? 'مفعّل'
                                                    : 'غير مفعّل'),
                                                trailing: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Switch(
                                                      value: isActive,
                                                      onChanged: (v) async {
                                                        try {
                                                          await ref
                                                              .read(
                                                                  driverRepositoryProvider)
                                                              .updateAvailabilitySlot(
                                                                slotId: slotId,
                                                                dayOfWeek:
                                                                    slotDayOfWeek,
                                                                startMin:
                                                                    startMin,
                                                                endMin: endMin,
                                                                isActive: v,
                                                              );
                                                          ref.invalidate(
                                                              driverAvailabilitySlotsProvider(
                                                                  userId));
                                                        } catch (e) {
                                                          if (!context
                                                              .mounted) {
                                                            return;
                                                          }
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                            SnackBar(
                                                                content: Text(
                                                                    'تعذر التحديث: ${uiErrorMessage(e)}')),
                                                          );
                                                        }
                                                      },
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.delete_outline,
                                                          color: Colors.red),
                                                      onPressed: () async {
                                                        final confirmed =
                                                            await showDialog<
                                                                bool>(
                                                          context: context,
                                                          builder: (ctx) {
                                                            return AlertDialog(
                                                              title: const Text(
                                                                  'حذف وقت النشاط'),
                                                              content: Text(
                                                                'حذف ${_formatMinutes(startMin)} - ${_formatMinutes(endMin)}؟',
                                                              ),
                                                              actions: [
                                                                TextButton(
                                                                  onPressed: () =>
                                                                      Navigator.pop(
                                                                          ctx,
                                                                          false),
                                                                  child: const Text(
                                                                      'إلغاء'),
                                                                ),
                                                                ElevatedButton(
                                                                  onPressed: () =>
                                                                      Navigator.pop(
                                                                          ctx,
                                                                          true),
                                                                  child:
                                                                      const Text(
                                                                          'حذف'),
                                                                ),
                                                              ],
                                                            );
                                                          },
                                                        );
                                                        if (confirmed != true) {
                                                          return;
                                                        }
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
                                                          if (!context
                                                              .mounted) {
                                                            return;
                                                          }
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                            SnackBar(
                                                                content: Text(
                                                                    'تعذر الحذف: ${uiErrorMessage(e)}')),
                                                          );
                                                        }
                                                      },
                                                    ),
                                                  ],
                                                ),
                                                onTap: () => _openSlotEditor(
                                                  context: context,
                                                  userId: userId,
                                                  allSlots: slots,
                                                  slot: slot,
                                                  initialDayOfWeek:
                                                      selectedDayOfWeek,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            );
                          },
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (err, _) => ErrorView(
                            title: 'تعذر تحميل أوقات النشاط',
                            error: err,
                            onRetry: () => ref.invalidate(
                                driverAvailabilitySlotsProvider(userId)),
                          ),
                        ),
                  ),
                ],
              ),
            ),
    );
  }
}
