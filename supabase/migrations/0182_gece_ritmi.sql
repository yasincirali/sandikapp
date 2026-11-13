-- 0182 — Gece ritmi: kripto ve yurt içi kotasyon gece seyrek, rate-limit
-- temizliği günde bir (2026-11-13)
--
-- ## İstek
-- yasin (2026-11-13): Supabase Free "Log Ingestion 0,94 / 1 GB"; "bu
-- kayıtları da azaltalım, müşteri ihtiyaçlarına göre cron joblarda bir
-- optimizasyon yap".
--
-- ## Neden bu üç iş
-- 0113 notu geçerli: log hacmi `console.log`'dan değil ÇAĞRI SAYISINDAN
-- gelir (edge fonksiyonları yalnız hata yazıyor; 13 Kas kontrolü). Canlı
-- cron sayımı (13 Kas, son 24 saat): kripto-fiyat 720, yurt-ici-kotasyon
-- 288 tur — edge'e giden zamanlanmış çağrıların büyük kısmı. İkisi de 7/24
-- aynı ritimde koşuyor; oysa TR 00:00–06:59 arası (UTC 21:00–03:59)
-- uygulamayı açan neredeyse yok, fiyat alarmları zaten koşmuyor (pencere
-- TR 08:00–21:30, 0046/0168) ve sabah ilk açılışta fiyat yine taze.
--
-- ## Yeni ritim (cron saatleri UTC)
-- * kripto-fiyat: gündüz `*/2 4-20` (aynı), gece yeni `kripto-fiyat-gece`
--   `*/5 0-3,21-23`. 5 dakika, "Gecikmeli" etiketinin 10 dakikalık
--   eşiğinin altında (`KriptoFiyat.bayatlikEsigi`) → gece açan kullanıcı
--   da etiket görmez. Günde 720 → 594 tur (−126).
-- * yurt-ici-kotasyon: gündüz `*/5 4-20` (aynı), gece yeni
--   `yurt-ici-kotasyon-gece` `*/10 0-3,21-23`. Altının GÜNLÜK grafiği gece
--   saatlerinde 10 dakikalık noktalarla çizilir (5 dakikalık kova düzeni
--   aynı; boş kova çizgiyi kırmaz, iki nokta arası düz bağlanır). Hafta
--   sonu kaydı — 0101'in asıl nedeni — gündüz 5 dakikada sürer.
--   Günde 288 → 246 tur (−42).
-- * purge-rate-limit-attempts: saatte bir → günde bir (`17 3 * * *`).
--   Silme kuralı aynı (24 saatten eski deneme); satır en çok ~48 saat
--   yaşar, sayaç `p_window_seconds` ile zaman damgasına bakar, birikmiş
--   eski satır sonucu değiştirmez. Günde 24 → 1 tur (−23).
--
-- ## Neden iki ayrı iş, fonksiyonda saat filtresi değil
-- 0168 kararıyla aynı: ritim cron tablosunda okunur, fonksiyon saat
-- bilmez. Gece işi gündüz işinin KOMUTUNU ve `active` bayrağını aynen
-- kopyalar: Vault'lu sarmalayıcı (0076) değişmez, iş kapalıysa gece işi de
-- kapalı doğar.
--
-- ## Değişmeyen (bilerek)
-- * live-activity-push her dakika (yasin kararı, 0100). Oturum yoksa HTTP
--   atmadan döner; edge logu üretmez.
-- * check-price-alerts(-hizli): alarmın geç gelmesi doğrudan müşteri
--   şikâyeti (0168); pencere zaten gece kapalı.
--
-- ## Geri alma (yeni migration olarak)
--   select cron.unschedule(jobid) from cron.job
--    where jobname in ('kripto-fiyat-gece', 'yurt-ici-kotasyon-gece');
--   select cron.alter_job(jobid, schedule := '*/2 * * * *') from cron.job where jobname = 'kripto-fiyat';
--   select cron.alter_job(jobid, schedule := '*/5 * * * *') from cron.job where jobname = 'yurt-ici-kotasyon';
--   select cron.alter_job(jobid, schedule := '17 * * * *') from cron.job where jobname = 'purge-rate-limit-attempts';
--
-- Eski sürümler: istemci tarafı yok; tablolar ve RPC'ler aynı.

do $$
declare
  r record;
  gece text;
begin
  for r in
    select * from (values
      ('kripto-fiyat',      '*/2 4-20 * * *', 'kripto-fiyat-gece',      '*/5 0-3,21-23 * * *'),
      ('yurt-ici-kotasyon', '*/5 4-20 * * *', 'yurt-ici-kotasyon-gece', '*/10 0-3,21-23 * * *')
    ) as t(ad, gunduz, gece_ad, gece_takvim)
  loop
    if not exists (select 1 from cron.job where jobname = r.ad) then
      raise notice '0182: % isi yok, atlandi.', r.ad;
      continue;
    end if;
    -- Tekrar koşulursa (yerel yığın) gece işi yeniden kurulur.
    perform cron.unschedule(jobid) from cron.job where jobname = r.gece_ad;
    perform cron.schedule(r.gece_ad, r.gece_takvim,
                          (select command from cron.job where jobname = r.ad));
    perform cron.alter_job(job_id := g.jobid, active := a.active)
       from cron.job g, cron.job a
      where g.jobname = r.gece_ad and a.jobname = r.ad;
    perform cron.alter_job(job_id := jobid, schedule := r.gunduz)
       from cron.job where jobname = r.ad;
  end loop;

  perform cron.alter_job(job_id := jobid, schedule := '17 3 * * *')
     from cron.job where jobname = 'purge-rate-limit-attempts';
end $$;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from cron.job where jobname = 'kripto-fiyat')
     and not exists (
       select 1 from cron.job g join cron.job a on a.jobname = 'kripto-fiyat'
        where g.jobname = 'kripto-fiyat-gece'
          and g.schedule = '*/5 0-3,21-23 * * *'
          and a.schedule = '*/2 4-20 * * *'
          and g.command = a.command and g.active = a.active) then
    raise exception '0182: kripto-fiyat gunduz/gece ritmi kurulmadi';
  end if;
  if exists (select 1 from cron.job where jobname = 'yurt-ici-kotasyon')
     and not exists (
       select 1 from cron.job g join cron.job a on a.jobname = 'yurt-ici-kotasyon'
        where g.jobname = 'yurt-ici-kotasyon-gece'
          and g.schedule = '*/10 0-3,21-23 * * *'
          and a.schedule = '*/5 4-20 * * *'
          and g.command = a.command and g.active = a.active) then
    raise exception '0182: yurt-ici-kotasyon gunduz/gece ritmi kurulmadi';
  end if;
  if exists (select 1 from cron.job
              where jobname = 'purge-rate-limit-attempts'
                and schedule <> '17 3 * * *') then
    raise exception '0182: purge-rate-limit-attempts gunde bire inmedi';
  end if;
end $$;
