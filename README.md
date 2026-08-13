# ProgaNaandro

Анонимный общий чат для Android 7.0+ (API 24). Клиент: Expo / React Native. Онлайн-сообщения и анонимная авторизация: Supabase.

## Запуск

1. Создайте проект Supabase и включите **Anonymous Sign-Ins** в Authentication → Providers.
2. Выполните SQL ниже в Supabase SQL Editor.
3. Создайте `.env`:

```env
EXPO_PUBLIC_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
EXPO_PUBLIC_SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

4. Запустите приложение:

```bash
npm install
npx expo start
```

## База данных

```sql
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  nickname text not null check (char_length(nickname) between 2 and 24),
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

alter table public.messages enable row level security;

create policy "authenticated users can read messages"
on public.messages for select to authenticated using (true);

create policy "users can send their own messages"
on public.messages for insert to authenticated
with check (auth.uid() = user_id);

alter publication supabase_realtime add table public.messages;

create index messages_created_at_idx on public.messages(created_at desc);
```

## Совместимость

Минимальная версия: Android 7.0, API 24. Перед релизом проект нужно собрать через EAS Build и проверить на эмуляторе API 24 и актуальном Android.

## Уже работает

Анонимный вход, локальное сохранение ника, общий realtime-чат, история последних 200 сообщений, состояния загрузки и ошибок.

## Дальше

Модерация, жалобы и блокировка пользователей, антиспам, комнаты, push-уведомления, аватары без персональных данных и релизная сборка APK/AAB.
