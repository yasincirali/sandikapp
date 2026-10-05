-- 0113 — kripto-fiyat dakikada bir yerine iki dakikada bir (2026-10-05)
--
-- ⚠️ NUMARA GEÇİCİ (0109 notu): dağıtımdan ÖNCE iki sunucunun defterine
-- bakılır; doluysa sıradaki boş numaraya yeniden adlandırılır.
--
-- ## İstek
-- Kullanıcı (2026-10-05): Supabase Free plan "Log Ingestion 1.22 / 1 GB"
-- aşıldı; rahatlatmak için ne yapalım.
--
-- ## Neden bu iş
-- Log hacmi kodun `console.log`'undan değil, ÇAĞRI SAYISINDAN geliyor:
-- her cron turu Postgres logunda pg_cron/pg_net satırları, edge logunda
-- istek satırı ve function logunda açılış/kapanış olayları bırakır.
-- `kripto-fiyat` (0074, her dakika, 7/24) günde 1.440 tur ile sunucudaki
-- zamanlanmış çağrıların ~%78'i. Sıradaki `yurt-ici-kotasyon` 288 tur.
-- İki dakikaya çekmek bu tek işin log, cron geçmişi ve edge çağrı
-- payını yarıya indirir (günde −720 tur).
--
-- ## Ekranda ne değişir
-- Kripto fiyatı en çok ~2 dakika yaşlı olur (önce ~1). İstemci değişmez:
-- "Gecikmeli" etiketi `guncellendi` 10 dakikayı geçince çıkar
-- (`kripto_gecikme_etiketi.dart`), iki dakikalık ritim bunun çok altında.
-- Uygulamanın 30 sn'lik nabzı sunucudaki son satırı okumaya devam eder.
-- Fiyat alarmları 30 dakikada bir koşar; etkilenmez. Binance ağırlığı da
-- yarıya iner.
--
-- ## Geri alma
-- `select cron.alter_job(jobid, schedule := '* * * * *') from cron.job
--  where jobname = 'kripto-fiyat';` — yeni migration olarak.
--
-- `cron.alter_job` (0082/0093/0110 notu): `active` bayrağı korunur —
-- Frankfurt'ta iş geçişe kadar bilinçli KAPALI kalır.
select cron.alter_job(jobid, schedule := '*/2 * * * *')
  from cron.job where jobname = 'kripto-fiyat';

-- ── Doğrulama ──────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from cron.job
                  where jobname = 'kripto-fiyat'
                    and schedule = '*/2 * * * *') then
    raise exception 'kripto-fiyat takvimi */2 * * * * olmali';
  end if;
end $$;
