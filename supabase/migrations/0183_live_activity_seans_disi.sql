-- 0183 — Canlı Etkinlik: seans içinde dakikada bir, dışında 5 dakikada bir
-- (2026-11-13)
--
-- ## Karar
-- yasin (2026-11-13, karar kartı "Canlı Etkinlik borsa kapalıyken 5
-- dakikada bir mi güncellensin?" → "Evet, seans dışı 5 dk"). 0100'ün
-- "her zaman 1 dk" kararını seans DIŞI için değiştirir.
--
-- ## Neden
-- Log Ingestion 0,94 / 1 GB (0182 notu). Son 24 saat ölçümü: kilit ekranı
-- push'u günde 1.438 edge çağrısı ve ~5.500 REST isteği
-- (`live_activity_sessions`) — toplam log satırlarının ~dörtte biri, yalnız
-- 1–2 açık oturum için. Oturumlar 11 saat sürüyor ve geceye taşıyor; BIST
-- ve TEFAS seans dışında değişmez, kripto/altın 5 dakikalık adımla yeter.
--
-- ## Yeni ritim (cron saatleri UTC; TR = UTC+3)
-- * live-activity-push:        `* 7-15 * * 1-5`  hafta içi TR 10:00–18:59
--   (BIST 10:00–18:10 + kapanış sonrası)
-- * live-activity-push-gece:   `*/5 0-6,16-23 * * *` her gün seans dışı
-- * live-activity-push-hsonu:  `*/5 7-15 * * 0,6`  hafta sonu gündüz
-- Üç ifade ayrık: aynı dakikada iki tur koşmaz. Fonksiyon tarifsiz satırı
-- zaten yalnız 5'in katı dakikalarda push'lar (0100); seans dışı ritim onunla
-- hizalı. Günde 1.440 → ~840 tur hafta içi, 288 hafta sonu.
--
-- Ek işler ana işin komutunu ve `active` bayrağını kopyalar (0182 deseni);
-- sarmalayıcı oturum yoksa yine HTTP atmaz.
--
-- ## Geri alma (yeni migration olarak)
--   select cron.unschedule(jobid) from cron.job
--    where jobname in ('live-activity-push-gece', 'live-activity-push-hsonu');
--   select cron.alter_job(jobid, schedule := '* * * * *') from cron.job where jobname = 'live-activity-push';

do $$
declare
  r record;
begin
  if not exists (select 1 from cron.job where jobname = 'live-activity-push') then
    raise notice '0183: live-activity-push isi yok, atlandi.';
    return;
  end if;
  for r in
    select * from (values
      ('live-activity-push-gece',  '*/5 0-6,16-23 * * *'),
      ('live-activity-push-hsonu', '*/5 7-15 * * 0,6')
    ) as t(ad, takvim)
  loop
    perform cron.unschedule(jobid) from cron.job where jobname = r.ad;
    perform cron.schedule(r.ad, r.takvim,
      (select command from cron.job where jobname = 'live-activity-push'));
    perform cron.alter_job(job_id := g.jobid, active := a.active)
       from cron.job g, cron.job a
      where g.jobname = r.ad and a.jobname = 'live-activity-push';
  end loop;
  perform cron.alter_job(job_id := jobid, schedule := '* 7-15 * * 1-5')
     from cron.job where jobname = 'live-activity-push';
end $$;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from cron.job where jobname = 'live-activity-push')
     and (select count(*) from cron.job g join cron.job a on a.jobname = 'live-activity-push'
           where a.schedule = '* 7-15 * * 1-5'
             and g.command = a.command and g.active = a.active
             and ((g.jobname = 'live-activity-push-gece' and g.schedule = '*/5 0-6,16-23 * * *')
               or (g.jobname = 'live-activity-push-hsonu' and g.schedule = '*/5 7-15 * * 0,6'))) <> 2 then
    raise exception '0183: live-activity-push seans ritmi kurulmadi';
  end if;
end $$;
