-- 0101 — Yurt içi altın/döviz kotasyonunun gün içi kaydı (2026-10-03)
--
-- ## Neden
-- Hafta sonu Performans › GÜNLÜK'te dolar ve altın dümdüz çiziliyordu
-- (kullanıcı sorusu 2026-10-03: "Neden düz çizgi peki. Değeri oynak değil
-- mi?"). Grafiğin şekli Yahoo'dan geliyor; uluslararası piyasa Cumartesi
-- 00:00 – Pazartesi 00:00 (TR) kapalı olduğu için seri Cuma'da bitiyor.
-- Ekrandaki fiyat ise yurt içi kotasyon (truncgil) ve o hafta sonu da
-- fiyat veriyor — ama yalnızca ANLIK değeri biliniyordu. Kullanıcı kararı:
-- "Evet bunu yapalım ama fiyat tutarlı ve doğru şeyi göstermeli."
--
-- `yurt-ici-kotasyon` edge function'ı beş dakikada bir truncgil'i okur ve
-- her altın ayarı + TL döviz için bir satır yazar. İstemci, uluslararası
-- seri susmuşken GÜNLÜK şeklini bu tablodan kurar (Remote Config
-- `hafta_sonu_yurt_ici_seri`, varsayılan KAPALI).
--
-- ## Eski sürümler
-- Yalnızca EKLER: yeni tablo, yeni tetikleyici, yeni cron. Hiçbir mevcut
-- kolona/RPC'ye dokunmaz; eski build'ler tabloyu hiç okumaz.
--
-- ## Yetki: herkese açık piyasa verisi, yalnız OKU (0089 deseni)
-- Kişisel veri değil; oturum açmış her kullanıcı okur. Yazma yalnızca
-- service_role (edge function). anon okumaz. GRANT ve RLS ayrı katmanlar;
-- ikisi de yazılır ve sonda doğrulanır.

-- ── 1) Tablo ────────────────────────────────────────────────────────────────
create table if not exists public.yurt_ici_kotasyon (
  -- Uygulamanın iç sembolü: 'ALTIN_GRAM', 'ALTIN_CEYREK', 'USDTRY=X' …
  sembol       text not null check (length(sembol) between 1 and 40),
  -- 5 dakikalık kovanın başı (UTC). Geç kalan tur aynı kovaya yazar.
  ts           timestamptz not null,
  -- TL birim fiyat — uygulamanın gösterdiği alan (`Buying` önce).
  fiyat        numeric not null check (fiyat > 0),
  -- Kaynağın kendi günlük yüzdesi (teşhis için; grafik kullanmaz).
  degisim_pct  numeric,
  primary key (sembol, ts)
);

-- Saklama silmesi `ts` ile yapılır (sembol öneki olmadan).
create index if not exists yurt_ici_kotasyon_ts_idx
  on public.yurt_ici_kotasyon (ts);

comment on table public.yurt_ici_kotasyon is
  'Yurt ici altin/doviz kotasyonu, 5 dk kova (0101). Kaynak truncgil; '
  'yalniz yurt-ici-kotasyon (service_role) yazar, authenticated yalniz okur. 10 gun saklanir.';

-- ── 2) RLS ──────────────────────────────────────────────────────────────────
alter table public.yurt_ici_kotasyon enable row level security;
alter table public.yurt_ici_kotasyon force row level security;

drop policy if exists yurt_ici_kotasyon_select on public.yurt_ici_kotasyon;
create policy yurt_ici_kotasyon_select
  on public.yurt_ici_kotasyon
  for select to authenticated
  -- Piyasa verisi: satır sahibi yok, her oturum okur.
  using (true);

-- INSERT/UPDATE/DELETE politikası BİLEREK yok; authenticated için GRANT de
-- yok. Kullanıcı başkalarının grafiğine nokta ekleyemesin.

-- ── 3) GRANT ────────────────────────────────────────────────────────────────
revoke all on table public.yurt_ici_kotasyon from public, anon, authenticated;
grant select on table public.yurt_ici_kotasyon to authenticated;
grant select, insert, update, delete on table public.yurt_ici_kotasyon to service_role;

