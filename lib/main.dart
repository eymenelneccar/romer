import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_theme.dart';
import 'core/constants.dart';
import 'core/user_facing_exception.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (AppConstants.supabaseUrl.isEmpty ||
        AppConstants.supabaseAnonKey.isEmpty) {
      throw const UserFacingException(
        'Supabase غير مهيأ. مرّر SUPABASE_URL و SUPABASE_ANON_KEY عبر --dart-define.',
      );
    }

    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );

    runApp(const ProviderScope(child: NaemiTeamApp()));
  } catch (e, st) {
    debugPrint('Bootstrap failed: $e');
    debugPrintStack(stackTrace: st);
    runApp(_BootstrapErrorApp(error: e));
  }
}

class _BootstrapErrorApp extends StatelessWidget {
  final Object error;

  const _BootstrapErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    final message = error is UserFacingException
        ? error.toString()
        : 'تعذر تشغيل التطبيق حالياً.';
    final isSupabaseConfigError = message.contains('SUPABASE_URL') ||
        message.contains('SUPABASE_ANON_KEY') ||
        message.toLowerCase().contains('supabase');

    const runCmd =
        'flutter run --dart-define=SUPABASE_URL=YOUR_SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY';
    const buildApkCmd =
        'flutter build apk --release --dart-define=SUPABASE_URL=YOUR_SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY';
    const fromFileCmd = 'flutter run --dart-define-from-file=env.json';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: isSupabaseConfigError
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.settings_suggest_outlined, size: 44),
                          const SizedBox(height: 12),
                          const Text(
                            'إعدادات Supabase غير مهيأة',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'وين ألقى القيم؟',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Supabase Dashboard > Project Settings > API',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'أوامر سريعة (انسخ وبدّل القيم):',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          const _CodeBlock(text: runCmd),
                          const SizedBox(height: 10),
                          const _CodeBlock(text: buildApkCmd),
                          const SizedBox(height: 10),
                          const _CodeBlock(text: fromFileCmd),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    const ClipboardData(text: runCmd),
                                  );
                                },
                                icon: const Icon(Icons.copy),
                                label: const Text('نسخ أمر التشغيل'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    const ClipboardData(
                                      text:
                                          'SUPABASE_URL\nSUPABASE_ANON_KEY\nAUTH_EMAIL_REDIRECT_URL',
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_all_outlined),
                                label: const Text('نسخ أسماء المتغيرات'),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Text(
                        message,
                        textAlign: TextAlign.center,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String text;

  const _CodeBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}

class NaemiTeamApp extends ConsumerWidget {
  const NaemiTeamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    return ScreenUtilInit(
      designSize:
          const Size(375, 812), // Design size based on iPhone X/11 dimensions
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: 'نعيمي تيم',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          // Localization Setup
          locale: const Locale('ar'), // Force Arabic
          supportedLocales: const [
            Locale('ar'),
            Locale('en'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
        );
      },
    );
  }
}
