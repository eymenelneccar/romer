class AppConstants {
  static const String supportWhatsAppNumber = '96407726676453';

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://sblybqtzapgfnexnwktk.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNibHlicXR6YXBnZm5leG53a3RrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjYwNjMxMzgsImV4cCI6MjA4MTYzOTEzOH0.vLzD5e446tNqF6gfr51Fva0FqveRqCUwT09wXmDz-j8',
  );

  static String get authEmailRedirectUrl {
    const configured =
        String.fromEnvironment('AUTH_EMAIL_REDIRECT_URL', defaultValue: '');
    if (configured.isNotEmpty) return configured;
    return '$supabaseUrl/auth/v1/callback';
  }
}
