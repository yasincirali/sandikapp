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
