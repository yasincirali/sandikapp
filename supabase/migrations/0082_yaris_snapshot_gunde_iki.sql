-- 0082 — Yarış snapshot'ı günde iki kez: 10:00 ve 15:00 TR (2026-09-29)
--
-- 0081 günde bir (18:40 TR) koşuyordu. Kullanıcı kararı: doğruluk için günde
-- iki koşu — 10:00 (BIST açılışı, dünkü kapanış + sabah kuru/altını) ve
-- 15:00 (seans ortası). RPC'ler kullanıcı başına son 24 saatteki EN YENİ
-- satırı okur, uygunluk kuralı (0059) FARKLI GÜN sayar: iki koşu havuzu
-- şişirmez, yalnız değeri tazeler. Satır sayısı 8/kullanıcı/gün; saklama
-- (400 gün) bunu rahat taşır.
--
-- `cron.alter_job` ile: `cron.schedule` aynı adı yeniden kurar ve `active`
-- bayrağını sıfırlayabilir; Frankfurt'ta işler geçişe kadar bilinçli KAPALI
-- (`active=false`), bu bayrak korunmalı. alter_job yalnızca takvimi değiştirir.
-- TR = UTC+3, DST yok → 07:00 ve 12:00 UTC.

select cron.alter_job(jobid, schedule := '0 7,12 * * *')
  from cron.job where jobname = 'leaderboard-snapshot';

-- ── Doğrulama ──────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from cron.job
                  where jobname = 'leaderboard-snapshot'
                    and schedule = '0 7,12 * * *') then
    raise exception 'leaderboard-snapshot takvimi 0 7,12 * * * olmali';
  end if;
end $$;
