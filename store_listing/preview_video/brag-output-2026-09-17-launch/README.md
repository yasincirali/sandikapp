# brag çıktısı — launch videosu (mağaza videosundan bağımsız)

`/brag` (ton: default, landscape, müzik+SFX, anlatım yok), 2026-09-17.
Ekran kaydı **kullanılmadı**: uygulama arayüzü HTML/CSS ile yeniden çizildi,
hareket GSAP; render Hyperframes. Paylaşım için (X / LinkedIn / GitHub README).

| Dosya | Ne |
|---|---|
| `brag.mp4` | 1920×1080 · 30 fps · H.264 · 21,6 s · 0. kare = poster |
| `brag.jpg` | Poster (7,8 sn — wordmark + rozet + telefon) |
| `brag-plan.md` / `composition-brief.md` | Plan, storyboard, Hyperframes sözleşmesi |
| `share-copy.txt` | Paylaşım metni |
| `composition/index.html` | Tek dosya kompozisyon, tek GSAP timeline |
| `composition/audio-data.js` | Müzikten çıkarılmış 16 bant (bass → glow nefesi) |

## Yeniden üretmek

```bash
cd composition
export PATH="../../brag-output/composition/tools:$PATH"   # ffmpeg-static (bkz. ../brag-output/README.md)
npx hyperframes check --at 1.5,3.4,5.2,7.6,9.8,11.8,14.9,16.2,19.0
npx hyperframes render --quality delivery --output ../brag_render.mp4
cd .. && ffmpeg -ss 7.8 -i brag_render.mp4 -frames:v 1 -q:v 2 brag.jpg
ffmpeg -i brag_render.mp4 -i brag.jpg -filter_complex "[0:v][1:v]overlay=0:0:enable='eq(n,0)'[v]" \
  -map "[v]" -map 0:a? -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p -c:a copy -movflags +faststart brag.mp4
```

Ses bantlarını yenilemek: `python ~/.claude/skills/hyperframes-creative/scripts/extract-audio-data.py <mp3> --fps 30 --bands 16 -o audio-data.json`
ve ilk 660 kareyi `var AUDIO_DATA = …;` olarak `audio-data.js`'e yaz.

## Kararlar (neden)

- **Sayılar `DEMO_PORTFOY.md`'den** (+%34,35 · TÜFE %31,51 · +2,85 puan · ₺766.876 ·
  beş varlık). Brag'in "uydurma sayı yok / ürünün kendi iddiası" kuralı; ayrıca
  proje kuralı (fiyat_kaynagi "uydurma sayı yasak") tanıtımda da geçerli sayıldı.
- **Tek font (DM Sans).** House-style serif+sans ister; marka tek fontlu, brag
  "projenin kimliği kazanır" der. Ağırlık kontrastı (900 / 500) ile telafi edildi.
- **Telefon zamanlanmamış, sahneler içeriğini değiştiriyor.** Beş ayrı mock yerine
  tek çerçeve: süreklilik hissi + `video_nested`/overlap tuzaklarından uzak.
- **Beat kilitleri** vol-9 preset'inden: 4,23 · 8,44 · 12,65 strong cue; rozet 6,34;
  kartlar 8,96–11,06 beat-grid (set 1,6 sn tutuluyor — okuma tabanı).
- **Audio-reactive yalnızca dekoratifte:** bass EMA → amber glow ölçeği ve telefon
  ışığı. Metin nabız atmaz.
- **Hayalet wordmark `data-layout-ignore`:** %7 opaklıkta dekoratif metin; kontrast
  denetimi metin sanıyordu.
- **`nth-of-type` tuzağı:** `#p-list` içindeki başlık ve segment de `div`; satırları
  `querySelectorAll(".row")[i]` ile seç. İlk taslakta 4–5. satır hiç gizlenmemişti.
- **Müzik 0,5 kazanç:** dosya −14,4 LUFS; 0,35'te karışım −23,5 LUFS çıktı (sessiz).
  brag'in "0,5 üstü olmaz" tavanında kalındı.
- **`letterSpacing` tween'i lint hatası** (piksele oturan yerleşim özelliği) →
  `scaleX` ile değiştirildi.

Müzik lisansı: `YAPMAN_GEREKENLER.md` "Anlatımlı önizleme videosu" maddesi bu
video için de geçerli (aynı ende.app serisi).

## Metin turu 2 (2026-09-18)

Kullanıcı isteği: "daha anlaşılır, basit; gösterilen her özelliği net anlatsın."
Jargon çıkarıldı (TÜFE → Enflasyon, nominal/reel → "kârını enflasyonla kıyaslar",
XU100 → BIST 100, BIST/TEFAS → Hisse/Fon). Her sahne artık bir özelliği düz
cümleyle söylüyor:

| Sahne | Metin |
|---|---|
| 1 | %34,35 · Enflasyon %31,51 · **Enflasyonu geçtin mi?** |
| 2 | Hisse, fon, altın ve döviz — tek uygulamada. / Kârını enflasyonla kıyaslar: **gerçek kazancını** görürsün. |
| 3 | Hisse · Fon · Altın · Döviz / Varlığını ekle; fiyat ve kâr/zarar kendiliğinden güncellenir. |
| 4 | Portföyünü **BIST 100** ile karşılaştır. / Hedef fiyata gelince bildirim al. |
| 5 | sandık · Portföyün, tek sandıkta · Hisse · Fon · Altın · Döviz |

Yan etki: uzun açıklama cümlesi 2 satıra indi → h2/h3 puntoları küçültüldü, grafik
190 px'e çekildi (onay şeridi alarm kartına biniyordu, check yakaladı).
