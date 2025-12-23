import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/screens/signup_screen.dart';
import 'features/driver/presentation/screens/driver_map_screen.dart';
import 'features/driver/presentation/screens/wallet_screen.dart';
import 'features/driver/presentation/screens/order_history_screen.dart';
import 'features/driver/presentation/screens/driver_settings_screen.dart';
import 'features/driver/presentation/screens/driver_slots_screen.dart';
import 'features/restaurant/presentation/screens/restaurant_dashboard_screen.dart';
import 'features/restaurant/presentation/screens/create_order_screen.dart';
import 'features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'features/admin/presentation/screens/admin_drivers_screen.dart';
import 'features/admin/presentation/screens/admin_restaurants_screen.dart';
import 'features/admin/presentation/screens/admin_users_screen.dart';
import 'features/admin/presentation/screens/admin_zones_screen.dart';
import 'features/admin/presentation/screens/admin_new_members_screen.dart';
import 'features/auth/presentation/screens/approval_status_screen.dart';

final routerProfileCacheProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: GoRouterRefreshStream(
        ref.read(authRepositoryProvider).authStateChanges),
    redirect: (context, state) async {
      final authRepo = ref.read(authRepositoryProvider);
      final isLoggedIn = authRepo.currentSession != null;
      final path = state.uri.path;
      final isLoginRoute = path == '/login';
      final isSignUpRoute = path == '/signup';
      final isApprovalRoute = path == '/approval';

      if (!isLoggedIn) {
        ref.read(routerProfileCacheProvider.notifier).state = null;
        return (isLoginRoute || isSignUpRoute) ? null : '/login';
      }

      Map<String, dynamic>? profile = ref.read(routerProfileCacheProvider);
      if (profile == null) {
        final fetchedProfile = await authRepo.getOrCreateCurrentUserProfile();
        if (fetchedProfile == null) return '/login';
        ref.read(routerProfileCacheProvider.notifier).state = fetchedProfile;
        profile = fetchedProfile;
      }

      final rawRole = profile['role']?.toString();
      final effectiveRole =
          (rawRole == 'admin' || rawRole == 'restaurant' || rawRole == 'driver')
              ? rawRole!
              : 'driver';
      final approvalStatus = profile['approval_status']?.toString();
      final isApproved =
          profile['is_approved'] == true || approvalStatus == 'approved';

      String homeForRole(String role) {
        if (role == 'admin') return '/admin';
        if (role == 'restaurant') return '/restaurant';
        return '/driver';
      }

      if (effectiveRole != 'admin' && !isApproved) {
        if (isApprovalRoute) return null;
        return '/approval';
      }

      if (isLoginRoute || isSignUpRoute) return homeForRole(effectiveRole);
      if (isApprovalRoute) return homeForRole(effectiveRole);

      final isAdminRoute = path.startsWith('/admin');
      final isRestaurantRoute = path.startsWith('/restaurant');
      final isDriverRoute = path.startsWith('/driver');

      final isAllowed = switch (effectiveRole) {
        'admin' => isAdminRoute,
        'restaurant' => isRestaurantRoute,
        _ => isDriverRoute,
      };

      if (!isAllowed) return homeForRole(effectiveRole);

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: '/approval',
        builder: (context, state) => const ApprovalStatusScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboardScreen(),
        routes: [
          GoRoute(
            path: 'drivers',
            builder: (context, state) => const AdminDriversScreen(),
          ),
          GoRoute(
            path: 'restaurants',
            builder: (context, state) => const AdminRestaurantsScreen(),
          ),
          GoRoute(
            path: 'zones',
            builder: (context, state) => const AdminZonesScreen(),
          ),
          GoRoute(
            path: 'users',
            builder: (context, state) => const AdminUsersScreen(),
          ),
          GoRoute(
            path: 'new-members',
            builder: (context, state) => const AdminNewMembersScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/restaurant',
        builder: (context, state) => const RestaurantDashboardScreen(),
        routes: [
          GoRoute(
            path: 'create-order',
            builder: (context, state) => const CreateOrderScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/driver',
        builder: (context, state) => const DriverMapScreen(),
        routes: [
          GoRoute(
            path: 'wallet',
            builder: (context, state) => const WalletScreen(),
          ),
          GoRoute(
            path: 'history',
            builder: (context, state) => const OrderHistoryScreen(),
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) => const DriverSettingsScreen(),
          ),
          GoRoute(
            path: 'slots',
            builder: (context, state) => const DriverSlotsScreen(),
          ),
        ],
      ),
    ],
  );
});

// Helper class to convert Stream to Listenable for GoRouter
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
          (dynamic _) => notifyListeners(),
        );
  }

  late final dynamic _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
