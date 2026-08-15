-- Live Activity push döngüsü.
--
-- Seans içinde (hafta içi 10:00–18:10 TR) her 5 dakikada bir
-- `push-live-activity` edge function'ı tetiklenir; o da aktif oturumlara
-- APNs üzerinden güncelleme gönderir.
--
-- NEDEN 5 DAKİKA:
--   * "Canlı" vaadini karşılayacak kadar sık. 15 dakikada bir güncellenen
--     bir kilit ekranı kullanıcıya donuk hissettiriyordu.
--   * APNs kotasını yakmayacak kadar seyrek. Live Activity push'u
--     saatte ~12 istek/oturum demek; Apple'ın "makul kullanım" sınırının
--     çok altında.
--   * Seans dışında HİÇ çalışmaz (cron ifadesi saat aralığı içerir) —
--     gece boyunca boş sorgu atmak pil ve kota israfıdır.
--
-- pg_cron UTC çalışır. TR = UTC+3, yaz saati uygulanmıyor:
--   10:00 TR = 07:00 UTC
--   18:10 TR = 15:10 UTC
-- Bu yüzden aralık `7-15` (UTC) olarak yazılır.

set search_path = public, vault, net;

create or replace function trigger_live_activity_push()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  function_url text :=
    'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/push-live-activity';
  cron_secret text;
begin
  -- Sır Vault'ta; edge function aynı değeri bekler.
  select decrypted_secret into cron_secret
  from vault.decrypted_secrets
  where name = 'live_activity_cron_secret'
  limit 1;

  if cron_secret is null then
    raise exception 'Vault secret live_activity_cron_secret bulunamadi';
  end if;

  -- Aktif oturum yoksa hiç HTTP turu atma. Seans içinde bile çoğu
  -- kullanıcının açık oturumu olmaz; boş çağrı edge function'ı
  -- gereksiz uyandırır.
  if not exists (
    select 1 from live_activity_sessions where expires_at > now()
  ) then
    return;
  end if;

  -- net.http_post asenkrondur: isteği kuyruğa alır, yanıtı beklemez.
  perform net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || cron_secret
    ),
    body := '{}'::jsonb
  );
end;
$$;

-- Eski zamanlamayı temizle (idempotent yeniden çalıştırma için).
select cron.unschedule('live-activity-push')
where exists (
  select 1 from cron.job where jobname = 'live-activity-push'
);

-- HER GÜN, HER SAAT, 5 dakikada bir.
--
-- Saat aralığı KASITLI OLARAK dar tutulmuyor: kullanıcı gösterim
-- penceresini Ayarlar'dan değiştirebiliyor (gece piyasa izleyen ya da
-- hafta sonu kripto takip eden biri için sabit BIST saati anlamsız).
-- Cron'u BIST saatine kilitlemek, o kullanıcıların kilit ekranını
-- sessizce donuk bırakırdı.
--
-- Maliyet endişesi yersiz: fonksiyon ilk iş olarak aktif oturum var mı
-- diye bakar ve yoksa HTTP turu bile atmaz (yukarıdaki erken çıkış).
-- Gece boyunca bu, saniyenin altında süren tek bir indeks sorgusudur.
select cron.schedule(
  'live-activity-push',
  '*/5 * * * *',
  $$select trigger_live_activity_push()$$
);

-- Süresi dolmuş oturumları gecelik temizle.
--
-- Ayrı bir iş: push döngüsü yalnızca aktif satırları okur, ölüleri
-- silmez. Temizlik olmadan tablo her gün kullanıcı sayısı kadar çöp
-- satır büyür.
select cron.unschedule('live-activity-cleanup')
where exists (
  select 1 from cron.job where jobname = 'live-activity-cleanup'
);

select cron.schedule(
  'live-activity-cleanup',
  '0 21 * * *',
  $$select cleanup_expired_live_activities()$$
);
