-- ============================================================
-- 0084 — Zirvedeki Portföyler: fon kırılımı
-- ============================================================
--
-- Kullanıcı kararı (2026-09-29): "sadece kategori yerine fonda hangi fonlar
-- olduğu ve oranları da yazmalı".
--
-- - `zirve_allocation_snapshots.fon_detay`: {TEFAS kodu: toplam portföyün
--   yüzdesi}, Σ ≈ allocation_pct.fon. Yalnız TEFAS biçimindeki kamuya açık
--   kodlar (^[A-Z0-9]{3}$); serbest metin ve %1 altı kalemler "DIGER"de
--   toplanır (hesap `leaderboard-snapshot` › `fonDetayi`). Kullanıcının
--   yazdığı ad/not taşınmaz; istemci fon adını resmi TEFAS kataloğundan okur.
-- - Yeni RPC `zirve_portfoyleri`: `get_top_gainers_allocation` ile aynı
--   havuz ve k-anonimlik (k_min 8, n 3–4) + `fon_detay`. Eski RPC'nin dönüş
--   tipine sütun eklemek DROP ister (0059 dersi: GRANT'lar gider, yayındaki
--   eski sürümler kırılır) — o yüzden yeni ad, eski RPC aynen kalır.
-- - Yarış tabloları ve RPC'leri değişmez.
-- ============================================================

alter table public.zirve_allocation_snapshots
  add column if not exists fon_detay jsonb;

create or replace function public.zirve_portfoyleri(
  p_period_days integer,
  p_top_n integer default 3
)
returns table (
  rank integer,
  roi_pct numeric,
  allocation_pct jsonb,
  type_count integer,
  fon_detay jsonb
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
  v_top_n := least(greatest(coalesce(p_top_n, 3), n_min), n_max);

  select count(*) into v_total from public.zirve_havuz(p_period_days);
  if v_total < k_min then
    return;
  end if;

  -- `zirve_havuz` kullanıcı başına EN YENİ dağılım satırını seçer; fon
  -- kırılımı aynı satırdan (aynı sıralama, aynı pencere) okunur.
  return query
    select (row_number() over (order by h.roi_pct desc))::integer,
           h.roi_pct,
           h.allocation_pct,
           h.type_count,
           f.fon_detay
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
revoke all on function public.zirve_portfoyleri(integer, integer) from public, anon;
grant execute on function public.zirve_portfoyleri(integer, integer) to authenticated;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name = 'zirve_allocation_snapshots'
       and column_name = 'fon_detay'
  ) then
    raise exception 'zirve_allocation_snapshots.fon_detay yok';
  end if;
  if not has_function_privilege('authenticated', 'public.zirve_portfoyleri(integer, integer)', 'execute') then
    raise exception 'zirve_portfoyleri GRANT eksik';
  end if;
  if has_function_privilege('anon', 'public.zirve_portfoyleri(integer, integer)', 'execute') then
    raise exception 'zirve_portfoyleri anon''a açık olmamalı';
  end if;
  -- Tablo hâlâ istemciye kapalı (0083 sözleşmesi).
  if has_table_privilege('authenticated', 'public.zirve_allocation_snapshots', 'select') then
    raise exception 'zirve_allocation_snapshots istemciye açılmış';
  end if;
  -- Yarış tablosuna fon kırılımı sızmadı.
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name = 'user_allocation_snapshots'
       and column_name = 'fon_detay'
  ) then
    raise exception 'Yarış dağılım tablosunda fon_detay olmamalı';
  end if;
end $$;