-- ── 4) Tetikleyici ──────────────────────────────────────────────────────────
-- 0076 deseni. Secret fiyat alarmıyla PAYLAŞILIR (`price_alerts_cron_secret`
-- / `PRICE_ALERTS_CRON_SECRET`): ikisi de truncgil'den salt-okur fiyat
-- çeken işler; yeni secret iki sunucuda elle kurulum gerektirirdi (emsal
-- 0089: bes-parametre ↔ TÜFE çekimi).
create or replace function public.trigger_yurt_ici_kotasyon()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('yurt-ici-kotasyon'),
    headers := public.cron_headers('price_alerts_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    -- Tek truncgil isteği (10 sn zaman aşımı) + upsert + saklama silmesi.
    timeout_milliseconds := 30000
  );
end;
$$;

revoke all on function public.trigger_yurt_ici_kotasyon() from public, anon, authenticated;

-- ── 5) Zamanlama (pg_cron UTC) ──────────────────────────────────────────────
-- Beş dakikada bir: istemcinin gün içi slotu da 5 dakika.
select cron.unschedule(jobid) from cron.job where jobname = 'yurt-ici-kotasyon';
select cron.schedule('yurt-ici-kotasyon', '*/5 * * * *',
  $$select public.trigger_yurt_ici_kotasyon()$$);

-- İki sunucu birebir: proje "tüm cron kapalı" kipindeyse yeni iş de kapalı
-- doğar (0086/0089 gerekçesi; proje ref'i sabit yazılmaz).
do $$
begin
  if exists (select 1 from cron.job where jobname <> 'yurt-ici-kotasyon')
     and not exists (select 1 from cron.job
                      where jobname <> 'yurt-ici-kotasyon' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname = 'yurt-ici-kotasyon';
    raise notice '0101: projede tum cron isleri kapali — yurt-ici-kotasyon da kapali kuruldu.';
  end if;
end $$;

-- ── 6) Doğrulama ────────────────────────────────────────────────────────────
do $$
begin
  if not has_table_privilege('authenticated', 'public.yurt_ici_kotasyon', 'SELECT') then
    raise exception '0101: authenticated icin yurt_ici_kotasyon SELECT GRANT eksik';
  end if;
  if has_table_privilege('authenticated', 'public.yurt_ici_kotasyon', 'INSERT')
     or has_table_privilege('authenticated', 'public.yurt_ici_kotasyon', 'UPDATE')
     or has_table_privilege('authenticated', 'public.yurt_ici_kotasyon', 'DELETE') then
    raise exception '0101: authenticated yurt_ici_kotasyon tablosuna YAZAMAMALI';
  end if;
  if has_table_privilege('anon', 'public.yurt_ici_kotasyon', 'SELECT') then
    raise exception '0101: anon yurt_ici_kotasyon tablosunu okuyamamali';
  end if;
  if not has_table_privilege('service_role', 'public.yurt_ici_kotasyon', 'INSERT')
     or not has_table_privilege('service_role', 'public.yurt_ici_kotasyon', 'DELETE') then
    raise exception '0101: service_role icin yurt_ici_kotasyon INSERT/DELETE GRANT eksik';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.yurt_ici_kotasyon'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0101: yurt_ici_kotasyon RLS (enable + force) kapali';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'yurt_ici_kotasyon') <> 1
     or not exists (select 1 from pg_policies
                     where schemaname = 'public'
                       and tablename = 'yurt_ici_kotasyon'
                       and policyname = 'yurt_ici_kotasyon_select'
                       and cmd = 'SELECT') then
    raise exception '0101: yurt_ici_kotasyon yalniz select politikasini tasimali';
  end if;
  if not exists (select 1 from cron.job
                  where jobname = 'yurt-ici-kotasyon' and schedule = '*/5 * * * *') then
    raise exception '0101: yurt-ici-kotasyon cron isi kurulmadi';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_yurt_ici_kotasyon()', 'EXECUTE') then
    raise exception '0101: trigger_yurt_ici_kotasyon authenticated tarafindan cagrilabilir olmamali';
  end if;

  raise notice '0101 tamam: yurt_ici_kotasyon + RLS + GRANT + cron yerinde.';
end $$;
