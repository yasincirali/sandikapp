-- 0074 — Kripto piyasa verisi: katalog, anlık fiyat, grafik önbelleği
-- ============================================================
--
-- ── Karar (kullanıcı, 2026-09-25) ───────────────────────────────────────────
-- "Kripto varlıkları da burada izleyebilmeliyiz … public bir performans
-- sorunu yaratmayacak bir api üzerinden güvenli ve hızlı şekilde datayı
-- çekmeliyiz."
--
-- Diğer varlıklarda fiyatı her telefon kendisi çekiyor. Kriptoda fiyatı
-- SUNUCU çeker, telefon yalnızca bu tabloları okur:
--   · kripto_varlik        günlük katalog (kod, ad, logo, parite)  ← kripto-katalog
--   · kripto_fiyat         dakikalık TL fiyat + İstanbul günü açılışı ← kripto-fiyat
--   · kripto_seri_onbellek grafik mumları, istek üzerine, paylaşılan ← kripto-seri
-- Sağlayıcıya giden istek sayısı böylece kullanıcı sayısından bağımsızdır.
-- Gerekçelerin tamamı `supabase/functions/_shared/kripto.ts` başında.
--
-- ── Sembol biçimi ───────────────────────────────────────────────────────────
-- `assets.ticker` = 'KRIPTO:BTC' (TEFAS: öneki gibi). Tür sütununda kısıt
-- yok (0000); yeni tür adı ('kripto') şema değişikliği gerektirmez.
--
-- ── Erişim ──────────────────────────────────────────────────────────────────
-- Katalog ve fiyat piyasa verisidir, kişisel değil: oturumlu her kullanıcı
-- OKUR, yalnızca service_role (edge function) YAZAR. Seri önbelleğine
-- istemci hiç dokunmaz; kripto-seri fonksiyonu aracılık eder. anon'a hiçbir
-- şey yok. GRANT ve RLS ayrı şeylerdir; ikisi de yazılır ve doğrulanır
-- (0036/0042/0063 deseni).
--
-- ── Bölge ───────────────────────────────────────────────────────────────────
-- Binance ABD IP'lerine 451 döner. Cron çağrıları `x-region: eu-central-1`
-- ile Frankfurt'a sabitlenir (Supabase bölgesel çağrı). İstemci de
-- kripto-seri'yi aynı başlıkla çağırır.

-- ── Katalog ─────────────────────────────────────────────────────────────────
create table if not exists public.kripto_varlik (
  kod             text        primary key check (kod ~ '^[A-Z0-9]{2,15}$'),
  -- Binance varlık adı ('Bitcoin'). Varlık listesi o tur gelmediyse ilk
  -- kayıtta NULL kalabilir; istemci kodu gösterir.
  ad              text,
  logo_url        text        check (logo_url is null or logo_url like 'https://%'),
  -- USDT paritesinin 24 saatlik hacmine göre sıra (1 = en yüksek; USDT'nin
  -- kendisi 0). Arama sonuçlarının sırası; piyasa değeri Binance'te yok.
  hacim_sirasi    integer,
  -- Fiyatın hangi pariteden geleceğine YALNIZCA burası karar verir
  -- (fiyat kaynağı sözleşmesi madde 1).
  parite          text        not null check (parite in ('TRY', 'USDT')),
  binance_sembol  text        not null check (binance_sembol ~ '^[A-Z0-9]{4,20}$'),
  -- Listeden düşen coin silinmez (onu tutan kullanıcı var), pasifleşir.
  aktif           boolean     not null default true,
  guncellendi     timestamptz not null default now()
);

comment on table public.kripto_varlik is
  'Izlenebilir kripto paralar ve fiyat paritesi (kripto-katalog, saatlik). Uygulamadaki kripto aramasi burada calisir.';

create index if not exists kripto_varlik_aktif_sira_idx
  on public.kripto_varlik (aktif, hacim_sirasi);

-- ── Anlık fiyat ─────────────────────────────────────────────────────────────
create table if not exists public.kripto_fiyat (
  kod             text        primary key
                              references public.kripto_varlik (kod) on delete cascade,
  -- `double precision`: SHIB (~0,0004 ₺) ile BTC (~4 milyon ₺) aynı sütunda,
  -- 15 anlamlı hane ikisine de yeter. `assets.current_price` ile aynı tip.
  fiyat_try       double precision not null check (fiyat_try > 0),
  -- USD karşılığı (USDT paritesi ya da TRY ÷ USDTTRY). İleride USD
  -- maliyetli kripto için; bugün yalnızca bilgi.
  fiyat_usd       double precision check (fiyat_usd is null or fiyat_usd > 0),
  -- İstanbul gününün (00:00) açılışı. Bilinmiyorsa NULL: günlük yüzde
  -- gösterilmez, uydurulmaz (sözleşme madde 3).
  gun_acilis_try  double precision check (gun_acilis_try is null or gun_acilis_try > 0),
  gun             date        not null,
  kaynak          text        not null check (kaynak in ('binance_try', 'binance_usdt')),
  guncellendi     timestamptz not null default now()
);

comment on table public.kripto_fiyat is
  'Kripto TL fiyati, dakikada bir (kripto-fiyat). Istemci, widget ve alarmlar kripto fiyatini yalnizca buradan okur.';

-- ── Grafik önbelleği ────────────────────────────────────────────────────────
create table if not exists public.kripto_seri_onbellek (
  -- 'BTC|1h|1mo' — kullanıcıya değil isteğe bağlı, herkes paylaşır.
  anahtar      text        primary key check (length(anahtar) <= 40),
  -- [[açılış ms, fiyat_try], …] eski→yeni.
  noktalar     jsonb       not null,
  guncellendi  timestamptz not null default now()
);

