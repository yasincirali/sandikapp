-- ============================================================
-- 0085 — Zirve: en az 2 farklı varlık + "sen" işareti
-- ============================================================
--
-- 1) Kullanıcı kararı (2026-09-29): "portföyde minimum 2 farklı varlık
--    varsa eklenmeli". `zirve_allocation_snapshots.varlik_sayisi` =
--    bugünkü portföydeki farklı açık pozisyon sayısı (snapshot fonksiyonu
--    `varlikSayisi`, satılmış pozisyon sayılmaz). Havuz, kullanıcının EN
--    YENİ dağılım satırında bu sayı ≥ 2 olanlardan oluşur. Eski satırlarda
--    sütun boş → havuza girmez; bir sonraki cron koşusu doldurur.
--    Ölçüldü (Tokyo, 2026-09-29): 11 kişilik havuzun ~6'sı bu şartı
--    sağlıyor — havuz k_min 8'in altına iner, zirve dolana kadar kapanır.
--    Bilinçli: kural kullanıcının.
--
-- 2) Açık bulgu kapatıldı: kullanıcı kendini hem "Sen" (istemci getirisi)
--    hem "2." (sunucu getirisi) olarak, iki farklı sayıyla görüyordu.
--    - `zirve_portfoyleri` artık `ben` döner: satır çağıranın kendisine mi
--      ait (auth.uid()). Başkasına bir şey sızdırmaz; yalnız çağırana kendi
--      satırını söyler. Dönüş tipi değiştiği için DROP + CREATE (0084'te
--      eklendi, yayında sürüm yok; GRANT aşağıda yeniden).
--    - `zirve_benim`: çağıranın havuzdaki kendi değeri (getiri, dağılım,
--      fon kırılımı). Havuzdaysa ekran "Sen"i BUNUNLA çizer; zirveyle aynı
--      kaynak, aynı saat. Havuzda değilse satır dönmez, ekran istemci
--      hesabına düşer.
-- ============================================================

alter table public.zirve_allocation_snapshots
  add column if not exists varlik_sayisi integer;

-- Dönüş tipi aynı → create or replace yeterli.
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
    -- Önce EN YENİ satır seçilir, şart sonra uygulanır: dün 2 varlığı olup
    -- bugün teke inen portföy eski satırıyla havuzda kalmasın.
    select distinct on (a.user_id)
           a.user_id, a.allocation_pct, a.type_count, a.varlik_sayisi
      from public.zirve_allocation_snapshots a
     where a.created_at >= now() - interval '24 hours'
       and a.type_count >= 1
       and a.user_id in (select uygun.user_id from uygun)
     order by a.user_id, a.created_at desc
  )
  select r.user_id, r.roi_pct, d.allocation_pct, d.type_count
    from son_roi r
    join son_dagilim d on d.user_id = r.user_id
   where coalesce(d.varlik_sayisi, 0) >= 2;
$$;
revoke all on function public.zirve_havuz(integer) from public, anon, authenticated;

drop function if exists public.zirve_portfoyleri(integer, integer);
create function public.zirve_portfoyleri(
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
revoke all on function public.zirve_portfoyleri(integer, integer) from public, anon;
grant execute on function public.zirve_portfoyleri(integer, integer) to authenticated;

-- Çağıranın kendi havuz değeri; yalnız kendi satırı (auth.uid()).
create or replace function public.zirve_benim(p_period_days integer)
returns table (roi_pct numeric, allocation_pct jsonb, fon_detay jsonb)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select h.roi_pct, h.allocation_pct, f.fon_detay
    from public.zirve_havuz(p_period_days) h
    left join lateral (
      select a.fon_detay
        from public.zirve_allocation_snapshots a
       where a.user_id = h.user_id
         and a.created_at >= now() - interval '24 hours'
       order by a.created_at desc
       limit 1
    ) f on true
   where h.user_id = auth.uid();
$$;
revoke all on function public.zirve_benim(integer) from public, anon;
grant execute on function public.zirve_benim(integer) to authenticated;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name = 'zirve_allocation_snapshots'
       and column_name = 'varlik_sayisi'
  ) then
    raise exception 'zirve_allocation_snapshots.varlik_sayisi yok';
  end if;
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'zirve_portfoyleri'
       and 'ben' = any (p.proargnames)
  ) then
    raise exception 'zirve_portfoyleri ben sütununu döndürmüyor';
  end if;
  if not has_function_privilege('authenticated', 'public.zirve_portfoyleri(integer, integer)', 'execute')
     or not has_function_privilege('authenticated', 'public.zirve_benim(integer)', 'execute') then
    raise exception 'zirve RPC GRANT eksik';
  end if;
  if has_function_privilege('anon', 'public.zirve_portfoyleri(integer, integer)', 'execute')
     or has_function_privilege('anon', 'public.zirve_benim(integer)', 'execute') then
    raise exception 'zirve RPC anon''a açık olmamalı';
  end if;
  if has_function_privilege('authenticated', 'public.zirve_havuz(integer)', 'execute') then
    raise exception 'zirve_havuz istemciye açık olmamalı';
  end if;
end $$;
