-- Cron sırrı okumasını BELİRLENİR hale getirir.
--
-- ## Sorun
-- `0033` sırrı şöyle okuyordu:
--
--   select decrypted_secret into cron_secret
--   from vault.decrypted_secrets
--   where name = 'live_activity_cron_secret'
--   limit 1;
--
-- `limit 1` var ama `order by` YOK. Vault aynı adla birden fazla kayıt
-- tutmayı engellemez (`vault.create_secret` her çağrıda YENİ satır ekler,
-- üzerine yazmaz). Kullanıcı sırrı yenilemek için komutu ikinci kez
-- çalıştırdığında iki kayıt oluşur ve Postgres hangisini döndüreceğini
-- garanti etmez.
--
-- Sonuç sessiz ve teşhisi zor: cron ESKİ sırrı okuyup edge function'a
-- yanlış Bearer token gönderir, fonksiyon 401 döner, kilit ekranı hiç
-- güncellenmez — ama hiçbir yerde "yanlış sır" yazmaz.
--
-- ## Çözüm
-- En SON oluşturulan kayıt kullanılır (`order by created_at desc`).
-- Kullanıcı sırrı yenilediğinde beklediği davranış budur.
--
-- Ayrıca mükerrer kayıt varsa uyarı basılır: sessizce doğru olanı seçmek
-- sorunu gizler, kullanıcı Vault'unda çöp biriktiğini bilmelidir.

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
  secret_count int;
begin
  select count(*) into secret_count
  from vault.decrypted_secrets
  where name = 'live_activity_cron_secret';

  if secret_count > 1 then
    raise warning
      'live_activity_cron_secret icin % kayit var; EN YENISI kullanilacak. '
      'Temizlemek icin: delete from vault.secrets where name = %L;',
      secret_count, 'live_activity_cron_secret';
  end if;

  -- En son yazılan kayıt — `order by` olmadan hangisinin geleceği
  -- garanti değildi.
  select decrypted_secret into cron_secret
  from vault.decrypted_secrets
  where name = 'live_activity_cron_secret'
  order by created_at desc
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

comment on function trigger_live_activity_push is
  'Live Activity push dongusu. Vault sirrini EN YENI kayittan okur; '
  'mukerrer kayit varsa uyari basar.';
