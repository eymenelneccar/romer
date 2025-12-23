import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';
import '../../../core/constants.dart';
import '../../../core/user_facing_exception.dart';

// Provider for AuthRepository
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(Supabase.instance.client);
});

String _arabicAuthErrorMessage(Object error) {
  if (error is AuthException) {
    final msg = error.message.toLowerCase();

    if (msg.contains('password') &&
        (msg.contains('at least') ||
            msg.contains('6') ||
            msg.contains('weak'))) {
      return 'كلمة المرور ضعيفة. يجب أن تكون 6 أحرف على الأقل.';
    }

    if (msg.contains('user already registered') ||
        msg.contains('already registered') ||
        msg.contains('already exists') ||
        msg.contains('already been registered')) {
      return 'هذا البريد الإلكتروني مستخدم مسبقاً. استخدم بريدًا آخر أو سجل الدخول.';
    }

    if (msg.contains('email not confirmed') ||
        msg.contains('not confirmed') ||
        msg.contains('email_not_confirmed')) {
      return 'هذا الحساب غير مفعّل حالياً. الرجاء التواصل مع الدعم أو المحاولة لاحقاً.';
    }

    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid') && msg.contains('credentials')) {
      return 'البريد الإلكتروني أو كلمة المرور غير صحيحة. تأكد من كتابة البريد بشكل صحيح ومن حالة الأحرف في كلمة المرور ثم حاول مرة أخرى.';
    }

    if (msg.contains('invalid email') ||
        msg.contains('email') && msg.contains('invalid')) {
      return 'صيغة البريد الإلكتروني غير صحيحة. تأكد أنه يحتوي على علامة @ واسم نطاق صحيح.';
    }

    if (msg.contains('too many requests') || msg.contains('rate limit')) {
      return 'تم تنفيذ محاولات كثيرة خلال وقت قصير. انتظر قليلاً ثم حاول مرة أخرى.';
    }

    if (msg.contains('user not found') || msg.contains('not found')) {
      return 'هذا البريد الإلكتروني غير مسجل لدينا. تأكد من البريد أو أنشئ حساباً جديداً.';
    }

    if (msg.contains('network') ||
        msg.contains('timeout') ||
        msg.contains('socket')) {
      return 'تعذر الاتصال بالخادم حالياً. تأكد من اتصال الإنترنت ثم حاول مرة أخرى.';
    }
  }

  return 'تعذر إتمام العملية حالياً. حاول مرة أخرى بعد قليل.';
}

class AuthRepository {
  final SupabaseClient _supabase;

  AuthRepository(this._supabase);

