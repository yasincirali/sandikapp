-- 0100 — Live Activity push döngüsü dakikada bir (2026-10-03)
--
-- Kullanıcı kararı: "Canlı aktiviteler her zaman 1 dk'da bir performans
-- günlükle eş olmalı." Uygulama kapalıyken kilit ekranını yalnızca sunucu
-- tazeler; 0033'ten beri `*/5` idi ve yazılı metni olduğu gibi basıyordu.
--
-- Bu migration YALNIZCA takvimi değiştirir. Kadansın kendisi fonksiyonda:
-- `push-live-activity` tarifi OLMAYAN satırı (eski sürüm ya da
-- `canli_etkinlik_dakikalik` bayrağı kapalı istemci) yine yalnızca 5'in
-- katı dakikalarda push'lar — o kullanıcılar için APNs trafiği ve görünen
-- davranış değişmez. Tarifli satır her dakika canlı kotasyonla ileri
-- taşınır (`_shared/canli_etkinlik.ts`).
--
-- YAYIN SIRASI: önce fonksiyon, sonra bu migration. Eski fonksiyon dakikalık
-- çağrıda her satırı her dakika aynı metinle push'lardı (zararsız ama boşa
-- APNs bütçesi).
--
-- Maliyet: `trigger_live_activity_push` aktif oturum yoksa HTTP turu bile
-- atmaz (0033/0076); gece boyunca dakikada bir indeks sorgusu.
--
-- `cron.alter_job` ile (0082 ile aynı gerekçe): `cron.schedule` işi yeniden
-- kurar ve `active` bayrağını sıfırlayabilir; Frankfurt'ta işler geçişe kadar
-- bilinçli KAPALI, bu bayrak korunmalı.

select cron.alter_job(jobid, schedule := '* * * * *')
  from cron.job where jobname = 'live-activity-push';

-- ── Doğrulama ──────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from cron.job
                  where jobname = 'live-activity-push'
                    and schedule = '* * * * *') then
    raise exception 'live-activity-push takvimi * * * * * olmali';
  end if;
end $$;
