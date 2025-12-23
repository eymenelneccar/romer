import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/user_facing_exception.dart';
import '../controllers/restaurant_controller.dart';

class CreateOrderScreen extends HookConsumerWidget {
  const CreateOrderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameController = useTextEditingController();
    final phoneController = useTextEditingController();
    final addressController = useTextEditingController();
    final priceController = useTextEditingController();
    final deliveryFeeController = useTextEditingController();

    final state = ref.watch(restaurantControllerProvider);
    final zonePricingAsync = ref.watch(restaurantZonePricingProvider);
    final selectedZoneId = useState<int?>(null);

    useEffect(() {
      final zp = zonePricingAsync.valueOrNull;
      if (zp != null && zp.isNotEmpty) {
        final firstId = (zp.first['zone_id'] as num?)?.toInt() ??
            (zp.first['zone_id'] as int?);
        if (selectedZoneId.value == null && firstId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (selectedZoneId.value != null) return;
            selectedZoneId.value = firstId;
          });
        }

        final current = selectedZoneId.value;
        if (current != null) {
          final row = zp.firstWhere(
            (e) =>
                (e['zone_id'] as num?)?.toInt() == current ||
                e['zone_id'] == current,
            orElse: () => <String, dynamic>{},
          );
          final fee = (row['delivery_fee'] as num?)?.toDouble();
          if (fee != null) {
            deliveryFeeController.text = fee.toString();
          }
        }
      } else if (deliveryFeeController.text.trim().isEmpty) {
        deliveryFeeController.text = '0';
      }
      return null;
    }, [zonePricingAsync, selectedZoneId.value]);

    // Listen for success
    ref.listen(restaurantControllerProvider, (previous, next) {
      final wasLoading = previous?.isLoading ?? false;
      if (wasLoading && !next.isLoading && next.hasValue) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم إرسال الطلب بنجاح!'),
              backgroundColor: Colors.green),
        );
        context.pop();
      }
      final err = next.error;
      if (!next.isLoading && err != null) {
        final message = err is UserFacingException
            ? err.toString()
            : 'تعذر إرسال الطلب الآن. حاول مرة أخرى.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('إنشاء طلب جديد'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20.w),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 520;

                final priceField = TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'سعر الطلب',
                    suffixText: 'د.ع',
                  ),
                );

                final deliveryFeeField = _buildDeliveryFeeField(
                  context,
                  zonePricingAsync,
                  selectedZoneId,
                  deliveryFeeController,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSectionTitle('بيانات العميل'),
                    SizedBox(height: 10.h),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم العميل',
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    SizedBox(height: 15.h),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف',
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                    SizedBox(height: 15.h),
                    TextField(
                      controller: addressController,
                      maxLines: 2,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        labelText: 'عنوان التوصيل / رابط فقط',
                        prefixIcon: Icon(Icons.location_on),
                      ),
                    ),
                    SizedBox(height: 30.h),
                    _buildSectionTitle('تفاصيل الدفع'),
                    SizedBox(height: 10.h),
                    if (stacked) ...[
                      priceField,
                      SizedBox(height: 12.h),
                      deliveryFeeField,
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: priceField),
                          SizedBox(width: 15.w),
                          Expanded(child: deliveryFeeField),
                        ],
                      ),
                    SizedBox(height: 50.h),
                    SizedBox(
                      height: 50.h,
                      child: ElevatedButton(
                        onPressed: state.isLoading
                            ? null
                            : () async {
                                if (nameController.text.isEmpty ||
                                    priceController.text.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'الرجاء تعبئة الحقول المطلوبة')),
                                  );
                                  return;
                                }

                                if (addressController.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'الرجاء إدخال عنوان التوصيل / رابط')),
                                  );
                                  return;
                                }

                                final coords = _tryParseLatLngFromText(
                                    addressController.text.trim());

                                ref
                                    .read(restaurantControllerProvider.notifier)
                                    .submitOrder(
                                      customerName: nameController.text,
                                      phone: phoneController.text,
                                      address: addressController.text,
                                      price: double.tryParse(
                                              priceController.text) ??
                                          0.0,
                                      deliveryFee: double.tryParse(
                                              deliveryFeeController.text) ??
                                          0.0,
                                      customerLat: coords?.lat,
                                      customerLng: coords?.lng,
                                    );
                              },
                        child: state.isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text(
                                'إرسال الطلب للسائقين',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18.sp,
        fontWeight: FontWeight.bold,
        color: Colors.grey[800],
      ),
    );
  }

  Widget _buildDeliveryFeeField(
    BuildContext context,
    AsyncValue<List<Map<String, dynamic>>> zonePricingAsync,
    ValueNotifier<int?> selectedZoneId,
    TextEditingController deliveryFeeController,
  ) {
    final zonePricing =
        zonePricingAsync.valueOrNull ?? const <Map<String, dynamic>>[];
    if (zonePricing.isEmpty) {
      return TextField(
        controller: deliveryFeeController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'رسوم التوصيل',
          suffixText: 'د.ع',
        ),
      );
    }

    final items = zonePricing
        .map((z) {
          final zid = (z['zone_id'] as num?)?.toInt() ?? (z['zone_id'] as int?);
          if (zid == null) return null;
          final name = z['zone_name']?.toString().trim();
          final fee = (z['delivery_fee'] as num?)?.toDouble() ?? 0.0;
          final label =
              '${name?.isNotEmpty == true ? name! : 'منطقة'} - ${fee.toStringAsFixed(fee.truncateToDouble() == fee ? 0 : 2)} د.ع';
          return DropdownMenuItem<int>(
            value: zid,
            child: Text(label, overflow: TextOverflow.ellipsis),
          );
        })
        .whereType<DropdownMenuItem<int>>()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          value: selectedZoneId.value,
          decoration: const InputDecoration(
            labelText: 'المنطقة',
            prefixIcon: Icon(Icons.map_outlined),
          ),
          items: items,
          onChanged: (v) => selectedZoneId.value = v,
        ),
        SizedBox(height: 10.h),
        TextField(
          controller: deliveryFeeController,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'رسوم التوصيل',
            suffixText: 'د.ع',
          ),
        ),
      ],
    );
  }

  ({double lat, double lng})? _tryParseLatLngFromText(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final patterns = <RegExp>[
      RegExp(r'@(-?\d{1,2}\.\d+),(-?\d{1,3}\.\d+)'),
      RegExp(r'(?:q|query|ll)=(-?\d{1,2}\.\d+),(-?\d{1,3}\.\d+)'),
      RegExp(r'(-?\d{1,2}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)'),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(t);
      if (m == null) continue;
      final lat = double.tryParse(m.group(1) ?? '');
      final lng = double.tryParse(m.group(2) ?? '');
      if (lat == null || lng == null) continue;
      if (lat < -90 || lat > 90) continue;
      if (lng < -180 || lng > 180) continue;
      return (lat: lat, lng: lng);
    }

    return null;
  }
}
