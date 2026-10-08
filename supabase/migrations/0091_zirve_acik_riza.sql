-- 0091 — Zirvedeki Portföyler: açık rızaya dayalı havuz (2026-10-01)
--
-- ## Karar değişikliği
-- 0083 (2026-09-29) havuzu beyana DAYANDIRMAMIŞTI: portföyü olan herkes
-- anonim olarak ölçülüyordu; hukuki dayanak KVKK 5(2)(c)+(f) yazılmıştı.
-- 2026-09-30 emülatör raporu bunu hukuki soru olarak açtı; kullanıcı kararı
-- (2026-10-01): "Zirvedeki portföyler için açık rıza ve in-app açıklama
-- yazalım; her türlü anonim olduğunu ve diğer kullanıcıların hangi oranlarda
-- hangi varlıkları tuttuğu bilgilerinin kendilerine hizmet olarak sunulacağı
-- bilgisi verilebilir."
--
-- Yeni kural:
--   * Havuza YALNIZCA açık rıza veren girer (`zirve_havuzu_uygun`).
--   * Ölçüm de yalnız rıza verenler için yapılır (`leaderboard-snapshot`,
--     veri minimizasyonu — rızası olmayanın getirisi hiç hesaplanıp
--     saklanmaz).
--   * Karşılıklılık: listeyi yalnız havuza katılan görür
--     (`zirve_portfoyleri` rızasız çağırana boş döner). Hizmetin kendisi
--     "katılanların anonim dağılımını görmek"tir; katılmayan veri vermez,
--     veri de görmez. ⚠️ Hukukçuya gösterilecek: açık rıza bir hizmetin
--     ŞARTI yapılamaz ilkesiyle ilişkisi — burada rıza, hizmetin konusu
--     olan veri paylaşımının kendisidir (YAPMAN_GEREKENLER).
--   * Geri çekme her an: satır `geri_cekildi_at` alır ve kullanıcının
--     zirve ölçümleri ANINDA silinir.
--
-- ## Neden `profiles` değil ayrı tablo
-- `profiles` ortaklara açık (`profiles_select_partner`, 0078): rıza durumu
-- orada dursaydı ortak "zirveye katılmış mı" görebilirdi. Ayrıca açık rızanın
-- İSPATI veri sorumlusundadır — ne zaman, hangi metin sürümüyle verildiği
-- saklanır; geri çekilince satır silinmez, damgalanır.

-- ── 1) Tablo ────────────────────────────────────────────────────────────────
create table if not exists public.zirve_rizalari (
  user_id         uuid primary key references auth.users(id) on delete cascade,
  verildi_at      timestamptz not null default now(),
  -- İstemcinin gösterdiği açıklama metninin sürümü (ör. '2026-10-01').
  metin_surumu    text not null check (length(metin_surumu) between 1 and 32),
  geri_cekildi_at timestamptz
);

comment on table public.zirve_rizalari is
  'Zirvedeki Portfoyler acik riza kaydi (0091). Yalniz zirve_rizasi_ayarla '
  'RPC yazar; kullanici yalniz kendi satirini okur.';

alter table public.zirve_rizalari enable row level security;
alter table public.zirve_rizalari force row level security;

drop policy if exists zirve_rizalari_own_select on public.zirve_rizalari;
create policy zirve_rizalari_own_select
  on public.zirve_rizalari
  for select to authenticated
  using ((select auth.uid()) = user_id);

-- Yazma yalnız RPC üzerinden (security definer): geri çekmede ölçümlerin
-- silinmesi aynı işlemde olmalı; doğrudan UPDATE bunu atlatırdı.
revoke all on table public.zirve_rizalari from public, anon, authenticated;
grant select on table public.zirve_rizalari to authenticated;
grant select, insert, update, delete on table public.zirve_rizalari to service_role;

-- ── 2) RPC: rıza ver / geri çek ─────────────────────────────────────────────
create or replace function public.zirve_rizasi_ayarla(p_ver boolean, p_metin_surumu text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'oturum yok' using errcode = '42501';
  end if;
  if p_ver then
    if p_metin_surumu is null or length(p_metin_surumu) not between 1 and 32 then
      raise exception 'gecersiz metin surumu' using errcode = '22023';
    end if;
    insert into public.zirve_rizalari (user_id, verildi_at, metin_surumu, geri_cekildi_at)
    values (v_uid, now(), p_metin_surumu, null)
    on conflict (user_id) do update
      set verildi_at = now(),
          metin_surumu = excluded.metin_surumu,
          geri_cekildi_at = null;
  else
    update public.zirve_rizalari
       set geri_cekildi_at = now()
     where user_id = v_uid and geri_cekildi_at is null;
    -- Geri çekme = havuzdan çıkış + ölçümlerin silinmesi, aynı işlemde.
    delete from public.zirve_roi_snapshots        where user_id = v_uid;
    delete from public.zirve_allocation_snapshots where user_id = v_uid;
  end if;
end;
$$;
revoke all on function public.zirve_rizasi_ayarla(boolean, text) from public, anon;
grant execute on function public.zirve_rizasi_ayarla(boolean, text) to authenticated;

-- ── 3) Uygunluk: rıza şartı ─────────────────────────────────────────────────
-- 0083'teki koşullar aynen; tek ek `zirve_rizalari`.
create or replace function public.zirve_havuzu_uygun()
returns table (user_id uuid)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select u.id
    from auth.users u
    join public.zirve_rizalari r
      on r.user_id = u.id and r.geri_cekildi_at is null
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

