# naemi_team

تطبيق Flutter لإدارة توصيلات (سائق / مطعم / أدمن) مبني على Supabase.

## Getting Started

### المتطلبات
- Flutter SDK
- حساب Supabase (Project)

### الإعداد
التطبيق يعتمد على تمرير إعدادات Supabase عبر `--dart-define` (ولا توجد قيم افتراضية داخل الكود).

### التشغيل
ثبت الاعتمادات:
```bash
flutter pub get
```

شغّل التطبيق مع إعدادات Supabase:
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

### الفحوصات
```bash
flutter analyze
flutter test
```

### قاعدة البيانات (Supabase)
- ملفات الـ migrations موجودة في `supabase/migrations/`
- بعد تعديل/إضافة migrations طبّقها على مشروع Supabase حسب طريقة تشغيل فريقك (Supabase CLI أو Dashboard).
