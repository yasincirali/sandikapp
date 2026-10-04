-- 0103 — Fon para akışı ve büyük giriş/çıkış olayları (Balina B1, 2026-10-04)
--
-- ## Neden
-- Kullanıcı isteği: "toplu para girişi" gibi verileri fon bazında göstermek.
-- TEFAS her fonun günlük dolaşımdaki pay adedini ve büyüklüğünü yayınlıyor;
-- pay farkı × o günün fiyatı = o gün fona giren/çıkan para. `akis-gozlem`
-- edge function'ı bu veriyi günde birkaç kez okur, `fon_akis_gunluk`'a yazar
-- ve kurala uyan günleri `balina_olay`'a işler. İstemci kartı (Remote Config
-- `balina_radari_acik`, varsayılan KAPALI) yalnız bu iki tabloyu okur: kart,
-- olay listesi ve ileride bildirim AYNI satırdan beslenir.
--
-- ## Eski sürümler
-- Yalnızca EKLER: iki tablo, bir tur tablosu, bir istatistik fonksiyonu, bir
-- tetikleyici, bir cron. Mevcut hiçbir kolona/RPC'ye dokunmaz; eski build'ler
-- tabloları hiç okumaz.
--
-- ## Yetki: herkese açık piyasa verisi, yalnız OKU (0101 deseni)
-- Kişisel veri yok; oturum açmış her kullanıcı okur. Yazma yalnızca
-- service_role (edge function). anon okumaz. GRANT ve RLS ayrı katmanlar;
-- ikisi de yazılır ve sonda doğrulanır.

-- ── 1) Günlük fon durumu ────────────────────────────────────────────────────
create table if not exists public.fon_akis_gunluk (
  -- TEFAS fon kodu ('TTE', 'AH5'); uygulamadaki ticker'ın 'TEFAS:' sonrası.
  fon_kodu        text not null check (fon_kodu ~ '^[A-Z0-9]{2,6}$'),
  -- Fiyatın (NAV) ait olduğu gün, TR takvimi.
  tarih           date not null,
  -- 'YAT' yatırım fonu, 'EMK' emeklilik (BES) fonu.
  fon_tipi        text not null check (fon_tipi in ('YAT', 'EMK')),
  -- Dolaşımdaki pay adedi (emeklilik fonlarında kesirli).
  pay_adedi       numeric not null check (pay_adedi > 0),
  -- Fon toplam değeri, TL.
  portfoy_degeri  numeric not null check (portfoy_degeri > 0),
  -- (pay − önceki günün payı) × (değer / pay), TL. Önceki gün bilinmiyorsa
  -- NULL — sıfır "para girmedi" demek olurdu.
  net_akis        numeric,
  -- Yatırımcı sayısı. Yalnız portföylerde tutulan fonlar için ve yalnız
  -- görüntünün bu güne ait olduğu kanıtlanınca dolar; aksi hâlde NULL.
  yatirimci       integer check (yatirimci is null or yatirimci >= 0),
  primary key (fon_kodu, tarih)
);

-- Gün bazlı okuma (önceki günün payları, istatistik penceresi, saklama silmesi).
create index if not exists fon_akis_gunluk_tarih_idx
  on public.fon_akis_gunluk (tarih);

comment on table public.fon_akis_gunluk is
  'TEFAS fonlarinin gunluk pay adedi, buyuklugu ve net para akisi (0103). '
  'Yalniz akis-gozlem (service_role) yazar, authenticated yalniz okur. 400 gun saklanir.';

-- ── 2) Olaylar ──────────────────────────────────────────────────────────────
-- `ticker` uygulamadaki biçimde ('TEFAS:TTE'): hisse ve kripto olayları
-- (sonraki dilimler) aynı tabloya yeni `tur` değerleriyle girer ve tek liste
-- olarak okunur.
create table if not exists public.balina_olay (
  ticker          text not null check (length(ticker) between 3 and 40),
  tarih           date not null,
  tur             text not null check (tur in ('fon_giris', 'fon_cikis')),
  -- Net akış, TL; girişte artı, çıkışta eksi.
  tutar           numeric not null check (tutar <> 0),
  -- |tutar| / fon büyüklüğü (0,031 = %3,1).
  buyukluk_orani  numeric not null check (buyukluk_orani > 0),
  -- |tutar| / geçmiş günlük akışların standart sapması.
  sapma_kati      numeric not null check (sapma_kati > 0),
  primary key (ticker, tarih)
);

