-- 0105 — Kripto alıcı baskısı ve hacim (Balina B3, 2026-10-05)
--
-- ## Neden
-- Hisse hacim radarının (0104) kripto karşılığı. Binance günlük mumları iki
-- şey veriyor: işlem hacmi (USDT) ve piyasa emriyle ALAN tarafın o hacimdeki
-- payı. `kripto-hacim-gozlem` edge function'ı portföylerde tutulan coinler
-- için bunları `kripto_hacim_gunluk`'a yazar; olağandışı hacim günlerini
-- `balina_olay`'a `kripto_hacim_*` türüyle işler.
--
-- Tutarlar USDT'dir (en derin tahta USDT paritesi); TL'ye çevrilmez. Kimin
-- alıp sattığı bu veride yok; zincir üstü veri kapsam dışı (kullanıcı kararı
-- 2026-09-25: kripto yalnız Binance).
--
-- ## Eski sürümler
-- Yalnızca EKLER / gevşetir: yeni tablo, `balina_olay.tur` listesine iki
-- değer, bir boş bırakılabilir sütun. 0103/0104 istemcisi kripto satırlarını
-- `tur` süzgeciyle hiç okumaz.
--
-- ## Yetki: 0103/0104 ile aynı — oturum okur, yalnız service_role yazar.

