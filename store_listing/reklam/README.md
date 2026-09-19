# Reklam paketi — sandık (2026-09-19)

Sosyal medya ve mağaza dışı kanallar için üç video + beş görsel. Kaynak kod
`store_listing/preview_video/src/reklam/` (aynı Remotion projesi, ayrı
kompozisyonlar); çıktılar `out/`, gözle kontrol kareleri `check/`.

## Çıktılar

| Dosya | Kanal | Boyut | Süre | Mesaj |
|---|---|---|---|---|
| `out/sandik_reel_9x16_15s.mp4` | Instagram Reels · TikTok · YouTube Shorts | 1080×1920 | 15 sn | "Paran arttı mı, yoksa sadece **eridi** mi?" → getiri − TÜFE = fark → uygulama → kapsam → CTA |
| `out/sandik_kare_1x1_12s.mp4` | Instagram/Facebook akış | 1080×1080 | 12 sn | "Kârın gerçekten kârın mı?" → fiş (fiyat farkı, komisyon, temettü, gerçek kâr) → CTA |
| `out/sandik_bumper_16x9_6s.mp4` | YouTube bumper / pre-roll | 1920×1080 | 6 sn | logo sting → "Enflasyonu geçtin mi?" → CTA |
| `out/sandik_kare_enflasyon_1080.png` | Instagram gönderi, X | 1080×1080 | — | eridi mi? + telefon |
| `out/sandik_kare_altin_1080.png` | Instagram gönderi, X | 1080×1080 | — | "Altın mı, dolar mı, hisse mi kazandırdı?" + getiri listesi (biri kırmızı) |
| `out/sandik_kare_ortak_1080.png` | Instagram gönderi | 1080×1080 | — | "Eşinle aynı sandık." Ben / Ayşe / Birlikte |
| `out/sandik_hikaye_1080x1920.png` | Instagram/Facebook hikâye | 1080×1920 | — | eridi mi? + rozet + telefon |
| `out/sandik_banner_1600x900.png` | X / LinkedIn başlık, README | 1600×900 | — | "Enflasyonu geçtin mi?" + telefon |

## Kararlar

- **Arayüz ekran kaydı değil, yeniden çizim.** Reklam görselinde "Test"
  ortak adı, kayıt rozeti gibi gerçek hesap izleri olmamalı; sayılar
  `DEMO_PORTFOY.md` ile birebir (₺766.876 · +%34,35 · TÜFE %31,51 · +2,85 puan).
  Launch videosu aynı yolu seçmişti, kullanıcı üslubu beğendi. Bu yol mağaza
  **önizlemesinde** kullanılamaz (Apple 2.3.4 yalnızca ekran kaydı) — bu
  bileşenler yalnızca reklamda.
- **Tek kanca, tek CTA.** ui-ux-pro-max "Minimal Single Column" ve
  "Video-First Hero" kalıplarından yargı alındı (bir başlık, ≤3 madde, tek
  eylem, koyu zemin + marka vurgusu); önerdiği rose/blue paleti ALINMADI —
  sandık amber/gold/gain/loss + DM Sans.
- **Amber kare başına bir öğe.** Hero renk yalnızca vurgulanan kelimede ya
  da CTA pilinde parlar; ikisi aynı karede parlamaz (remotion skill kuralı).
- **Kesimler vuruşta.** Müzik 114 BPM (brag beat-grid'inden türetildi);
  sahne başları 4 · 10 · 16 · 22 vuruş.
- **"Ücretsiz" iddiası** doğru: paywall Remote Config'de kapalı, IAP yok.
  Android yayına çıkınca CTA `ui.tsx` → `StoreLine` metninden güncellenir
  ("Şimdi App Store'da · Ücretsiz" → "App Store ve Google Play'de").
- **Erime efekti** yalnızca "eridi" kelimesinde — reklamın tek aşırılığı.
  Kalan hareket: giriş (opacity+y+scale), sayaç, çubuk dolumu, nefes.

## Ses ve lisans

- Müzik: "Happy Beats / Business Moves vol-11", Sascha Ende (ende.app),
  CC BY 4.0, ticari kullanım serbest — `preview_video/SES_LISANS.md`.
- SFX: Kenney.nl (CC0) + kendi sentetik whoosh/pop/thump.
- Seslendirme yok; videolar sessiz izlendiğinde de tam anlaşılır.

## Yeniden üretim

```bash
cd store_listing/preview_video
node scripts/render_reklam.mjs            # hepsi (kontrol kareleri + 3 video + 5 görsel)
node scripts/render_reklam.mjs check      # yalnızca kontrol kareleri
node scripts/render_reklam.mjs AdReel     # tek kompozisyon
npm run studio                            # tarayıcıda önizleme
```

Metin/sayı değişikliği: `src/reklam/theme.ts` (`DEMO`), sahne metinleri
ilgili `Reel.tsx` / `Square.tsx` / `Bumper.tsx` / `Stills.tsx` içinde.

## Yükleme notları

- Reels/TikTok: kritik metin dikeyde 230–1660 px arasında (platform arayüzü
  üstü/altı kapatır). Altyazı gerekmez, konuşma yok.
- YouTube bumper 6 sn sınırı tam; atlanamaz format.
- Görsellerde fiyat/getiri iddiası demo portföydür; "geçmiş performans"
  uyarısı gerekirse gönderi metnine: *"Örnek portföy; yatırım tavsiyesi değildir."*
