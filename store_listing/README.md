# Play Store Listing Materyalleri

## Dosya Yapısı

```
store_listing/
  tr-TR/
    title.txt              (max 30 karakter)
    short_description.txt  (max 80 karakter)
    full_description.txt   (max 4000 karakter)
    whats_new.txt          (max 500 karakter, her sürüm güncellenir)
  en-US/
    (aynı yapı)
  screenshots/             ← OLUŞTURULACAK (emülatörden)
    tr-TR/
      phone/               ← 2-8 adet, min 320px, max 3840px
    en-US/
      phone/
  feature_graphic.png      ← 1024x500px, zorunlu
  icon.png                 ← 512x512px, 32-bit PNG, zorunlu
```

## Yapılacaklar

> Tam yayın adımları: [`PLAY_STORE_YAYIN_REHBERI.md`](../PLAY_STORE_YAYIN_REHBERI.md)

- [ ] **Ekran görüntüleri — yeniden üretilmeli.** `screenshots/orig/` altındaki
      7 görsel 1125x2436 (2,17:1). Play en fazla **2:1** orana izin verir, bu
      dosyalar yüklemede reddedilir. Ham görüntüleri `screenshots/raw/` içine
      koyup `python build_screenshots.py` çalıştır → `screenshots/out/1080x1920/`
      klasörünü Play'e yükle. Sıralama için `SCREENSHOT_PLAN.md`.
- [ ] `feature_graphic.png` — 1024x500 banner (sandık logosu + koyu zemin + slogan)
- [ ] `icon.png` — 512x512, 32-bit PNG, alfa kanalsız
      (kaynak: `../assets/images/sandik_icon.png`, 1024x1024)
- [ ] `tr-TR/full_description.txt` sonundaki "ARAMA" bölümünü ilk yayında
      çıkar — Play'in metadata politikası anahtar kelime tekrarına App
      Store'dan daha sert (rehber §6.4)
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
