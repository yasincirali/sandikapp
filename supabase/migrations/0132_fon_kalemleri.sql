-- 0132 — Fon X-Ray, Katman A: KAP aylık Portföy Dağılım Raporu kalemleri
-- (2026-10-10)
--
-- ## Neden
-- Katman B (0131) "fonun %40'ı hisse" der; "hangi hisse" demez. Kalem
-- verisinin (THYAO %8) TEK olgusal kaynağı KAP'taki aylık "Portföy Dağılım
-- Raporu" — yapısal veri değil, kurucuya göre düzeni değişen bir PDF eki,
-- ay sonundan ~6 iş günü sonra. Araştırma: tmp/arastirma/reports/
-- Fon XRay veri kaynakları.md.
--
-- ## Kanıt zinciri: beş kontrol, biri düşerse belgenin TAMAMI reddedilir
-- `fon-kalem-raporu` PDF metnini çıkarır, kalemleri yapay zekâyla ayıklar ve
-- `_shared/fon_kalem.ts` şu beş kontrolü uygular: (1) her ağırlık PDF
-- metninde aynen geçer, (2) toplam %100 ± 1,5, (3) aynı ay sonu TEFAS hisse
-- toplamıyla ± 3 puan, (4) fon türünün yasal bandı, (5) şema. Reddedilen
-- belge `durum = 'red'` ile yazılır (aynı ay tekrar denenmez, para harcanmaz)
-- ve istemciye hiç görünmez; o fon Katman B'de kalır ("hatalı göstermektense
-- hiç gösterme", fonlu kararı).
--
-- ## Kişisel veri
-- Yok. Modele giden kamuya açık bir KAP belgesinin metni; kullanıcının
-- miktarı, maliyeti, kimliği GİTMEZ. Hangi fonların işleneceği "en az bir
-- kullanıcı tutuyor mu" sorusuyla seçilir, kimin tuttuğu yazılmaz.
--
-- ## Bayrak
-- Sunucuda `FON_KALEM_ACIK=1` function secret'ı yoksa fonksiyon hiçbir şey
-- yapmaz (KAP'a, TEFAS'a, modele gitmez). İstemcide `fon_xray_kalem` Remote
-- Config bayrağı varsayılan KAPALI; kapalıyken bu tablo okunmaz.
--
-- ## Eski istemciler
-- Yalnız EKLER: iki tablo, bir tetikleyici, bir cron işi.
--
-- ## Dağıtım sırası
-- Bu migration (iki sunucu) → `fon-kalem-raporu` fonksiyonu (iki sunucu) →
-- ayın 8'inde `FON_KALEM_ACIK=1` secret'ı → ilk tur elle:
-- `select public.trigger_fon_kalem_raporu();` → kontrol:
-- `select durum, count(*) from public.fon_kalemleri group by 1;`

-- ── 1) Kalemler (fon × ay) ──────────────────────────────────────────────────
create table if not exists public.fon_kalemleri (
  fon_kodu    text not null check (fon_kodu ~ '^[A-Z0-9]{2,8}$'),
  -- Raporun ait olduğu ay sonu (ör. 2026-09-30).
  donem       date not null,
  -- 'gecti' = beş kontrolün beşi de geçti; 'red' = biri düştü, kalemler boş.
  durum       text not null check (durum in ('gecti', 'red')),
  -- [{ad, kod, tur, agirlik}] — ağırlık fon portföy değerine göre %, PDF'te
  -- yazdığı gibi (aynı kalemin lot satırları toplanır, başka yuvarlama yok).
  kalemler    jsonb not null default '[]'::jsonb check (jsonb_typeof(kalemler) = 'array'),
  -- KAP bildiriminin herkese açık sayfası (kaynak satırında bağlantı).
  kaynak_url  text check (kaynak_url is null or kaynak_url ~ '^https://www\.kap\.org\.tr/'),
  -- Kontrol özeti: {kontroller, neden, tefas_tarih, hisse_toplam, tefas_hs,
  -- model, maliyet_usd …}. Ham model yanıtı ve PDF metni YAZILMAZ.
  dogrulama   jsonb not null default '{}'::jsonb check (jsonb_typeof(dogrulama) = 'object'),
  alindi      timestamptz not null default now(),
  primary key (fon_kodu, donem),
  constraint fon_kalemleri_red_bos check (durum = 'gecti' or kalemler = '[]'::jsonb)
);

comment on table public.fon_kalemleri is
  'Fon X-Ray Katman A (0132): KAP Portfoy Dagilim Raporu kalemleri, bes kontrolden gecen belgeler. '
  'fon-kalem-raporu (service_role) yazar; okuma premium_icerik_gorebilir() ve durum=gecti.';

alter table public.fon_kalemleri enable row level security;
alter table public.fon_kalemleri force row level security;

drop policy if exists fon_kalemleri_premium on public.fon_kalemleri;
create policy fon_kalemleri_premium
  on public.fon_kalemleri
  for select to authenticated
  using (durum = 'gecti' and (select public.premium_icerik_gorebilir()));

revoke all on table public.fon_kalemleri from public, anon, authenticated;
grant select on table public.fon_kalemleri to authenticated;
grant select, insert, update, delete on table public.fon_kalemleri to service_role;

