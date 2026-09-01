-- Aynı cihaza ÇOKLU push gitmesini bitirir.
--
-- ## Belirti
-- Kullanıcı tek bir sinyal için aynı telefonda birden çok bildirim alıyordu.
-- `collapseLotsToPositions` (0f1ee9d) lot çoklanmasını çözmüştü — o katman
-- doğru çalışıyor. Kalan çoklanma ORADAN DEĞİL, gönderim katmanından geliyor:
--
--   for (const token of tokensByUser.get(asset.user_id) ?? []) { ... }
--
-- Kullanıcının KAÇ token'ı varsa o kadar push gider. Tablo `token` PK'lı
-- olduğu için aynı token çoğalamaz, ama AYNI CİHAZ zamanla birden çok token
-- üretir:
--   · FCM token'ı rotasyona uğrar (yeniden kurulum, veri temizleme, uzun
--     süre kullanılmama, uygulama güncellemesi),
--   · istemci eski token'ı yalnızca `_currentToken` BELLEKTE doluysa
--     siliyordu; uygulama yeniden başlayınca o alan null olur ve eski satır
--     tabloda sonsuza dek kalır,
--   · FCM eski token'ı çoğu zaman GEÇERLİ sayıp aynı cihaza teslim eder,
--     yani `UNREGISTERED` temizliği de devreye girmez.
-- Sonuç: her kurulum/rotasyon tabloya bir satır daha ekler, kullanıcı her
-- sinyalde bir fazla bildirim alır.
--
-- ## Çözüm
-- Cihaz başına KALICI bir kimlik (`device_id`) ekleniyor. İstemci bunu
-- `shared_preferences`'ta saklar — token rotasyona uğrasa da değişmez.
-- `(user_id, device_id)` üzerinde tekillik: aynı cihazın yeni token'ı eskisinin
-- ÜZERİNE yazılır, satır çoğalmaz.
--
-- `token` PK olarak KALIYOR: cihaz el değiştirirse (aynı token başka
-- kullanıcıya) mevcut upsert davranışı korunmalı.

alter table user_push_tokens
  add column if not exists device_id text;

-- ── Mevcut kopyaları temizle ────────────────────────────────────────────────
--
-- `device_id` geriye dönük bilinemez: eski satırların hangi fiziksel cihaza
-- ait olduğu kayıtlı değil. Bu yüzden (user_id, platform) başına yalnızca EN
-- TAZE satır bırakılır. Kullanıcı zaten şu an o cihazdan bildirim alıyor;
-- eski token'lar ya aynı cihazın kopyası (silinmeli) ya da artık kullanılmayan
-- bir kurulum (yine silinmeli).
--
-- Gerçekten iki AYRI cihaz kullanan biri (telefon + tablet, ikisi de android)
-- bir cihazda bildirim almayı keser; uygulamayı bir kez açtığında istemci
-- yeni `device_id` ile satırını tekrar yazar ve düzelir. Kalıcı bir kayıp
-- değil, tek seferlik bir yeniden kayıt.
delete from user_push_tokens t
where exists (
  select 1 from user_push_tokens newer
  where newer.user_id = t.user_id
    and coalesce(newer.platform, 'unknown') = coalesce(t.platform, 'unknown')
    and (newer.updated_at, newer.token) > (t.updated_at, t.token)
);

-- Aynı kullanıcı + aynı cihaz = TEK satır.
-- `device_id is not null` koşulu: kimliği henüz bilinmeyen eski satırlar
-- (istemci güncellemesi gelene kadar) kısıtı tetiklemesin.
create unique index if not exists user_push_tokens_user_device_uidx
  on user_push_tokens(user_id, device_id)
  where device_id is not null;

comment on column user_push_tokens.device_id is
  'Cihaz başına kalıcı kimlik (istemci shared_preferences''ta üretir/saklar). '
  'FCM token rotasyona uğradığında satırın çoğalmasını engeller — aksi halde '
  'kullanıcı aynı telefonda her rotasyon için bir fazla push alır.';
