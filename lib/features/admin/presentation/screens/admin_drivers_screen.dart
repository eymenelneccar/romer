import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/admin_repository.dart';
import '../controllers/admin_controller.dart';
import '../../../../core/error_view.dart';
import '../../../../core/user_facing_exception.dart';

class AdminDriversScreen extends ConsumerStatefulWidget {
  const AdminDriversScreen({super.key});

  @override
  ConsumerState<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends ConsumerState<AdminDriversScreen> {
  final Set<String> _settlingDriverIds = <String>{};

  Future<Uint8List> _capturePng(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) {
      throw Exception('Invoice not ready');
    }
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw Exception('Invoice not ready');
    }
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('Failed to encode invoice');
    }
    return byteData.buffer.asUint8List();
  }

  Future<void> _shareInvoice({
    required GlobalKey repaintKey,
    required int transactionId,
    required String driverName,
  }) async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المشاركة كصورة غير مدعومة على الويب.')),
      );
      return;
    }

    final bytes = await _capturePng(repaintKey);
    final file = File(
      '${Directory.systemTemp.path}/naemi_invoice_$transactionId.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'فاتورة تصفية حساب - $driverName (#$transactionId)',
      ),
    );
  }

  Future<void> _showInvoiceDialog({
    required Map<String, dynamic> result,
    required Map<String, dynamic> driver,
  }) async {
    final key = GlobalKey();
    final txId = (result['transaction_id'] as num?)?.toInt() ?? 0;
    final prev = (result['previous_balance'] as num?)?.toDouble() ?? 0.0;
    final naemiShare = prev * 0.2;
    final createdAtRaw = result['created_at']?.toString();
    final createdAt =
        createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw);

    final driverName = driver['name']?.toString().trim().isNotEmpty == true
        ? driver['name']?.toString().trim()
        : 'سائق';

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('فاتورة تصفية الحساب'),
          content: SingleChildScrollView(
            child: RepaintBoundary(
              key: key,
              child: Container(
                width: 520.w,
                padding: EdgeInsets.all(14.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: DefaultTextStyle(
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.receipt_long_outlined),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              'نعيمي تيم - تصفية محفظة',
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10.h),
                      _invoiceLine(
                        'التاريخ',
                        createdAt == null
                            ? '—'
                            : DateFormat('yyyy/MM/dd - HH:mm', 'ar')
                                .format(createdAt.toLocal()),
                      ),
                      const Divider(height: 18),
                      _invoiceLine('السائق', driverName ?? 'سائق'),
                      const Divider(height: 18),
                      _invoiceLine(
                        'المبلغ طالع',
                        '${prev.toStringAsFixed(2)} د.ع',
                      ),
                      _invoiceLine(
                        'نسبة نعيمي (20%)',
                        '${naemiShare.toStringAsFixed(2)} د.ع',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await _shareInvoice(
                  repaintKey: key,
                  transactionId: txId,
                  driverName: driverName ?? 'سائق',
                );
              },
              icon: const Icon(Icons.share),
              label: const Text('مشاركة واتساب'),
            ),
          ],
        );
      },
    );
  }

  Widget _invoiceLine(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
          Text(value, textAlign: TextAlign.left),
        ],
      ),
    );
  }

  Future<void> _settleDriver({
    required Map<String, dynamic> driver,
  }) async {
    final id = driver['id']?.toString();
    if (id == null || id.isEmpty) return;

    final walletBalance = (driver['wallet_balance'] as num?)?.toDouble() ?? 0.0;
    final driverName = driver['name']?.toString().trim().isNotEmpty == true
        ? driver['name']?.toString().trim()
        : 'سائق';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('تصفية الحساب'),
          content: Text(
            'هل تريد تصفير محفظة $driverName؟\n'
            'الرصيد الحالي: ${walletBalance.toStringAsFixed(2)} د.ع',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تصفية'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() => _settlingDriverIds.add(id));
    try {
      final result = await ref
          .read(adminRepositoryProvider)
          .settleDriverWallet(driverId: id);
      if (!mounted) return;
      await _showInvoiceDialog(result: result, driver: driver);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشلت تصفية الحساب: ${uiErrorMessage(e)}')),
      );
    } finally {
      if (mounted) {
        setState(() => _settlingDriverIds.remove(id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final driversAsync = ref.watch(adminDriversProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة السائقين'),
      ),
      body: driversAsync.when(
        data: (drivers) {
          if (drivers.isEmpty) {
            return const Center(child: Text('لا يوجد سائقون حالياً'));
          }

          return ListView.separated(
            padding: EdgeInsets.all(16.w),
            itemCount: drivers.length,
            separatorBuilder: (_, __) => SizedBox(height: 10.h),
            itemBuilder: (context, index) {
              final driver = drivers[index];
              final driverId = driver['id']?.toString();
              final name = driver['name']?.toString().trim();
              final phone = driver['phone']?.toString().trim();
              final isAvailable = driver['is_available'] == true;
              final lat = (driver['current_lat'] as num?)?.toDouble();
              final lng = (driver['current_lng'] as num?)?.toDouble();
              final walletBalance =
                  (driver['wallet_balance'] as num?)?.toDouble() ?? 0.0;
              final deliveredCount =
                  (driver['delivered_orders_count'] as num?)?.toInt() ?? 0;
              final naemiShare = walletBalance * 0.2;
              final isSettling =
                  driverId != null && _settlingDriverIds.contains(driverId);

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  side: BorderSide(color: Colors.grey[200]!),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        isAvailable ? Colors.green[50] : Colors.red[50],
                    child: Icon(
                      Icons.directions_car,
                      color: isAvailable ? Colors.green : Colors.red,
                    ),
                  ),
                  title: Text(name?.isNotEmpty == true ? name! : 'سائق'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (phone?.isNotEmpty == true) Text(phone!),
                      Text('الطلبات المُوصلة: $deliveredCount'),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'محفظته: ${walletBalance.toStringAsFixed(2)} د.ع',
                            ),
                          ),
                          SizedBox(width: 8.w),
                          OutlinedButton(
                            onPressed: (isSettling ||
                                    driverId == null ||
                                    driverId.isEmpty)
                                ? null
                                : () => _settleDriver(driver: driver),
                            child: isSettling
                                ? SizedBox(
                                    height: 16.sp,
                                    width: 16.sp,
                                    child: const CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('تصفية الحساب'),
                          ),
                        ],
                      ),
                      Text(
                          'نسبة نعيمي (20%): ${naemiShare.toStringAsFixed(2)} د.ع'),
                      if (lat != null && lng != null)
                        Text(
                            'الموقع: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'),
                    ],
                  ),
                  trailing: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: (isAvailable ? Colors.green : Colors.red)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20.r),
                      border: Border.all(
                          color: isAvailable ? Colors.green : Colors.red),
                    ),
                    child: Text(
                      isAvailable ? 'متاح' : 'غير متاح',
                      style: TextStyle(
                        color: isAvailable ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.sp,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorView(
          title: 'تعذر تحميل السائقين',
          error: err,
          onRetry: () => ref.invalidate(adminDriversProvider),
        ),
      ),
    );
  }
}
