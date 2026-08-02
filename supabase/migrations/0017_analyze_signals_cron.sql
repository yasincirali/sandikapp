-- analyze-signals edge function'ını zamanlanmış olarak tetikler.
--
-- Sinyal bildirimleri sunucu taraflıdır: cron → edge function → TA → FCM.
-- Cihazın açık olması gerekmez, uygulama kapalıyken de bildirim gider.
--
-- Vault'ta `analyze_signals_cron_secret` adıyla, edge function'daki
-- ANALYZE_SIGNALS_CRON_SECRET ile AYNI string bulunmalıdır. Eşleşmezse
-- fonksiyon 401 "Yetkisiz cron cagrisi" döner.

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net;

create or replace function public.trigger_analyze_signals(slot text)
returns void
language plpgsql
security definer
-- search_path sabitleniyor: security definer fonksiyonda arama yolu
-- kaçırılırsa yetki yükseltme vektörü olur.
set search_path = public, vault, net
as $$
declare
  function_url text := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/analyze-signals';
  cron_secret  text;
begin
  select decrypted_secret into cron_secret
  from vault.decrypted_secrets
  where name = 'analyze_signals_cron_secret';

  if cron_secret is null then
    raise exception 'Vault secret analyze_signals_cron_secret bulunamadi';
  end if;

  -- net.http_post asenkrondur: isteği kuyruğa alır, yanıtı beklemez.
  -- Yanıtlar net._http_response tablosunda görülebilir.
  perform net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || cron_secret
    ),
    body := jsonb_build_object('slot', slot)
  );
end;
$$;

-- Fonksiyon yalnızca cron (postgres) tarafından çağrılmalı; istemciye açma.
revoke all on function public.trigger_analyze_signals(text) from public, anon, authenticated;

-- Yeniden çalıştırılabilir olsun: varsa önce kaldır.
-- (cron.unschedule bilinmeyen job adında hata verir, o yüzden koşullu.)
select cron.unschedule(jobid) from cron.job
 where jobname in ('analyze-signals-morning', 'analyze-signals-afternoon');

-- pg_cron UTC ile çalışır. TR 11:00 = 08:00 UTC, TR 15:00 = 12:00 UTC.
select cron.schedule('analyze-signals-morning', '0 8 * * *',
  $$select public.trigger_analyze_signals('morning')$$);
select cron.schedule('analyze-signals-afternoon', '0 12 * * *',
  $$select public.trigger_analyze_signals('afternoon')$$);
