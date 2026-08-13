-- Run once in Supabase SQL Editor after the initial messages migration.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null check (char_length(nickname) between 2 and 24),
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
update public.messages set room_id=(select id from public.rooms where name='Общая' limit 1)
where room_id is null and conversation_id is null;
alter table public.messages drop constraint if exists messages_destination_check;
alter table public.messages add constraint messages_destination_check check (
  (room_id is not null and conversation_id is null) or
  (room_id is null and conversation_id is not null)
);

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.direct_conversations enable row level security;
alter table public.conversation_members enable row level security;

drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles for select to authenticated using (true);
drop policy if exists "manage own profile" on public.profiles;
create policy "manage own profile" on public.profiles for all to authenticated using (auth.uid()=id) with check (auth.uid()=id);
drop policy if exists "rooms readable" on public.rooms;
create policy "rooms readable" on public.rooms for select to authenticated using (true);
drop policy if exists "members see conversations" on public.direct_conversations;
create policy "members see conversations" on public.direct_conversations for select to authenticated using (
  exists(select 1 from public.conversation_members cm where cm.conversation_id=id and cm.user_id=auth.uid())
);
drop policy if exists "members see membership" on public.conversation_members;
create policy "members see membership" on public.conversation_members for select to authenticated using (
  exists(select 1 from public.conversation_members mine where mine.conversation_id=conversation_id and mine.user_id=auth.uid())
);

drop policy if exists "authenticated users can read messages" on public.messages;
drop policy if exists "users can send their own messages" on public.messages;
create policy "read allowed messages" on public.messages for select to authenticated using (
  room_id is not null or exists(select 1 from public.conversation_members cm where cm.conversation_id=messages.conversation_id and cm.user_id=auth.uid())
);
create policy "send allowed messages" on public.messages for insert to authenticated with check (
  auth.uid()=user_id and (room_id is not null or exists(select 1 from public.conversation_members cm where cm.conversation_id=messages.conversation_id and cm.user_id=auth.uid()))
);

create or replace function public.start_dm(target uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare found uuid; created uuid;
begin
  if target=auth.uid() then raise exception 'Cannot message yourself'; end if;
  select c.id into found from direct_conversations c
  where exists(select 1 from conversation_members a where a.conversation_id=c.id and a.user_id=auth.uid())
    and exists(select 1 from conversation_members b where b.conversation_id=c.id and b.user_id=target)
    and (select count(*) from conversation_members x where x.conversation_id=c.id)=2 limit 1;
  if found is not null then return found; end if;
  insert into direct_conversations default values returning id into created;
  insert into conversation_members(conversation_id,user_id) values(created,auth.uid()),(created,target);
  return created;
end; $$;
grant execute on function public.start_dm(uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('avatars','avatars',true,2097152,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true;
drop policy if exists "public avatar read" on storage.objects;
create policy "public avatar read" on storage.objects for select using(bucket_id='avatars');
drop policy if exists "own avatar upload" on storage.objects;
create policy "own avatar upload" on storage.objects for insert to authenticated with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "own avatar update" on storage.objects;
create policy "own avatar update" on storage.objects for update to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);

create index if not exists messages_room_created_idx on public.messages(room_id,created_at desc);
create index if not exists messages_dm_created_idx on public.messages(conversation_id,created_at desc);
