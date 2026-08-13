# ProgaNaandro

Анонимный чат для Android 7.0+ (API 24): комнаты, личные сообщения, профили, ники и аватары.

## APK

Сборка настроена через EAS. Для GitHub Actions добавьте в **Settings → Secrets and variables → Actions**:

- `EXPO_TOKEN`: токен Expo с https://expo.dev/accounts/[account]/settings/access-tokens
- `EXPO_PUBLIC_SUPABASE_ANON_KEY`: publishable/anon key проекта Supabase

Затем откройте **Actions → Build Android APK → Run workflow**. Готовый APK появится в результате workflow и в EAS Builds.

Для локальной сборки:

```bash
npm install
npx eas-cli login
npx eas build --platform android --profile preview
```

## OTA-обновления

Изменения JavaScript и интерфейса можно выпускать через `eas update --branch production` без нового APK, если они совместимы с установленной нативной версией. Новые нативные библиотеки, разрешения, SDK или изменения `app.json` требуют новой сборки.

## База

Выполните `supabase/rooms_and_dms.sql` после базовой миграции сообщений в Supabase SQL Editor. Anonymous Sign-Ins должны быть включены.
