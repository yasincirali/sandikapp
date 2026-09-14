-- 0000 — Taban şema (profiles, assets, snapshots, davet/ortaklık, push token,
--        disclaimer, db_logs) — YENİ ORTAM kurulumu için
-- ============================================================
--
-- ── Neden bu dosya var ──────────────────────────────────────────────────────
-- Migration defteri 0007'den başlıyordu. Taban tablolar kök `supabase_schema.sql`
-- ile Dashboard'dan elle kurulmuş, o dosya da 2026-09 güvenlik denetiminde
-- (0008 ile kapatılan zafiyetli politikaları hâlâ taşıdığı için) nota
-- indirilmişti. Sonuç: `supabase db reset` ile SIFIRDAN bir ortam
-- KURULAMIYORDU — 0007+ `public.assets`, `public.profiles` gibi tablolara
-- dayanıyor. Yol haritası 3.16 (integration_test) bu yüzden "test Supabase
-- projesi ister" diye bekliyordu; asıl eksik hosted proje değil, taban
-- şemanın migration olarak var olmamasıydı.
--
-- İçerik `supabase_schema.sql`'in son tam sürümünden (git 1b23813) alındı ve
-- 0008'in SONRAKİ durumuna getirildi:
--   · 0008'in DÜŞÜRDÜĞÜ dört politika (`invites_redeem_select`,
--     `invites_claim_update`, `invites_target_update`, `partnerships_insert`)
--     BURADA YOK. Canlıda zaten yoklar; yeniden yaratmak zafiyeti geri
--     getirirdi. Taze ortamda 0008'in `drop policy if exists`'i no-op kalır.
--   · `db_logs_insert` ve `handle_new_user` doğrudan 0008'in sertleştirilmiş
--     hâliyle yazıldı (0008 yine üstüne yazar; sonuç aynı).
--
-- ── Canlı proje için GÜVENLİ: her ifade idempotent ─────────────────────────
-- Canlıda bu tabloların hepsi var. `supabase db push` bu dosyayı "0007'den
-- önce eklenen migration" diye görür ve `--include-all` ister; o yolla
-- koşarsa da hiçbir şeyi değiştirmez: `create table if not exists`,
-- `create index if not exists`, politikalar `pg_policies` denetimiyle
-- yalnızca YOKSA yaratılır, `create or replace function` 0008 ile aynı
-- gövde. Tercih edilen yol yine de deftere işaretlemek:
--   supabase migration repair --status applied 0000
-- (bkz. YAPMAN_GEREKENLER.md). İki yol da aynı yere çıkar.
--
-- Deno/CI yerel yığını (`supabase start` + `seed.sql`) bu dosyayla açılır;
-- `integration_test/` ve `tool/supabase_smoke.sh` ona dayanır.

create extension if not exists "pgcrypto";

-- ── Tablolar ────────────────────────────────────────────────────────────────

create table if not exists public.profiles (
  id                    uuid primary key references auth.users(id) on delete cascade,
  email                 text not null,
  display_name          text not null,
  onboarding_completed  boolean not null default false,
  created_at            timestamptz not null default now()
);
alter table public.profiles
  add column if not exists onboarding_completed boolean not null default false;

create table if not exists public.assets (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  name             text not null,
  ticker           text not null default '',
  type             text not null,
  sub_category     text,
  unit_type        text not null default 'piece',
  quantity         double precision not null,
  purchase_price   double precision not null,
  currency         text not null default 'TRY',
  current_price    double precision not null,
  last_updated     timestamptz,
  added_date       timestamptz not null default now(),
  notes            text not null default '',
  is_manual_price  boolean not null default false,
  purchase_fx_rate double precision not null default 1.0
);
create index if not exists assets_user_id_idx on public.assets(user_id);

create table if not exists public.snapshots (
  id       bigserial primary key,
  user_id  uuid not null references auth.users(id) on delete cascade,
  ts       timestamptz not null default now(),
  data     jsonb not null
);
create index if not exists snapshots_user_ts_idx on public.snapshots(user_id, ts);