create index if not exists balina_olay_tarih_idx
  on public.balina_olay (tarih);

comment on table public.balina_olay is
  'Kurala uyan buyuk para giris/cikis gunleri (0103). Kural _shared/balina.ts; '
  'yalniz akis-gozlem (service_role) yazar, authenticated yalniz okur.';

-- ── 3) Tur defteri ──────────────────────────────────────────────────────────
-- Hangi gün çekildi, kaç fon geldi, artık değişmez mi. İstemci OKUMAZ.
create table if not exists public.fon_akis_tur (
  tarih       date primary key,
  fon_sayisi  integer not null check (fon_sayisi >= 0),
  -- true: gün bir daha sorulmaz (yeterince eski ya da tatil olduğu kesin).
  kesin       boolean not null default false,
  cekildi     timestamptz not null default now()
);

comment on table public.fon_akis_tur is
  'akis-gozlem tur defteri (0103): gun basina cekilen fon sayisi. Yalniz service_role.';

-- ── 4) RLS ──────────────────────────────────────────────────────────────────
alter table public.fon_akis_gunluk enable row level security;
alter table public.fon_akis_gunluk force row level security;
alter table public.balina_olay enable row level security;
alter table public.balina_olay force row level security;
alter table public.fon_akis_tur enable row level security;
alter table public.fon_akis_tur force row level security;

drop policy if exists fon_akis_gunluk_select on public.fon_akis_gunluk;
create policy fon_akis_gunluk_select
  on public.fon_akis_gunluk
  for select to authenticated
  -- Piyasa verisi: satır sahibi yok, her oturum okur.
  using (true);

drop policy if exists balina_olay_select on public.balina_olay;
create policy balina_olay_select
  on public.balina_olay
  for select to authenticated
  using (true);

-- INSERT/UPDATE/DELETE politikası BİLEREK yok; authenticated için GRANT de
-- yok. `fon_akis_tur` için hiç politika yok: yalnız service_role (RLS'i aşar).

-- ── 5) GRANT ────────────────────────────────────────────────────────────────
revoke all on table public.fon_akis_gunluk from public, anon, authenticated;
revoke all on table public.balina_olay     from public, anon, authenticated;
revoke all on table public.fon_akis_tur    from public, anon, authenticated;
grant select on table public.fon_akis_gunluk to authenticated;
grant select on table public.balina_olay     to authenticated;
grant select, insert, update, delete on table public.fon_akis_gunluk to service_role;
grant select, insert, update, delete on table public.balina_olay     to service_role;
grant select, insert, update, delete on table public.fon_akis_tur    to service_role;

-- ── 6) Sapma istatistiği ────────────────────────────────────────────────────
-- Olay kuralı TypeScript'te (`_shared/balina.ts`, Deno testli); burada yalnız
-- kümeleme var. 1.400 fon × 60 gün satırı fonksiyona taşımak yerine fon
-- başına tek satır döner. Pencere `p_gun`'den ÖNCEKİ 90 takvim günü (~60
-- işlem günü): günün kendi akışı kendi eşiğini şişirmesin.
create or replace function public.akis_sapma(p_gun date)
returns table (fon_kodu text, gozlem integer, sapma numeric)
language sql
stable
security invoker
set search_path = public
as $$
  select g.fon_kodu,
         count(g.net_akis)::integer,
         stddev_samp(g.net_akis)
    from public.fon_akis_gunluk g
   where g.tarih < p_gun
     and g.tarih >= p_gun - 90
     and g.net_akis is not null
   group by g.fon_kodu;
$$;

revoke all on function public.akis_sapma(date) from public, anon, authenticated;
grant execute on function public.akis_sapma(date) to service_role;

-- ── 7) Tetikleyici ──────────────────────────────────────────────────────────
-- 0101 deseni. Secret NAV gözlemiyle PAYLAŞILIR (`tefas_nav_cron_secret` /
-- `TEFAS_NAV_CRON_SECRET`): ikisi de TEFAS'tan salt-okur veri çeken işler;
-- yeni secret iki sunucuda elle kurulum gerektirirdi (emsal 0089, 0101).
create or replace function public.trigger_akis_gozlem()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('akis-gozlem'),
    headers := public.cron_headers('tefas_nav_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    -- Tur başına en çok 14 gün × 2 TEFAS isteği + toplu yazma.
    timeout_milliseconds := 140000
  );
end;
$$;

revoke all on function public.trigger_akis_gozlem() from public, anon, authenticated;

