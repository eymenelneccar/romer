import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../../data/auth_repository.dart';
import '../controllers/auth_controller.dart';
import '../../../../core/user_facing_exception.dart';

class SignUpScreen extends HookConsumerWidget {
  const SignUpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final nameController = useTextEditingController();
    final phoneController = useTextEditingController();
    final emailController = useTextEditingController();
    final passwordController = useTextEditingController();
    final restaurantAddressController = useTextEditingController();
    final authState = ref.watch(authControllerProvider);
    final requestedRole = useState<String>('driver');
    final avatarFile = useState<XFile?>(null);
    final avatarBytes = useState<Uint8List?>(null);

    useListenable(nameController);
    useListenable(phoneController);
    useListenable(emailController);
    useListenable(passwordController);
    useListenable(restaurantAddressController);

    bool isValidEmail(String value) {
      final v = value.trim();
      if (v.isEmpty) return false;
      return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
    }

    bool isValidPhone(String value) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      return digits.length >= 10 && digits.length <= 15;
    }

    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final restaurantAddress = restaurantAddressController.text.trim();

    final canSubmit = !authState.isLoading &&
        avatarBytes.value != null &&
        name.isNotEmpty &&
        isValidPhone(phone) &&
        isValidEmail(email) &&
        password.length >= 6 &&
        (requestedRole.value != 'restaurant' || restaurantAddress.isNotEmpty);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('إنشاء حساب'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20.w),
        child: Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 10.h),
              Center(
                child: InkWell(
                  onTap: authState.isLoading
                      ? null
                      : () async {
                          final picker = ImagePicker();
                          final picked = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 80,
                            maxWidth: 1000,
                          );
                          if (picked == null) return;
                          avatarFile.value = picked;
                          avatarBytes.value = await picked.readAsBytes();
                        },
                  borderRadius: BorderRadius.circular(60.r),
                  child: CircleAvatar(
                    radius: 44.r,
                    backgroundColor: Colors.grey[100],
                    backgroundImage: avatarBytes.value != null
                        ? MemoryImage(avatarBytes.value!)
                        : null,
                    child: avatarBytes.value == null
                        ? Icon(Icons.camera_alt_outlined,
                            color: Colors.grey[700])
                        : null,
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              Text(
                'اضغط لاختيار الصورة',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700]),
              ),
              SizedBox(height: 20.h),
              DropdownButtonFormField<String>(
                value: requestedRole.value,
                items: const [
                  DropdownMenuItem(value: 'driver', child: Text('سائق دراجة')),
                  DropdownMenuItem(value: 'restaurant', child: Text('مطعم')),
                ],
                onChanged: authState.isLoading
                    ? null
                    : (v) => requestedRole.value = v ?? 'driver',
                decoration: const InputDecoration(
                  labelText: 'اختر نوع الحساب',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              SizedBox(height: 15.h),
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'الاسم',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'الرجاء إدخال الاسم';
                  }
                  return null;
                },
              ),
              SizedBox(height: 15.h),
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم الجوال',
                  prefixIcon: Icon(Icons.phone),
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'الرجاء إدخال رقم الجوال';
                  if (!isValidPhone(value)) return 'رقم الجوال غير صحيح';
                  return null;
                },
              ),
              SizedBox(height: 15.h),
              TextFormField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'الرجاء إدخال البريد الإلكتروني';
                  if (!isValidEmail(value)) {
                    return 'صيغة البريد الإلكتروني غير صحيحة';
                  }
                  return null;
                },
              ),
              SizedBox(height: 15.h),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'الرجاء إدخال كلمة المرور';
                  if (value.length < 6) {
                    return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                  }
                  return null;
                },
              ),
              if (requestedRole.value == 'restaurant') ...[
                SizedBox(height: 15.h),
                TextFormField(
                  controller: restaurantAddressController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'عنوان المطعم بالتفصيل',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  validator: (v) {
                    if (requestedRole.value != 'restaurant') return null;
                    final value = (v ?? '').trim();
                    if (value.isEmpty) {
                      return 'الرجاء إدخال عنوان المطعم بالتفصيل';
                    }
                    return null;
                  },
                ),
              ],
              SizedBox(height: 30.h),
              SizedBox(
                height: 50.h,
                child: ElevatedButton(
                  onPressed: canSubmit
                      ? () async {
                          final isValid =
                              formKey.currentState?.validate() ?? false;
                          if (!isValid) return;
                          if (avatarBytes.value == null) return;

                          final session = await ref
                              .read(authControllerProvider.notifier)
                              .signUp(
                                email: email,
                                password: password,
                                name: name,
                                requestedRole: requestedRole.value,
                                phone: phone,
                                restaurantAddress:
                                    requestedRole.value == 'restaurant'
                                        ? restaurantAddress
                                        : null,
                              );

                          if (!context.mounted) return;

                          if (session != null &&
                              avatarFile.value != null &&
                              avatarBytes.value != null) {
                            try {
                              final repo = ref.read(authRepositoryProvider);
                              final url = await repo.uploadCurrentUserAvatar(
                                bytes: avatarBytes.value!,
                                fileName: avatarFile.value!.name,
                              );
                              await repo.updateCurrentUserAvatarUrl(url);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'تعذر رفع الصورة: ${uiErrorMessage(e)}')),
                                );
                              }
                            }
                          }

                          if (!context.mounted) return;

                          if (session == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'تم إنشاء الحساب. يمكنك تسجيل الدخول الآن وانتظار موافقة الأدمن.'),
                              ),
                            );
                            context.go('/login');
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'تم تقديم طلبك. انتظر موافقة الأدمن.')),
                            );
                            context.go('/approval');
                          }
                        }
                      : null,
                  child: authState.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'إنشاء حساب',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              SizedBox(height: 16.h),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('لديك حساب؟ تسجيل الدخول'),
              ),
              if (authState.hasError) ...[
                SizedBox(height: 10.h),
                Text(
                  authState.error == null
                      ? ''
                      : uiErrorMessage(authState.error!),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
