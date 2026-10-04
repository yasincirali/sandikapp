-- 0106 — Hisse hacim radarı (Balina B2, 2026-10-04)
--
-- ## Neden
-- Fon tarafında para akışı ölçülebiliyor (0105). Hissede lisanssız veriyle
-- ölçülebilen tek şey HACİM: bir günün para hacmi (işlem adedi × kapanış)
-- kendi son 20 gününe göre olağandışı büyük mü. `hacim-gozlem` edge
-- function'ı portföylerde tutulan BIST hisselerinin günlük kapanış ve
-- hacmini okur, `hisse_hacim_gunluk`'a yazar; kurala uyan günleri
-- `balina_olay`'a `hisse_hacim_*` türüyle işler. Kimin alıp sattığı bu veride
-- YOK (aracı kurum dağılımı lisans ister); istemci kartı bunu açıkça yazar.
--
-- ## Eski sürümler
-- Yalnızca EKLER / gevşetir: yeni tablo, `balina_olay`'a iki boş bırakılabilir
-- sütun, `tur` listesine iki değer, `buyukluk_orani` artık boş olabilir
-- (hisse olayında "fon büyüklüğüne oran" yoktur; sıfır yazmak uydurma olurdu).
-- 0105'ün istemcisi fon satırlarını `ticker` ile süzer, hisse satırı görmez.
--
-- ## Yetki: 0105 ile aynı — oturum okur, yalnız service_role yazar.

-- ── 1) Günlük hacim ─────────────────────────────────────────────────────────
create table if not exists public.hisse_hacim_gunluk (
  -- Uygulamadaki ticker ile birebir (Yahoo sembolü): 'THYAO.IS'.
  ticker      text not null check (ticker ~ '^[A-Z0-9]{2,10}\.IS$'),
  -- İşlem günü, TR takvimi.
  tarih       date not null,
  kapanis     numeric not null check (kapanis > 0),
  -- İşlem adedi (lot).
  hacim       numeric not null check (hacim >= 0),
  -- kapanis × hacim, TL.
  para_hacmi  numeric not null check (para_hacmi >= 0),
  primary key (ticker, tarih)
);

create index if not exists hisse_hacim_gunluk_tarih_idx
  on public.hisse_hacim_gunluk (tarih);

comment on table public.hisse_hacim_gunluk is
  'Portfoylerde tutulan BIST hisselerinin gunluk kapanis ve hacmi (0106). '
  'Yalniz hacim-gozlem (service_role) yazar, authenticated yalniz okur. 400 gun saklanir.';

alter table public.hisse_hacim_gunluk enable row level security;
alter table public.hisse_hacim_gunluk force row level security;

drop policy if exists hisse_hacim_gunluk_select on public.hisse_hacim_gunluk;
create policy hisse_hacim_gunluk_select
  on public.hisse_hacim_gunluk
  for select to authenticated
  using (true);

revoke all on table public.hisse_hacim_gunluk from public, anon, authenticated;
grant select on table public.hisse_hacim_gunluk to authenticated;
grant select, insert, update, delete on table public.hisse_hacim_gunluk to service_role;

-- ── 2) Olay tablosu hisse türlerini alır ────────────────────────────────────
alter table public.balina_olay drop constraint if exists balina_olay_tur_check;
alter table public.balina_olay add constraint balina_olay_tur_check
  check (tur in ('fon_giris', 'fon_cikis',
                 'hisse_hacim_yukselis', 'hisse_hacim_dusus'));

-- Fon olayında dolu (akış / akış öncesi büyüklük); hisse olayında NULL.
alter table public.balina_olay alter column buyukluk_orani drop not null;

alter table public.balina_olay
  -- Hisse: günün para hacmi / son 20 günün ortalaması. Fon olayında NULL.
  add column if not exists ortalama_kati numeric
    check (ortalama_kati is null or ortalama_kati > 0),
  -- Hisse: günün kapanış değişimi (0,041 = +%4,1). Fon olayında NULL.
  add column if not exists fiyat_degisim numeric;

-- Tür ile dolu alanlar tutarlı olsun: yarım satır hiçbir yüzeyde okunmaz.
alter table public.balina_olay drop constraint if exists balina_olay_alan_tutarliligi;
alter table public.balina_olay add constraint balina_olay_alan_tutarliligi check (
  (tur like 'fon\_%' and buyukluk_orani is not null)
  or (tur like 'hisse\_hacim\_%' and ortalama_kati is not null
      and fiyat_degisim is not null and tutar > 0)
);

