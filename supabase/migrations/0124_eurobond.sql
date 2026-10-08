-- 0124 — Eurobond piyasa verisi: katalog, fiyat, grafik önbelleği + tür koruması
-- ============================================================
--
-- ⚠️ NUMARA GEÇİCİ (0109 notu): dağıtımdan ÖNCE iki sunucunun defterine
-- bakılır; doluysa sıradaki boş numaraya yeniden adlandırılır.
--
-- ── Karar (kullanıcı, 2026-10-08) ───────────────────────────────────────────
-- "Varlık tiplerimize eurobond ve ABD borsası verilerini eklemeliyiz …
-- performanslı ve ücretsiz kaynaklardan anlık ve zaman aralığına göre."
--
-- Kripto (0074) gibi: fiyatı SUNUCU çeker, telefon yalnızca tabloyu okur.
--   · eurobond_katalog        ISIN, ad, kupon, vade, sıklık    ← eurobond-fiyat
--   · eurobond_fiyat          Frankfurt temiz fiyatı + Ziraat banka fiyatı ← eurobond-fiyat
--   · eurobond_seri_onbellek  grafik, istek üzerine, paylaşılan ← eurobond-seri
-- Kaynakların ölçümü ve gerekçesi `supabase/functions/_shared/eurobond.ts`.
--
-- ABD hissesi bu migration'da YOK: Yahoo'dan telefon çeker (BIST yolu),
-- sunucuda tablo gerektirmez.
--
-- ── Yer ─────────────────────────────────────────────────────────────────────
-- ~37 ISIN; fiyat tablosu ISIN başına TEK satır (upsert). Önbellek bir
-- günden eski satırı siler. 500 MB sınırına etkisi ihmal edilebilir.
--
-- ── Eski sürümler ───────────────────────────────────────────────────────────
-- Tür sütununda kısıt yok (0000); 'eurobond' adı şema değişikliği istemez.
-- Eski uygulama 'eurobond'u tanımaz, "Diğer" sayar; bir lotu düzenlerse
-- tam satır yazımı türü 'diger'e çevirirdi. Aşağıdaki tetikleyici bunu
-- sunucuda geri çevirir (bkz. §4).
--
-- ── Secret ──────────────────────────────────────────────────────────────────
-- Yeni secret YOK: cron `kripto_cron_secret` ile imzalanır (piyasa verisi
-- işi; 0115'te kripto-hacim-gozlem de başka işin secret'ını kullanıyor).
-- Fonksiyon tarafı `KRIPTO_CRON_SECRET` okur.

-- ── 1) Katalog ──────────────────────────────────────────────────────────────
create table if not exists public.eurobond_katalog (
  isin          text        primary key check (isin ~ '^[A-Z]{2}[A-Z0-9]{9}[0-9]$'),
  -- "Türkiye %9,875 2028"
  ad            text        not null check (length(ad) between 3 and 80),
  para_birimi   text        not null check (para_birimi in ('USD', 'EUR')),
  -- Yıllık kupon, oran (0.09875). Frankfurt sembol adından okunur.
  kupon_orani   double precision not null check (kupon_orani > 0 and kupon_orani < 0.3),
  vade          date        not null,
  -- Frankfurt adındaki "22/28" → 2022. Kurumsal kupon stopajı ihraç
  -- vadesine bağlı; Hazine için yalnız bilgi.
  ihrac_yili    integer     check (ihrac_yili is null or ihrac_yili between 1990 and 2100),
  kupon_sikligi smallint    not null check (kupon_sikligi in (1, 2)),
  ihracci       text        not null default 'hazine' check (ihracci in ('hazine', 'ozel_sektor')),
  -- Bankanın listesinden düşen (vadesi gelen) tahvil silinmez: onu tutan
  -- kullanıcı var.
  aktif         boolean     not null default true,
  guncellendi   timestamptz not null default now()
);

comment on table public.eurobond_katalog is
  'Izlenebilir eurobondlar (eurobond-fiyat). Uygulamadaki eurobond aramasi burada calisir.';

