-- 0144 — Zirve: "neden henüz havuzda değilim?" (kullanıcı bulgusu 2026-10-12)
--
-- yasin eski tarihli varlıklarla üç hesap açtı, rıza verdirdi; "Havuz N/8"
-- artmadı. Neden: `zirve_havuzu_uygun` (0091) hesabın 7 günlük olmasını
-- ister ve bu şart varlık tarihine değil hesabın açılışına bakar (sahte
-- hesapla havuz doldurmayı engeller). Getirileri zaten ölçülüyordu; ekran
-- ise 7 gün şartını hiç söylemiyordu, kullanıcı neyi beklediğini bilemedi.
--
-- Bu RPC çağırana YALNIZ KENDİ şartlarının ne zaman dolacağını döner;
-- ekran (`ZirveGovdesi`) havuzda değilsen eksik şartı ve tarihini yazar.
-- Kural DEĞİŞMEZ: tarihler `zirve_havuzu_uygun` (0091), leaderboard-snapshot
-- `ilkEdinmeAni` + `siralama_asgari_olcum_gun` (0128) ve `zirve_havuz`
-- (0085, 2 varlık + son 24 saatte ölçüm) ile aynı kaynaktan hesaplanır.
--
-- Yalnız ekleme: eski istemci bu fonksiyonu çağırmaz; yeni istemci eski
-- sunucuda hata alır ve kartı göstermez (canlı kullanıcı kuralı).

create or replace function public.zirve_katilim_durumum(p_period_days integer)
returns table (
  hesap_hazir_at  timestamptz,  -- hesap 7 günlük olunca (0091)
  varlik_hazir_at timestamptz,  -- en eski varlık 5 günlük olunca (0091)
  olcum_hazir_at  timestamptz,  -- ilk alımın edinmesinden asgari gün sonra (0128)
  varlik_sayisi   integer,      -- son 24 saatteki ölçümdeki açık varlık sayısı
  olculdu         boolean,      -- bu dönem için son 24 saatte getiri yazıldı mı
  havuzda         boolean       -- bu dönemin havuzunda mı (`zirve_havuz`)
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    u.created_at + interval '7 days',
    (select min(a.added_date) + interval '5 days'
       from public.assets a
      where a.user_id = u.id and a.deleted_at is null),
    -- `ilkEdinmeAni`: silinmemiş, miktarı olan alımların en eskisi.
    (select min(coalesce(a.added_date, a.created_at))
            + make_interval(days => public.siralama_asgari_olcum_gun())
       from public.assets a
      where a.user_id = u.id and a.deleted_at is null
        and coalesce(a.kind, 'buy') = 'buy' and a.quantity > 0),
    (select s.varlik_sayisi
       from public.zirve_allocation_snapshots s
      where s.user_id = u.id and s.created_at >= now() - interval '24 hours'
      order by s.created_at desc
      limit 1),
    exists (select 1
              from public.zirve_roi_snapshots r
             where r.user_id = u.id and r.period_days = p_period_days
               and r.created_at >= now() - interval '24 hours'),
    exists (select 1 from public.zirve_havuz(p_period_days) h where h.user_id = u.id)
  from auth.users u
  where u.id = auth.uid();
$$;
revoke all on function public.zirve_katilim_durumum(integer) from public, anon;
grant execute on function public.zirve_katilim_durumum(integer) to authenticated;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if not has_function_privilege('authenticated', 'public.zirve_katilim_durumum(integer)', 'execute') then
    raise exception '0144: zirve_katilim_durumum authenticated EXECUTE eksik';
  end if;
  if has_function_privilege('anon', 'public.zirve_katilim_durumum(integer)', 'execute') then
    raise exception '0144: zirve_katilim_durumum anon tarafindan cagrilabilir olmamali';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'zirve_katilim_durumum'
                    and p.prosecdef
                    and array_to_string(p.proconfig, ',') like '%search_path%') then
    raise exception '0144: zirve_katilim_durumum security definer + search_path olmali';
  end if;
end $$;
