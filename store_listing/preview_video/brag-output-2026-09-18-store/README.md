# brag çıktısı — mağaza önizlemesi, açıklamalı (seslendirmesiz)

2026-09-18. Kullanıcı kararı: launch videosunun sade/açıklayıcı üslubu mağaza
videosuna taşındı; seslendirme kaldırıldı. Görsel içerik gerçek ekran kaydı
(Apple 2.3.4), her sahnede özellik başlığı + tek açıklayıcı cümle.

| Dosya | Ne |
|---|---|
| `brag.mp4` | 886×1920 · 30 fps · H.264 CBR 11 Mbps · AAC 256k · 28,0 s · 0. kare = poster |
| `brag.jpg` | Poster (2,4 sn) |
| `brag-plan.md` | Sahne tablosu, metinler, ses kararı |
| `composition/index.html` | Kompozisyon |

Kopyası: `../out/sandik_preview_iphone_aciklamali.mp4`. Önceki anlatımlı sürüm
`../brag-output/` içinde duruyor (ihtiyaç olursa).

## Yeniden üretmek

`../brag-output/README.md` ile aynı akış (klipler oradaki `scripts/prep_media.py`
ile üretildi ve buraya kopyalandı; ffmpeg-static `../brag-output/composition/tools/`).

```bash
cd composition && export PATH="../../brag-output/composition/tools:$PATH"
npx hyperframes check --at 1.6,6.5,11.5,15.6,19.2,22.8,26.0
npx hyperframes render --video-bitrate 11M --output ../brag_render.mp4
# poster + CBR 11M + AAC 256k: ../brag-output/README.md'deki ffmpeg komutu
```

## Kararlar (neden)

- **Seslendirme yok.** Kullanıcı "olmasa da olur" dedi; panel metni özelliği zaten
  söylüyor, TTS lisans sorusu da ortadan kalkıyor. Müzik ducking'i gereksizleşti,
  yatak 0,45'e çıktı (karışım ≈ −21 LUFS).
- **Panel = başlık + cümle.** Launch videosundaki gibi jargon yok (TÜFE, reel,
  XU100 geçmiyor). Panel iki satır olunca 1. sahnede "Ayşe" maskesine bindi;
  yalnızca o sahnede panel aşağı alındı (`.low`, sekme çubuğunun üstünde).
- **Dağılım sahnesi geri geldi** (anlatımlı sürümde süre yüzünden çıkarılmıştı):
  seslendirme olmayınca 3,2 sn'lik pencereye sığdı.
- Sahne başları vol-11 beat-grid'inde (4,75 · 8,96 · 13,70 · 17,39 · 21,07), kapanış
  24,23 strong cue.
