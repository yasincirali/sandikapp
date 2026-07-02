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
