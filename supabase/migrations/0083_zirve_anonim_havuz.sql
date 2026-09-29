-- ============================================================
-- 0083 — Zirvedeki Portföyler: beyana dayanmayan anonim havuz
-- ============================================================
--
-- Kullanıcı kararı (2026-09-29): "zirvedeki portföylere dahiliyet ve
-- izleme herhangi bir beyana dayalı olmamalı; bu anonim bir alan
-- olduğundan rıza metinlerine eklenmeli" ve "yarış ekranı widget'ı ve
-- mekaniği değişmemeli".
--
-- ## Neden AYRI tablolar
-- Yarış (ortak sıralaması + genel yüzdelik) `user_roi_snapshots` /
-- `user_allocation_snapshots` tablolarını ve `leaderboard_eligible_users()`
-- kuralını kullanır. Ortaklar birbirinin satırını RLS ile okur
-- (`fetchPartnerRois`). Zirve için herkesin snapshot'ı O tablolara
-- yazılsaydı yarışa katılmamış bir ortak sıralamada görünmeye başlar,
-- genel yüzdelik havuzu da genişlerdi — yani Yarış mekaniği değişirdi.
-- Zirve kendi tablolarına yazar; Yarış tabloları ve kuralları bu
-- migration'da HİÇ değişmez (tek istisna: temizlik fonksiyonu zirve
-- tablolarını da siler, yarış satırlarının süresi aynı).
--
-- ## Anonimlik
-- - Tablolarda RLS açık, politika YOK; `anon`/`authenticated` tablo
--   yetkisi yok. Yalnızca service role yazar (leaderboard-snapshot cron).
-- - İstemci yalnızca iki RPC görür: `get_top_gainers_allocation`
--   (sıra, getiri, tür payı; kimlik yok) ve `zirve_havuz_boyutu` (sayı).
-- - k-anonimlik: havuz 8'in altındaysa satır dönmez; en fazla 4 satır
--   (0031'deki k_min / n_max aynen).
--
-- ## Uygunluk (0059'dan farkı)
-- Beyan yok: yarışa katılım (`leaderboard_opt_in`) aranmaz.
-- - Hesap ≥ 7 gün (Sybil maliyeti aynen).
-- - Portföyde 5 günden eski en az bir aktif kayıt. Eski "30 günde 5 ayrı
--   gün snapshot" kuralı istemci snapshot'ına dayanıyordu; artık sunucu
--   herkes için ölçtüğünden yeni katılan beş gün beklemesin diye
--   portföyün yaşından okunur.
-- - En az 1 tür. Eski ">= 2 tür" parmak izi filtresi 18 portföyden 9'unu
--   dışarıda bırakıyordu (ölçüldü 2026-09-29, Tokyo: 2 tür + 7 gün = 7
--   kişi, eşik 8). Tek türlü bir portföy ("%100 altın") 8+ kişilik
--   havuzda kimliği ele vermez.
-- ============================================================

-- ── 1) Tablolar ─────────────────────────────────────────────────────────────
create table if not exists public.zirve_roi_snapshots (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  period_days integer not null check (period_days in (7, 30, 180, 365)),
  roi_pct     numeric(10, 4) not null,
  created_at  timestamptz not null default now()
);

create table if not exists public.zirve_allocation_snapshots (
  id             bigint generated always as identity primary key,
  user_id        uuid not null references auth.users(id) on delete cascade,
  allocation_pct jsonb not null,
  type_count     integer not null check (type_count >= 1),
  created_at     timestamptz not null default now()
);

-- RPC'nin tek erişim deseni: "bu dönem, son 24 saat, kullanıcı başına en
-- yeni satır". Kapsayan indeks tabloya dönmeden okur.
create index if not exists zirve_roi_snapshots_donem_zaman
  on public.zirve_roi_snapshots (period_days, created_at desc)
  include (user_id, roi_pct);
create index if not exists zirve_allocation_snapshots_zaman
  on public.zirve_allocation_snapshots (created_at desc)
  include (user_id, type_count);
