# Store Listing Materyalleri (Play Store + App Store)

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
  app_store/                       ← App Store Connect metadata (iOS)
    tr-TR/
      promotional_text.txt (max 170 karakter, review olmadan güncellenebilir)
      description.txt      (max 4000 karakter)
      keywords.txt          (max 100 karakter, virgülle ayrılmış)
    en-US/
      (aynı yapı)
    support_url.txt         (app geneli, zorunlu)
    marketing_url.txt       (app geneli, opsiyonel)
    copyright.txt           (app geneli, örn. "© 2026 Yasin Cirali")
```

## App Store Connect'e Girilecekler

`store_listing/app_store/` altındaki dosyaların içeriğini App Store Connect →
App Bilgileri / Sürüm sayfasındaki ilgili alanlara olduğu gibi yapıştır:

- **Promotional Text / Keywords / Description:** dile göre `tr-TR/` veya
  `en-US/` klasöründen, App Store Connect'te o dilin lokalizasyon sekmesine.
- **Support URL, Marketing URL, Copyright:** app geneli (lokalize değil),
  kök `app_store/` klasöründen.
- Support URL şu an `legal_doc_screen.dart` ve `register_screen.dart`
  içinde kullanılan aynı GitHub Pages sitesini (`yasincirali.github.io/sandikapp`)
  gösteriyor; destek e-postası (`sandikapp.destek@gmail.com`) o sayfada yer
  almıyorsa siteye bir iletişim/destek bölümü eklenmesi önerilir.
- `app_store/*/description.txt` metinleri, Play Store'daki `full_description.txt`'ten
  kasıtlı olarak farklı: kod incelemesiyle doğrulanan gerçek özellikler (TEFAS
  entegrasyonu, altın alt türleri — gram/çeyrek/yarım/ata/reşat/cumhuriyet/ons,
  emtia takibi, teknik sinyal bildirimleri, ortaklıkta salt-okunur erişim) eklendi.
  "Ekran görüntüsü gizleme" iddiası App Store metninden çıkarıldı çünkü bu özellik
  yalnızca Android'de (`MainActivity.kt` → `FLAG_SECURE`) var; iOS tarafında
  karşılığı yok, App Store'da yanlış iddia olurdu.

## Yapılacaklar

- [ ] `screenshots/tr-TR/phone/` — emülatörden en az 4 ekran görüntüsü (Ana ekran, Dağılım, Performans, Profil)
- [ ] `feature_graphic.png` — 1024x500px banner (sandık logosu + koyu arka plan + tagline)
- [ ] `icon.png` — 512x512px (mevcut `assets/images/sandik_icon.png` kullanılabilir, boyutlandır)
- [ ] `[ŞİRKET ADI]` placeholder'larını `full_description.txt` gerekmiyorsa kontrol et — şu an yok
- [ ] `legal/tr/PRIVACY_POLICY.md` → public URL'e deploy → Play Console'a gir

## Google Play Console'da Manuel Girilecekler

- **Kategori:** Finans
- **Content rating:** Everyone (yatırım uyarısı disclaimer var)
- **Target audience:** 18+
- **Privacy Policy URL:** https://[WEBSITE]/privacy
- **App category:** Finance > Personal Finance
- **Data safety section:**
  - Toplanan veriler: E-posta adresi (hesap oluşturma, zorunlu, şifrelenmemiş paylaşım yok)
  - Konum: Hayır
  - Finansal bilgi: Hayır (fiyatlar kamuya açık API'den, kullanıcı girişi portföy miktarı — Supabase'de şifreli)
  - Uygulama aktivitesi: Çökme günlükleri (Firebase Crashlytics, anonim)
