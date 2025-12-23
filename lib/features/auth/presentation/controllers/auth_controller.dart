import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/auth_repository.dart';

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
  return AuthController(ref.read(authRepositoryProvider));
});

class AuthController extends StateNotifier<AsyncValue<void>> {
  final AuthRepository _authRepository;

  AuthController(this._authRepository) : super(const AsyncValue.data(null));

  Future<void> signIn({required String email, required String password}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => _authRepository.signIn(email: email, password: password));
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _authRepository.signOut());
  }

  Future<Session?> signUp({
    required String email,
    required String password,
    required String name,
    required String requestedRole,
    String? phone,
    String? restaurantAddress,
  }) async {
    state = const AsyncValue.loading();
    Session? session;
    state = await AsyncValue.guard(() async {
      session = await _authRepository.signUp(
        email: email,
        password: password,
        name: name,
        requestedRole: requestedRole,
        phone: phone,
        restaurantAddress: restaurantAddress,
      );
    });
    return session;
  }
}

// Provider to get the current user profile including role
final userProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  // Watch auth state changes to refresh profile on login/logout
  final authState = ref.watch(authStateChangesProvider);

  return authState.when(
    data: (state) {
      if (state.session == null) return null;
      return ref.read(authRepositoryProvider).getOrCreateCurrentUserProfile();
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

// Stream provider for auth state
final authStateChangesProvider = StreamProvider((ref) {
  return ref.read(authRepositoryProvider).authStateChanges;
});
