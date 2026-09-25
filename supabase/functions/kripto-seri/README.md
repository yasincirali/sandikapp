# kripto-seri

Uygulama bir kripto grafiği açtığında çağırır. Binance mumlarını TL'ye
çevirip `kripto_seri_onbellek`'e yazar; aynı `(kod, aralık, dönem)` isteği
bir bar boyunca (60 sn – 1 saat) herkese aynı satırdan döner.

- Gövde: `{ "kod": "BTC", "aralik": "1h", "donem": "1mo" }`.
  Aralık: `1m 5m 15m 1h 1d 1wk`; dönem: `1d 5d 1mo 3mo 6mo 1y 2y 5y max`
  (Yahoo adları — `ResolutionTier` değişmeden kullanılır).
- Yanıt: `{ noktalar: [[açılış_ms, fiyat_try], …], bayat? }`.
- Auth: oturumlu kullanıcı (`auth.getUser`); anon anahtarı yetmez.
  Katalogda olmayan kod için sağlayıcıya gidilmez (404).
- USDT paritesinde USDTTRY mumu ile aynı açılış anında çarpılır; kuru
  olmayan nokta düşer.
- İstemci `x-region: eu-central-1` başlığıyla çağırır.
