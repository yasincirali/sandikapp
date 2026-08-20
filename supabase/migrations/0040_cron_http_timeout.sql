-- Cron çağrılarına gerçekçi bir timeout verir.
--
-- ## Belirti
-- Sinyal turlarının çoğu `net._http_response` içinde `status_code = null`,
-- gövde boş olarak görünüyordu. "Cron çalışmıyor" ya da "fonksiyon patlıyor"
-- gibi okunuyordu; ikisi de değildi.
--
-- ## Gerçek sebep
-- `net.http_post` varsayılan olarak **5 saniye** sonra vazgeçer. Bu tur ise
-- her seferinde tam analiz yapıyor: ~10 sembol için fiyat geçmişi çekiyor,
-- varlıkları değerlendiriyor, sonra FCM'e push gönderiyor. Bu iş 5 saniyeye
-- sığmıyor.
--
-- Kritik ayrım: pg_net yalnızca YANITI beklemeyi bırakır — edge function
-- sunucuda çalışmaya devam eder ve bildirimleri gönderir. Bu yüzden sistem
-- "bazen çalışıyor" gibi görünüyordu.
--
-- Daha da yanıltıcısı, iki durum tam TERS okunuyordu:
--   * gövde DÖNEN tur  → hiç gönderim yapmayan (dolayısıyla hızlı) tur,
--   * gövde DÖNMEYEN tur → gerçekten iş yapan (dolayısıyla yavaş) tur.
-- Yani teşhis ekranındaki "başarılı" görünen satırlar aslında bildirim
-- göndermeyen turlardı.
--
-- ## Çözüm
-- 60 saniye: ölçülen tur süresinin (~6-15 sn) çok üstünde, ama pg_net
-- kuyruğunu tıkayacak kadar uzun değil. Timeout yalnızca yanıt bekleme
-- süresidir; işin kendisini kısaltmaz ya da uzatmaz.

create or replace function public.trigger_analyze_signals(slot text)
returns void
language plpgsql
security definer
set search_path to 'public', 'vault', 'net'
as $function$
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
  --
  -- timeout_milliseconds AÇIKÇA verilmeli: varsayılan 5 sn bu tur için
  -- yetersiz ve yanıtın sessizce kaybolmasına yol açıyor (yukarıya bak).
  perform net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || cron_secret
    ),
    body := jsonb_build_object('slot', slot),
    timeout_milliseconds := 60000
  );
end;
$function$;

-- Live Activity turu da aynı varsayılana tabiydi; o da APNs'e gidiyor.
do $$
declare
  tanim text;
begin
  select pg_get_functiondef(p.oid) into tanim
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where p.proname = 'trigger_live_activity_push' and n.nspname = 'public';

  if tanim is not null and tanim not like '%timeout_milliseconds%' then
    raise warning 'trigger_live_activity_push hala varsayilan 5sn timeout kullaniyor';
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'trigger_analyze_signals'
      and n.nspname = 'public'
      and pg_get_functiondef(p.oid) like '%timeout_milliseconds%'
  ) then
    raise exception 'trigger_analyze_signals timeout ayari uygulanamadi';
  end if;
end $$;
