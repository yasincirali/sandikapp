-- Live Activity'nin tema bayrağı — oturum satırında AYRI sütun.
--
-- ## Neden `summary` içindeki alan yetmedi
-- Tema bugüne kadar yalnızca `summary` JSON'unun içinde taşınıyordu ve o
-- JSON YALNIZCA portföy özeti yazılırken güncelleniyor. Bu üç durumda
-- bayrak sessizce ESKİ kalıyor ve sunucu kilit ekranına yanlış paleti
-- push'luyor:
--
--   1. Kullanıcı temayı gösterim penceresi DIŞINDA değiştirirse
--      (`LiveActivityService.sync` pencere dışında oturumu bitirip erken
--      döner, özet hiç yazılmaz),
--   2. yeni bir oturum satırı açıldığında (`_registerToken` upsert'i özet
--      YAZMAZ; satır bir süre `summary: null` durur ve o aralıkta
--      gelen push varsayılan KOYU paletle gider),
--   3. özet eski ANLAM sürümüyle yazılmışsa sunucu satırı `skippedStale`
--      sayar — rakamlar için doğru davranış ama tema rakam değil.
--
-- Kullanıcı bulgusu ("uygulamayı kill edince tema değişiyor") tam olarak
-- bu: uygulama açıkken ActivityKit doğru paleti basıyor, kapandıktan sonra
-- yüzeyi besleyen TEK şey bu satır olduğu için palet geri dönüyordu.
--
-- Sütun, özetten BAĞIMSIZ yazılır (`pushThemeToServer`): pencereye,
-- fiyat verisine, şema sürümüne ve tekrar-eleme anahtarına takılmaz.
--
-- ## Varsayılan neden `false`
-- Koyu palet bugüne kadarki davranış. Sütunu `not null default false`
-- yapmak, henüz tema yazmamış eski satırların da geçerli bir değer
-- taşımasını sağlar; sunucu tarafında `null` ayrımı yapmak gerekmez.
alter table live_activity_sessions
  add column if not exists is_light_theme boolean not null default false;

comment on column live_activity_sessions.is_light_theme is
  'Uygulamanin COZULMUS tema tercihi (acik mi). Push icerigi bu sutundan '
  'beslenir; summary.isLightTheme yalnizca geriye donuk yedektir. '
  'Istemci bunu ozetten BAGIMSIZ yazar, boylece gosterim penceresi '
  'disinda yapilan tema degisimi de kilit ekranina ulasir.';