-- Hesap silme cascade'i ve kullanıcı başına temizlik için.
create index if not exists zirve_roi_snapshots_kullanici
  on public.zirve_roi_snapshots (user_id);
create index if not exists zirve_allocation_snapshots_kullanici
  on public.zirve_allocation_snapshots (user_id);

alter table public.zirve_roi_snapshots        enable row level security;
alter table public.zirve_allocation_snapshots enable row level security;
-- Politika bilerek YOK. GRANT ile RLS ayrı şeyler: ikisi de kapalı.
revoke all on table public.zirve_roi_snapshots        from public, anon, authenticated;
revoke all on table public.zirve_allocation_snapshots from public, anon, authenticated;

-- ── 2) Uygunluk ─────────────────────────────────────────────────────────────
create or replace function public.zirve_havuzu_uygun()
returns table (user_id uuid)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select u.id
    from auth.users u
   where u.created_at <= now() - interval '7 days'
     and u.deleted_at is null
     and exists (
       select 1
         from public.assets a
        where a.user_id = u.id
          and a.deleted_at is null
          and a.added_date <= now() - interval '5 days'
     );
$$;
revoke all on function public.zirve_havuzu_uygun() from public, anon, authenticated;

-- Havuzun kendisi: uygun + son 24 saatte hem getiri hem dağılım satırı
-- olanlar, kullanıcı başına en yeni değer. İç fonksiyon — istemciye kapalı;
-- iki RPC aynı tanımı paylaşsın diye tek yerde.
create or replace function public.zirve_havuz(p_period_days integer)
returns table (user_id uuid, roi_pct numeric, allocation_pct jsonb, type_count integer)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with uygun as (
    select e.user_id from public.zirve_havuzu_uygun() e
  ),
  son_roi as (
    select distinct on (s.user_id) s.user_id, s.roi_pct
      from public.zirve_roi_snapshots s
     where s.period_days = p_period_days
       and s.created_at >= now() - interval '24 hours'
       and s.user_id in (select uygun.user_id from uygun)
     order by s.user_id, s.created_at desc
  ),
  son_dagilim as (
    select distinct on (a.user_id) a.user_id, a.allocation_pct, a.type_count
      from public.zirve_allocation_snapshots a
     where a.created_at >= now() - interval '24 hours'
       and a.type_count >= 1
       and a.user_id in (select uygun.user_id from uygun)
     order by a.user_id, a.created_at desc
  )
  select r.user_id, r.roi_pct, d.allocation_pct, d.type_count
    from son_roi r
    join son_dagilim d on d.user_id = r.user_id;
$$;
revoke all on function public.zirve_havuz(integer) from public, anon, authenticated;