create table if not exists public.partner_invites (
  id             uuid primary key default gen_random_uuid(),
  from_user_id   uuid not null references auth.users(id) on delete cascade,
  to_user_id     uuid references auth.users(id) on delete cascade,
  requester_name text,
  code           text not null unique,
  payload        text not null,
  expires_at     timestamptz not null,
  used           boolean not null default false,
  status         text not null default 'pending'
);

create table if not exists public.user_push_tokens (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  token      text not null unique,
  platform   text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists user_push_tokens_user_id_idx
  on public.user_push_tokens(user_id);

create table if not exists public.partnerships (
  id          uuid primary key default gen_random_uuid(),
  user_id_1   uuid not null references auth.users(id) on delete cascade,
  user_id_2   uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  active      boolean not null default true,
  unique (user_id_1, user_id_2)
);
create index if not exists partnerships_user1_idx on public.partnerships(user_id_1);
create index if not exists partnerships_user2_idx on public.partnerships(user_id_2);

-- Yasal uyarı onay kaydı — hukuki delil: UPDATE/DELETE politikası YOK
-- (varsayılan red), FORCE RLS aşağıda.
create table if not exists public.disclaimer_acceptances (
  id                  bigserial primary key,
  user_id             uuid not null references auth.users(id) on delete cascade,
  accepted_at         timestamptz not null default now(),
  disclaimer_version  text not null,
  disclaimer_hash     text not null,
  app_version         text not null,
  platform            text not null,
  device_model        text,
  locale              text,
  unique (user_id, disclaimer_version)
);
create index if not exists disclaimer_acceptances_user_idx
  on public.disclaimer_acceptances(user_id, accepted_at desc);

-- İstemci tarafı DB isteği günlüğü. user_id nullable: oturumsuz istekleri
-- (login, register) de yakalar. Retention 0056'da.
create table if not exists public.db_logs (
  id            bigserial primary key,
  user_id       uuid references auth.users(id) on delete set null,
  ts            timestamptz not null default now(),
  sdk           text not null,
  source        text not null,
  table_name    text not null,
  op            text not null,
  request_json  jsonb,
  response_json jsonb,
  duration_ms   integer not null,
  is_error      boolean not null default false
);
create index if not exists db_logs_user_ts_idx on public.db_logs(user_id, ts desc);
create index if not exists db_logs_source_idx  on public.db_logs(source);

-- ── RLS ─────────────────────────────────────────────────────────────────────

alter table public.profiles               enable row level security;
alter table public.assets                 enable row level security;
alter table public.snapshots              enable row level security;
alter table public.partner_invites        enable row level security;
alter table public.user_push_tokens       enable row level security;
alter table public.partnerships           enable row level security;
alter table public.disclaimer_acceptances enable row level security;
alter table public.disclaimer_acceptances force  row level security;
alter table public.db_logs                enable row level security;

-- Politikalar yalnızca YOKSA yaratılır (`create policy if not exists` yok).
-- Canlıda hepsi var → bu blok orada tamamen no-op.
do $$
begin
  -- profiles
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='profiles_select_own') then
    create policy "profiles_select_own" on public.profiles
      for select using (auth.uid() = id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='profiles_insert_own') then
    create policy "profiles_insert_own" on public.profiles
      for insert with check (auth.uid() = id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='profiles_update_own') then
    create policy "profiles_update_own" on public.profiles
      for update using (auth.uid() = id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='profiles_select_partner') then
    create policy "profiles_select_partner" on public.profiles
      for select using (
        exists (
          select 1 from public.partnerships p
          where (p.user_id_1 = auth.uid() and p.user_id_2 = id)
             or (p.user_id_2 = auth.uid() and p.user_id_1 = id)
        )
      );
  end if;

  -- assets
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='assets' and policyname='assets_own') then
    create policy "assets_own" on public.assets
      for all using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='assets' and policyname='assets_partner_read') then
    create policy "assets_partner_read" on public.assets
      for select using (
        exists (
          select 1 from public.partnerships p
          where p.active = true
            and ((p.user_id_1 = auth.uid() and p.user_id_2 = user_id)
              or (p.user_id_2 = auth.uid() and p.user_id_1 = user_id))
        )
      );
  end if;

  -- snapshots
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='snapshots' and policyname='snapshots_own') then
    create policy "snapshots_own" on public.snapshots
      for all using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;

  -- partner_invites — 0008 sonrası küme: redeem/claim/target_update YOK
  -- (davet kullanımı `redeem-invite-code` edge function'ında, service-role).
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='partner_invites' and policyname='invites_own_insert') then
    create policy "invites_own_insert" on public.partner_invites
      for insert with check (auth.uid() = from_user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='partner_invites' and policyname='invites_own_select') then
    create policy "invites_own_select" on public.partner_invites
      for select using (auth.uid() = from_user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='partner_invites' and policyname='invites_own_update') then
    create policy "invites_own_update" on public.partner_invites
      for update using (auth.uid() = from_user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='partner_invites' and policyname='invites_target_select') then
    create policy "invites_target_select" on public.partner_invites
      for select using (auth.uid() = to_user_id);
  end if;

  -- user_push_tokens
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='user_push_tokens' and policyname='push_tokens_own_select') then
    create policy "push_tokens_own_select" on public.user_push_tokens
      for select using (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='user_push_tokens' and policyname='push_tokens_own_insert') then
    create policy "push_tokens_own_insert" on public.user_push_tokens
      for insert with check (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='user_push_tokens' and policyname='push_tokens_own_update') then
    create policy "push_tokens_own_update" on public.user_push_tokens
      for update using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='user_push_tokens' and policyname='push_tokens_own_delete') then
    create policy "push_tokens_own_delete" on public.user_push_tokens
      for delete using (auth.uid() = user_id);
  end if;

  -- partnerships — insert politikası YOK (0008 A3: yalnız `accept-invite`
  -- edge function'ı, service-role ile ekler).
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='partnerships' and policyname='partnerships_select') then
    create policy "partnerships_select" on public.partnerships
      for select using (auth.uid() = user_id_1 or auth.uid() = user_id_2);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='partnerships' and policyname='partnerships_update') then
    create policy "partnerships_update" on public.partnerships
      for update using (auth.uid() = user_id_1 or auth.uid() = user_id_2);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='partnerships' and policyname='partnerships_delete') then
    create policy "partnerships_delete" on public.partnerships
      for delete using (auth.uid() = user_id_1 or auth.uid() = user_id_2);
  end if;

  -- disclaimer_acceptances
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='disclaimer_acceptances' and policyname='disclaimer_insert_own') then
    create policy "disclaimer_insert_own" on public.disclaimer_acceptances
      for insert with check (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='disclaimer_acceptances' and policyname='disclaimer_select_own') then
    create policy "disclaimer_select_own" on public.disclaimer_acceptances
      for select using (auth.uid() = user_id);
  end if;

  -- db_logs — 0008 A6 hâli (user_id başkasına yazılamaz).
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='db_logs' and policyname='db_logs_insert') then
    create policy "db_logs_insert" on public.db_logs
      for insert with check (
        auth.uid() is not null
        and (user_id is null or user_id = auth.uid())
      );
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='db_logs' and policyname='db_logs_select_own') then
    create policy "db_logs_select_own" on public.db_logs
      for select using (auth.uid() = user_id);
  end if;
end $$;

-- ── Realtime: davet tablosu yayına ekli olsun (istemci dinliyor) ────────────
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'partner_invites'
     ) then
    execute 'alter publication supabase_realtime add table public.partner_invites';
  end if;
end $$;

-- ── Yeni kullanıcı → profil satırı (0008 C1 hâli: search_path sabit) ────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