-- ── 2) KAP liste taraması (yalnız sunucu) ──────────────────────────────────
-- KAP'ın liste ucu (`disclosure/funds/byCriteria`) sayfalama vermiyor ve
-- yanıtı 2.000 satırda kesiyor; günde ~1 MB. Her turda aynı günleri
-- yeniden indirmek KAP'a gereksiz yük (ve 429). Gün BİTTİKTEN sonra
-- taranmış bir gün kesindir, bir daha istenmez; yalnız Portföy Dağılım
-- Raporu satırları (kod, bildirim no, yıl, ay) saklanır.
create table if not exists public.fon_kalem_taramasi (
  gun      date primary key,
  -- [{fon_kodu, index, yil, ay}]
  pdr      jsonb not null default '[]'::jsonb check (jsonb_typeof(pdr) = 'array'),
  satir    integer not null default 0 check (satir >= 0),
  -- Yanıt 2.000 satırda kesildi: o günün erken bildirimleri görünmeyebilir.
  kesik    boolean not null default false,
  tarandi  timestamptz not null default now()
);

comment on table public.fon_kalem_taramasi is
  'fon-kalem-raporu KAP liste onbellegi (0132). Yalniz service_role; istemciye kapali.';

alter table public.fon_kalem_taramasi enable row level security;
alter table public.fon_kalem_taramasi force row level security;
revoke all on table public.fon_kalem_taramasi from public, anon, authenticated;
grant select, insert, update, delete on table public.fon_kalem_taramasi to service_role;

-- ── 3) Tetikleyici ──────────────────────────────────────────────────────────
-- Ayrı secret açılmadı: öteki yapay zekâ işi (`analiz-hazirla`, 0117) ile
-- aynı secret; ikisi de modele kamu verisi gönderen cron.
create or replace function public.trigger_fon_kalem_raporu()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('fon-kalem-raporu'),
    headers := public.cron_headers('price_alerts_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    -- Tur başına birkaç fon: KAP (3 sn aralık) + TEFAS + model çağrısı.
    timeout_milliseconds := 150000
  );
end;
$$;

revoke all on function public.trigger_fon_kalem_raporu() from public, anon, authenticated;

-- Raporlar ay sonundan ~6 iş günü sonra (Eylül 2026 → 8 Ekim akşamı).
-- Ayın 8-12'si, günde dört tur (TR 08:15, 12:15, 16:15, 20:15): tur başına
-- az fon işlenir (edge function süre sınırı); işlenen ya da reddedilen
-- (fon, ay) bir daha denenmez, liste taraması önbellekte.
select cron.unschedule(jobid) from cron.job where jobname = 'fon-kalem-raporu';
select cron.schedule('fon-kalem-raporu', '15 5,9,13,17 8-12 * *',
  $$select public.trigger_fon_kalem_raporu()$$);

-- İki sunucu birebir; tek bilinçli fark cron `active` (0119 kuralı).
do $$
begin
  if exists (select 1 from cron.job where jobname <> 'fon-kalem-raporu')
     and not exists (select 1 from cron.job where jobname <> 'fon-kalem-raporu' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname = 'fon-kalem-raporu';
    raise notice '0132: projede tum cron isleri kapali — fon-kalem-raporu da kapali kuruldu.';
  end if;
end $$;

-- ── 4) Doğrulama ────────────────────────────────────────────────────────────
do $$
begin
  if not has_table_privilege('authenticated', 'public.fon_kalemleri', 'SELECT') then
    raise exception '0132: authenticated icin fon_kalemleri SELECT GRANT eksik';
  end if;
  if has_table_privilege('authenticated', 'public.fon_kalemleri', 'INSERT')
     or has_table_privilege('authenticated', 'public.fon_kalemleri', 'UPDATE')
     or has_table_privilege('authenticated', 'public.fon_kalemleri', 'DELETE') then
    raise exception '0132: authenticated fon_kalemleri tablosuna YAZAMAMALI';
  end if;
  if has_table_privilege('anon', 'public.fon_kalemleri', 'SELECT') then
    raise exception '0132: anon fon_kalemleri tablosunu okuyamamali';
  end if;
  if has_table_privilege('authenticated', 'public.fon_kalem_taramasi', 'SELECT')
     or has_table_privilege('anon', 'public.fon_kalem_taramasi', 'SELECT') then
    raise exception '0132: fon_kalem_taramasi istemciye kapali olmali';
  end if;
  if (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public'
         and c.relname in ('fon_kalemleri', 'fon_kalem_taramasi')
         and c.relrowsecurity and c.relforcerowsecurity) <> 2 then
    raise exception '0132: RLS/FORCE RLS acik degil';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'fon_kalemleri') <> 1 then
    raise exception '0132: fon_kalemleri yalniz Premium select politikasini tasimali';
  end if;
  if not exists (select 1 from pg_policies
                  where schemaname = 'public' and tablename = 'fon_kalemleri'
                    and cmd = 'SELECT' and qual like '%premium_icerik_gorebilir%'
                    and qual like '%gecti%') then
    raise exception '0132: fon_kalemleri politikasi Premium + durum=gecti sormuyor';
  end if;
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'fon_kalem_taramasi') then
    raise exception '0132: fon_kalem_taramasi politika tasimamali (yalniz service_role)';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_fon_kalem_raporu()', 'EXECUTE')
     or has_function_privilege('anon', 'public.trigger_fon_kalem_raporu()', 'EXECUTE') then
    raise exception '0132: trigger_fon_kalem_raporu istemciden cagrilabilir olmamali';
  end if;
  if not exists (select 1 from cron.job where jobname = 'fon-kalem-raporu') then
    raise exception '0132: fon-kalem-raporu cron isi kurulmadi';
  end if;
  raise notice '0132 tamam: fon_kalemleri + fon_kalem_taramasi + cron kuruldu.';
end $$;
