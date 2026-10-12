-- Live Activity: son yüksek öncelikli push'un görünür içerik imzası.
--
-- ## Neden (kaynak kullanımı denetimi, 2026-10-12)
-- `push-live-activity` dakikada bir (0100) HER güncellemeyi
-- `apns-priority: 10` ile gönderiyordu. Saat damgası sunucuda üretildiği
-- için rakam değişmese de her push "yeni" sayılıyor; varsayılan pencerede
-- (10:00–18:10) kullanıcı başına ~490 yüksek öncelikli push. Apple öncelik
-- 10'u Live Activity bütçesinden düşer, bütçe aşılınca güncellemeleri
-- KISAR — yani rakam değiştiğinde de geç gelebilir.
--
-- Fonksiyon artık görünen rakamlar (tutar, yüzde, eğri, piyasa durumu,
-- tema…) son yüksek öncelikli push'takiyle AYNIYSA aynı push'u öncelik 5
-- ile gönderir; değiştiyse 10. Push sayısı ve içeriği DEĞİŞMEZ: kilit
-- ekranındaki saat her dakika yine tazelenir, yeni rakam yine hemen gider.
--
-- ## Geriye uyum
-- Yalnızca EKLEYEN, boş olabilir sütun. İstemci bu sütunu okumaz ve
-- yazmaz (eski ve yeni sürümler aynı). Sütun yokken ya da boşken fonksiyon
-- bugünkü davranışa (öncelik 10) düşer.
alter table live_activity_sessions
  add column if not exists son_push_imzasi text;

comment on column live_activity_sessions.son_push_imzasi is
  'Son apns-priority 10 pushun gorunur icerik imzasi (saat haric). '
  'Yalnizca push-live-activity yazar/okur; ayni imza oncelik 5 ile gider.';
