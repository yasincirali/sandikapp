# App Store Önizleme Videosu — sandık

Remotion projesi. `store_listing/preview_video/`.

## Durum

| | |
|---|---|
| Kurgu, zamanlama, ses, grade | ✅ hazır ve render edilmiş |
| Görsel kaynak | ⚠️ **geçici** — statik ekran görüntüleri |
| Gerçek ekran kaydı | ⛔ bekleniyor → `CEKIM_SENARYOSU.md` |

Şu anki `out/sandik_preview_iphone.mp4` **teslim edilebilir değil**, kurgu
provasıdır. Sebebi aşağıda.

## Neden gerçek kayıt şart

Apple App Review 2.3.4:

> "previews may only use **video screen captures of the app itself**. …
> You can add narration and video or textual overlays to help explain
> anything that isn't clear from the video alone."

Statik ekran görüntüsünü Ken Burns ile hareketlendirmek "screen capture"
sayılmayabilir. Kurgu zaten gerçek kaydı bekleyecek şekilde yazıldı:
`src/components/Capture.tsx` içinde `HAS_CAPTURE = false`.

**Kayıt geldiğinde:**
1. Dosyayı `public/shots/kayit.mov` olarak koy.
2. `Capture.tsx` → `HAS_CAPTURE = true`.
3. `src/Preview.tsx` içindeki `startFrom` değerlerini kaydın gerçek
   zamanlamasına göre düzelt (şu an çekim senaryosuna göre tahmini).
4. `PrivacyMask` gereksizleşir (kurgusal hesapla çekildiyse) — kaldır.
5. Yeniden render et.

## Anlatımlı sürüm — `brag-output/` (2026-09-17)

Kullanıcı isteği: "daha profesyonel, basit açıklayıcı cümleler, profesyonel ses".
`/brag --voice --tone app-store` ile ikinci bir hat kuruldu: aynı ekran
kayıtlarından, altı sahne + kapanış, Türkçe anlatım (edge-tts AhmetNeural),
müzik yatağı ve seyrek SFX; render **Hyperframes**. Teslim dosyası
`brag-output/brag.mp4` = `out/sandik_preview_iphone_anlatimli.mp4`.
Kararlar ve yeniden üretim: `brag-output/README.md`. Bu Remotion kurgusu
(`src/`) sessiz/SFX'li sürüm olarak duruyor; ikisi bağımsızdır.

## Açıklamalı, seslendirmesiz mağaza sürümü — `brag-output-2026-09-18-store/` (2026-09-18) ← GÜNCEL

Launch videosunun sade üslubu mağaza videosuna taşındı: gerçek ekran kayıtları,
her sahnede özellik başlığı + tek açıklayıcı cümle, seslendirme yok, müzik + seyrek
SFX. Teslim: `brag-output-2026-09-18-store/brag.mp4` = `out/sandik_preview_iphone_aciklamali.mp4`
(886×1920 · 30 fps · CBR 11 Mbps · AAC 256k · 28,0 s). Anlatımlı sürüm yedek olarak duruyor.

## Launch videosu — `brag-output-2026-09-17-launch/` (2026-09-17)

Mağaza videosundan **bağımsız** üçüncü hat: ekran kaydı yok, arayüz HTML/GSAP ile
yeniden çizildi (brag "recreate a working-app moment"), 1920×1080, 21,6 sn,
müzik + SFX, anlatım yok. Paylaşım için (X / LinkedIn / README). Sayılar
`DEMO_PORTFOY.md`'den. Kararlar: o klasördeki README.

## Tanıtım videosu — `Tanitim` (2026-09-21) ← GÜNCEL ARAYÜZ

"Son haliyle, ilgi çekici, işlevleri basitçe anlatan" tanıtım. 1920×1080 · 30 fps ·
27,4 sn · müzik (vol-11, 114 BPM ızgarası) + SFX, anlatım yok. Teslim
`out/sandik_tanitim_16x9.mp4`; kontrol kareleri `out/check_tanitim/`.
Kod `src/reklam/Tanitim.tsx` + `src/reklam/ui_home.tsx`; render
`node scripts/render_tanitim.mjs` (ya da `npx remotion render src/index.ts Tanitim …`).

