-- Supabase'e benzeyen asgari yapı: iki veritabanında da aynı şema.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;

create schema if not exists auth;
create schema if not exists cron;
create table cron.job (jobid serial primary key, jobname text, active boolean default true);

create table auth.users (
  id uuid primary key,
  email text,
  encrypted_password text,
  email_confirmed_at timestamptz,
  confirmed_at timestamptz generated always as (email_confirmed_at) stored,
  raw_user_meta_data jsonb
);
create table auth.identities (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null,
  identity_data jsonb
);
create table auth.sessions (id uuid primary key, user_id uuid references auth.users(id) on delete cascade);

create type public.varlik_tipi as enum ('hisse', 'altin', 'kripto');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz default now()
);

-- Supabase'deki handle_new_user deseni: replica modunda ÇALIŞMAMALI.
create function public.handle_new_user() returns trigger language plpgsql as $$
begin
  insert into public.profiles (id, display_name) values (new.id, new.raw_user_meta_data->>'display_name');
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create table public.assets (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id),
  tip public.varlik_tipi not null,
  ticker text not null,
  quantity numeric(20, 8),
  notes text,
  etiketler text[],
  meta jsonb,
  deleted_at timestamptz,
  deger numeric generated always as (quantity * 2) stored
);

create table public.db_logs (id serial primary key, mesaj text);

-- İki taraflı ilişki: tek-kullanıcı kopyasında karşı taraf yoksa GELMEMELİ.
create table public.partnerships (
  id bigint generated always as identity primary key,
  user_id_1 uuid references auth.users(id),
  user_id_2 uuid references auth.users(id),
  status text
);
-- Başka kullanıcıların izini taşıyan log: tek-kullanıcıda kopyalanmaz.
create table public.account_deletion_log (id serial primary key, user_id_hash text);

grant usage on schema public to anon, authenticated;
