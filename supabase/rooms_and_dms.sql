-- Run once in Supabase SQL Editor after the initial messages migration.
-- Safe to re-run. This migration keeps room messages public to signed-in users,
-- while direct messages are visible only to their two participants.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null check (
    char_length(nickname) between 2 and 24
    and nickname = btrim(nickname)
    and nickname !~ '[[:cntrl:]]'
  ),
  avatar_url text,
  updated_at timestamptz not null default now()
);
create unique index if not exists profiles_nickname_lower_idx on public.profiles(lower(nickname));

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text not null default '',
  created_at timestamptz not null default now()
);
insert into public.rooms(name, description) values
  ('Общая', 'Разговор обо всём'),
  ('Знакомства', 'Новые люди и общение'),
  ('Игры', 'Во что играем сегодня')
on conflict (name) do nothing;

create table if not exists public.direct_conversations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);
create table if not exists public.conversation_members (
  conversation_id uuid not null references public.direct_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key(conversation_id, user_id)
);

alter table public.messages add column if not exists room_id uuid references public.rooms(id) on delete cascade;
alter table public.messages add column if not exists conversation_id uuid references public.direct_conversations(id) on delete cascade;
update public.messages
set room_id = (select id from public.rooms where name = 'Общая' limit 1)
where room_id is null and conversation_id is null;
alter table public.messages drop constraint if exists messages_destination_check;
alter table public.messages add constraint messages_destination_check check (
  (room_id is not null and conversation_id is null) or
  (room_id is null and conversation_id is not null)
);
alter table public.messages drop constraint if exists messages_body_nonblank_check;
alter table public.messages add constraint messages_body_nonblank_check check (
  char_length(body) between 1 and 1000 and body ~ '[^[:space:]]'
);

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.direct_conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;

-- SECURITY DEFINER is needed here to avoid a recursive RLS policy on
-- conversation_members. Empty search_path plus fully qualified names prevents
-- object-shadowing attacks. The function exposes only membership for the caller.
create or replace function public.is_conversation_member(conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.conversation_members as cm
    where cm.conversation_id = conversation
      and cm.user_id = auth.uid()
  );
$$;
revoke all on function public.is_conversation_member(uuid) from public;
grant execute on function public.is_conversation_member(uuid) to authenticated;

-- Profiles: all signed-in users may discover nicknames for DMs; only the owner
-- may create or edit their profile. Profiles cannot be deleted from the client.
drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles
for select to authenticated using (true);
drop policy if exists "manage own profile" on public.profiles;
drop policy if exists "insert own profile" on public.profiles;
create policy "insert own profile" on public.profiles
for insert to authenticated with check (auth.uid() = id);
drop policy if exists "update own profile" on public.profiles;
create policy "update own profile" on public.profiles
for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- Rooms are curated by the database owner; clients can only read them.
drop policy if exists "rooms readable" on public.rooms;
create policy "rooms readable" on public.rooms
for select to authenticated using (true);

-- Direct conversations and memberships are visible only to participants.
drop policy if exists "members see conversations" on public.direct_conversations;
create policy "members see conversations" on public.direct_conversations
for select to authenticated using (public.is_conversation_member(id));
drop policy if exists "members see membership" on public.conversation_members;
create policy "members see membership" on public.conversation_members
for select to authenticated using (public.is_conversation_member(conversation_id));

-- Room messages are readable by every signed-in user. Direct messages require
-- membership. Clients may only insert messages under their own auth user id.
drop policy if exists "authenticated users can read messages" on public.messages;
drop policy if exists "users can send their own messages" on public.messages;
drop policy if exists "read allowed messages" on public.messages;
create policy "read allowed messages" on public.messages
for select to authenticated using (
  room_id is not null
  or public.is_conversation_member(conversation_id)
);
drop policy if exists "send allowed messages" on public.messages;
create policy "send allowed messages" on public.messages
for insert to authenticated with check (
  auth.uid() = user_id
  and (
    room_id is not null
    or public.is_conversation_member(conversation_id)
  )
);

-- Creates or reuses a two-person DM. No direct INSERT policies exist on the
-- conversation tables, so membership cannot be forged from the client.
create or replace function public.start_dm(target uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  found uuid;
  created uuid;
begin
  if caller is null then
    raise exception 'Authentication required';
  end if;
  if target is null or target = caller then
    raise exception 'Invalid direct-message target';
  end if;
  if not exists (select 1 from public.profiles where id = target) then
    raise exception 'Profile not found';
  end if;

  select c.id into found
  from public.direct_conversations as c
  where exists (
      select 1 from public.conversation_members as a
      where a.conversation_id = c.id and a.user_id = caller
    )
    and exists (
      select 1 from public.conversation_members as b
      where b.conversation_id = c.id and b.user_id = target
    )
    and (
      select count(*) from public.conversation_members as x
      where x.conversation_id = c.id
    ) = 2
  order by c.created_at
  limit 1;

  if found is not null then
    return found;
  end if;

  insert into public.direct_conversations default values returning id into created;
  insert into public.conversation_members(conversation_id, user_id)
  values (created, caller), (created, target);
  return created;
end;
$$;
revoke all on function public.start_dm(uuid) from public;
grant execute on function public.start_dm(uuid) to authenticated;

-- Basic database-side anti-spam. It is intentionally small and complements,
-- rather than replaces, CAPTCHA and moderation.
create or replace function public.enforce_message_rate_limit()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.messages
    where user_id = auth.uid()
      and created_at > now() - interval '1 second'
  ) then
    raise exception 'Please wait before sending another message';
  end if;
  return new;
end;
$$;
revoke all on function public.enforce_message_rate_limit() from public;
drop trigger if exists messages_rate_limit on public.messages;
create trigger messages_rate_limit
before insert on public.messages
for each row execute function public.enforce_message_rate_limit();

-- Avatars are public by product design. Uploads and replacements are limited to
-- a user's own folder and to the bucket MIME/size restrictions.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "public avatar read" on storage.objects;
create policy "public avatar read" on storage.objects
for select to public using (bucket_id = 'avatars');
drop policy if exists "own avatar upload" on storage.objects;
create policy "own avatar upload" on storage.objects
for insert to authenticated with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);
drop policy if exists "own avatar update" on storage.objects;
create policy "own avatar update" on storage.objects
for update to authenticated using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
) with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create index if not exists conversation_members_user_idx
on public.conversation_members(user_id, conversation_id);
create index if not exists messages_user_created_idx
on public.messages(user_id, created_at desc);
create index if not exists messages_room_created_idx
on public.messages(room_id, created_at desc);
create index if not exists messages_dm_created_idx
on public.messages(conversation_id, created_at desc);
