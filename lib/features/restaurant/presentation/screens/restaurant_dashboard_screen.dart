import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/data/auth_repository.dart';
import '../controllers/restaurant_controller.dart';
import '../../data/restaurant_repository.dart';
import '../../../../core/constants.dart';
import '../../../../core/user_facing_exception.dart';
import '../../../../core/error_view.dart';

class RestaurantDashboardScreen extends ConsumerStatefulWidget {
  const RestaurantDashboardScreen({super.key});

  @override
  ConsumerState<RestaurantDashboardScreen> createState() =>
      _RestaurantDashboardScreenState();
}

class _RestaurantDashboardScreenState
    extends ConsumerState<RestaurantDashboardScreen> {
  String _filter = 'all';
  String _section = 'active';
  Timer? _ticker;
  final Set<int> _resendingOrderIds = <int>{};

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _sanitizePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9+]'), '').trim();

  String _phoneForWaMe(String phone) {
    var p = _sanitizePhone(phone);
    if (p.startsWith('+')) p = p.substring(1);
    return p;
  }

  String _buildSupportMessage(String section, Map<String, dynamic>? profile) {
    final name = profile?['name']?.toString().trim();
    final phone = profile?['phone']?.toString().trim();
    final userId = profile?['id']?.toString().trim();

    final lines = <String>[
      'السلام عليكم',
      'مركز المساعدة - قسم المطعم',
      'الموضوع: $section',
      if (name != null && name.isNotEmpty) 'الاسم: $name',
      if (phone != null && phone.isNotEmpty) 'رقم الجوال: $phone',
      if (userId != null && userId.isNotEmpty) 'معرّف الحساب: $userId',
    ];
    return lines.join('\n');
  }

  Future<void> _openSupportWhatsApp(BuildContext context, String section,
      Map<String, dynamic>? profile) async {
    final p = _phoneForWaMe(AppConstants.supportWhatsAppNumber);
    if (p.isEmpty) return;

    final text = Uri.encodeComponent(_buildSupportMessage(section, profile));
    final appUri = Uri.parse('whatsapp://send?phone=$p&text=$text');
    if (!kIsWeb && await canLaunchUrl(appUri)) {
      await launchUrl(appUri, mode: LaunchMode.externalApplication);
      return;
    }

    final webUri = Uri.parse('https://wa.me/$p?text=$text');
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showHelpDialog(
      BuildContext context, Map<String, dynamic>? profile) async {
    final theme = Theme.of(context);
    await showDialog<void>(
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
            trailing: const Icon(Icons.chevron_left, color: Colors.redAccent),
            onTap: () async {
              Navigator.pop(ctx);
              await _openSupportWhatsApp(context, section, profile);
            },
          );
        }

        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'اختر القسم المطلوب',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        supportTile(
                          icon: Icons.list_alt_outlined,
                          title: 'الطلبات النشطة',
                          section: 'الطلبات النشطة',
                        ),
                        const Divider(height: 1),
                        supportTile(
                          icon: Icons.add,
                          title: 'اطلب سائق',
                          section: 'اطلب سائق',
                        ),
                        const Divider(height: 1),
                        supportTile(
                          icon: Icons.location_on_outlined,
                          title: 'المناطق والتسعير',
                          section: 'المناطق والتسعير',
                        ),
                        const Divider(height: 1),
                        supportTile(
                          icon: Icons.payments_outlined,
                          title: 'مشاكل الدفع',
                          section: 'مشاكل الدفع',
                        ),
                        const Divider(height: 1),
                        supportTile(
                          icon: Icons.more_horiz,
                          title: 'استفسار عام',
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
  }

  Future<void> _resendOrder(BuildContext context, int orderId) async {
    if (_resendingOrderIds.contains(orderId)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _resendingOrderIds.add(orderId);
    });
    try {
      await ref.read(restaurantRepositoryProvider).resendOrder(orderId);
      if (mounted) {
        messenger.showSnackBar(
            const SnackBar(content: Text('تمت إعادة إرسال الطلب بنجاح')));
      }
    } catch (e) {
      final message =
          e is UserFacingException ? e.toString() : 'تعذر إعادة إرسال الطلب';
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() {
          _resendingOrderIds.remove(orderId);
        });
      }
    }
  }

  Future<void> _openEditRestaurantProfileSheet(
      BuildContext context, Map<String, dynamic>? profile) async {
    final messenger = ScaffoldMessenger.of(context);
    final nameController =
        TextEditingController(text: profile?['name']?.toString() ?? '');
    final phoneController =
        TextEditingController(text: profile?['phone']?.toString() ?? '');
    final addressController = TextEditingController(
        text: profile?['restaurant_address']?.toString() ?? '');
    Uint8List? pickedBytes;
    String? pickedFileName;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var isSaving = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final currentAvatarUrl = profile?['avatar_url']?.toString().trim();

            Future<void> pickImage() async {
              if (isSaving) return;
              final picker = ImagePicker();
              final picked = await picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 80,
                maxWidth: 1200,
              );
              if (picked == null) return;
              final bytes = await picked.readAsBytes();
              setSheetState(() {
                pickedBytes = bytes;
                pickedFileName = picked.name;
              });
            }

            Future<void> save() async {
              if (isSaving) return;
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              final address = addressController.text.trim();
              if (name.isEmpty || phone.isEmpty || address.isEmpty) {
                messenger.showSnackBar(const SnackBar(
                    content: Text('الرجاء تعبئة الاسم والرقم والعنوان')));
                return;
              }

              setSheetState(() => isSaving = true);
              try {
                String? avatarUrl = currentAvatarUrl;
                if (pickedBytes != null) {
                  final url = await ref
                      .read(authRepositoryProvider)
                      .uploadCurrentUserAvatar(
                        bytes: pickedBytes!,
                        fileName: pickedFileName ?? 'avatar.jpg',
                      );
                  avatarUrl = url;
                }

                await ref.read(authRepositoryProvider).updateCurrentUserProfile(
                      name: name,
                      phone: phone,
                      restaurantAddress: address,
                      avatarUrl: avatarUrl,
                    );
                ref.invalidate(userProfileProvider);
                if (ctx.mounted) Navigator.pop(ctx);
                messenger.showSnackBar(
                    const SnackBar(content: Text('تم حفظ بيانات البروفايل')));
              } catch (e) {
                final message = e is UserFacingException
                    ? e.toString()
                    : 'تعذر حفظ البيانات';
                messenger.showSnackBar(SnackBar(
                    content: Text(message), backgroundColor: Colors.red));
                setSheetState(() => isSaving = false);
              }
            }

            final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: EdgeInsets.only(
                    left: 16, right: 16, top: 14, bottom: 16 + bottomInset),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'بروفايل المطعم',
                              style: Theme.of(ctx)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            onPressed:
                                isSaving ? null : () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: InkWell(
                          onTap: isSaving ? null : pickImage,
                          borderRadius: BorderRadius.circular(999),
                          child: CircleAvatar(
                            radius: 46,
                            backgroundColor: Colors.grey[100],
                            backgroundImage: pickedBytes != null
                                ? MemoryImage(pickedBytes!)
                                : (currentAvatarUrl != null &&
                                        currentAvatarUrl.isNotEmpty)
                                    ? NetworkImage(currentAvatarUrl)
                                    : null,
                            child: (pickedBytes == null &&
                                    (currentAvatarUrl == null ||
                                        currentAvatarUrl.isEmpty))
                                ? Icon(Icons.camera_alt_outlined,
                                    color: Colors.grey[700], size: 26)
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameController,
                        enabled: !isSaving,
                        decoration: const InputDecoration(
                          labelText: 'اسم المطعم',
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneController,
                        enabled: !isSaving,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'رقم الجوال',
                          prefixIcon: Icon(Icons.phone),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: addressController,
                        enabled: !isSaving,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'عنوان المطعم',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: isSaving ? null : save,
                          icon: isSaving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(isSaving ? 'جاري الحفظ...' : 'حفظ'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(restaurantOrdersProvider);
    final profile = ref.watch(userProfileProvider).value;
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 420;
    final isTiny = screenWidth < 360;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        drawer: _buildDrawer(context, profile),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          leading: Builder(
            builder: (ctx) {
              return IconButton(
                icon: const Icon(Icons.menu, color: Colors.black87),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              );
            },
          ),
          title: Text(
            _section == 'history' ? 'سجل الطلبات' : 'الطلبات النشطة',
            style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18),
          ),
          actions: [
            if (!isCompact)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3F6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Colors.green, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'تحديث مباشر',
                        style: TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            if (!isCompact) const SizedBox(width: 10),
            Padding(
              padding:
                  const EdgeInsets.only(left: 12, right: 6, top: 8, bottom: 8),
              child: isTiny
                  ? SizedBox(
                      height: 40,
                      width: 46,
                      child: ElevatedButton(
                        onPressed: () =>
                            context.push('/restaurant/create-order'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF25C05),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Icon(Icons.add, size: 20),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: () => context.push('/restaurant/create-order'),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(isTiny ? 'اطلب' : 'اطلب سائق'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF25C05),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ordersAsync.when(
              data: (orders) {
                final now = DateTime.now();
                DateTime? createdAtFor(Map<String, dynamic> o) {
                  final raw = o['created_at']?.toString();
                  if (raw == null) return null;
                  return DateTime.tryParse(raw)?.toLocal();
                }

                bool isOlderThan24h(Map<String, dynamic> o) {
                  final createdAt = createdAtFor(o);
                  if (createdAt == null) return false;
                  return now.difference(createdAt) >= const Duration(hours: 24);
                }

                final activeOrders = orders.where((o) {
                  final s = o['status']?.toString();
                  final isActiveStatus = s == 'pending' ||
                      s == 'pending_repost' ||
                      s == 'accepted' ||
                      s == 'picked_up';
                  if (!isActiveStatus) return false;
                  return !isOlderThan24h(o);
                }).toList();

                final historyOrders =
                    orders.where((o) => isOlderThan24h(o)).toList()
                      ..sort((a, b) {
                        final da = createdAtFor(a);
                        final db = createdAtFor(b);
                        if (da == null && db == null) return 0;
                        if (da == null) return 1;
                        if (db == null) return -1;
                        return db.compareTo(da);
                      });

                final pendingCount = activeOrders.where((o) {
                  final s = o['status']?.toString();
                  return s == 'pending' || s == 'pending_repost';
                }).length;
                final deliveringCount = activeOrders.where((o) {
                  final s = o['status']?.toString();
                  return s == 'accepted' || s == 'picked_up';
                }).length;

                bool isToday(DateTime t) =>
                    t.year == now.year &&
                    t.month == now.month &&
                    t.day == now.day;
                final deliveredTodayCount = orders.where((o) {
                  if (o['status']?.toString() != 'delivered') return false;
                  final createdAt = o['created_at']?.toString();
                  if (createdAt == null) return false;
                  final parsed = DateTime.tryParse(createdAt);
                  if (parsed == null) return false;
                  return isToday(parsed.toLocal());
                }).length;

                final filteredActiveOrders = activeOrders.where((o) {
                  if (_filter == 'pending') {
                    final s = o['status']?.toString();
                    return s == 'pending' || s == 'pending_repost';
                  }
                  if (_filter == 'accepted') {
                    return o['status']?.toString() == 'accepted';
                  }
                  return true;
                }).toList();

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 900;
                    final contentWidth = constraints.maxWidth;
                    final columns =
                        contentWidth >= 900 ? 3 : (contentWidth >= 600 ? 2 : 1);
                    const gap = 12.0;
                    final cardWidth = columns == 1
                        ? contentWidth
                        : (contentWidth - (gap * (columns - 1))) / columns;
                    final maxBodyWidth = constraints.maxWidth >= 900
                        ? (constraints.maxWidth * 0.72).clamp(0.0, 960.0)
                        : constraints.maxWidth;

                    return Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: maxBodyWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                SizedBox(
                                  width: cardWidth,
                                  child: _StatCard(
                                    icon: Icons.hourglass_bottom,
                                    iconBg: const Color(0xFFFFF4D6),
                                    iconColor: const Color(0xFFF0A500),
                                    title: 'الطلبات المعلقة',
                                    value: pendingCount.toString(),
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: _StatCard(
                                    icon: Icons.circle_outlined,
                                    iconBg: const Color(0xFFE8F1FF),
                                    iconColor: const Color(0xFF2D6BFF),
                                    title: 'جاري التوصيل',
                                    value: deliveringCount.toString(),
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: _StatCard(
                                    icon: Icons.check_circle,
                                    iconBg: const Color(0xFFEAF8EE),
                                    iconColor: const Color(0xFF2EAD5B),
                                    title: 'تم التوصيل اليوم',
                                    value: deliveredTodayCount.toString(),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      _section == 'history'
                                          ? 'سجل الطلبات'
                                          : 'قائمة الطلبات',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 10),
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          _FilterPill(
                                            label: 'الطلبات النشطة',
                                            selected: _section == 'active',
                                            onTap: () => setState(
                                                () => _section = 'active'),
                                          ),
                                          const SizedBox(width: 8),
                                          _FilterPill(
                                            label: 'سجل الطلبات',
                                            selected: _section == 'history',
                                            onTap: () => setState(
                                                () => _section = 'history'),
                                          ),
                                          if (_section == 'active') ...[
                                            const SizedBox(width: 8),
                                            _FilterPill(
                                              label: 'الكل',
                                              selected: _filter == 'all',
                                              onTap: () => setState(
                                                  () => _filter = 'all'),
                                            ),
                                            const SizedBox(width: 8),
                                            _FilterPill(
                                              label: 'معلق',
                                              selected: _filter == 'pending',
                                              onTap: () => setState(
                                                  () => _filter = 'pending'),
                                            ),
                                            const SizedBox(width: 8),
                                            _FilterPill(
                                              label: 'مقبول',
                                              selected: _filter == 'accepted',
                                              onTap: () => setState(
                                                  () => _filter = 'accepted'),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Expanded(
                                      child: _section == 'history'
                                          ? _OrdersHistoryList(
                                              orders: historyOrders)
                                          : filteredActiveOrders.isEmpty
                                              ? Center(
                                                  child: Text(
                                                    'لا توجد طلبات مطابقة',
                                                    style: TextStyle(
                                                        color:
                                                            Colors.grey[600]),
                                                  ),
                                                )
                                              : isWide
                                                  ? _OrdersTable(
                                                      orders:
                                                          filteredActiveOrders,
                                                      onResend: (id) =>
                                                          _resendOrder(
                                                              context, id),
                                                      isResending: (id) =>
                                                          _resendingOrderIds
                                                              .contains(id),
                                                    )
                                                  : _OrdersCardsList(
                                                      orders:
                                                          filteredActiveOrders,
                                                      onResend: (id) =>
                                                          _resendOrder(
                                                              context, id),
                                                      isResending: (id) =>
                                                          _resendingOrderIds
                                                              .contains(id),
                                                    ),
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
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => ErrorView(
                title: 'تعذر تحميل الطلبات',
                error: err,
                onRetry: () => ref.invalidate(restaurantOrdersProvider),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Drawer _buildDrawer(BuildContext context, Map<String, dynamic>? profile) {
    final theme = Theme.of(context);
    final name = profile?['name']?.toString().trim();
    final phone = profile?['phone']?.toString().trim();
    final address = profile?['restaurant_address']?.toString().trim();
    final avatarUrl = profile?['avatar_url']?.toString().trim();

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                  top: 18, bottom: 16, left: 16, right: 16),
              decoration: BoxDecoration(color: theme.primaryColor),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.white,
                    backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? NetworkImage(avatarUrl)
                        : null,
                    child: (avatarUrl == null || avatarUrl.isEmpty)
                        ? Icon(Icons.storefront,
                            size: 30, color: Colors.grey[700])
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (name != null && name.isNotEmpty) ? name : 'المطعم',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (address != null && address.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                        if (phone != null && phone.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            phone,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(
                          _openEditRestaurantProfileSheet(context, profile));
                    },
                    icon: const Icon(Icons.edit, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('اطلب سائق'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/restaurant/create-order');
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.manage_accounts_outlined),
                    title: const Text('تعديل البروفايل'),
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(
                          _openEditRestaurantProfileSheet(context, profile));
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.support_agent_outlined),
                    title: const Text('مركز المساعدة'),
                    onTap: () {
                      Navigator.pop(context);
                      _showHelpDialog(context, profile);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('تسجيل الخروج'),
                    onTap: () {
                      Navigator.pop(context);
                      ref.read(authControllerProvider.notifier).signOut();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String value;

  const _StatCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(value,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: selected ? Colors.black : Colors.grey[300]!),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _OrdersHistoryList extends StatelessWidget {
  final List<Map<String, dynamic>> orders;

  const _OrdersHistoryList({required this.orders});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Text(
          'لا يوجد طلبات في السجل بعد',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    DateTime? createdAtFor(Map<String, dynamic> o) {
      final raw = o['created_at']?.toString();
      if (raw == null) return null;
      return DateTime.tryParse(raw)?.toLocal();
    }

    String dateKey(DateTime d) {
      final y = d.year.toString().padLeft(4, '0');
      final m = d.month.toString().padLeft(2, '0');
      final day = d.day.toString().padLeft(2, '0');
      return '$y/$m/$day';
    }

    final groups = <String, List<Map<String, dynamic>>>{};
    final groupDates = <String, DateTime?>{};

    for (final o in orders) {
      final createdAt = createdAtFor(o);
      if (createdAt == null) {
        groups.putIfAbsent('بدون تاريخ', () => <Map<String, dynamic>>[]).add(o);
        continue;
      }
      final dayOnly = DateTime(createdAt.year, createdAt.month, createdAt.day);
      final key = dateKey(dayOnly);
      groups.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(o);
      groupDates[key] = dayOnly;
    }

    for (final e in groups.entries) {
      e.value.sort((a, b) {
        final da = createdAtFor(a);
        final db = createdAtFor(b);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
    }

    final keys = groups.keys.toList()
      ..sort((a, b) {
        final da = groupDates[a];
        final db = groupDates[b];
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final key = keys[index];
        final items = groups[key] ?? const <Map<String, dynamic>>[];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: index == 0,
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      key,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    '(${items.length})',
                    style: TextStyle(
                        color: Colors.grey[700], fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              children: [
                Padding(
                  padding:
                      const EdgeInsets.only(left: 12, right: 12, bottom: 12),
                  child: Column(
                    children: items
                        .map(
                          (o) => Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _HistoryOrderCard(order: o),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistoryOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;

  const _HistoryOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final customer = (order['customer_details'] as Map?) ?? {};
    final status = order['status']?.toString();
    final statusUi = _statusUI(status);
    final price = (order['price'] as num?)?.toDouble() ?? 0.0;
    final branchId = (order['branch_id'] as num?)?.toInt();
    final phone = customer['phone']?.toString() ?? '—';
    final name = customer['name']?.toString() ?? '—';
    final address = customer['address']?.toString() ?? '—';

    final driverId = order['driver_id']?.toString().trim();
    final driverName = order['driver_name']?.toString().trim();
    final driverPhone = order['driver_phone']?.toString().trim();
    final driverText = (driverName != null &&
            driverName.isNotEmpty &&
            driverPhone != null &&
            driverPhone.isNotEmpty)
        ? 'السائق: $driverName - $driverPhone'
        : (driverPhone != null && driverPhone.isNotEmpty)
            ? 'رقم السائق: $driverPhone'
            : (driverId != null && driverId.isNotEmpty)
                ? 'معرّف السائق: $driverId'
                : null;

    String? timeText() {
      final raw = order['created_at']?.toString();
      if (raw == null) return null;
      final dt = DateTime.tryParse(raw)?.toLocal();
      if (dt == null) return null;
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }

    final t = timeText();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'طلب #${order['id']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              _StatusChip(color: statusUi.color, label: statusUi.label),
            ],
          ),
          if (t != null) ...[
            const SizedBox(height: 6),
            Text(
              'الوقت: $t',
              style: TextStyle(
                  color: Colors.grey[700], fontWeight: FontWeight.w600),
            ),
          ],
          if (driverText != null) ...[
            const SizedBox(height: 6),
            Text(
              driverText,
              style: TextStyle(
                  color: Colors.grey[700], fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 10),
          Text('رقم الهاتف: $phone', style: TextStyle(color: Colors.grey[700])),
          Text('العميل: $name', style: TextStyle(color: Colors.grey[700])),
          Text(
            'العنوان: $address',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey[700]),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${price.toStringAsFixed(0)} د.ع',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              Text(
                branchId == null ? '—' : 'فرع #$branchId',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrdersCardsList extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final Future<void> Function(int orderId) onResend;
  final bool Function(int orderId) isResending;

  const _OrdersCardsList({
    required this.orders,
    required this.onResend,
    required this.isResending,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    DateTime? baseTimeFor(Map<String, dynamic> order) {
      final customer = (order['customer_details'] as Map?) ?? {};
      final resendAt = customer['resend_at']?.toString().trim();
      final raw = (resendAt != null && resendAt.isNotEmpty)
          ? resendAt
          : order['created_at']?.toString();
      if (raw == null) return null;
      return DateTime.tryParse(raw)?.toLocal();
    }

    String formatMMSS(Duration d) {
      final seconds = d.inSeconds.clamp(0, 24 * 60 * 60);
      final m = (seconds ~/ 60).toString().padLeft(2, '0');
      final s = (seconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    return ListView.separated(
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final o = orders[index];
        final customer = (o['customer_details'] as Map?) ?? {};
        final status = o['status']?.toString();
        final statusUi = _statusUI(status);
        final price = (o['price'] as num?)?.toDouble() ?? 0.0;
        final branchId = (o['branch_id'] as num?)?.toInt();
        final phone = customer['phone']?.toString() ?? '—';
        final name = customer['name']?.toString() ?? '—';
        final address = customer['address']?.toString() ?? '—';
        final driverId = o['driver_id']?.toString().trim();
        final driverName = o['driver_name']?.toString().trim();
        final driverPhone = o['driver_phone']?.toString().trim();
        final driverText = (driverName != null &&
                driverName.isNotEmpty &&
                driverPhone != null &&
                driverPhone.isNotEmpty)
            ? 'السائق: $driverName - $driverPhone'
            : (driverPhone != null && driverPhone.isNotEmpty)
                ? 'رقم السائق: $driverPhone'
                : (driverId != null && driverId.isNotEmpty)
                    ? 'معرّف السائق: $driverId'
                    : null;

        final orderId = (o['id'] as num?)?.toInt();
        final canShowResend =
            (status == 'pending' || status == 'pending_repost') &&
                (driverId == null || driverId.isEmpty);
        final base = canShowResend ? baseTimeFor(o) : null;
        final remaining = base == null
            ? null
            : (const Duration(minutes: 3) - now.difference(base));
        final canResend = remaining == null ? false : remaining.inSeconds <= 0;
        final loading = orderId == null ? false : isResending(orderId);

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text('طلب #${o['id']}',
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                  _StatusChip(color: statusUi.color, label: statusUi.label),
                ],
              ),
              if (status != 'pending' && driverText != null) ...[
                const SizedBox(height: 6),
                Text(
                  driverText,
                  style: TextStyle(
                      color: Colors.grey[700], fontWeight: FontWeight.w700),
                ),
              ],
              if (canShowResend && remaining != null && orderId != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed:
                      (!canResend || loading) ? null : () => onResend(orderId),
                  icon: loading
                      ? const SizedBox.shrink()
                      : const Icon(Icons.refresh),
                  label: Text(
                    loading
                        ? 'جاري الإرسال...'
                        : canResend
                            ? 'إعادة إرسال الطلب'
                            : 'إعادة الإرسال بعد ${formatMMSS(remaining)}',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text('رقم الهاتف: $phone',
                  style: TextStyle(color: Colors.grey[700])),
              Text('العميل: $name', style: TextStyle(color: Colors.grey[700])),
              Text('العنوان: $address',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[700])),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '${price.toStringAsFixed(0)} د.ع',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  Text(
                    branchId == null ? '—' : 'فرع #$branchId',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrdersTable extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final Future<void> Function(int orderId) onResend;
  final bool Function(int orderId) isResending;

  const _OrdersTable({
    required this.orders,
    required this.onResend,
    required this.isResending,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final addressCellWidth =
        screenWidth >= 1200 ? 360.0 : (screenWidth >= 900 ? 300.0 : 240.0);

    DateTime? baseTimeFor(Map<String, dynamic> order) {
      final customer = (order['customer_details'] as Map?) ?? {};
      final resendAt = customer['resend_at']?.toString().trim();
      final raw = (resendAt != null && resendAt.isNotEmpty)
          ? resendAt
          : order['created_at']?.toString();
      if (raw == null) return null;
      return DateTime.tryParse(raw)?.toLocal();
    }

    String formatMMSS(Duration d) {
      final seconds = d.inSeconds.clamp(0, 24 * 60 * 60);
      final m = (seconds ~/ 60).toString().padLeft(2, '0');
      final s = (seconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 44,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 56,
        columns: const [
          DataColumn(label: Text('رقم الهاتف')),
          DataColumn(label: Text('العميل')),
          DataColumn(label: Text('العنوان')),
          DataColumn(label: Text('قيمة الطلب')),
          DataColumn(label: Text('السائق')),
          DataColumn(label: Text('إعادة الإرسال')),
          DataColumn(label: Text('الحالة')),
          DataColumn(label: Text('الفرع')),
        ],
        rows: orders.map((o) {
          final customer = (o['customer_details'] as Map?) ?? {};
          final phone = customer['phone']?.toString() ?? '—';
          final name = customer['name']?.toString() ?? '—';
          final address = customer['address']?.toString() ?? '—';
          final price = (o['price'] as num?)?.toDouble() ?? 0.0;
          final driverPhone = o['driver_phone']?.toString().trim();
          final driverId = o['driver_id']?.toString().trim();
          final driverCellText = (driverPhone != null && driverPhone.isNotEmpty)
              ? driverPhone
              : (driverId != null && driverId.isNotEmpty)
                  ? driverId
                  : '—';
          final status = o['status']?.toString();
          final orderId = (o['id'] as num?)?.toInt();
          final canShowResend =
              (status == 'pending' || status == 'pending_repost') &&
                  (driverId == null || driverId.isEmpty);
          final base = canShowResend ? baseTimeFor(o) : null;
          final remaining = base == null
              ? null
              : (const Duration(minutes: 3) - now.difference(base));
          final canResend =
              remaining == null ? false : remaining.inSeconds <= 0;
          final loading = orderId == null ? false : isResending(orderId);
          final statusUi = _statusUI(status);
          final branchId = (o['branch_id'] as num?)?.toInt();

          return DataRow(
            cells: [
              DataCell(Text(phone)),
              DataCell(Text(name)),
              DataCell(SizedBox(
                  width: addressCellWidth,
                  child: Text(address,
                      maxLines: 1, overflow: TextOverflow.ellipsis))),
              DataCell(Text('${price.toStringAsFixed(0)} د.ع')),
              DataCell(Text(driverCellText)),
              DataCell(
                (canShowResend && remaining != null && orderId != null)
                    ? OutlinedButton(
                        onPressed: (!canResend || loading)
                            ? null
                            : () => onResend(orderId),
                        child: Text(
                          loading
                              ? 'جاري الإرسال...'
                              : canResend
                                  ? 'إعادة إرسال'
                                  : formatMMSS(remaining),
                        ),
                      )
                    : const Text('—'),
              ),
              DataCell(
                  _StatusChip(color: statusUi.color, label: statusUi.label)),
              DataCell(Text(branchId == null ? '—' : 'فرع #$branchId')),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final Color color;
  final String label;

  const _StatusChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}

({Color color, String label}) _statusUI(String? status) {
  switch (status) {
    case 'pending':
    case 'pending_repost':
      return (color: const Color(0xFFF0A500), label: 'معلق');
    case 'accepted':
      return (color: const Color(0xFF2D6BFF), label: 'مقبول');
    case 'picked_up':
      return (color: const Color(0xFF7A4EE8), label: 'جاري التوصيل');
    case 'delivered':
      return (color: const Color(0xFF2EAD5B), label: 'تم التوصيل');
    default:
      return (color: Colors.grey, label: status ?? '—');
  }
}
