-- 0110 — TÜFE çekimi ve aylık özet hafta sonuna takılmasın (2026-10-05)
--
-- ⚠️ NUMARA GEÇİCİ (0109 notu): dağıtımdan ÖNCE iki sunucunun defterine
-- bakılır; 0110 doluysa sıradaki boş numaraya yeniden adlandırılır. Gövde
-- yalnız takvim değiştirir, numaradan bağımsızdır.
--
-- ## Arıza
-- Kullanıcı (2026-10-05): Eylül TÜFE'si açıklandı ama uygulamadaki aylık
-- enflasyon karşılaştırması hâlâ Ağustos'u gösteriyor.
--
-- Kök neden takvim: `fetch-inflation` yalnız ayın 3'ü ve 4'ü 07:05 UTC'de
-- koşuyordu (0053), aylık özet de yalnız 3'ü ve 4'ü 07:30'da (0093).
-- Ekim 2026'da 3'ü CUMARTESİ, 4'ü PAZAR. TÜİK hafta sonuna denk gelen
-- bülteni ilk iş gününe kaydırıyor (Ocak 2024, Ağustos 2025 örnekleri) ve
-- EVDS seriyi iş gününde yayımlıyor; iki tur da `no_new_data` döndü ve
-- bir sonraki deneme KASIM'ın 3'üydü. Tablo Ağustos'ta kaldı; istemci
-- (`InflationService`, eksik ayda 30 dk'da bir yeniden sorar) tablodaki
-- son ayı doğru gösteriyor. Aylık özet push'u da aynı sebeple gitmedi:
-- ayın TÜFE'si yokken `tufe_bekleniyor` deyip susuyor.
--
-- ## Düzeltme
-- Her iki iş de ayın 3'ü–12'si arasında HER GÜN koşar:
-- * `fetch-inflation`        07:05 UTC (TR 10:05) — bülten 10:00'da
-- * `fetch-inflation-retry`  13:05 UTC (TR 16:05) — EVDS aynı gün geç
--   yayımlarsa uygulama akşamdan önce yeni ayı görür
-- * `monthly-summary`        07:30 UTC (TR 10:30) — TÜFE'den sonra
--
-- Neden güvenli:
-- * `fetch-inflation` `period` üzerinden UPSERT eder; aynı ayı on kez
--   yazmak tek satır bırakır (TÜİK revizyonu da yakalanır). Push göndermez.
-- * `monthly-summary` ay başına TEK push'u `inflation_push_log(period)`
--   kilidiyle sağlar (0093): TÜFE yoksa kilit alınmaz ve susar, gönderdiği
--   gün kilit alınır, sonraki günler `zaten gonderildi` der.
--   `ayPenceresi` ayın hangi günü koşarsa koşsun GEÇEN ayı verir.
-- * 12'si üst sınır: bayram tatili + hafta sonu bile ilk iş gününü 12'den
--   öteye itmez; sonrası her gün boşuna EVDS çağrısı olurdu.
-- * İstemci değişmez; eski ve yeni sürümler aynı tabloyu okur.
--
-- `cron.alter_job` (0082/0093 notu): `active` bayrağı korunur — Frankfurt'ta
-- işler geçişe kadar bilinçli KAPALI kalır.

select cron.alter_job(jobid, schedule := '5 7 3-12 * *')
  from cron.job where jobname = 'fetch-inflation';

select cron.alter_job(jobid, schedule := '5 13 3-12 * *')
  from cron.job where jobname = 'fetch-inflation-retry';

select cron.alter_job(jobid, schedule := '30 7 3-12 * *')
  from cron.job where jobname = 'monthly-summary';

-- ── Doğrulama ──────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from cron.job
                  where jobname = 'fetch-inflation'
                    and schedule = '5 7 3-12 * *') then
    raise exception 'fetch-inflation takvimi 5 7 3-12 * * olmali';
  end if;
  if not exists (select 1 from cron.job
                  where jobname = 'fetch-inflation-retry'
                    and schedule = '5 13 3-12 * *') then
    raise exception 'fetch-inflation-retry takvimi 5 13 3-12 * * olmali';
  end if;
  if not exists (select 1 from cron.job
                  where jobname = 'monthly-summary'
                    and schedule = '30 7 3-12 * *') then
    raise exception 'monthly-summary takvimi 30 7 3-12 * * olmali';
  end if;
end $$;