-- ── 3) İstemci RPC'leri ────────────────────────────────────────────────────
-- Aynı imza ve dönüş tipi (create or replace yeterli, GRANT'lar korunur).
-- Yarış ekranı 2026-09-29'dan beri bu RPC'yi çağırmıyor; eski sürümler
-- çağırırsa zirve havuzunu görür — anonim ve eşikli, sorun değil.
create or replace function public.get_top_gainers_allocation(
  p_period_days integer,
  p_top_n integer default 3
)
returns table (
  rank integer,
  roi_pct numeric,
  allocation_pct jsonb,
  type_count integer
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  k_min integer := 8;  -- k-anonimlik alt sınırı (0031)
  n_min integer := 3;  -- tekil ifşa koruması: asla 3'ten az satır
  n_max integer := 4;  -- havuzun yarısından fazlası dökülmesin (k_min/2)
  v_total integer;
  v_top_n integer;
begin
  if p_period_days not in (7, 30, 180, 365) then
    return;
  end if;
  v_top_n := least(greatest(coalesce(p_top_n, 3), n_min), n_max);

  select count(*) into v_total from public.zirve_havuz(p_period_days);
  if v_total < k_min then
    return;
  end if;

  return query
    select (row_number() over (order by h.roi_pct desc))::integer,
           h.roi_pct,
           h.allocation_pct,
           h.type_count
      from public.zirve_havuz(p_period_days) h
     order by h.roi_pct desc
     limit v_top_n;
end;
$$;
revoke all on function public.get_top_gainers_allocation(integer, integer) from public, anon;
grant execute on function public.get_top_gainers_allocation(integer, integer) to authenticated;

-- Boş durum "Havuz oluşuyor: N portföy var, 8 olunca…" diyebilsin diye.
-- Yarış'ın `leaderboard_pool_size`'ı DEĞİŞMEDİ (Yarış mekaniği).
create or replace function public.zirve_havuz_boyutu(p_period_days integer default 30)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
           when p_period_days in (7, 30, 180, 365)
           then (select count(*)::integer from public.zirve_havuz(p_period_days))
           else 0
         end;
$$;
revoke all on function public.zirve_havuz_boyutu(integer) from public, anon;
grant execute on function public.zirve_havuz_boyutu(integer) to authenticated;

-- ── 4) Temizlik ─────────────────────────────────────────────────────────────
-- Mevcut haftalık cron (0081, 'leaderboard-snapshot-retention') aynı
-- fonksiyonu çağırır; yeni cron yok (Frankfurt'ta cron'lar bilinçli kapalı,
-- yeni bir iş orada açık doğardı). Yarış satırlarının süresi AYNI (400
-- gün); zirve satırları gizlilik politikasındaki "son 365 gün" ile uyumlu.
create or replace function public.cleanup_leaderboard_snapshots()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.user_roi_snapshots         where created_at < now() - interval '400 days';
  delete from public.user_allocation_snapshots  where created_at < now() - interval '400 days';
  delete from public.zirve_roi_snapshots        where created_at < now() - interval '365 days';
  delete from public.zirve_allocation_snapshots where created_at < now() - interval '365 days';
end;
$$;
revoke all on function public.cleanup_leaderboard_snapshots() from public, anon, authenticated;

-- ── 5) Doğrulama ────────────────────────────────────────────────────────────
do $$
declare
  t text;
begin
  foreach t in array array['zirve_roi_snapshots', 'zirve_allocation_snapshots'] loop
    if not (select c.relrowsecurity from pg_class c
             where c.oid = format('public.%I', t)::regclass) then
      raise exception '%: RLS kapalı', t;
    end if;
    if exists (select 1 from pg_policies p
                where p.schemaname = 'public' and p.tablename = t) then
      raise exception '%: politika olmamalı (yalnız service role yazar)', t;
    end if;
    if has_table_privilege('authenticated', format('public.%I', t), 'select')
       or has_table_privilege('anon', format('public.%I', t), 'select') then
      raise exception '%: istemci tabloyu okuyabiliyor', t;
    end if;
    if not has_table_privilege('service_role', format('public.%I', t), 'insert') then
      raise exception '%: service_role yazamıyor', t;
    end if;
  end loop;

  if has_function_privilege('authenticated', 'public.zirve_havuzu_uygun()', 'execute')
     or has_function_privilege('authenticated', 'public.zirve_havuz(integer)', 'execute') then
    raise exception 'iç zirve fonksiyonları istemciye açık olmamalı';
  end if;
  if not has_function_privilege('authenticated', 'public.get_top_gainers_allocation(integer, integer)', 'execute')
     or not has_function_privilege('authenticated', 'public.zirve_havuz_boyutu(integer)', 'execute') then
    raise exception 'zirve RPC GRANT eksik';
  end if;
  if has_function_privilege('anon', 'public.get_top_gainers_allocation(integer, integer)', 'execute')
     or has_function_privilege('anon', 'public.zirve_havuz_boyutu(integer)', 'execute') then
    raise exception 'zirve RPC anon''a açık olmamalı';
  end if;
  -- Yarış kuralı değişmedi: uygunluk fonksiyonu hâlâ istemciye kapalı ve yerinde.
  if has_function_privilege('authenticated', 'public.leaderboard_eligible_users()', 'execute') then
    raise exception 'leaderboard_eligible_users istemciye açılmış';
  end if;
end $$;
