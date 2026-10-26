# widget-fiyat

Tek varlık ana ekran widget'ı (iOS `SandikVarlikWidget`, Android
`SandikVarlikWidgetProvider`) uygulama açılmadan fiyatını tazelemek için
çağırır (yasin onayı 2026-10-26). Widget yarım saatte bir ve yalnız seçili
varlık sunucu kapsamındaysa ister.

- Gövde: `{ "semboller": ["ALTIN_GRAM24", "USDTRY=X", "KRIPTO:BTC"] }`,
  en çok 5 sembol, gövde ≤ 1 KB (aşan 400/413).
- Kapsam (beyaz liste, `_shared/widget_fiyat.ts › widgetSembolTuru`):
  - altın ayarları + `USDTRY=X`/`EURTRY=X`/`GBPTRY=X` → `yurt_ici_kotasyon`
    (0101) son kaydı; fiyat `Buying` (uygulamanın gösterdiği alan), yüzde
    truncgil `Change`'i (uygulamanın gösterdiği yüzde).
  - `KRIPTO:<KOD>` → `kripto_fiyat` (0074); yüzde İstanbul günü açılışına göre.
  - Hisse, fon, endeks, emtia, eurobond: kapsam dışı (sunucuda canlı tutulmuyor);
    widget o varlıklarda yalnız uygulamanın yazdığı değeri gösterir.
  Bilinmeyen sembol yok sayılır.
- Yanıt: `{ "<SEMBOL>": { "fiyat": 6123.45, "zaman": <epoch ms>, "degisim"?: 0.42 } }`.
  Bayat kayıt (yurt içi > 2 sa, kripto > 30 dk) yanıtta YOK — uydurma sayı yok.
  `Cache-Control: public, max-age=60`; isolate içinde de 60 sn önbellek.
- Auth: Supabase varsayılanı (`verify_jwt = true`); widget anon anahtarla
  çağırır (`apikey` + `Authorization: Bearer <anon>`). Oturum jetonu YOK,
  kişisel veri okunmaz/dönmez. Okuma service role ile; tabloların anon
  GRANT/RLS'i değişmedi.
- Hata: `{ "error": "istek" | "method" | "sunucu" }`; ayrıntı yalnız sunucu
  günlüğünde.
- Dağıtım: yalnız fonksiyon (`functions: "widget-fiyat"`, `migrations: false`),
  iki sunucuya. Migration gerekmez.
- Testi: `supabase/tests/widget_fiyat_test.ts`.