comment on table public.kripto_seri_onbellek is
  'Kripto grafik mumlari (kripto-seri). Yalniz service_role; istemci fonksiyon uzerinden okur.';

-- ── RLS ─────────────────────────────────────────────────────────────────────
alter table public.kripto_varlik        enable row level security;
alter table public.kripto_varlik        force  row level security;
alter table public.kripto_fiyat         enable row level security;
alter table public.kripto_fiyat         force  row level security;
alter table public.kripto_seri_onbellek enable row level security;
alter table public.kripto_seri_onbellek force  row level security;

drop policy if exists kripto_varlik_select on public.kripto_varlik;
create policy kripto_varlik_select on public.kripto_varlik
  for select to authenticated using (true);

drop policy if exists kripto_fiyat_select on public.kripto_fiyat;
create policy kripto_fiyat_select on public.kripto_fiyat
  for select to authenticated using (true);
-- kripto_seri_onbellek: politika YOK → istemciye kapalı (varsayılan red).

-- ── GRANT ───────────────────────────────────────────────────────────────────
-- Supabase'in varsayılan ayrıcalıkları yeni tabloda authenticated'a ALL
-- verir; önce hepsi geri alınır, sonra yalnız gereken.
revoke all on public.kripto_varlik        from public, anon, authenticated;
revoke all on public.kripto_fiyat         from public, anon, authenticated;
revoke all on public.kripto_seri_onbellek from public, anon, authenticated;
grant select on public.kripto_varlik to authenticated;
grant select on public.kripto_fiyat  to authenticated;
grant all on public.kripto_varlik        to service_role;
grant all on public.kripto_fiyat         to service_role;
grant all on public.kripto_seri_onbellek to service_role;

do $$
begin
  if not has_table_privilege('authenticated', 'public.kripto_varlik', 'select')
     or not has_table_privilege('authenticated', 'public.kripto_fiyat', 'select') then
    raise exception 'kripto: authenticated SELECT grant eksik';
  end if;
  if has_table_privilege('authenticated', 'public.kripto_varlik', 'insert')
     or has_table_privilege('authenticated', 'public.kripto_fiyat', 'insert')
     or has_table_privilege('authenticated', 'public.kripto_fiyat', 'update') then
    raise exception 'kripto: authenticated yazma yetkisi verilmemeli';
  end if;
  if has_table_privilege('authenticated', 'public.kripto_seri_onbellek', 'select') then
    raise exception 'kripto_seri_onbellek: authenticated erisimi olmamali';
  end if;
  if has_table_privilege('anon', 'public.kripto_varlik', 'select')
     or has_table_privilege('anon', 'public.kripto_fiyat', 'select')
     or has_table_privilege('anon', 'public.kripto_seri_onbellek', 'select') then
    raise exception 'kripto: anon SELECT verilmemeli';
  end if;
  if (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public'
         and c.relname in ('kripto_varlik', 'kripto_fiyat', 'kripto_seri_onbellek')
         and c.relrowsecurity and c.relforcerowsecurity) <> 3 then
    raise exception 'kripto: RLS/FORCE RLS acik degil';
  end if;
end $$;

-- ── Temizlik ────────────────────────────────────────────────────────────────
-- En uzun TTL 1 saat; bir günden eski satır artık kimsenin okumadığı bir
-- (kod, aralık, dönem) birleşimidir.
create or replace function public.cleanup_kripto_seri_onbellek()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.kripto_seri_onbellek
   where guncellendi < now() - interval '1 day';
$$;

revoke all on function public.cleanup_kripto_seri_onbellek() from public, anon, authenticated;

-- ── Tetikleyiciler (0054 `cron_headers` deseni + bölge başlığı) ─────────────
create or replace function public.trigger_kripto_fiyat()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/kripto-fiyat',
    headers := public.cron_headers('kripto_cron_secret')
               || jsonb_build_object('x-region', 'eu-central-1'),
    body := jsonb_build_object('source', 'cron'),
    -- ~4 paralel Binance isteği + tek upsert; 10 sn zaman aşımı × yedek.
    timeout_milliseconds := 45000
  );
end;
$$;

revoke all on function public.trigger_kripto_fiyat() from public, anon, authenticated;

create or replace function public.trigger_kripto_katalog()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/kripto-katalog',
    headers := public.cron_headers('kripto_cron_secret')
               || jsonb_build_object('x-region', 'eu-central-1'),
    body := jsonb_build_object('source', 'cron'),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_kripto_katalog() from public, anon, authenticated;

-- ── Zamanlama (pg_cron UTC) ─────────────────────────────────────────────────
select cron.unschedule(jobid) from cron.job
 where jobname in ('kripto-fiyat', 'kripto-katalog', 'kripto-seri-onbellek-cleanup');

-- Her dakika, 7/24: kripto piyasası kapanmıyor.
select cron.schedule('kripto-fiyat', '* * * * *',
  $$select public.trigger_kripto_fiyat()$$);

-- Saatte bir (xx:10). Günde bir yeterdi; saatlik seçildi ki dağıtımdan
-- sonraki ilk katalog elle tetiklenmeden bir saat içinde kurulsun ve tek
-- turluk bir kesinti günü kaçırtmasın. Tur başına ~100 Binance ağırlığı.
select cron.schedule('kripto-katalog', '10 * * * *',
  $$select public.trigger_kripto_katalog()$$);

select cron.schedule('kripto-seri-onbellek-cleanup', '40 1 * * *',
  $$select public.cleanup_kripto_seri_onbellek()$$);
