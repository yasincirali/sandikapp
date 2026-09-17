# brag çıktısı — anlatımlı mağaza önizlemesi

`/brag --voice --tone app-store --format vertical` (2026-09-17) ile üretildi.
Araç zinciri: **brag** (hikâye, storyboard, müzik/SFX) → **Hyperframes** (HTML
kompozisyon, `check`, render) → ffmpeg (poster kare + mağaza kodlaması).

| Dosya | Ne |
|---|---|
| `brag.mp4` | Teslim: 886×1920 · 30 fps · H.264 CBR 11 Mbps · AAC 256k · 28,4 s · 0. kare = poster |
| `brag.jpg` | Poster (2,4 sn — açılış alt yazısı oturmuş) |
| `brag-plan.md` | 9 soruluk rubrik, açı, storyboard, anlatım metni |
| `composition-brief.md` | Hyperframes'e verilen sözleşme |
| `share-copy.txt` | Paylaşım metni |
| `composition/index.html` | Kompozisyon — tek dosya, tek GSAP timeline |
| `scripts/prep_media.py` | Klipleri ve anlatım WAV'larını yeniden üretir |

Aynı dosya `../out/sandik_preview_iphone_anlatimli.mp4` olarak da kopyalandı.

## Yeniden üretmek

```bash
cd composition
npm install                                  # hyperframes + ffmpeg-static + ffprobe-static
mkdir -p tools && cp node_modules/ffmpeg-static/ffmpeg.exe tools/ \
  && cp node_modules/ffprobe-static/bin/win32/x64/ffprobe.exe tools/
export PATH="$PWD/tools:$PATH"               # Hyperframes ffmpeg'i PATH'te arar
python ../scripts/prep_media.py              # klipler + VO (edge-tts mp3'leri vo/ altında olmalı)
npx hyperframes check                        # tek kapı: lint + runtime + layout + kontrast
npx hyperframes render --video-bitrate 11M --output ../brag_render.mp4
```

Sonra poster + mağaza kodlaması (brag step-4 "bake as frame 0" + App Store spec):

```bash
ffmpeg -ss 2.4 -i brag_render.mp4 -frames:v 1 -q:v 2 brag.jpg
ffmpeg -i brag_render.mp4 -i brag.jpg \
  -filter_complex "[0:v][1:v]overlay=0:0:enable='eq(n,0)'[v]" -map "[v]" -map 0:a \
  -c:v libx264 -preset slow -b:v 11M -minrate 11M -maxrate 11M -bufsize 22M \
  -x264-params nal-hrd=cbr:force-cfr=1 -pix_fmt yuv420p -r 30 \
  -c:a aac -b:a 256k -ar 48000 -movflags +faststart brag.mp4
```

## Kararlar (neden)

- **Türkçe anlatım edge-tts ile.** brag'in tek sağlayıcısı Kokoro; `hyperframes tts
  --list` Türkçe ses vermiyor. `tr-TR-AhmetNeural` kullanıldı; `tr-TR-EmelNeural`
  alternatifi `composition/assets/vo/e_*.wav`. Değiştirmek için index.html'de
  `a_` → `e_` ve SCENES tablosundaki `voLen` değerleri.
- **28,4 sn, brag'in 25 sn tavanının üstünde.** Altı Türkçe cümle 25'e sığmadı;
  App Store sınırı 30 sn. Sahne süreleri anlatıma göre esnetildi.
- **Müzik ducking timeline tween'iyle, carve ile değil.** `carve.mjs` dry-run
  çalıştı (6 bant, −19 dB taban) ama seviye zarfını dosya seviyesinden ölçüyor;
  timeline'daki 0,34 kazancıyla çift ducking oluyor ve bed neredeyse kayboluyor.
  Manuel zarf: 0,34 yatak, anlatım altında 0,16 (≈ −6,5 dB fark ölçüldü).
- **Audio-reactive yok.** İçerik ekran kaydı; üstüne nefes alan glow Apple
  2.3.4'ün "screen capture" ruhuna aykırı.
- **Kanıt klibi dondurmalı.** Kayıtta reel getiri kartı 2 sn'de yukarı kayıp
  gidiyordu; 0,75 sn kaydırma + `tpad` ile son kare tutuluyor.
- **Remotion'un ffmpeg'i kullanılamaz.** `@remotion/compositor` ffmpeg'i kısıtlı
  build: filtergraph ayrıştırıcısı `scale=…,fps=30`'u bile reddediyor,
  `silenceremove` yok, Hyperframes kare çıkarımı onunla düşüyor. Tam sürüm
  `composition/tools/` (ffmpeg-static).
- **Git Bash tuzağı.** `scale=886:1920` gibi `:` içeren argümanları MSYS yol
  dönüşümü bozar; ffmpeg çağrıları Python `subprocess` ile yapılır.

## Mağaza kuralları

2.3.4 yalnızca ekran kaydı + açıklayıcı overlay/anlatım (✓), 2.3.7 fiyat yok (✓),
2.3.9 kurgusal ad maskesi "Ayşe" (✓, kalıcı çözüm demo hesapla yeniden çekim),
2.3.10 Android/Play yok (✓). **Müzik ve TTS lisansı** → `YAPMAN_GEREKENLER.md`.
