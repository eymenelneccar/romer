class UserFacingException implements Exception {
  final String message;

  const UserFacingException(this.message);

  @override
  String toString() => message;
}

String uiErrorTitle(Object error) {
  if (error is UserFacingException) return 'تنبيه';
  return 'تعذر إكمال العملية';
}

String uiErrorMessage(Object error) {
  if (error is UserFacingException) return error.message;

  final raw = error.toString();

  if (raw.contains('SocketException') ||
      raw.contains('Failed host lookup') ||
      raw.contains('Connection refused') ||
      raw.contains('Network is unreachable')) {
    return 'تعذر الاتصال بالإنترنت حالياً.';
  }

  if (raw.contains('JWT') ||
      raw.contains('invalid jwt') ||
      raw.contains('Invalid JWT') ||
      raw.contains('AuthApiException') ||
      raw.contains('invalid_grant') ||
      raw.contains('refresh token')) {
    return 'انتهت الجلسة أو بيانات الدخول غير صالحة. سجّل دخولك من جديد.';
  }

  if (raw.contains('infinite recursion detected in policy') ||
      raw.contains('42P17')) {
    return 'مشكلة بصلاحيات قاعدة البيانات تمنع تحميل البيانات حالياً.';
  }

  if (raw.contains('permission denied') || raw.contains('42501')) {
    return 'لا تملك صلاحية للوصول لهذه البيانات.';
  }

  return 'حدثت مشكلة أثناء تحميل البيانات. حاول مرة أخرى لاحقاً.';
}

List<String> uiErrorHints(Object error) {
  final raw = error.toString();

  if (raw.contains('infinite recursion detected in policy') ||
      raw.contains('42P17') ||
      raw.contains('permission denied') ||
      raw.contains('42501')) {
    return const [
      'جرّب إعادة المحاولة بعد قليل.',
      'إذا استمرت المشكلة، تواصل مع الإدارة لإصلاح الصلاحيات.',
    ];
  }

  if (raw.contains('SocketException') ||
      raw.contains('Failed host lookup') ||
      raw.contains('Network is unreachable')) {
    return const [
      'تأكد من تشغيل الإنترنت أو بيانات الهاتف.',
      'جرّب تبديل الشبكة (Wi‑Fi/بيانات) ثم أعد المحاولة.',
    ];
  }

  return const [
    'تأكد من الإنترنت ثم أعد المحاولة.',
    'إذا استمرت المشكلة، تواصل مع الدعم.',
  ];
}
