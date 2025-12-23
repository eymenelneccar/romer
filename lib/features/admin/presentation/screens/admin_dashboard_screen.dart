import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../controllers/admin_controller.dart';
import '../../../../core/constants.dart';
import '../../../../core/error_view.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  String _sanitizePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9+]'), '').trim();

  String _ordersQuery = '';
  int? _ordersSortColumnIndex;
  bool _ordersSortAscending = true;
  late final TextEditingController _ordersSearchController;

  String _driversQuery = '';
  int? _driversSortColumnIndex;
  bool _driversSortAscending = true;
  late final TextEditingController _driversSearchController;

  String _restaurantsQuery = '';
  int? _restaurantsSortColumnIndex;
  bool _restaurantsSortAscending = false;
  late final TextEditingController _restaurantsSearchController;

  @override
  void initState() {
    super.initState();
    _ordersSearchController = TextEditingController();
    _driversSearchController = TextEditingController();
    _restaurantsSearchController = TextEditingController();
  }

  @override
  void dispose() {
    _ordersSearchController.dispose();
    _driversSearchController.dispose();
    _restaurantsSearchController.dispose();
    super.dispose();
  }

  String _phoneForWaMe(String phone) {
    var p = _sanitizePhone(phone);
    if (p.startsWith('+')) p = p.substring(1);
    return p;
  }

  String _buildSupportMessage(String section) {
    final lines = <String>[
      'السلام عليكم',
      'مركز المساعدة - قسم الأدمن',
      'الموضوع: $section',
    ];
    return lines.join('\n');
  }

  Future<void> _openSupportWhatsApp(
      BuildContext context, String section) async {
    final p = _phoneForWaMe(AppConstants.supportWhatsAppNumber);
    if (p.isEmpty) return;

    final text = Uri.encodeComponent(_buildSupportMessage(section));
    final appUri = Uri.parse('whatsapp://send?phone=$p&text=$text');
    if (!kIsWeb && await canLaunchUrl(appUri)) {
      await launchUrl(appUri, mode: LaunchMode.externalApplication);
      return;
    }

    final webUri = Uri.parse('https://wa.me/$p?text=$text');
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showHelpDialog(BuildContext context) async {
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
              await _openSupportWhatsApp(context, section);
            },
          );
        }

        return Dialog(
          insetPadding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 24.h),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
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
                    SizedBox(width: 48.w),
                  ],
                ),
                SizedBox(height: 6.h),
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
                SizedBox(height: 6.h),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        supportTile(
                          icon: Icons.map_outlined,
                          title: 'الخريطة الحية',
                          section: 'الخريطة الحية',
                        ),
                        const Divider(height: 1),
                        supportTile(
                          icon: Icons.person_add_alt_1_outlined,
                          title: 'أعضاء جدد',
                          section: 'أعضاء جدد',
                        ),
                        const Divider(height: 1),
                        supportTile(
                          icon: Icons.directions_car_filled_outlined,
                          title: 'إدارة السائقين',
                          section: 'إدارة السائقين',
                        ),
                        const Divider(height: 1),
                        supportTile(
                          icon: Icons.store_outlined,
                          title: 'إدارة المطاعم',
                          section: 'إدارة المطاعم',
                        ),
                        const Divider(height: 1),
                        supportTile(
                          icon: Icons.people_outline,
                          title: 'إدارة المستخدمين',
                          section: 'إدارة المستخدمين',
                        ),
                        const Divider(height: 1),
                        supportTile(
                          icon: Icons.location_on_outlined,
                          title: 'المناطق (Zones)',
                          section: 'المناطق',
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

  String _fmtMoney(num? v) => ((v ?? 0).toDouble()).toStringAsFixed(2);

  DateTime? _parseCreatedAt(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  String _fmtTime(Object? createdAt) {
    final dt = _parseCreatedAt(createdAt);
    if (dt == null) return '—';
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  ({Color color, String label}) _statusUI(String? status) {
    switch (status) {
      case 'pending':
      case 'pending_repost':
        return (color: const Color(0xFFF0A500), label: 'معلق');
      case 'accepted':
        return (color: const Color(0xFF2D6BFF), label: 'قيد التنفيذ');
      case 'picked_up':
        return (color: const Color(0xFF7A4EE8), label: 'جاري التوصيل');
      case 'delivered':
        return (color: const Color(0xFF2EAD5B), label: 'تم التوصيل');
      case 'cancelled':
        return (color: const Color(0xFFEF4444), label: 'ملغي');
      default:
        return (color: Colors.grey, label: status ?? '—');
    }
  }

  bool _matchesQuery(String? value, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final v = (value ?? '').trim().toLowerCase();
    return v.contains(q);
  }

  int _cmpNum(num? a, num? b) => (a ?? 0).compareTo(b ?? 0);

  int _cmpBool(bool a, bool b) => (a == b) ? 0 : (a ? 1 : -1);

  void _sortOrders(List<Map<String, dynamic>> list) {
    final col = _ordersSortColumnIndex;
    if (col == null) return;

    int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
      switch (col) {
        case 0:
          return _cmpNum((a['id'] as num?), (b['id'] as num?));
        case 1:
          return (a['status']?.toString() ?? '')
              .compareTo(b['status']?.toString() ?? '');
        case 2:
          return (a['restaurant_name']?.toString() ?? '')
              .compareTo(b['restaurant_name']?.toString() ?? '');
        case 3:
          return (a['driver_name']?.toString() ?? '')
              .compareTo(b['driver_name']?.toString() ?? '');
        case 4:
          return _cmpNum(
              (a['delivery_fee'] as num?), (b['delivery_fee'] as num?));
        case 5:
          final da = _parseCreatedAt(a['created_at']);
          final db = _parseCreatedAt(b['created_at']);
          return (da ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(db ?? DateTime.fromMillisecondsSinceEpoch(0));
        default:
          return 0;
      }
    }

    list.sort((a, b) => _ordersSortAscending ? cmp(a, b) : cmp(b, a));
  }

  void _sortDrivers(List<Map<String, dynamic>> list) {
    final col = _driversSortColumnIndex;
    if (col == null) return;

    int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
      switch (col) {
        case 0:
          return (a['name']?.toString() ?? '')
              .compareTo(b['name']?.toString() ?? '');
        case 1:
          return _cmpBool(a['is_available'] == true, b['is_available'] == true);
        case 2:
          return _cmpNum(
              (a['wallet_balance'] as num?), (b['wallet_balance'] as num?));
        case 3:
          return _cmpNum((a['delivered_orders_count'] as num?),
              (b['delivered_orders_count'] as num?));
        case 4:
          return _cmpNum((a['naemi_share_total'] as num?),
              (b['naemi_share_total'] as num?));
        default:
          return 0;
      }
    }

    list.sort((a, b) => _driversSortAscending ? cmp(a, b) : cmp(b, a));
  }

  void _sortRestaurants(List<Map<String, dynamic>> list) {
    final col = _restaurantsSortColumnIndex;
    if (col == null) return;

    int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
      switch (col) {
        case 0:
          return (a['name']?.toString() ?? '')
              .compareTo(b['name']?.toString() ?? '');
        case 1:
          return _cmpNum((a['outgoing_orders_count'] as num?),
              (b['outgoing_orders_count'] as num?));
        default:
          return 0;
      }
    }

    list.sort((a, b) => _restaurantsSortAscending ? cmp(a, b) : cmp(b, a));
  }

  Widget _tableSearchField({
    required String hint,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return SizedBox(
      width: 280.w,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
          contentPadding:
              EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required BuildContext context,
    required String title,
    VoidCallback? onTap,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
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
                    title,
                    style:
                        TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w800),
                  ),
                ),
                if (onTap != null)
                  TextButton(
                    onPressed: onTap,
                    child: const Text('إدارة'),
                  ),
              ],
            ),
            SizedBox(height: 10.h),
            child,
          ],
        ),
      ),
    );
  }

  Widget _statTile({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            width: 40.w,
            height: 40.w,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(icon, color: color, size: 20.sp),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 3.h),
                Text(
                  value,
                  style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyTable(
    String title, {
    Object? error,
    VoidCallback? onRetry,
  }) {
    if (error != null) {
      return ErrorView(
        title: title,
        error: error,
        onRetry: onRetry,
        compact: true,
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 14.h),
      child: Center(
        child: Text(
          title,
          style:
              TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(adminOrdersProvider);
    final driversAsync = ref.watch(adminDriversProvider);
    final restaurantsAsync = ref.watch(adminRestaurantsProvider);
    final zonesAsync = ref.watch(adminZonesProvider);
    final pendingAsync = ref.watch(adminPendingMembersProvider);

    final onlineCount = ref.watch(onlineDriversCountProvider).valueOrNull;
    final activeOrdersCount = ref.watch(activeOrdersCountProvider).valueOrNull;
    final totalDriversCount = driversAsync.valueOrNull?.length;
    final restaurantsCount = restaurantsAsync.valueOrNull?.length;
    final zonesCount = zonesAsync.valueOrNull?.length;
    final pendingCount = ref.watch(pendingMembersCountProvider).valueOrNull;

    final topPending =
        (pendingAsync.valueOrNull ?? const <Map<String, dynamic>>[])
            .take(10)
            .toList();

    return Scaffold(
      drawer: _buildAdminDrawer(context),
      appBar: AppBar(
        title: const Text('لوحة الإدارة'),
        actions: [
          IconButton(
            onPressed: () => _showHelpDialog(context),
            icon: const Icon(Icons.support_agent_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminOrdersProvider);
          ref.invalidate(adminDriversProvider);
          ref.invalidate(adminRestaurantsProvider);
          ref.invalidate(adminPendingMembersProvider);
        },
        child: ListView(
          padding: EdgeInsets.all(16.w),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'نظرة عامة',
                    style:
                        TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w900),
                  ),
                ),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF3FF),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7.w,
                        height: 7.w,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2D7CFB),
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        'مباشر',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF2D7CFB),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            LayoutBuilder(
              builder: (context, c) {
                final isWide = c.maxWidth >= 560;
                final cardWidth = isWide ? (c.maxWidth - 12.w) / 2 : c.maxWidth;
                final gap = 12.w;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _statTile(
                        icon: Icons.directions_car,
                        color: const Color(0xFF22C55E),
                        title: 'السائقين المتصلين',
                        value: onlineCount?.toString() ?? '—',
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _statTile(
                        icon: Icons.groups_2_outlined,
                        color: const Color(0xFF0EA5E9),
                        title: 'إجمالي السائقين',
                        value: totalDriversCount?.toString() ?? '—',
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _statTile(
                        icon: Icons.shopping_bag_outlined,
                        color: const Color(0xFFF59E0B),
                        title: 'الطلبات النشطة',
                        value: activeOrdersCount?.toString() ?? '—',
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _statTile(
                        icon: Icons.store_outlined,
                        color: const Color(0xFF2D7CFB),
                        title: 'المطاعم',
                        value: restaurantsCount?.toString() ?? '—',
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _statTile(
                        icon: Icons.location_on_outlined,
                        color: const Color(0xFF7A4EE8),
                        title: 'المناطق',
                        value: zonesCount?.toString() ?? '—',
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _statTile(
                        icon: Icons.person_add_alt_1_outlined,
                        color: const Color(0xFFEF4444),
                        title: 'أعضاء بانتظار الموافقة',
                        value: pendingCount?.toString() ?? '—',
                      ),
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: 14.h),
            _sectionCard(
              context: context,
              title: 'إجراءات سريعة',
              child: Wrap(
                spacing: 10.w,
                runSpacing: 10.w,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.push('/admin/drivers'),
                    icon: const Icon(Icons.directions_car_filled_outlined),
                    label: const Text('السائقين'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/admin/restaurants'),
                    icon: const Icon(Icons.store_outlined),
                    label: const Text('المطاعم'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/admin/new-members'),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('أعضاء جدد'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/admin/users'),
                    icon: const Icon(Icons.people_outline),
                    label: const Text('المستخدمين'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/admin/zones'),
                    icon: const Icon(Icons.location_on_outlined),
                    label: const Text('المناطق'),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            _sectionCard(
              context: context,
              title: 'الطلبات النشطة (آخر 24 ساعة)',
              child: ordersAsync.when(
                data: (orders) {
                  final filtered = orders.where((o) {
                    if (_ordersQuery.trim().isEmpty) return true;
                    final id = (o['id'] as num?)?.toInt().toString();
                    return _matchesQuery(id, _ordersQuery) ||
                        _matchesQuery(
                            o['restaurant_name']?.toString(), _ordersQuery) ||
                        _matchesQuery(
                            o['driver_name']?.toString(), _ordersQuery);
                  }).toList();

                  if (_ordersSortColumnIndex == null) {
                    _ordersSortColumnIndex = 5;
                    _ordersSortAscending = false;
                  }
                  _sortOrders(filtered);
                  final visible = filtered.take(20).toList();

                  if (visible.isEmpty) {
                    return _emptyTable('لا توجد طلبات مطابقة');
                  }

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10.w,
                          runSpacing: 10.w,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _tableSearchField(
                              hint: 'بحث: رقم الطلب / المطعم / السائق',
                              controller: _ordersSearchController,
                              onChanged: (v) =>
                                  setState(() => _ordersQuery = v),
                            ),
                            Text(
                              '(${filtered.length})',
                              style: TextStyle(
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        SizedBox(height: 10.h),
                        DataTable(
                          sortColumnIndex: _ordersSortColumnIndex,
                          sortAscending: _ordersSortAscending,
                          headingRowHeight: 40.h,
                          dataRowMinHeight: 42.h,
                          dataRowMaxHeight: 56.h,
                          columns: [
                            DataColumn(
                              label: const Text('رقم'),
                              onSort: (i, asc) => setState(() {
                                _ordersSortColumnIndex = i;
                                _ordersSortAscending = asc;
                              }),
                            ),
                            DataColumn(
                              label: const Text('الحالة'),
                              onSort: (i, asc) => setState(() {
                                _ordersSortColumnIndex = i;
                                _ordersSortAscending = asc;
                              }),
                            ),
                            DataColumn(
                              label: const Text('المطعم'),
                              onSort: (i, asc) => setState(() {
                                _ordersSortColumnIndex = i;
                                _ordersSortAscending = asc;
                              }),
                            ),
                            DataColumn(
                              label: const Text('السائق'),
                              onSort: (i, asc) => setState(() {
                                _ordersSortColumnIndex = i;
                                _ordersSortAscending = asc;
                              }),
                            ),
                            DataColumn(
                              numeric: true,
                              label: const Text('الأجرة'),
                              onSort: (i, asc) => setState(() {
                                _ordersSortColumnIndex = i;
                                _ordersSortAscending = asc;
                              }),
                            ),
                            DataColumn(
                              label: const Text('الوقت'),
                              onSort: (i, asc) => setState(() {
                                _ordersSortColumnIndex = i;
                                _ordersSortAscending = asc;
                              }),
                            ),
                          ],
                          rows: [
                            for (final o in visible)
                              DataRow(
                                cells: [
                                  DataCell(Text(
                                      '#${(o['id'] as num?)?.toInt() ?? '—'}')),
                                  DataCell(
                                    Builder(
                                      builder: (context) {
                                        final s = o['status']?.toString();
                                        final ui = _statusUI(s);
                                        return Container(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 10.w, vertical: 4.h),
                                          decoration: BoxDecoration(
                                            color: ui.color.withOpacity(0.10),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(color: ui.color),
                                          ),
                                          child: Text(
                                            ui.label,
                                            style: TextStyle(
                                                color: ui.color,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12.sp),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  DataCell(Text(
                                      o['restaurant_name']?.toString() ?? '—')),
                                  DataCell(Text(
                                      o['driver_name']?.toString() ?? '—')),
                                  DataCell(Text(
                                      '${_fmtMoney(o['delivery_fee'] as num?)} د.ع')),
                                  DataCell(Text(_fmtTime(o['created_at']))),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const Center(
                    child: Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator())),
                error: (err, _) => _emptyTable(
                  'تعذر تحميل الطلبات',
                  error: err,
                  onRetry: () => ref.invalidate(adminOrdersProvider),
                ),
              ),
            ),
            SizedBox(height: 12.h),
            _sectionCard(
              context: context,
              title: 'السائقون',
              onTap: () => context.push('/admin/drivers'),
              child: driversAsync.when(
                data: (drivers) {
                  final filtered = drivers.where((d) {
                    if (_driversQuery.trim().isEmpty) return true;
                    return _matchesQuery(
                            d['name']?.toString(), _driversQuery) ||
                        _matchesQuery(d['phone']?.toString(), _driversQuery);
                  }).toList();

                  if (_driversSortColumnIndex == null) {
                    _driversSortColumnIndex = 1;
                    _driversSortAscending = false;
                  }
                  _sortDrivers(filtered);
                  final visible = filtered.take(20).toList();

                  if (visible.isEmpty) {
                    return _emptyTable('لا توجد نتائج مطابقة');
                  }
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10.w,
                          runSpacing: 10.w,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _tableSearchField(
                              hint: 'بحث: اسم / رقم هاتف',
                              controller: _driversSearchController,
                              onChanged: (v) =>
                                  setState(() => _driversQuery = v),
                            ),
                            Text(
                              '(${filtered.length})',
                              style: TextStyle(
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        SizedBox(height: 10.h),
                        DataTable(
                          sortColumnIndex: _driversSortColumnIndex,
                          sortAscending: _driversSortAscending,
                          headingRowHeight: 40.h,
                          dataRowMinHeight: 42.h,
                          dataRowMaxHeight: 56.h,
                          columns: [
                            DataColumn(
                              label: const Text('السائق'),
                              onSort: (i, asc) => setState(() {
                                _driversSortColumnIndex = i;
                                _driversSortAscending = asc;
                              }),
                            ),
                            DataColumn(
                              label: const Text('الحالة'),
                              onSort: (i, asc) => setState(() {
                                _driversSortColumnIndex = i;
                                _driversSortAscending = asc;
                              }),
                            ),
                            DataColumn(
                              numeric: true,
                              label: const Text('محفظته'),
                              onSort: (i, asc) => setState(() {
                                _driversSortColumnIndex = i;
                                _driversSortAscending = asc;
                              }),
                            ),
                            DataColumn(
                              numeric: true,
                              label: const Text('طلبات موصلة'),
                              onSort: (i, asc) => setState(() {
                                _driversSortColumnIndex = i;
                                _driversSortAscending = asc;
                              }),
                            ),
                            DataColumn(
                              numeric: true,
                              label: const Text('حصة نعيمي'),
                              onSort: (i, asc) => setState(() {
                                _driversSortColumnIndex = i;
                                _driversSortAscending = asc;
                              }),
                            ),
                          ],
                          rows: [
                            for (final d in visible)
                              DataRow(
                                cells: [
                                  DataCell(Text(d['name']?.toString() ?? '—')),
                                  DataCell(
                                    Text(
                                      d['is_available'] == true
                                          ? 'متاح'
                                          : 'غير متاح',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: d['is_available'] == true
                                            ? const Color(0xFF22C55E)
                                            : const Color(0xFFEF4444),
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(
                                      '${_fmtMoney(d['wallet_balance'] as num?)} د.ع')),
                                  DataCell(Text(
                                      '${(d['delivered_orders_count'] as num?)?.toInt() ?? 0}')),
                                  DataCell(Text(
                                      '${_fmtMoney(d['naemi_share_total'] as num?)} د.ع')),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const Center(
                    child: Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator())),
                error: (err, _) => _emptyTable(
                  'تعذر تحميل السائقين',
                  error: err,
                  onRetry: () => ref.invalidate(adminDriversProvider),
                ),
              ),
            ),
            SizedBox(height: 12.h),
            _sectionCard(
              context: context,
              title: 'المطاعم (طلبات طالعة)',
              onTap: () => context.push('/admin/restaurants'),
              child: restaurantsAsync.when(
                data: (restaurants) {
                  final filtered = restaurants.where((r) {
                    if (_restaurantsQuery.trim().isEmpty) return true;
                    return _matchesQuery(
                            r['name']?.toString(), _restaurantsQuery) ||
                        _matchesQuery(
                            r['email']?.toString(), _restaurantsQuery) ||
                        _matchesQuery(
                            r['phone']?.toString(), _restaurantsQuery);
                  }).toList();

                  if (_restaurantsSortColumnIndex == null) {
                    _restaurantsSortColumnIndex = 1;
                    _restaurantsSortAscending = false;
                  }
                  _sortRestaurants(filtered);
                  final visible = filtered.take(20).toList();

                  if (visible.isEmpty) {
                    return _emptyTable('لا توجد نتائج مطابقة');
                  }
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10.w,
                          runSpacing: 10.w,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _tableSearchField(
                              hint: 'بحث: اسم / هاتف / إيميل',
                              controller: _restaurantsSearchController,
                              onChanged: (v) =>
                                  setState(() => _restaurantsQuery = v),
                            ),
                            Text(
                              '(${filtered.length})',
                              style: TextStyle(
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        SizedBox(height: 10.h),
                        DataTable(
                          sortColumnIndex: _restaurantsSortColumnIndex,
                          sortAscending: _restaurantsSortAscending,
                          headingRowHeight: 40.h,
                          dataRowMinHeight: 42.h,
                          dataRowMaxHeight: 56.h,
                          columns: [
                            DataColumn(
                              label: const Text('المطعم'),
                              onSort: (i, asc) => setState(() {
                                _restaurantsSortColumnIndex = i;
                                _restaurantsSortAscending = asc;
                              }),
                            ),
                            DataColumn(
                              numeric: true,
                              label: const Text('طلبات طالعة'),
                              onSort: (i, asc) => setState(() {
                                _restaurantsSortColumnIndex = i;
                                _restaurantsSortAscending = asc;
                              }),
                            ),
                          ],
                          rows: [
                            for (final r in visible)
                              DataRow(
                                cells: [
                                  DataCell(
                                      Text(r['name']?.toString() ?? 'مطعم')),
                                  DataCell(Text(
                                      '${(r['outgoing_orders_count'] as num?)?.toInt() ?? 0}')),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const Center(
                    child: Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator())),
                error: (err, _) => _emptyTable(
                  'تعذر تحميل المطاعم',
                  error: err,
                  onRetry: () => ref.invalidate(adminRestaurantsProvider),
                ),
              ),
            ),
            SizedBox(height: 12.h),
            _sectionCard(
              context: context,
              title: 'أعضاء جدد',
              onTap: () => context.push('/admin/new-members'),
              child: pendingAsync.when(
                data: (_) {
                  if (topPending.isEmpty) {
                    return _emptyTable('لا يوجد أعضاء بانتظار الموافقة');
                  }
                  return Column(
                    children: [
                      for (final p in topPending)
                        Padding(
                          padding: EdgeInsets.only(bottom: 10.h),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18.r,
                                backgroundColor: Colors.grey[100],
                                child: const Icon(Icons.person_outline),
                              ),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p['name']?.toString() ?? 'مستخدم',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.sp),
                                    ),
                                    SizedBox(height: 2.h),
                                    Text(
                                      p['email']?.toString() ?? '—',
                                      style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12.sp,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 10.w),
                              Text(
                                (p['requested_role']?.toString() ?? '').isEmpty
                                    ? '—'
                                    : p['requested_role'].toString(),
                                style: TextStyle(
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
                loading: () => const Center(
                    child: Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator())),
                error: (err, _) => _emptyTable(
                  'تعذر تحميل الأعضاء',
                  error: err,
                  onRetry: () => ref.invalidate(adminPendingMembersProvider),
                ),
              ),
            ),
            SizedBox(height: 10.h),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminDrawer(BuildContext context) {
    final pendingCount =
        ref.watch(pendingMembersCountProvider).valueOrNull ?? 0;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 10.h),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'لوحة الإدارة',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          'Super Admin',
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 38.w,
                    height: 38.w,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D7CFB),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: IconButton(
                      onPressed: () =>
                          ref.read(authControllerProvider.notifier).signOut(),
                      icon: const Icon(Icons.logout),
                      color: Colors.white,
                      splashRadius: 20.r,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              child: SizedBox(
                width: double.infinity,
                height: 46.h,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.dashboard_outlined),
                  label: const Text('لوحة البيانات'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D7CFB),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    textStyle: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 6.h),
              child: Text(
                'الإدارة',
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[600],
                ),
              ),
            ),
            _buildDrawerItem(
              context,
              icon: Icons.person_add_alt_1_outlined,
              title: 'أعضاء جدد',
              trailing: pendingCount > 0
                  ? Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        pendingCount.toString(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : null,
              onTap: () => context.push('/admin/new-members'),
            ),
            _buildDrawerItem(
              context,
              icon: Icons.directions_car_filled_outlined,
              title: 'إدارة السائقين',
              onTap: () => context.push('/admin/drivers'),
            ),
            _buildDrawerItem(
              context,
              icon: Icons.store_outlined,
              title: 'إدارة المطاعم',
              onTap: () => context.push('/admin/restaurants'),
            ),
            _buildDrawerItem(
              context,
              icon: Icons.people_outline,
              title: 'إدارة المستخدمين',
              onTap: () => context.push('/admin/users'),
            ),
            _buildDrawerItem(
              context,
              icon: Icons.location_on_outlined,
              title: 'المناطق (Zones)',
              onTap: () => context.push('/admin/zones'),
            ),
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 6.h),
              child: Text(
                'المساعدة والدعم',
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[600],
                ),
              ),
            ),
            _buildDrawerItem(
              context,
              icon: Icons.support_agent_outlined,
              title: 'مركز المساعدة',
              onTap: () => _showHelpDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w),
      leading: Icon(icon, color: Colors.grey[700]),
      trailing: trailing,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14.sp,
          fontWeight: FontWeight.w600,
          color: Colors.grey[800],
        ),
      ),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}
