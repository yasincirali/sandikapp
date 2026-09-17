# Hyperframes Composition Brief: sandık (launch)

## Objective
sandık için paylaşılabilir launch/brag videosu — mağaza önizlemesinden
bağımsız, uygulama arayüzü HTML ile yeniden çizilmiş, brag'in hareket diliyle.

## Output
- Composition directory: `brag-output-2026-09-17-launch/composition/`
- Rendered video: `brag-output-2026-09-17-launch/brag.mp4`
- Format: landscape — 1920x1080, 30 fps
- Duration: 21,6 s

## Source Material
- Project root: `c:\projects\PortfoyTakip`
- Primary files read: `lib/theme/sandik.dart`, `store_listing/DEMO_PORTFOY.md`
  (sayılar), `lib/utils/tr_format.dart` (₺ ve % biçimi), `assets/images/sandik_icon.png`
- Product name: sandık
- Tagline / strongest claim: "+2,85 puan enflasyonun önündesin" · "Portföyün, tek sandıkta"
- Key UI or visual moment to recreate: ana ekran TOPLAM NET VARLIK kartı + yeşil
  enflasyon rozeti; varlık listesi satırları; karşılaştırma çizgisi; alarm şeridi
- Copy that must appear verbatim:
  - Enflasyonu geçtin mi?
  - +2,85 puan enflasyonun önündesin
  - Portföyün, tek sandıkta

## Creative Direction
- Tone preset: default
- Creative direction: sakin özgüven — ürün kendi sayılarıyla konuşur
- Interpretation: sol metin / sağ telefon zonu; sahneler içerik değişimiyle akar,
  telefon 4,23–17,38 arasında sabit; her giriş farklı yön ve ease
- Angle / Hook / Outro: bkz. brag-plan.md
- Avoid: generic SaaS dili, gradient text, eşit ağırlıklı ortalanmış yığın
  (kapanış hariç), waveform/equalizer, uydurma sayı

## Visual Identity
- Background: #0A1E15 · Text: #FFFFFF · Accent: #F5A623 / #F5C842 · gain #3DB77F · loss #FF6B52
- Display font: DM Sans 800/900 (`assets/fonts`, @font-face) · Body: DM Sans 500/600
- Visual references: uygulamanın kart yarıçapı 20, sekme çubuğu amber, rozet yeşil

## Storyboard
1. Hook — 4,23 s — %34,35 sayaç, TÜFE %31,51, "Enflasyonu geçtin mi?"
2. Reveal — 4,21 s — wordmark; telefon: toplam sayaç + rozet (6,34 cue)
3. Varlıklar — 4,21 s — 5 kart beat-grid'de
4. Karşılaştır + Alarm — 4,73 s — çizgi grafik çizimi, alarm şeridi (15,28)
5. Kapanış — 4,22 s — ikon + wordmark + alt satır

## Audio
- Audio role: warm bed
- Audio arc: fade-in → sabit 0,35 → kapanışta 1,5 sn fade-out
- Music: `assets/music/happy-beats-business-moves-vol-9-by-ende-dot-app.mp3`
- Music cue guidance: preset vol-9 — strong cue kilitleri 4,23 / 8,44 / 12,65 (+6,34 rozet); beat-grid 8,96…11,06 kartlar
- Audio-reactive treatment: subtle — `audio-data.js` (extract-audio-data.py, 16 bant); bass → glow ölçeği, treble → wordmark glow
- Audio-coupled moments: bkz. plan; SFX dosyaları `assets/sfx/` (drop_001/002, impactSoft_medium_000, card-place-1..4, card-slide-1, switch_001, impactBell_heavy_000)
- SFX analysis guidance: card-place HF riski yüksek → tek tek, 0,55 ses; card-slide-1 orta

## Hyperframes Instructions
Standalone `index.html`, tek paused GSAP timeline `window.__timelines["sandik-launch"]`,
vendored GSAP, yerel @font-face. `npx hyperframes check` tek kapı.
