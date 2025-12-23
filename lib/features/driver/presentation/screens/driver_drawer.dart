import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../../core/constants.dart';

class DriverDrawer extends ConsumerWidget {
  const DriverDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userProfile = ref.watch(userProfileProvider);
    final theme = Theme.of(context);
    final profile = userProfile.value;

    String sanitizePhone(String phone) =>
        phone.replaceAll(RegExp(r'[^0-9+]'), '').trim();

    String phoneForWaMe(String phone) {
      var p = sanitizePhone(phone);
      if (p.startsWith('+')) p = p.substring(1);
      return p;
    }

    String buildSupportMessage(String section) {
      final name = profile?['name']?.toString().trim();
      final phone = profile?['phone']?.toString().trim();
      final userId = profile?['id']?.toString().trim();

      final lines = <String>[
        'السلام عليكم',
        'مركز المساعدة - قسم السائق',
        'الموضوع: $section',
        if (name != null && name.isNotEmpty) 'الاسم: $name',
        if (phone != null && phone.isNotEmpty) 'رقم الجوال: $phone',
        if (userId != null && userId.isNotEmpty) 'معرّف الحساب: $userId',
      ];
      return lines.join('\n');
    }

    Future<void> openSupportWhatsApp(String section) async {
      final p = phoneForWaMe(AppConstants.supportWhatsAppNumber);
      if (p.isEmpty) return;

      final text = Uri.encodeComponent(buildSupportMessage(section));
      final appUri = Uri.parse('whatsapp://send?phone=$p&text=$text');
      if (!kIsWeb && await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
        return;
      }

      final webUri = Uri.parse('https://wa.me/$p?text=$text');
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }

    return Drawer(
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
                top: 50.h, bottom: 20.h, left: 20.w, right: 20.w),
            decoration: BoxDecoration(
              color: theme.primaryColor,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 40.r,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: 40.r, color: Colors.grey),
                  // TODO: Add actual image if available
                ),
                SizedBox(height: 15.h),
                Text(
                  userProfile.value?['name'] ?? 'السائق',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  userProfile.value?['email'] ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          // Menu Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildMenuItem(
                  context,
                  icon: Icons.map,
                  title: 'الخريطة',
                  onTap: () {
                    context.pop(); // Close drawer
                    // Navigate if needed, but we are likely already on map
                  },
                ),
                _buildMenuItem(
                  context,
                  icon: Icons.calendar_month_outlined,
                  title: 'أوقات النشاط',
                  onTap: () {
                    context.pop();
                    context.push('/driver/slots');
                  },
                ),
                _buildMenuItem(
                  context,
                  icon: Icons.account_balance_wallet,
                  title: 'المحفظة',
                  subtitle: 'نسبة فريق نعيمي تيم 20%',
                  onTap: () {
                    context.pop();
                    context.push('/driver/wallet');
                  },
                ),
                _buildMenuItem(
                  context,
                  icon: Icons.history,
                  title: 'سجل الطلبات',
                  onTap: () {
                    context.pop();
                    context.push('/driver/history');
                  },
                ),
                _buildMenuItem(
                  context,
                  icon: Icons.settings,
                  title: 'الإعدادات',
                  onTap: () {
                    context.pop();
                    context.push('/driver/settings');
                  },
                ),
                Padding(
                  padding: EdgeInsets.only(
                      top: 8.h, left: 16.w, right: 16.w, bottom: 6.h),
                  child: Text(
                    'المساعدة والدعم',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.black54,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildMenuItem(
                  context,
                  icon: Icons.support_agent_outlined,
                  title: 'مركز المساعدة',
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) {
                        Widget supportTile({
                          required IconData icon,
                          required String title,
                          required String section,
                        }) {
                          return ListTile(
                            leading: Icon(icon, color: theme.primaryColor),
                            title: Text(title, textAlign: TextAlign.right),
                            trailing: const Icon(Icons.chevron_left,
                                color: Colors.redAccent),
                            onTap: () async {
                              Navigator.pop(ctx);
                              await openSupportWhatsApp(section);
                            },
                          );
                        }

                        return Dialog(
                          insetPadding: EdgeInsets.symmetric(
                              horizontal: 18.w, vertical: 24.h),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 14.w, vertical: 12.h),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      icon: const Icon(Icons.close),
                                    ),
                                    Expanded(
                                      child: Text(
                                        'مركز المساعدة',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    SizedBox(width: 48.w),
                                  ],
                                ),
                                SizedBox(height: 6.h),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'كيف يمكننا مساعدتك؟',
                                    textAlign: TextAlign.right,
                                    style:
                                        theme.textTheme.headlineSmall?.copyWith(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 6.h),
                                Flexible(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      children: [
                                        supportTile(
                                          icon: Icons.shopping_bag_outlined,
                                          title: 'هل تحتاج إلى دعم بخصوص طلبك؟',
                                          section: 'الطلبات',
                                        ),
                                        const Divider(height: 1),
                                        supportTile(
                                          icon: Icons.settings_outlined,
                                          title: 'مشاكل التطبيق',
                                          section: 'مشاكل التطبيق',
                                        ),
                                        const Divider(height: 1),
                                        supportTile(
                                          icon: Icons.schedule_outlined,
                                          title: 'ساعات عملي',
                                          section: 'أوقات النشاط',
                                        ),
                                        const Divider(height: 1),
                                        supportTile(
                                          icon: Icons.business_center_outlined,
                                          title: 'مشاكل المعدات',
                                          section: 'مشاكل المعدات',
                                        ),
                                        const Divider(height: 1),
                                        supportTile(
                                          icon: Icons.more_horiz,
                                          title: 'مواضيع خارج التوصيل',
                                          section: 'مواضيع خارج التوصيل',
                                        ),
                                        const Divider(height: 1),
                                        supportTile(
                                          icon: Icons.mail_outline,
                                          title: 'طلباتي',
                                          section: 'استفسار عام',
                                        ),
                                      ],
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
                ),
                const Divider(),
                _buildMenuItem(
                  context,
                  icon: Icons.logout,
                  title: 'تسجيل الخروج',
                  color: Colors.red,
                  onTap: () {
                    ref.read(authControllerProvider.notifier).signOut();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? Theme.of(context).primaryColor),
      title: Text(
        title,
        style: TextStyle(
          color: color ?? Colors.black87,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
      onTap: onTap,
    );
  }
}
