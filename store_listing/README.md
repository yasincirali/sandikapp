# Play Store Listing Materyalleri

## Dosya Yapısı

```
store_listing/
  tr-TR/ en-US/            ← mağazadan bağımsız metinler
    title.txt              (max 30 karakter)
    short_description.txt  (max 80 karakter)
    full_description.txt   (max 4000 karakter)
    whats_new.txt          (max 500 karakter, her sürüm güncellenir)

  android/                 ← Play Console'a yüklenecekler  (README.md)
    graphics/
      icon_512.png                  512x512, alfa yok
      feature_graphic_1024x500.png  1024x500, alfa yok
    screenshots/
      set_a/1080x1920/   (7 kare)
      set_b/1080x1920/   (8 kare)   ⚠️ ikisi karıştırılmaz

  ios/                     ← App Store Connect'e yüklenecekler (README.md)
    APP_STORE_1.1.3.md
    screenshots/
      set_a/1242x2688/  set_a/1284x2778/
      set_b/1242x2688/  set_b/1284x2778/

  screenshots/             ← GİRDİ (çıktı değil)
    raw/ raw_v2/           ham telefon görüntüleri
    orig/                  eski 1125x2436 kareler, Play'e uymaz
    grid/                  hizalama denetimi için ızgara bindirmesi

  build_screenshots.py     raw/ + raw_v2/ → android/ ve ios/
  build_store_graphics.py  ikon + feature graphic → android/graphics/
```

**Çıktı klasörleri türetilmiştir ve `.gitignore`'dadır** — repoda yalnızca
kaynak (ham görüntüler + betikler) ile mağaza README'leri durur. Console'a
yüklemeden önce betiği koş; elle düzenleme, bir sonraki koşuda kaybolur.
Mağaza başına ayrı klasör olmasının nedeni: Play en fazla 2:1 en-boy
oranına izin verir, App Store kareleri 2,16:1'dir ve Play yüklemede
reddeder. Ayrıntı: [`android/README.md`](android/README.md),
[`ios/README.md`](ios/README.md).

## Yapılacaklar

> Tam yayın adımları: [`PLAY_STORE_YAYIN_REHBERI.md`](../PLAY_STORE_YAYIN_REHBERI.md)

- [x] **Ekran görüntüleri Play formatında üretildi.** Eski `screenshots/orig/`
      kareleri 1125x2436 (2,17:1) olduğu için reddedilirdi; artık
      `android/screenshots/set_a|set_b/1080x1920/` (1,78:1, alfa yok).
      ⚠️ İki set başka portföylere ait, **karıştırma** — birini seç.
      Sıralama için [`SCREENSHOT_PLAN.md`](SCREENSHOT_PLAN.md).
- [x] `android/graphics/feature_graphic_1024x500.png` — betikle üretiliyor
- [x] `android/graphics/icon_512.png` — 512x512, alfa kanalsız
      (kaynak: `../assets/images/sandik_icon.png`, 1024x1024)
- [ ] **Tablet görselleri** — zorunlu değil, büyük ekran sıralamasında avantaj
- [x] `tr-TR/full_description.txt` App Store açıklamasıyla birebir hizalandı
      (kaynak: [`ios/APP_STORE_1.1.3.md`](ios/APP_STORE_1.1.3.md)); eski "ARAMA"
      varyant listesi kalktı.
      Alan alan eşleme tablosu: rehber §12
- [x] Hukuki sayfalar yayında: `https://yasincirali.github.io/sandikapp/privacy`
      (`docs/` → GitHub Pages). Console'a girmeden önce tarayıcıda açıp doğrula.

## Google Play Console'da Manuel Girilecekler

- **Kategori:** Finans
- **Content rating:** IARC anketi → muhtemelen Everyone/3+ (kumar/şiddet yok)
- **Target audience:** 18+
- **Privacy Policy URL:** https://yasincirali.github.io/sandikapp/privacy
- **Hesap silme URL:** https://yasincirali.github.io/sandikapp/data-deletion
- **App access:** Uygulama girişsiz kullanılamıyor → reviewer için kalıcı
  demo hesabı gir (rehber §5.2)
- **Data safety:** [`DATA_SAFETY_FORM.md`](DATA_SAFETY_FORM.md) — Advertising
  ID satırı eksik, rehber §5.3'e bak
- **Financial features declaration:** zorunlu; sinyal özelliği nedeniyle
  dikkatli doldurulmalı (rehber §5.4)
