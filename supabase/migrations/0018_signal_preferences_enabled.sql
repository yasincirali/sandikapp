-- Bildirim ana anahtarını sunucuya taşır.
--
-- Sorun: "Sinyal bildirimleri" aç/kapa tercihi yalnızca SharedPreferences'ta
-- tutuluyordu. Sinyal analizi sunucuda çalıştığı ve push'u sunucu gönderdiği
-- için kapalı olması hiçbir işe yaramıyordu — kullanıcı bildirimleri kapatsa
-- bile sunucu push atmaya devam ediyordu. (Local bildirim kontrolü
-- NotificationService içinde var ama sinyal push'ları artık local değil.)
--
-- Ayrıca uygulama silinip yeniden kurulduğunda bu tercih sıfırlanıyordu.

alter table signal_preferences
  add column if not exists signals_enabled boolean not null default true;

comment on column signal_preferences.signals_enabled is
  'Bu varlık türü için sinyal push gönderilsin mi. false ise analiz yapılsa '
  'bile bildirim gitmez. Kullanıcının ana bildirim anahtarı buraya yazılır.';
