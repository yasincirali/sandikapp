# Mağaza grafikleri — Play Console'a ne yüklenecek

**Üretim:** `cd store_listing && python build_store_graphics.py`
(ekran görüntüleri ayrı: `python build_screenshots.py`)

Bu klasördeki dosyalar **türetilmiş çıktıdır** — elle düzenleme. Kaynak
değişirse (`assets/images/sandik_icon.png`, palet, slogan) betiği yeniden
koş. Elle Canva'da yapılan bir grafik bir sonraki sürümde "hangi dosyadan
üretmiştik" sorusunu doğurur ve palet kayar.

## Play Console → Mağaza ayarları → Ana mağaza sayfası

| Console alanı | Dosya | Kural |
|---|---|---|
| Uygulama simgesi | `icon_512.png` | 512×512, 32-bit PNG, **alfa yok** ✓ |
| Öne çıkan grafik | `feature_graphic_1024x500.png` | 1024×500, alfa yok ✓ |
| Telefon ekran görüntüleri | `../screenshots/out/1080x1920/` (7 adet) ve/veya `../screenshots/out_v2/1080x1920/` (8 adet) | 1080×1920 = 1,78:1, 2:1 sınırının altında ✓ |

⚠️ **Ekran görüntülerinde iki set karıştırılmaz.** `out/` ile `out_v2/`
BAŞKA portföylere ait; tek galeride karıştırmak "aynı portföy tüm
karelerde" tutarlılığını bozar. Birini seç. Sıralama için
`../SCREENSHOT_PLAN.md`.

## Neden bu tasarım kararları

**İkon — iki kez yuvarlanmış köşe tuzağı.** Kaynak PNG'nin köşeleri zaten
yuvarlak ve dışı şeffaf. Şeffaflık koyu zemine düzleştirilirse ikonun
çevresinde koyu bir çerçeve kalıyor ve Play kendi maskesini onun üstüne
uygulayınca logonun kenarı kesilip halka oluşuyor. Bu yüzden opak pikseller
`getbbox` ile kırpılıp tuval TAM dolduruluyor — Play'in maskesi logonun
kendi köşesiyle çakışsın diye. **Köşe yuvarlama uygulanmıyor.**

**Feature graphic — punto ölçümle seçiliyor.** Sabit punto yazmak yerine
metnin gerçek genişliği ölçülüp güvenli kenara (%8) sığana kadar
küçültülüyor. Slogan ileride değişirse grafik sessizce bozulmaz. İlk
denemede 38pt slogan sağ kenarı aşıyordu.

**Slogan finansal politika uyumlu.** "Gerçek kâr/zarar, tek ekranda" ürünün
ne yaptığını söylüyor; kazanç/getiri vaat etmiyor. Play'in finansal
uygulama politikası vaat eden metinlere sert davranıyor.

## Kalan görsel işler (zorunlu değil)

- **Tablet görselleri** — zorunlu değil ama büyük ekran sıralamasında
  avantaj sağlıyor. 7" ve 10" için ayrı set.
- **Promo video** — opsiyonel, YouTube linki.
