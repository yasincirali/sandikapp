# Brag Plan: sandık

Çalıştırma: `/brag --voice --tone app-store --format vertical` (2026-09-17).

## What is this app?
sandık, BIST hisse, TEFAS fon, döviz ve altını tek yerde takip eden bir portföy
uygulaması; rakiplerden farkı nominal kârı değil **enflasyona göre reel getiriyi**
söylemesi.

## The angle
Kullanıcının gerçek sorusu "param arttı mı" değil, "param eridi mi". Video bu
soruyla açılır, uygulamanın ekran kaydıyla cevabı gösterir, sonra dört işlevi
(kanıt kartı, ekleme, alarm, endeks karşılaştırması) birer cümleyle geçer.
Sloganlar yok; anlatım **ekranda olup biteni açıklar** (Apple 2.3.4 "narration
… to help explain").

## Hook (first 2-3 seconds)
Ana ekran: TOPLAM NET VARLIK + yeşil rozet "31,49 puan enflasyonun önündesin".
Alt yazı: **Enflasyonu geçtin mi?** Anlatım: "Paran enflasyonu geçti mi? sandık
söyler."

## Key moments (the middle)
- Performans → reel getiri kartı: Nominal %63,00 · TÜFE %31,51 · +31,5 puan —
  iddianın kanıtı, üç satır ayrı ayrı okunuyor.
- Varlık Ekle formu → **Ekle** dokunuşu → listeye düşen yeni fon (DLY).
  Gerçek "giriş → eylem → sonuç" akışı.
- KCHOL detayında "alarm kuruldu" onay şeridi.
- Takip listesi: Portföyüm vs ALTIN_GRAM vs XU100 vs THYAO, 1A çizgileri.

## Outro / punchline
Koyu zemin, uygulama ikonu + **sandık** wordmark'ı, alt satır "Portföyün, tek
sandıkta." Mağaza rozeti / indirme CTA'sı yok (2.3.4), fiyat yok (2.3.7).

## User flow worth showing
Varlık Ekle formu (tür seçili: Fon, DLY aranmış, 1000 adet, fiyat "Otomatik")
→ Ekle butonuna dokunuş → Portföy listesinde yeni satır. Sahne 3 tamamen bu.

## Tone
- Preset: app-store
- Creative direction: "sakin, profesyonel, açıklayıcı — reklam değil, ürün turu"
- Interpretation: kısa cümleler, her sahnede tek fikir, 0,4 sn crossfade, yumuşak
  müzik yatağı, anlatım ekranı okumaz — anlamını söyler.

## Format: vertical — 886x1920 (Apple App Preview, tüm güncel iPhone'lar)
## Duration: 28,4 s

Brag'in 15–25 sn kuralının üstünde, **nedeni**: Türkçe anlatım altı cümleyle
25 saniyeye sığmadı; App Store önizleme sınırı 30 sn ve bu master doğrudan
mağazaya gidecek. Her sahne kendi anlatım satırının süresine göre esnetildi
(brag step-3 "let the voice set the pace").

## Visual identity (from the project)
- Background: #0A1E15 (SandikPalette.dark bg)
- Surface: #112E28
- Accent: #F5A623 (amber) · Display gold: #F5C842
- Gain: #3DB77F · Loss: #FF6B52
- Text: #FFFFFF · ikincil rgba(255,255,255,0.55)
- Display font: DM Sans (assets/fonts, uygulamanın kendi dosyaları)
- Body font: DM Sans
- Strongest visual element: yeşil enflasyon rozeti + sarı TOPLAM NET VARLIK

## Share copy (draft)
sandık yayında: hisse, fon, altın ve döviz tek portföyde — ve paranın
enflasyonu geçip geçmediğini tek bakışta söylüyor.

## Audio direction
- Role: warm bed under narration; narration is the lead.
- Music: `happy-beats-business-moves-vol-11-by-ende-dot-app.mp3` (114,84 BPM,
  warm/business-y — app-store önerisi)
- Music treatment: 0→0,30 fade-in 0,8 sn; anlatım altında 0,13'e iner, cümle
  bitince 0,6 sn'de geri gelir; son 1,2 sn fade-out.
- Music cue guidance: preset `assets/music/cues/…vol-11.music-cues.md`.
  Sahne başlangıçları beat-grid'e oturtuldu: 4,75 · 10,54 · 16,34 · 19,49;
  kapanış **24,23 strong cue**'ya kilitli.
- Audio-reactive treatment: none — içerik ekran kaydı, üstüne nefes alan glow
  eklemek 2.3.4'ün "screen capture" ruhunu bozar. Belgelendi, atlandı.
- SFX posture: sparse, professional restraint (app-store: alt yazı başına bir
  `drop_001`, kapanışta `impactBell_heavy_000`).
- Audio-coupled moments: alt yazı panelinin girişi (drop), wordmark inişi (bell).
- Restraint rule: whoosh yok, tuş sesi yok, ekran kaydının kendi sesi yok
  (kayıt zaten sessiz).

## Voiceover script (tr-TR, hitap "sen")
Kokoro'da Türkçe ses yok (`hyperframes tts --list`: en/es/fr/hi/it/pt/ja/zh).
Bu yüzden anlatım **edge-tts `tr-TR-AhmetNeural`** ile üretildi; `tr-TR-EmelNeural`
(kadın) alternatifi `assets/vo/e_*.wav` olarak yanında duruyor.

| # | Sahne | Satır | Süre |
|---|---|---|---|
| 1 | rozet | Paran enflasyonu geçti mi? sandık söyler. | 3,92 s |
| 2 | kanıt | Nominal getiri, enflasyon, aradaki fark. Hepsi ayrı ayrı. | 5,23 s |
| 3 | ekle | Hisse, fon, altın, döviz. Ekle, gerisi otomatik. | 4,76 s |
| 4 | alarm | Hedef fiyata gelince haber verir. | 1,93 s |
| 5 | takip | Endeksi geçiyor musun? Karşılaştır. | 3,54 s |
| 6 | kapanış | sandık. Portföyün, tek sandıkta. | 3,52 s |

## Storyboard

### Scene 1 — Rozet (hook) — 4,75 s (0,00–4,75)
Ana ekran kaydı (kayit.mov 0,9 sn'den). TOPLAM NET VARLIK ₺973.501, yeşil
rozet "31,49 puan enflasyonun önündesin". Alt yazı: **Enflasyonu** geçtin mi?
Gizlilik maskesi: ortak seçicideki gerçek "Test" adı "Ayşe" ile örtülür (2.3.9).
Sequential/interaction: none — kare durur, izleyici rozeti okur.
Audio intent: soru sorulur, müzik yeni giriyor.
Audio-coupled idea: alt yazı girişinde drop.
Music: bed fade-in.
Transition mood: soft crossfade → Scene 2

### Scene 2 — Kanıt — 5,79 s (4,75–10,54)
Performans sekmesi, reel getiri kartı: Nominal %63,00 · Dönem TÜFE %31,51 ·
Puan farkı +31,5. Alt yazı: Nominal değil, **reel** getiri.
Sequential/interaction: none.
Audio intent: sakin, açıklayıcı.
Transition mood: soft crossfade → Scene 3

### Scene 3 — Ekle — 5,80 s (10,54–16,34)
Varlık Ekle formu (Fon · DLY · 1000 adet · fiyat Otomatik) → Ekle dokunuşu
(ilk ~1,6 sn) → Portföy listesi, yeni satır. Alt yazı: Ekle, **gerisi** otomatik.
Sequential/interaction: yes — gerçek kayıttaki dokunuş ve sonuç.
Audio intent: "kolay" hissi.
Transition mood: soft crossfade → Scene 4

### Scene 4 — Alarm — 3,15 s (16,34–19,49)
KCHOL detayı, alt şerit "KCHOL için alarm kuruldu: ₺216,83 üstüne çıkınca".
Alt yazı: Hedefe gelince **bildirim**.
Sequential/interaction: onay şeridi kareye girer.
Transition mood: soft crossfade → Scene 5

### Scene 5 — Takip — 4,74 s (19,49–24,23)
Takip listesi, 1A karşılaştırma çizgileri + dört lejant. Alt yazı (üstte, lejant
kapanmasın): **Endeksi** geçiyor musun?
Sequential/interaction: none.
Transition mood: soft crossfade → Scene 6

### Scene 6 — Kapanış — 4,17 s (24,23–28,40)
Koyu radyal zemin, ikon + **sandık** (gold, glow) + "Portföyün, tek sandıkta".
Beat-locked: 24,23 (strong cue). Bell SFX wordmark'la aynı anda.
Audio intent: kapanış; müzik son 1,2 sn'de söner.

**Music mood for this video:** warm / upbeat-restrained
**Audio summary:** Müzik yatağı sessizce girer, altı anlatım cümlesinin altına
çekilir, kapanış zilinin ardından söner.
