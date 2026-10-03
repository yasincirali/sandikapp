# yurt-ici-kotasyon

Uygulamanın truncgil'den fiyatladığı **tüm altın ayarlarını ve TL dövizlerini**
(USD/EUR/GBP) beş dakikada bir `yurt_ici_kotasyon`'a yazar (5 dk kova, upsert).
Amaç: uluslararası piyasa kapalıyken (hafta sonu) Performans › GÜNLÜK ve
varlık sayfası GÜNLÜK grafiğinin şeklini, ekranda görünen yurt içi
kotasyondan çizebilmek. İstemci tarafı Remote Config `hafta_sonu_yurt_ici_seri`
bayrağının arkasında (varsayılan kapalı).

- Kaynak: `finans.truncgil.com/v4/today.json`, fiyat alanı uygulama ve fiyat
  alarmıyla aynı (`Buying` önce). Okunamayan sembol satır üretmez.
- Saklama: 10 gün; eski satırlar aynı turda silinir.
- Auth: `x-cron-secret` = `PRICE_ALERTS_CRON_SECRET` (Vault:
  `price_alerts_cron_secret`) — check-price-alerts ile paylaşılır, fail-closed.
- Gövde `{"dry_run": true}` → okur, yazmaz.
- Yanıt `{ok, yazilan, silinen}`; hata ayrıntısı yalnız sunucu günlüğünde.
- Saf yardımcı `_shared/live_prices.ts › yurtIciSatirlari`, testi
  `tests/yurt_ici_kotasyon_test.ts`.