Sekiz sahne, her biri özellik başlığı + tek düz cümle (2026-09-18 üslubu):
kanca → ana ekran → Bugün kartı → gerçek kazanç (KCHOL) → enflasyon → ortak
kaydırma (Ayşe'nin bugünü) → bildirimler → CTA.

Kararlar:
- **Arayüz `ui_home.tsx` ile yeniden çizildi**, ekran kaydı yok: güncel ana ekran
  (piyasa şeridi, görünüm çipi + sayfa noktaları, Bugün kartı, kaydırmalı geçiş)
  için cihaz kaydı bu turda yoktu; emülatör render edemiyor. `ui.tsx` PhoneHome
  eski (09-19) arayüzü çizer, reklam paketi onu kullanmaya devam eder.
- **Sayılar** DEMO_PORTFOY.md'den; DEMO'da olmayanlar `theme.ts` `TANITIM` altında
  ve TEMSİLİ (gün içi hareket, piyasa bandı, hedef, Ayşe'nin günü, bildirimler).
- **Türkçe büyük harf:** CSS `text-transform: uppercase` yalnızca `lang="tr"` ile
  i→İ yapar ("AYŞE'NİN"). Aynı hata uygulamada da vardı; `trBuyukHarf` ile düzeltildi.
- Bu video mağaza ÖNİZLEMESİ için geçersiz (Apple 2.3.4 yalnızca ekran kaydı);
  sosyal medya / README / reklam içindir.

## Reklam paketi — `../reklam/` (2026-09-19)

Aynı Remotion projesinde ayrı kompozisyonlar (`src/reklam/`): Reels 9:16 15 sn,
kare 1:1 12 sn, YouTube bumper 16:9 6 sn + beş statik görsel (kare ×3, hikâye,
banner). Arayüz ekran kaydı değil, HTML ile yeniden çizim (mağaza önizlemesinde
KULLANILMAZ — Apple 2.3.4). Kararlar ve yeniden üretim: `../reklam/README.md`;
render `node scripts/render_reklam.mjs`.

## Komutlar

```bash
npm run studio     # önizleme / zamanlama ayarı (tarayıcıda)

# Teslim master'ı — App Store spec'ine uygun
npx remotion render src/index.ts SandikPreview \
  out/sandik_preview_iphone.mp4 \
  --codec h264 --video-bitrate 11M \
  --audio-codec aac --audio-bitrate 256k --overwrite

# Kare çıkarıp gözle kontrol (zorunlu adım)
npx remotion still src/index.ts SandikPreview out/check_40.png --frame 40 --overwrite
```

iPad 13" ayrıca istenirse: kompozisyon `SandikPreviewIpad` (1200×1600).

## Doğrulanmış çıktı

`npx remotion ffprobe` ile teyit edildi:

| Gereksinim | Spec | Bizde |
|---|---|---|
| Süre | 15–30 sn | **24,0 sn** ✅ |
| Çözünürlük | 886×1920 (tüm güncel iPhone) | **886×1920** ✅ |
| FPS | maks 30, progressive | **30, progressive** ✅ |
| Codec | H.264 | **h264 (avc1)** ✅ |
| Video bit hızı | 10–12 Mbps | **10,05 Mbps** ✅ |
| Ses | stereo, 44.1/48 kHz, AAC 256k | **AAC 48 kHz stereo 253k** ✅ |
| Boyut | < 500 MB | **31 MB** ✅ |

## İçerik kuralları — neye uyuldu

- **2.3.4** — yalnızca uygulama ekranı + açıklayıcı metin. Stok görüntü,
  canlı çekim, el, saf motion-graphics **yok**.
- **2.3.7** — videoda **fiyat geçmiyor**.
- **2.3.8** — 4+ yaş derecesine uygun.
- **2.3.9** — ses tamamen sentetik (`scripts/gen-sfx.mjs`), telif zinciri
  yok. Gerçek kişi adı maskelendi (`PrivacyMask`) — kalıcı çözüm kurgusal
  hesapla çekim.
- **2.3.10** — Android / Google Play adı, ikonu, görseli **yok**.
- Kapanışta **mağaza rozeti ve "indir" CTA'sı bilerek yok**: 2.3.4 yalnızca
  açıklayıcı overlay'e izin veriyor, indirme çağrısı ekranı açıklamıyor.
  Kullanıcı zaten ürün sayfasında.

## Bilinen eksik — kayıt sırasında düzeltilecek

**Varlık detayı sahnesi (kare ~330).** Metin "Komisyon ve temettü dahil
gerçek kâr" diyor ama placeholder görüntüde komisyon/temettü satırları
görünmüyor, üstelik ekran zararda. İddia ile görüntü çelişiyor.

Çekim senaryosu adım 4 bunu çözüyor: **komisyonu ve temettüsü olan** bir
varlığın maliyet kırılımı kaydedilecek. Bu sahne videonun en güçlü
farklılaştırıcısı — görüntü iddiayı desteklemezse etkisi kaybolur.

## Mimari notu

- `src/theme.ts` — tek renk/easing kaynağı. Renkler `lib/theme/sandik.dart`
  `SandikPalette.dark`'tan birebir. Remotion skill'inin kendi paleti
  (mor/camgöbeği) **alınmadı**: tanıtımda uygulamanın kimliği kazanır.
- Bu proje Flutter'dan bağımsızdır; `lib/` altına hiçbir şey girmez,
  Remotion bağımlılığı uygulamaya eklenmez.
- `node_modules/` ve `out/` commit edilmez (bkz. `.gitignore`).

## App Store önizlemesi — 30 sn (2026-09-21 kaydı)

`Onizleme30` · 886×1920 · 30 fps · `out/sandik_onizleme_30sn.mp4`

```bash
node scripts/render_onizleme30.mjs check   # yalnızca kontrol kareleri
node scripts/render_onizleme30.mjs         # kareler + video
```

**Mesaj: "gerçeği söyler".** Kayıttaki portföy enflasyonun GERİSİNDE
(−0,5 / −20,6 / −9,2 puan, kırmızı). Eski kurgular yeşil demo portföye
dayanıyordu; bu kayıtla o iddia kurulamazdı. Kullanıcı kararı: kırmızıyı
gizleme, mesajı ona çevir. Videoda tek bir rakam rötuşlanmadı —
`fiyat_kaynagi.dart`'ın "uydurma sayı yasak" kuralının pazarlama tarafı.

Sahneler (ham kayıt saniyesi → altyazı):

| Sn | Kayıt | Üst etiket | Cümle |
|---|---|---|---|
| 0–4,7 | 04 | BUGÜN NE OLDU | Tüm paran **tek ekranda** |
| 4,7–9,5 | 10 | REEL GETİRİ | Kârın var ama **enflasyonu geçti mi?** |
| 9,5–14,2 | 56 | GÜNLÜK | Gün içinde **ne oldu** |
| 14,2–18,9 | 69 | NEREDEN GELDİ | Kendi paran mı, **piyasa mı?** |
| 18,9–23,7 | 84 | HER VARLIK | Aldığın günden **bugüne** |
| 23,7–26,9 | 31 | BİRLİKTE | İkinizin portföyü **tek toplamda** |
| 26,9–30 | — | — | sandık · Paran ne kadar, **gerçekte** ne kadar. |

Kesimler 114 BPM vuruş ızgarasında (`beat()`), müzik ve SFX reklam
hattıyla ortak. Ham kayıt `public/shots/kayit2.MP4` (1126×2436, 60 fps,
133 sn); kaynağı `video_source/kayit.MP4`.

**Altyazı konumu kritik:** `bottom: 300` — uygulamanın alt sekme çubuğu
kayıtta ~150 px yer kaplıyor ve ilk denemede metin "Ana / Portföy /
Performans" etiketlerinin üstüne biniyordu. Altyazının kendi gradyan
bandı var; açık renkli karta denk geldiğinde de okunur.
