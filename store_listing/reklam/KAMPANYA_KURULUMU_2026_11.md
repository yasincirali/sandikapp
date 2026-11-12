# Ücretli kampanya kurulumu — sandık (2026-11-12)

Plan ve gerekçe: thread "Sandık için reklam ve ASO planı" (Claude Doc
"Sandık reklam ve ASO başlangıç planı"). Bu dosya yasin'in panele birebir
gireceği listedir. Kampanyalar **duraklatılmış** kurulur; Android test satın
alması geçmeden açılmaz.

## 0. Ölçüm kararı (1. faz: yalnız yükleme)

Neden: RevenueCat'in AdServices token toplamasını açmak ve Firebase'i
Google Ads'e bağlamak, verinin yeni bir alıcıya/amaca gitmesi demek.
`legal/tr/COKEZ_VE_DEPOLAMA.md` bugün "Firebase dışında atıf SDK'sı yok"
diyor ve RevenueCat'i yalnız abonelik doğrulaması için sayıyor. Yasal metin
kuralına göre bu, "Sürüm" + "Onay sürümü" artışı ve herkese yeniden onay
demek. 10.000 ₺'lik ilk ay için bu bedele değmez.

- Apple Ads: yükleme, dokunma maliyeti (CPT) ve yükleme maliyeti (CPA)
  Apple Ads panelinden; App Store kendisi ölçer, SDK gerekmez.
- Google: kampanya hedefi **Yüklemeler**, ölçüm Google Play'den. Firebase'i
  Google Ads'e **bağlama** (yeni amaç olur).
- Deneme ve abonelik: RevenueCat'te günlük toplam, harcama günleriyle yan
  yana. Kelime bazında satış verisi bu fazda yok.
- 2. faz (harcama büyürse): AdServices + Firebase bağlantısı + yasal metin
  güncellemesi aynı PR'da.

## 1. Apple Search Ads (Advanced)

Ülke: Türkiye. Cihaz: iPhone (iPad kapalı; iPad ekran görüntüsü seti zayıf).
Teklif: Apple'ın önerdiği aralığın alt ucundan başla, ilk hafta veriye göre
ayarla. Tüm kelimeler **tam eşleşme**.

### Kampanya A — Marka (günlük 70 ₺)

| Grup | Kelimeler |
|---|---|
| Marka | sandık, sandik, sandık uygulama, sandık portföy, sandık yatırım |

Neden ayrı: App Store "sandık" (noktasız ı) aramasında bizi göstermiyor;
"sandik" 1. sırada. Marka sonucu ucuz görünür, başarı sayılmaz.

### Kampanya B — Kategori (günlük 120 ₺)

Her gruba Kampanya A'nın kelimeleri **negatif** eklenir (çakışma olmasın).

| Grup | Kelimeler | Özel ürün sayfası (varsa) |
|---|---|---|
| Portföy | portföy takibi, portföy takip, portfoy takip, yatırım takip, birikim takip, varlık takip | varsayılan |
| Hisse ve temettü | hisse takip, borsa takip, bist takip, hisse senedi takip, temettü takip, temettü takvimi | temettü |
| Altın, döviz, fon | altın takip, gram altın takip, döviz takip, tefas fon takip, fon takip | altın |

### Kampanya C — Keşif (günlük 20 ₺)

Search Match açık, kelime yok, düşük teklif. Arama terimleri raporundan
deneme getiren terim B'ye tam eşleşme olarak taşınır ve C'de negatif olur.

### Negatif kelimeler (B ve C)

Aracı kurum ve al-sat arayan kişi takip uygulaması istemiyor:
`hisse al sat`, `hesap aç`, `aracı kurum`, `kaldıraç`, `forex`, `kredi`,
`bedava`, `para kazan`, `kripto borsa`, `binance`. Rakip ve banka uygulama
adlarına teklif verilmez (pahalı, düşük niyet); arama terimi raporunda
görünürlerse negatife eklenir.

## 2. Google Ads — uygulama kampanyası (Android)

- Hedef: Yüklemeler. Ülke: Türkiye. Dil: Türkçe. Günlük 120 ₺, ilk 2 hafta
  hedef YBM (tCPI) girmeden "yükleme sayısını artır".
- Öğrenme döneminde (7–10 gün) bütçe/hedef değişmez.
- Finansal hizmet doğrulaması istenirse tamamlanır.

### Başlıklar (≤30 karakter)

1. Portföyün tek ekranda
2. Hisse, fon, altın, döviz
3. Enflasyonu geçtin mi?
4. Temettülerini takip et
5. TEFAS fonların bir arada

### Açıklamalar (≤90 karakter)

1. BIST hisselerini, TEFAS fonlarını, altını ve dövizi tek uygulamada takip et.
2. Gerçek getirini TÜFE ile karşılaştır, paranın eriyip erimediğini gör.
3. Temettü takvimi, fiyat alarmı ve aylık rapor. Ücretsiz başla.
4. Alış fiyatını gir, kârını ve zararını her gün güncel gör.
5. Eşinle ortak portföy tut, birikiminizi birlikte izleyin.

Metinler getiri vaadi ya da yatırım tavsiyesi içermez; sayı yok.

### Görsel ve video

`store_listing/reklam/out/` (README'deki tablo): 9:16 reel, 1:1 kare,
16:9 bumper, kare görseller. Arayüz yeniden çizim, sayılar
`DEMO_PORTFOY.md` ile aynı.

## 3. Karar kuralları

- 14 günde 300 ₺ harcayıp yükleme maliyeti grubun iki katını aşan kelime durur.
- İyi giden gruba bütçe en fazla %20 artar, artışlar arasında 3–5 gün.
- 30. gün: RevenueCat deneme ve abonelik sayıları ile yükleme değeri yeniden
  hesaplanır (varsayım: yükleyenlerin %3'ü yıllığa geçer → ~16 ₺/yükleme);
  bütçe büyür, aynı kalır ya da yalnız A kalır.
