# Hyperframes Composition Brief: sandık

## Objective
sandık için App Store önizlemesi olarak da kullanılabilecek kısa, anlatımlı
tanıtım videosu. Görsel içerik **yalnızca uygulamanın gerçek ekran kaydı**
(Apple 2.3.4); üstüne açıklayıcı alt yazı ve anlatım.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: vertical — 886x1920, 30 fps, H.264
- Duration: 28,4 s (App Store sınırı 30 s)

## Source Material
- Project root: `c:\projects\PortfoyTakip` (Flutter uygulaması)
- Primary files read: `lib/theme/sandik.dart` (palet), `store_listing/preview_video/src/*`
  (önceki Remotion kurgusu, ölçülmüş kayıt zamanları), `CEKIM_SENARYOSU.md`,
  `DEMO_PORTFOY.md`, `public/shots/kayit.mov` + `kayit2.MP4`
- Product name: sandık
- Tagline / strongest claim: "31,49 puan enflasyonun önündesin"
- Key UI or visual moment to recreate: hiçbiri yeniden çizilmez — gerçek kayıt
  klipleri `assets/clips/*.mp4` (886x1920, 30 fps, sessiz)
- Copy that must appear verbatim:
  - Enflasyonu geçtin mi?
  - Portföyün, tek sandıkta

## Creative Direction
- Tone preset: app-store
- Creative direction: sakin, profesyonel, açıklayıcı ürün turu
- Interpretation: her sahnede tek cümle alt yazı + tek cümle anlatım; 0,45 s
  crossfade; hareket yalnızca panel girişleri ve kapanış wordmark'ı
- Angle: bkz. brag-plan.md
- Hook: Enflasyonu geçtin mi?
- Outro / punchline: sandık — Portföyün, tek sandıkta.
- Avoid: pazarlama sloganı, fiyat/ücretsiz ibaresi, mağaza rozeti, Android/Play
  adı, stok görüntü, ekran kaydı dışı görsel dolgu

## Visual Identity
- Background: #0A1E15
- Text: #FFFFFF
- Accent: #F5A623 · gold #F5C842
- Display font: DM Sans 700/800 (`assets/fonts/DMSans-*.ttf`, @font-face)
- Body font: DM Sans 500/600
- Visual references from the project: önceki kurgunun Caption paneli
  (rgba(7,22,15,0.96), 1px amber çerçeve, radius 28), StatusBarPatch ("9:41"),
  PrivacyMask ("Ayşe")

## Storyboard
brag-plan.md storyboard'u sözleşmedir.

1. Rozet — 4,75 s — ana ekran + yeşil rozet; "Enflasyonu geçtin mi?"
2. Kanıt — 5,79 s — reel getiri kartı; "Nominal değil, reel getiri"
3. Ekle — 5,80 s — form → Ekle → liste; "Ekle, gerisi otomatik"
4. Alarm — 3,15 s — alarm onay şeridi; "Hedefe gelince bildirim"
5. Takip — 4,74 s — endeks karşılaştırması; "Endeksi geçiyor musun?" (üst)
6. Kapanış — 4,17 s — ikon + wordmark + alt satır

## Audio
- Audio role: warm bed under narration
- Audio arc: fade-in → anlatım altında 0,13 → cümle aralarında 0,30 → kapanış
  zili → 1,2 s fade-out
- Music: `assets/music/happy-beats-business-moves-vol-11-by-ende-dot-app.mp3`
- Music treatment: baseline 0,30; ducking tween'le (volume 0,13); son fade
- Music cue guidance: preset `~/.claude/skills/brag/assets/music/cues/…vol-11…`;
  sahne başları beat-grid'de (4,75 · 10,54 · 16,34 · 19,49), kapanış 24,23
  strong cue'ya kilitli (`// beat-locked`)
- Audio-reactive treatment: none (ekran kaydı üstüne reaktif glow 2.3.4 ruhuna
  aykırı; belgelendi)
- Audio-coupled moments:
  - her alt yazı paneli girişi — `sfx/interface/drop_001.ogg` @0,55
  - kapanış wordmark'ı — `sfx/impact/impactBell_heavy_000.ogg` @0,5
- Voiceover: `assets/vo/a_0N_*.wav` (edge-tts tr-TR-AhmetNeural; Kokoro'da
  Türkçe yok). Kendi track'inde, volume 1. Sahne süreleri anlatıma göre
  esnetildi.
- SFX selection guidance: sfx-analysis.md → drop_001 low HF risk, bell medium
- Audio files: `assets/music`, `assets/sfx`, `assets/vo` kompozisyon içinde

## Hyperframes Instructions
Standalone `index.html`, tek paused GSAP timeline (`window.__timelines["sandik-brag"]`),
vendored `vendor/gsap.min.js`. Video klipleri kök seviyesinde, zamanlanmamış
sarmalayıcı içinde (video_nested_in_timed_element kuralı). Her `<audio>` id'li
ve ayrı track index'te. `npx hyperframes check` tek kapı.