  Future<String> uploadCurrentUserAvatar({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const UserFacingException(
          'تعذر التحقق من تسجيل الدخول. الرجاء تسجيل الدخول مرة أخرى.');
    }
    if (bytes.isEmpty) {
      throw const UserFacingException(
          'الصورة غير صالحة. حاول اختيار صورة أخرى.');
    }

    final ext = _fileExt(fileName);
    final objectPath =
        '${user.id}/${DateTime.now().millisecondsSinceEpoch}$ext';
    final contentType = _contentTypeForExt(ext);

    try {
      await _supabase.storage.from('avatars').uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: contentType),
          );
    } on StorageException catch (e) {
      final status = e.statusCode?.toString();
      final msg = e.message.toLowerCase();
      if (status == '401' ||
          status == '403' ||
          msg.contains('unauthorized') ||
          msg.contains('row-level security')) {
        throw const UserFacingException(
            'صلاحياتك لا تسمح برفع الصورة حالياً. تواصل مع الأدمن.');
      }
      if (msg.contains('payload') && msg.contains('too large')) {
        throw const UserFacingException(
            'حجم الصورة كبير جداً. اختر صورة أصغر ثم حاول مرة أخرى.');
      }
      throw UserFacingException('تعذر رفع الصورة: ${e.message}');
    } on PostgrestException catch (e) {
      throw UserFacingException('تعذر رفع الصورة: ${e.message}');
    } catch (_) {
      throw const UserFacingException('تعذر رفع الصورة حالياً. حاول مرة أخرى.');
    }

    return _supabase.storage.from('avatars').getPublicUrl(objectPath);
  }

  Future<void> updateCurrentUserAvatarUrl(String avatarUrl) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const UserFacingException(
          'تعذر التحقق من تسجيل الدخول. الرجاء تسجيل الدخول مرة أخرى.');
    }

    await _supabase
        .from('profiles')
        .update({'avatar_url': avatarUrl}).eq('id', user.id);
  }

  Future<void> updateCurrentUserProfile({
    String? name,
    String? phone,
    String? restaurantAddress,
    String? avatarUrl,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const UserFacingException(
          'تعذر التحقق من تسجيل الدخول. الرجاء تسجيل الدخول مرة أخرى.');
    }

    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (phone != null) updates['phone'] = phone;
    if (restaurantAddress != null) {
      updates['restaurant_address'] = restaurantAddress;
    }
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (updates.isEmpty) return;

    try {
      await _supabase.from('profiles').update(updates).eq('id', user.id);
    } on PostgrestException catch (e) {
      throw UserFacingException('تعذر تحديث البيانات: ${e.message}');
    }
  }

  Future<Map<String, dynamic>?> getOrCreateCurrentUserProfile({
    String defaultRole = 'driver',
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return null;
    }

    final existing = await _supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (existing != null) return existing;

    final metadata = user.userMetadata ?? <String, dynamic>{};
    final name = metadata['name']?.toString();
    final phone = metadata['phone']?.toString();
    final requestedRole = metadata['requested_role']?.toString();
    final avatarUrl = metadata['avatar_url']?.toString();
    final restaurantAddress = metadata['restaurant_address']?.toString();
    final effectiveRequestedRole =
        (requestedRole == 'restaurant' || requestedRole == 'driver')
            ? requestedRole
            : defaultRole;

    final created = await _supabase
        .from('profiles')
        .insert({
          'id': user.id,
          'email': user.email,
          'name': name,
          'phone': phone,
          'role': defaultRole,
          'requested_role': effectiveRequestedRole,
          'approval_status': 'pending',
          'is_approved': false,
          'avatar_url': avatarUrl,
          'restaurant_address': restaurantAddress,
        })
        .select()
        .single();

    return created;
  }

  // Sign in with email and password
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      await getOrCreateCurrentUserProfile();
    } catch (e) {
      throw UserFacingException(_arabicAuthErrorMessage(e));
    }
  }

  Future<Session?> signUp({
    required String email,
    required String password,
    required String name,
    required String requestedRole,
    String? phone,
    String? restaurantAddress,
  }) async {
    try {
      final result = await _supabase.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: AppConstants.authEmailRedirectUrl,
        data: {
          'name': name,
          'requested_role': requestedRole,
          if (phone != null) 'phone': phone,
          if (restaurantAddress != null)
            'restaurant_address': restaurantAddress,
        },
      );

      if (result.session != null) {
        await getOrCreateCurrentUserProfile();
      }
      return result.session;
    } catch (e) {
      throw UserFacingException(_arabicAuthErrorMessage(e));
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // Get current user profile with role
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final response =
          await _supabase.from('profiles').select().eq('id', user.id).single();
      return response;
    } catch (e) {
      // If profile doesn't exist or error occurs
      return null;
    }
  }

  // Get current user session
  Session? get currentSession => _supabase.auth.currentSession;

  // Get current user
  User? get currentUser => _supabase.auth.currentUser;

  // Stream auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
}

String _fileExt(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot == -1 || dot == fileName.length - 1) return '';
  return fileName.substring(dot);
}

String _contentTypeForExt(String ext) {
  final e = ext.toLowerCase();
  switch (e) {
    case '.png':
      return 'image/png';
    case '.webp':
      return 'image/webp';
    case '.gif':
      return 'image/gif';
    case '.jpg':
    case '.jpeg':
    default:
      return 'image/jpeg';
  }
}
