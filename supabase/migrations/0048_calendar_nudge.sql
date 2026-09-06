-- 0048_calendar_nudge.sql
-- ============================================================
-- Takvim kancası: TÜİK enflasyon açıklaması.
--
-- TÜİK her ayın 3'ünde saat 10:00'da açıklıyor. Bildirim 10:15'te gider —
-- rakamın basına düşmesi ve tabloya girilmesi için çeyrek saat.
--
-- Bu, uydurulmuş bir hatırlatma DEĞİL: o sabah Türkiye'de zaten milyonlarca
-- kişi "ne kadar oldu?" diye bakıyor. Bildirim o merakı karşılıyor.
--
-- Fonksiyon veri yoksa SESSİZCE hiçbir şey göndermez (inflation_index boş
-- ya da bu ayın satırı henüz girilmemişse).
-- ============================================================

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net;

create or replace function public.trigger_calendar_nudge()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  function_url text := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/calendar-nudge';
  cron_secret  text;
begin
  select decrypted_secret into cron_secret
  from vault.decrypted_secrets
  where name = 'calendar_nudge_cron_secret';

  if cron_secret is null then
    raise exception 'Vault secret calendar_nudge_cron_secret bulunamadi';
  end if;

  perform net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || cron_secret
    ),
    body := jsonb_build_object('occasion', 'inflation_day')
  );
end;
$$;

revoke all on function public.trigger_calendar_nudge() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job
 where jobname in ('calendar-nudge-inflation', 'calendar-nudge-inflation-retry');

-- pg_cron UTC. TR 10:15 = 07:15 UTC, her ayın 3'ü.
select cron.schedule('calendar-nudge-inflation', '15 7 3 * *',
  $$select public.trigger_calendar_nudge()$$);

-- İkinci deneme: ayın 4'ü TR 10:15.
--
-- Endeks ELLE dolduruluyor; 3'ünde veri girilmemişse fonksiyon sessizce
-- hiçbir şey göndermez ve o ayın kancası tamamen kaçardı. İkinci tur,
-- veri bir gün geç girildiğinde bildirimi kurtarır. Aynı ay için iki kez
-- gönderim OLMAZ: ikinci tur çalıştığında tablodaki son satır zaten
-- beklenen ay olur ve ilk tur da göndermiş olsaydı... — bu senaryoyu
-- fonksiyon ELEMEZ, bu yüzden bkz. aşağıdaki uyarı.
--
-- ⚠️ BİLİNEN AÇIK: veri 3'ünde zamanında girilirse İKİ bildirim gider
-- (3'ünde ve 4'ünde). Çözüm bir gönderim defteri (daily_brief_log gibi);
-- TECHNICAL_DEBT.md'ye yazıldı. Şimdilik ikinci tur KAPALI bırakıldı —
-- kaçırılan bir kanca, çift bildirimden daha ucuz.
-- select cron.schedule('calendar-nudge-inflation-retry', '15 7 4 * *',
--   $$select public.trigger_calendar_nudge()$$);