-- ── 4) Karşılıklılık: liste yalnız katılana ─────────────────────────────────
-- Gövde 0085 ile aynı; başa rıza kapısı eklendi. Dönüş tipi aynı →
-- create or replace yeterli (GRANT'lar korunur).
create or replace function public.zirve_portfoyleri(
  p_period_days integer,
  p_top_n integer default 3
)
returns table (
  rank integer,
  roi_pct numeric,
  allocation_pct jsonb,
  type_count integer,
  fon_detay jsonb,
  ben boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  k_min integer := 8;  -- k-anonimlik alt sınırı (0031)
  n_min integer := 3;
  n_max integer := 4;
  v_total integer;
  v_top_n integer;
begin
  if p_period_days not in (7, 30, 180, 365) then
    return;
  end if;
  -- Rıza vermeyen başkalarının dağılımını görmez (karşılıklılık, 0091).
  if not exists (select 1 from public.zirve_rizalari r
                  where r.user_id = auth.uid() and r.geri_cekildi_at is null) then
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
           h.type_count,
           f.fon_detay,
           coalesce(h.user_id = auth.uid(), false)
      from public.zirve_havuz(p_period_days) h
      left join lateral (
        select a.fon_detay
          from public.zirve_allocation_snapshots a
         where a.user_id = h.user_id
           and a.created_at >= now() - interval '24 hours'
         order by a.created_at desc
         limit 1
      ) f on true
     order by h.roi_pct desc
     limit v_top_n;
end;
$$;

-- ── 5) Rızası olmayanın mevcut ölçümleri ────────────────────────────────────
-- 0083'ten bu yana herkes ölçüldü. Yeni dayanak açık rıza olduğundan, rıza
-- vermemiş (henüz kimse vermedi) kullanıcıların zirve satırları silinir.
delete from public.zirve_roi_snapshots s
 where not exists (select 1 from public.zirve_rizalari r
                    where r.user_id = s.user_id and r.geri_cekildi_at is null);
delete from public.zirve_allocation_snapshots s
 where not exists (select 1 from public.zirve_rizalari r
                    where r.user_id = s.user_id and r.geri_cekildi_at is null);

-- ── 6) Doğrulama ────────────────────────────────────────────────────────────
do $$
begin
  if not has_table_privilege('authenticated', 'public.zirve_rizalari', 'SELECT') then
    raise exception '0091: authenticated icin zirve_rizalari SELECT GRANT eksik';
  end if;
  if has_table_privilege('authenticated', 'public.zirve_rizalari', 'INSERT')
     or has_table_privilege('authenticated', 'public.zirve_rizalari', 'UPDATE')
     or has_table_privilege('authenticated', 'public.zirve_rizalari', 'DELETE') then
    raise exception '0091: authenticated zirve_rizalari tablosuna dogrudan YAZAMAMALI';
  end if;
  if has_table_privilege('anon', 'public.zirve_rizalari', 'SELECT') then
    raise exception '0091: anon zirve_rizalari tablosunu okuyamamali';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.zirve_rizalari'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0091: zirve_rizalari RLS (enable + force) kapali';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'zirve_rizalari') <> 1 then
    raise exception '0091: zirve_rizalari yalniz own_select politikasini tasimali';
  end if;
  if not has_function_privilege('authenticated', 'public.zirve_rizasi_ayarla(boolean, text)', 'EXECUTE') then
    raise exception '0091: zirve_rizasi_ayarla authenticated icin EXECUTE eksik';
  end if;
  if has_function_privilege('anon', 'public.zirve_rizasi_ayarla(boolean, text)', 'EXECUTE') then
    raise exception '0091: anon zirve_rizasi_ayarla cagiramamali';
  end if;
  if position('zirve_rizalari' in pg_get_functiondef('public.zirve_havuzu_uygun()'::regprocedure)) = 0 then
    raise exception '0091: zirve_havuzu_uygun riza sartini tasimiyor';
  end if;
  if position('zirve_rizalari' in pg_get_functiondef('public.zirve_portfoyleri(integer, integer)'::regprocedure)) = 0 then
    raise exception '0091: zirve_portfoyleri karsiliklilik kapisini tasimiyor';
  end if;
  if not has_function_privilege('authenticated', 'public.zirve_portfoyleri(integer, integer)', 'EXECUTE') then
    raise exception '0091: zirve_portfoyleri authenticated icin EXECUTE kayboldu';
  end if;
  raise notice '0091 tamam: zirve acik riza tablosu + RPC + uygunluk + karsiliklilik.';
end $$;