-- ── 3) Tetikleyici ──────────────────────────────────────────────────────────
-- Secret fiyat alarmıyla PAYLAŞILIR (`price_alerts_cron_secret` /
-- `PRICE_ALERTS_CRON_SECRET`): ikisi de Yahoo'dan salt-okur hisse verisi
-- çeken işler (emsal 0101: yurt-ici-kotasyon).
create or replace function public.trigger_hacim_gozlem()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('hacim-gozlem'),
    headers := public.cron_headers('price_alerts_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    -- Hisse başına bir Yahoo isteği (4'lü paralel, en çok 200 hisse).
    timeout_milliseconds := 140000
  );
end;
$$;

revoke all on function public.trigger_hacim_gozlem() from public, anon, authenticated;

-- ── 4) Zamanlama (pg_cron UTC) ──────────────────────────────────────────────
-- TR 18:45 ve 22:45, iş günleri. BIST sürekli işlem 18:00'de biter, Yahoo 15
-- dk gecikmeli; ilk tur günü kapatır, ikincisi Yahoo'nun geç düzelttiği barı
-- yakalar. Fonksiyon seansı bitmemiş günün barını yazmaz.
select cron.unschedule(jobid) from cron.job where jobname = 'hacim-gozlem';
select cron.schedule('hacim-gozlem', '45 15,19 * * 1-5',
  $$select public.trigger_hacim_gozlem()$$);

-- İki sunucu birebir: proje "tüm cron kapalı" kipindeyse yeni iş de kapalı
-- doğar (0086/0089/0101/0105 gerekçesi).
do $$
begin
  if exists (select 1 from cron.job where jobname <> 'hacim-gozlem')
     and not exists (select 1 from cron.job
                      where jobname <> 'hacim-gozlem' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname = 'hacim-gozlem';
    raise notice '0106: projede tum cron isleri kapali — hacim-gozlem de kapali kuruldu.';
  end if;
end $$;

-- ── 5) Doğrulama ────────────────────────────────────────────────────────────
do $$
begin
  if not has_table_privilege('authenticated', 'public.hisse_hacim_gunluk', 'SELECT') then
    raise exception '0106: authenticated icin hisse_hacim_gunluk SELECT GRANT eksik';
  end if;
  if has_table_privilege('authenticated', 'public.hisse_hacim_gunluk', 'INSERT')
     or has_table_privilege('authenticated', 'public.hisse_hacim_gunluk', 'UPDATE')
     or has_table_privilege('authenticated', 'public.hisse_hacim_gunluk', 'DELETE') then
    raise exception '0106: authenticated hisse_hacim_gunluk tablosuna YAZAMAMALI';
  end if;
  if has_table_privilege('anon', 'public.hisse_hacim_gunluk', 'SELECT') then
    raise exception '0106: anon hisse_hacim_gunluk tablosunu okuyamamali';
  end if;
  if not has_table_privilege('service_role', 'public.hisse_hacim_gunluk', 'INSERT')
     or not has_table_privilege('service_role', 'public.hisse_hacim_gunluk', 'DELETE') then
    raise exception '0106: service_role icin hisse_hacim_gunluk INSERT/DELETE GRANT eksik';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.hisse_hacim_gunluk'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0106: hisse_hacim_gunluk RLS (enable + force) kapali';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'hisse_hacim_gunluk') <> 1 then
    raise exception '0106: hisse_hacim_gunluk yalniz select politikasini tasimali';
  end if;
  if has_table_privilege('authenticated', 'public.balina_olay', 'INSERT') then
    raise exception '0106: authenticated balina_olay tablosuna YAZAMAMALI';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'balina_olay'
                    and column_name = 'ortalama_kati') then
    raise exception '0106: balina_olay.ortalama_kati eksik';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_hacim_gozlem()', 'EXECUTE') then
    raise exception '0106: trigger_hacim_gozlem authenticated tarafindan cagrilabilir olmamali';
  end if;
  if not exists (select 1 from cron.job
                  where jobname = 'hacim-gozlem' and schedule = '45 15,19 * * 1-5') then
    raise exception '0106: hacim-gozlem cron isi kurulmadi';
  end if;

  raise notice '0106 tamam: hisse_hacim_gunluk + balina_olay hisse turleri + cron yerinde.';
end $$;