-- ── 2) Fiyat ────────────────────────────────────────────────────────────────
create table if not exists public.eurobond_fiyat (
  isin               text        primary key
                                 references public.eurobond_katalog (isin) on delete cascade,
  -- Frankfurt son TEMİZ fiyat (100 nominal başına). Bilinmiyorsa NULL;
  -- uydurulmaz (fiyat kaynağı sözleşmesi madde 3).
  temiz_fiyat        double precision check (temiz_fiyat is null or temiz_fiyat > 0),
  onceki_kapanis     double precision check (onceki_kapanis is null or onceki_kapanis > 0),
  piyasa_zamani      timestamptz,
  -- Ziraat alış/satış — KİRLİ fiyat (işlemiş faiz dahil). Değerleme için
  -- değil; "bankaya satarsan" satırı ve makas masrafı için.
  banka_alis         double precision check (banka_alis is null or banka_alis > 0),
  banka_satis        double precision check (banka_satis is null or banka_satis > 0),
  banka_alis_getiri  double precision,
  banka_satis_getiri double precision,
  banka_guncellendi  timestamptz,
  guncellendi        timestamptz not null default now()
);

comment on table public.eurobond_fiyat is
  'Eurobond temiz fiyati (Frankfurt) ve banka alis/satis (Ziraat, kirli). Istemci eurobond fiyatini yalnizca buradan okur.';

-- ── 3) Grafik önbelleği ─────────────────────────────────────────────────────
create table if not exists public.eurobond_seri_onbellek (
  -- 'US900123DF45|1D|1y'
  anahtar      text        primary key check (length(anahtar) <= 40),
  -- [[ms, temiz_fiyat], …] eski→yeni.
  noktalar     jsonb       not null,
  guncellendi  timestamptz not null default now()
);

comment on table public.eurobond_seri_onbellek is
  'Eurobond grafik noktalari (eurobond-seri). Yalniz service_role; istemci fonksiyon uzerinden okur.';

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.eurobond_katalog       enable row level security;
alter table public.eurobond_katalog       force  row level security;
alter table public.eurobond_fiyat         enable row level security;
alter table public.eurobond_fiyat         force  row level security;
alter table public.eurobond_seri_onbellek enable row level security;
alter table public.eurobond_seri_onbellek force  row level security;

drop policy if exists eurobond_katalog_select on public.eurobond_katalog;
create policy eurobond_katalog_select on public.eurobond_katalog
  for select to authenticated using (true);

drop policy if exists eurobond_fiyat_select on public.eurobond_fiyat;
create policy eurobond_fiyat_select on public.eurobond_fiyat
  for select to authenticated using (true);
-- eurobond_seri_onbellek: politika YOK → istemciye kapalı.

-- ── GRANT ───────────────────────────────────────────────────────────────────
revoke all on public.eurobond_katalog       from public, anon, authenticated;
revoke all on public.eurobond_fiyat         from public, anon, authenticated;
revoke all on public.eurobond_seri_onbellek from public, anon, authenticated;
grant select on public.eurobond_katalog to authenticated;
grant select on public.eurobond_fiyat   to authenticated;
grant all on public.eurobond_katalog       to service_role;
grant all on public.eurobond_fiyat         to service_role;
grant all on public.eurobond_seri_onbellek to service_role;

-- ── 4) Tür koruması (eski sürümler) ─────────────────────────────────────────
-- Eski uygulama `EUROBOND:` önekli lotu 'diger' sanar ve düzenlerken tam
-- satırı geri yazar. Önek yalnızca eurobonddan doğar; 'diger' + önek her
-- zaman eurobonddur. Yeni sürümün yazdığı satır bundan etkilenmez.
create or replace function public.eurobond_turunu_koru()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.type = 'diger' and upper(coalesce(new.ticker, '')) like 'EUROBOND:%' then
    new.type := 'eurobond';
  end if;
  return new;
end;
$$;

revoke all on function public.eurobond_turunu_koru() from public, anon, authenticated;

drop trigger if exists assets_eurobond_turu on public.assets;
create trigger assets_eurobond_turu
  before insert or update of type, ticker on public.assets
  for each row execute function public.eurobond_turunu_koru();

