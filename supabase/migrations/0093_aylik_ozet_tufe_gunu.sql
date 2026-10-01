-- 0093 — Aylık özet TÜFE gününe taşındı (2026-10-01)
--
-- Kullanıcı bildirimi (ekran görüntüsüyle): 1 Ekim'de giden "Eylül özeti"
-- push'u "Enflasyon farkı Özet'te" diyordu; Özet'te Eylül değil AĞUSTOS
-- enflasyonu vardı, çünkü TÜİK Eylül TÜFE'sini 3 Ekim'de açıklıyor.
-- Kullanıcı kararı: aylık özet TÜFE açıklandıktan sonra, ayın TÜFE'siyle
-- TEK push olarak gitsin.
--
-- 1) `monthly-summary`: ayın 1'i 06:30 UTC → ayın 3'ü ve 4'ü 07:30 UTC
--    (TR 10:30), `fetch-inflation`'dan (07:05) sonra. Ayın TÜFE'si tabloda
--    yoksa fonksiyon hiçbir şey göndermez; 4'ündeki koşu yeniden dener.
--    Ay başına tek koşuyu fonksiyon `inflation_push_log` kilidiyle sağlar.
-- 2) `calendar-nudge-inflation(-retry)`: TAKVİMDEN KALKAR. Aynı gün 10:15'te
--    ikinci bir TÜFE push'u gönderiyordu (ve `fetch-inflation` 10:05'te
--    üçüncüsünü). Ulusal oran artık aylık özetin başlığında; özeti kapatan
--    kullanıcıya fonksiyon yalnızca TÜFE mesajını gönderir. `calendar-nudge`
--    fonksiyonu ve yıl sonu anı (0087, `calendar-nudge-year-end`) duruyor.
--
-- `cron.alter_job` ile (0082 notu): `cron.schedule` `active` bayrağını
-- sıfırlayabilir; Frankfurt'ta işler geçişe kadar bilinçli KAPALI.
--
-- Prod güvenliği: istemci tarafında değişiklik gerekmez — push türü
-- (`monthly_summary`, `inflation_day`) ve hedef ekran aynı. Fonksiyon
-- deploy'u bu migration'dan önce giderse 1'indeki koşu TÜFE bulamaz ve
-- sessiz kalır; migration önce giderse eski fonksiyon 3'ünde eski mesajı
-- gönderir. İkisi de çift push üretmez.

select cron.alter_job(jobid, schedule := '30 7 3,4 * *')
  from cron.job where jobname = 'monthly-summary';

select cron.unschedule(jobid) from cron.job
 where jobname in ('calendar-nudge-inflation', 'calendar-nudge-inflation-retry');

-- ── Doğrulama ──────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from cron.job
                  where jobname = 'monthly-summary'
                    and schedule = '30 7 3,4 * *') then
    raise exception 'monthly-summary takvimi 30 7 3,4 * * olmali';
  end if;
  if exists (select 1 from cron.job
              where jobname in ('calendar-nudge-inflation',
                                'calendar-nudge-inflation-retry')) then
    raise exception 'calendar-nudge TÜFE kancasi takvimden kalkmadi';
  end if;
end $$;
