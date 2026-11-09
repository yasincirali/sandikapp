-- 0164 — Saatlik kripto hacim işi 6 saatte bir (2026-10-21)
--
-- ## Neden (müşteri raporu 2026-10-21 21:15 #3; yasin "yapılmayan yap'ları yap")
-- `kripto-hacim-saatlik` (0115) saatte bir, günde 24 kez Binance'ten mum
-- çekip `kripto_hacim_saatlik`'a yazıyor. Bu tabloyu okuyan yüzey (balina /
-- hacim radarı) Premium ve paywall kapalıyken yalnız yöneticiye görünüyor:
-- kimsenin görmediği bir kart için günde 24 edge function çağrısı, ücretsiz
-- plan kotası ve Binance hız sınırı.
--
-- ## Neden durdurma değil, 6 saat
-- Her tur son 48 saatlik kapanmış mumları yeniden yazar (upsert): 6 saatlik
-- ritimde VERİ KAYBI YOK, yalnız tazelik 1 saatten 6 saate iner. Durdurmak
-- 8 günlük saklama penceresini boşaltır; paywall açıldığı gün kart boş
-- açılırdı. Dakika (7.) aynı kalır: saat başı kapanan mum yayınlanmış olur
-- ve 5 dakikalık fiyat alarmıyla çakışmaz.
--
-- ## Paywall açılınca
-- Kart herkese açılınca saatlik ritme dönmek ayrı bir migration'dır
-- (`'7 * * * *'`). `YAPMAN_GEREKENLER.md` paywall açılış adımlarına yazıldı.
--
-- ## Eski sürümler / iki sunucu
-- İstemci tarafı yok; yalnız zamanlama. `alter_job` işin `active` bayrağına
-- DOKUNMAZ: Tokyo'da kapalı olan iş kapalı kalır (tek bilinçli fark).
-- İş yoksa (taze yığın, 0115 öncesi) hiçbir şey yapılmaz.

do $$
declare
  j bigint;
begin
  select jobid into j from cron.job where jobname = 'kripto-hacim-saatlik';
  if j is null then
    raise notice '0164: kripto-hacim-saatlik isi yok, atlandi.';
    return;
  end if;
  perform cron.alter_job(job_id := j, schedule := '7 */6 * * *');
end $$;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from cron.job
              where jobname = 'kripto-hacim-saatlik'
                and schedule <> '7 */6 * * *') then
    raise exception '0164: kripto-hacim-saatlik zamanlamasi 6 saate inmedi';
  end if;
end $$;