-- ── 8) Zamanlama (pg_cron UTC) ──────────────────────────────────────────────
-- TR 08:15, 11:15, 14:15, 19:15 — her gün. Fonlar fiyatını gün içinde fon
-- fon yayınlıyor; son iki günü her tur yeniden çeker, eksik kalan tamamlanır.
-- Hafta sonu turu da koşar (Cuma'nın geç yayınlanan fonları) ama hafta sonu
-- günlerini sormaz. Dakika 15: yarım saatlik NAV gözlemiyle aynı ana binmesin.
select cron.unschedule(jobid) from cron.job where jobname = 'akis-gozlem';
select cron.schedule('akis-gozlem', '15 5,8,11,16 * * *',
  $$select public.trigger_akis_gozlem()$$);

-- İki sunucu birebir: proje "tüm cron kapalı" kipindeyse yeni iş de kapalı
-- doğar (0086/0089/0101 gerekçesi; proje ref'i sabit yazılmaz).
do $$
begin
  if exists (select 1 from cron.job where jobname <> 'akis-gozlem')
     and not exists (select 1 from cron.job
                      where jobname <> 'akis-gozlem' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname = 'akis-gozlem';
    raise notice '0103: projede tum cron isleri kapali — akis-gozlem de kapali kuruldu.';
  end if;
end $$;

-- ── 9) Doğrulama ────────────────────────────────────────────────────────────
do $$
declare
  t text;
begin
  foreach t in array array['fon_akis_gunluk', 'balina_olay'] loop
    if not has_table_privilege('authenticated', 'public.' || t, 'SELECT') then
      raise exception '0103: authenticated icin % SELECT GRANT eksik', t;
    end if;
    if (select count(*) from pg_policies
         where schemaname = 'public' and tablename = t) <> 1
       or not exists (select 1 from pg_policies
                       where schemaname = 'public' and tablename = t
                         and policyname = t || '_select' and cmd = 'SELECT') then
      raise exception '0103: % yalniz select politikasini tasimali', t;
    end if;
  end loop;

  foreach t in array array['fon_akis_gunluk', 'balina_olay', 'fon_akis_tur'] loop
    if has_table_privilege('authenticated', 'public.' || t, 'INSERT')
       or has_table_privilege('authenticated', 'public.' || t, 'UPDATE')
       or has_table_privilege('authenticated', 'public.' || t, 'DELETE') then
      raise exception '0103: authenticated % tablosuna YAZAMAMALI', t;
    end if;
    if has_table_privilege('anon', 'public.' || t, 'SELECT') then
      raise exception '0103: anon % tablosunu okuyamamali', t;
    end if;
    if not has_table_privilege('service_role', 'public.' || t, 'INSERT')
       or not has_table_privilege('service_role', 'public.' || t, 'DELETE') then
      raise exception '0103: service_role icin % INSERT/DELETE GRANT eksik', t;
    end if;
    if not exists (select 1 from pg_class
                    where oid = ('public.' || t)::regclass
                      and relrowsecurity and relforcerowsecurity) then
      raise exception '0103: % RLS (enable + force) kapali', t;
    end if;
  end loop;

  if has_table_privilege('authenticated', 'public.fon_akis_tur', 'SELECT') then
    raise exception '0103: authenticated fon_akis_tur tablosunu okuyamamali';
  end if;
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'fon_akis_tur') then
    raise exception '0103: fon_akis_tur politika tasimamali (yalniz service_role)';
  end if;

  if has_function_privilege('authenticated', 'public.akis_sapma(date)', 'EXECUTE')
     or has_function_privilege('anon', 'public.akis_sapma(date)', 'EXECUTE') then
    raise exception '0103: akis_sapma yalniz service_role tarafindan cagrilabilmeli';
  end if;
  if not has_function_privilege('service_role', 'public.akis_sapma(date)', 'EXECUTE') then
    raise exception '0103: service_role icin akis_sapma EXECUTE GRANT eksik';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_akis_gozlem()', 'EXECUTE') then
    raise exception '0103: trigger_akis_gozlem authenticated tarafindan cagrilabilir olmamali';
  end if;
  if not exists (select 1 from cron.job
                  where jobname = 'akis-gozlem' and schedule = '15 5,8,11,16 * * *') then
    raise exception '0103: akis-gozlem cron isi kurulmadi';
  end if;

  raise notice '0103 tamam: fon_akis_gunluk + balina_olay + RLS + GRANT + cron yerinde.';
end $$;
