# Brag Plan: sandık (launch)

Çalıştırma: `/brag` (ton: default, format: landscape, ses: yok, müzik+SFX: var),
2026-09-17. Mağaza önizlemesinden **bağımsız**: ekran kaydı yok, arayüz HTML/GSAP
ile yeniden çizildi; paylaşım videosu (X / LinkedIn / GitHub README).

## What is this app?
sandık: BIST hisse, TEFAS fon, döviz ve altını tek portföyde toplayan, kârı
enflasyona göre "reel" söyleyen kişisel portföy uygulaması.

## The angle
"Portföyün yeşil; peki para gerçekten arttı mı?" Sayı önce gelir (%34,35),
sonra TÜFE (%31,51), sonra soru. sandık'ın cevabı yeşil rozettir: **+2,85
puan enflasyonun önündesin.** Sonra üç somut şey: varlıklar tek tek düşer,
endeks çizgisi çizilir, alarm şeridi kalkar. Sayılar `DEMO_PORTFOY.md`'den —
uydurma değil.

## Hook (first 2-3 seconds)
Sol yarı, dev sayaç: **%34,35** "portföy getirisi" (0→34,35 sayar), altına
"TÜFE %31,51" kayar, sonra altın renkli soru: **Enflasyonu geçtin mi?**

## Key moments (the middle)
- Wordmark + ikon sola oturur; sağdaki telefon mock'unda TOPLAM NET VARLIK
  ₺0 → ₺766.876 sayar, yeşil rozet **+2,85 puan enflasyonun önündesin** 6,34 sn
  strong cue'da kayar.
- Beş varlık satırı beat-grid'de tek tek düşer (kart sesleri): Çeyrek Altın,
  DLY, KCHOL, ABD Doları, SAHOL (−%8,0 — her şey yeşil değil).
- Karşılaştırma çizgisi çizilir (Portföyüm altın, XU100 soluk), ardından alarm
  şeridi: "KCHOL için alarm kuruldu: ₺216,83 üstüne çıkınca".

## Outro / punchline
Her şey boşalır; ikon + **sandık** + "Portföyün, tek sandıkta." Alt satırda
mono etiket: BIST · TEFAS · Döviz · Altın.

## User flow worth showing
Giriş (toplam + rozet) → varlıklar → karşılaştır → alarm kur. Her adım
uygulamanın gerçek bileşenlerinin yeniden çizimi (renkler, metinler, biçim
`lib/theme/sandik.dart` ve `tr_format`'tan).

## Tone
- Preset: default
- Creative direction: "sakin özgüven — ürün kendi sayılarıyla konuşur"
- Interpretation: 5 sahne, 3–5 sn; expo/back ease karışımı; sol metin, sağ
  telefon; her girişte farklı yön; crossfade değil, içerik değişimi.

## Format: landscape — 1920x1080
## Duration: 21,6 s

## Visual identity (from the project)
- Background: #0A1E15 · surface #112E28 / #1A3D2E
- Accent: #F5A623 (amber) · gold #F5C842 · gain #3DB77F · loss #FF6B52
- Text: #FFFFFF · ikincil rgba(255,255,255,0.62)
- Display font: DM Sans 800/900 (marka fontu; serif eşleştirme bilinçli olarak
  yapılmadı — uygulama tek fontlu)
- Body font: DM Sans 500/600
- Strongest visual element: yeşil enflasyon rozeti + altın toplam

## Share copy (draft)
sandık'ı yaptım: hisse, fon, altın ve döviz tek portföyde — ve paranın
enflasyonu gerçekten geçip geçmediğini söylüyor.

## Audio direction
- Role: warm bed, mid-energy
- Music: `happy-beats-business-moves-vol-9-by-ende-dot-app.mp3` (114,84 BPM)
- Music treatment: 0→0,35 fade-in 0,6 sn; son 1,5 sn fade-out
- Music cue guidance: preset vol-9. Sahne başları strong cue: **4,23** (wordmark),
  **8,44** (varlıklar), **12,65** (grafik); rozet **6,34**; kartlar beat-grid
  8,96 · 9,50 · 10,01 · 10,54 · 11,06; alarm 15,28; kapanış 17,38.
- Audio-reactive treatment: subtle — bass (band 0) amber glow'u ve telefonun dış
  ışığını nefes aldırır (%0–12 ölçek), treble wordmark glow'unu hafif açar.
  Waveform/equalizer yok.
- SFX posture: moderate (default tone) — 3–5 anlamlı vuruş + kart dizisi
- Audio-coupled moments: sayaç (drop), hook satırı (soft impact), wordmark
  (soft impact), rozet (drop), 5 kart (card-place/slide), grafik (drop),
  alarm (switch), kapanış (bell)
- Restraint rule: her beat'e ses yok; kartlar dışında art arda vuruş yok

## Storyboard

### Scene 1 — Hook — 4,23 s (0,00–4,23)
Sol: "PORTFÖY GETİRİSİ" mono etiket, dev **%34,35** sayaç (0,3→1,8 sn), altına
"TÜFE %31,51" sağdan kayar (2,0), sonra altın **Enflasyonu geçtin mi?** (2,6, hold
1,6 sn). Sağ: boş telefon çerçevesi yavaşça belirir (ışık).
Sequential/interaction: sayaç + iki satır sıralı.
Audio-coupled idea: sayaç başı drop, soru satırı soft impact.
Transition mood: clean cut on strong cue → Scene 2

### Scene 2 — Reveal — 4,21 s (4,23–8,44)
Sol: ikon + **sandık** back.out ile iner (4,23), "Portföyün, tek sandıkta"
(4,7). Sağ telefon: TOPLAM NET VARLIK ₺0→₺766.876 (4,4→6,0), "+₺196.091 · %34,35"
yeşil, rozet **+2,85 puan enflasyonun önündesin** (6,34 strong cue).
Audio-coupled idea: wordmark soft impact, rozet drop.
Transition mood: içerik değişimi (telefon kalır) → Scene 3

### Scene 3 — Varlıklar — 4,21 s (8,44–12,65)
Sol: **Hisse · Fon · Altın · Döviz** (satır satır), altına "hepsi tek listede".
Sağ telefon: 5 satır beat-grid'de düşer, her biri card sesiyle; SAHOL kırmızı.
Sequential/interaction: yes — 5 kart, 0,5 sn arayla (okuma için son set 1,5 sn tutulur).
Transition mood: içerik değişimi → Scene 4

### Scene 4 — Karşılaştır + Alarm — 4,73 s (12,65–17,38)
Sol: **Endeksi geçiyor musun?** ; 15,28'de altına "Hedefte bildirim." Sağ telefon:
çizgi grafik çizilir (Portföyüm altın, XU100 soluk kırmızı, sıfır çizgisi kesikli),
lejant; 15,28'de yeşil alarm şeridi yukarı kayar.
Audio-coupled idea: grafik drop, alarm switch.
Transition mood: soft fade-out → Scene 5

### Scene 5 — Kapanış — 4,22 s (17,38–21,60)
Ortada ikon (back.out), **sandık** (glow), "Portföyün, tek sandıkta",
mono "BIST · TEFAS · Döviz · Altın". Bell 17,45. Son 0,4 sn fade.

**Music mood for this video:** upbeat, laid-back
**Audio summary:** Yatak sessizce girer, kartlar beat'e oturur, zil kapatır.