-- ── 5) Temizlik ─────────────────────────────────────────────────────────────
create or replace function public.cleanup_eurobond_seri_onbellek()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.eurobond_seri_onbellek
   where guncellendi < now() - interval '1 day';
$$;

revoke all on function public.cleanup_eurobond_seri_onbellek() from public, anon, authenticated;

-- ── 6) Tetikleyici (0076 edge_function_url + cron_headers deseni) ───────────
create or replace function public.trigger_eurobond_fiyat()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('eurobond-fiyat'),
    headers := public.cron_headers('kripto_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    -- ~37 Frankfurt isteği (6'lı paralel) + Ziraat + tek upsert.
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_eurobond_fiyat() from public, anon, authenticated;

-- Hafta içi 09:00–19:40 TR, 20 dakikada bir (06–16 UTC). Frankfurt seansı
-- 08:00–17:30 CET, Ziraat fiyatı günde bir-iki kez değişir. Günde 33 tur:
-- kripto'nun (720) yanında log/çağrı payı önemsiz (0113 dersi).
select cron.unschedule(jobid) from cron.job where jobname in ('eurobond-fiyat', 'eurobond-seri-onbellek-cleanup');
select cron.schedule('eurobond-fiyat', '*/20 6-16 * * 1-5',
  $$select public.trigger_eurobond_fiyat()$$);
select cron.schedule('eurobond-seri-onbellek-cleanup', '50 1 * * *',
  $$select public.cleanup_eurobond_seri_onbellek()$$);

-- İki sunucu birebir; tek bilinçli fark cron `active` (0119 kuralı).
do $$
begin
  if exists (select 1 from cron.job where jobname not like 'eurobond-%')
     and not exists (select 1 from cron.job where jobname not like 'eurobond-%' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname like 'eurobond-%';
    raise notice '0124: projede tum cron isleri kapali — eurobond isleri de kapali kuruldu.';
  end if;
end $$;

-- ── 7) Doğrulama ────────────────────────────────────────────────────────────
do $$
begin
  if not has_table_privilege('authenticated', 'public.eurobond_katalog', 'select')
     or not has_table_privilege('authenticated', 'public.eurobond_fiyat', 'select') then
    raise exception '0124: authenticated SELECT grant eksik';
  end if;
  if has_table_privilege('authenticated', 'public.eurobond_katalog', 'insert')
     or has_table_privilege('authenticated', 'public.eurobond_fiyat', 'insert')
     or has_table_privilege('authenticated', 'public.eurobond_fiyat', 'update') then
    raise exception '0124: authenticated yazma yetkisi verilmemeli';
  end if;
  if has_table_privilege('authenticated', 'public.eurobond_seri_onbellek', 'select')
     or has_table_privilege('anon', 'public.eurobond_katalog', 'select')
     or has_table_privilege('anon', 'public.eurobond_fiyat', 'select')
     or has_table_privilege('anon', 'public.eurobond_seri_onbellek', 'select') then
    raise exception '0124: onbellek/anon erisimi olmamali';
  end if;
  if (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public'
         and c.relname in ('eurobond_katalog', 'eurobond_fiyat', 'eurobond_seri_onbellek')
         and c.relrowsecurity and c.relforcerowsecurity) <> 3 then
    raise exception '0124: RLS/FORCE RLS acik degil';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_eurobond_fiyat()', 'EXECUTE')
     or has_function_privilege('anon', 'public.trigger_eurobond_fiyat()', 'EXECUTE') then
    raise exception '0124: trigger_eurobond_fiyat istemciden cagrilabilir olmamali';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'assets_eurobond_turu') then
    raise exception '0124: assets_eurobond_turu tetikleyicisi yok';
  end if;
  if not exists (select 1 from cron.job where jobname = 'eurobond-fiyat'
                    and schedule = '*/20 6-16 * * 1-5') then
    raise exception '0124: eurobond-fiyat cron isi kurulmadi';
  end if;
  raise notice '0124 tamam: eurobond katalog/fiyat/onbellek, tur korumasi ve cron kuruldu.';
end $$;