create table if not exists public.kripto_hacim_gunluk (
  -- Uygulamadaki ticker ile birebir: 'KRIPTO:BTC'.
  ticker      text not null check (ticker ~ '^KRIPTO:[A-Z0-9]{2,15}$'),
  -- Gün, İstanbul takvimi (mum 00:00 TR'de açılır).
  tarih       date not null,
  -- USDT kapanış.
  kapanis     numeric not null check (kapanis > 0),
  -- Günlük işlem hacmi, USDT.
  para_hacmi  numeric not null check (para_hacmi > 0),
  -- Taker alış hacmi / toplam hacim (0–1).
  alici_payi  numeric not null check (alici_payi >= 0 and alici_payi <= 1),
  primary key (ticker, tarih)
);

create index if not exists kripto_hacim_gunluk_tarih_idx
  on public.kripto_hacim_gunluk (tarih);

comment on table public.kripto_hacim_gunluk is
  'Portfoylerde tutulan coinlerin gunluk Binance USDT hacmi ve alici payi (0105). '
  'Yalniz kripto-hacim-gozlem (service_role) yazar, authenticated yalniz okur. 400 gun saklanir.';

alter table public.kripto_hacim_gunluk enable row level security;
alter table public.kripto_hacim_gunluk force row level security;

drop policy if exists kripto_hacim_gunluk_select on public.kripto_hacim_gunluk;
create policy kripto_hacim_gunluk_select
  on public.kripto_hacim_gunluk
  for select to authenticated
  using (true);

revoke all on table public.kripto_hacim_gunluk from public, anon, authenticated;
grant select on table public.kripto_hacim_gunluk to authenticated;
grant select, insert, update, delete on table public.kripto_hacim_gunluk to service_role;

-- ── Olay tablosu kripto türlerini alır ──────────────────────────────────────
alter table public.balina_olay drop constraint if exists balina_olay_tur_check;
alter table public.balina_olay add constraint balina_olay_tur_check
  check (tur in ('fon_giris', 'fon_cikis',
                 'hisse_hacim_yukselis', 'hisse_hacim_dusus',
                 'kripto_hacim_yukselis', 'kripto_hacim_dusus'));

alter table public.balina_olay
  -- Kripto: olay günündeki alıcı payı (0–1). Diğer türlerde NULL.
  add column if not exists alici_payi numeric
    check (alici_payi is null or (alici_payi >= 0 and alici_payi <= 1));

alter table public.balina_olay drop constraint if exists balina_olay_alan_tutarliligi;
alter table public.balina_olay add constraint balina_olay_alan_tutarliligi check (
  (tur like 'fon\_%' and buyukluk_orani is not null)
  or (tur like 'hisse\_hacim\_%' and ortalama_kati is not null
      and fiyat_degisim is not null and tutar > 0)
  or (tur like 'kripto\_hacim\_%' and ortalama_kati is not null
      and fiyat_degisim is not null and alici_payi is not null and tutar > 0)
);

-- ── Tetikleyici ─────────────────────────────────────────────────────────────
-- Secret fiyat alarmıyla PAYLAŞILIR (`price_alerts_cron_secret`): ikisi de
-- Binance'ten salt-okur piyasa verisi çeken işler (emsal 0101, 0104).
create or replace function public.trigger_kripto_hacim_gozlem()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('kripto-hacim-gozlem'),
    headers := public.cron_headers('price_alerts_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    timeout_milliseconds := 140000
  );
end;
$$;

revoke all on function public.trigger_kripto_hacim_gozlem() from public, anon, authenticated;

-- ── Zamanlama (pg_cron UTC) ─────────────────────────────────────────────────
-- TR 00:20 ve 06:20, her gün (kripto hafta sonu da işlem görür). Günlük mum
-- 00:00 TR'de kapanır; ilk tur günü yazar, ikincisi kaçan turu telafi eder.
select cron.unschedule(jobid) from cron.job where jobname = 'kripto-hacim-gozlem';
select cron.schedule('kripto-hacim-gozlem', '20 21,3 * * *',
  $$select public.trigger_kripto_hacim_gozlem()$$);

do $$
begin
  if exists (select 1 from cron.job where jobname <> 'kripto-hacim-gozlem')
     and not exists (select 1 from cron.job
                      where jobname <> 'kripto-hacim-gozlem' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname = 'kripto-hacim-gozlem';
    raise notice '0105: projede tum cron isleri kapali — kripto-hacim-gozlem de kapali kuruldu.';
  end if;
end $$;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if not has_table_privilege('authenticated', 'public.kripto_hacim_gunluk', 'SELECT') then
    raise exception '0105: authenticated icin kripto_hacim_gunluk SELECT GRANT eksik';
  end if;
  if has_table_privilege('authenticated', 'public.kripto_hacim_gunluk', 'INSERT')
     or has_table_privilege('authenticated', 'public.kripto_hacim_gunluk', 'UPDATE')
     or has_table_privilege('authenticated', 'public.kripto_hacim_gunluk', 'DELETE') then
    raise exception '0105: authenticated kripto_hacim_gunluk tablosuna YAZAMAMALI';
  end if;
  if has_table_privilege('anon', 'public.kripto_hacim_gunluk', 'SELECT') then
    raise exception '0105: anon kripto_hacim_gunluk tablosunu okuyamamali';
  end if;
  if not has_table_privilege('service_role', 'public.kripto_hacim_gunluk', 'INSERT')
     or not has_table_privilege('service_role', 'public.kripto_hacim_gunluk', 'DELETE') then
    raise exception '0105: service_role icin kripto_hacim_gunluk INSERT/DELETE GRANT eksik';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.kripto_hacim_gunluk'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0105: kripto_hacim_gunluk RLS (enable + force) kapali';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'kripto_hacim_gunluk') <> 1 then
    raise exception '0105: kripto_hacim_gunluk yalniz select politikasini tasimali';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_kripto_hacim_gozlem()', 'EXECUTE') then
    raise exception '0105: trigger_kripto_hacim_gozlem authenticated tarafindan cagrilabilir olmamali';
  end if;
  if not exists (select 1 from cron.job
                  where jobname = 'kripto-hacim-gozlem' and schedule = '20 21,3 * * *') then
    raise exception '0105: kripto-hacim-gozlem cron isi kurulmadi';
  end if;

  raise notice '0105 tamam: kripto_hacim_gunluk + balina_olay kripto turleri + cron yerinde.';
end $$;
