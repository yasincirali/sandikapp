# Google Play Yayın Rehberi — sandık (Android)

**Tarih:** 2026-09-05
**Kapsam:** `com.sandik.app` uygulamasının Google Play'de yayına çıkması için
gereken *her* adım — kod tarafında biten/eksik olanlar + senin Console'da,
tarayıcıda ve elden yapacakların.

> Bu dosya `YAPMAN_GEREKENLER.md`'nin (2026-05-11) Android/Play kısmının
> güncel ve doğrulanmış halidir. Oradaki §4 ve §6 bölümleri hâlâ geçerli ama
> aradan geçen sürede Play'in kuralları değişti (targetSdk 36, 16 KB sayfa
> boyutu, finansal özellik beyanı, geliştirici doğrulama). Çakışma olursa
> **bu dosya geçerlidir.**

---

## 0. Bir dakikalık özet — nerede duruyoruz

| Alan | Durum |
|---|---|
| Uygulama kodu, imza altyapısı, R8, CI | ✅ Hazır |
| Mağaza metinleri (TR + EN) | ✅ TR metni App Store ile birebir hizalandı (§6.4, §12) · EN için ASC'de karşılığı var mı? |
| Hukuki belgeler + web sayfaları | ✅ Bu tur onarıldı: bozuk kodlama düzeltildi, placeholder'lar dolduruldu (§7.2) |
| Data Safety envanteri | ✅ Yazılı · Advertising ID sorusu kapandı — izin manifest'ten düşürüldü (§5.3) |
| Release keystore | ❌ **SENDE** — yoksa hiçbir şey yüklenemez |
| Play Console hesabı + doğrulama | 🔄 **Kişisel hesap açıldı**, kimlik doğrulaması Google'da bekliyor (§1) |
| Ekran görüntüleri | ⚠️ Var ama **Play formatına uymuyor** (2,17:1 > 2:1 sınırı) — yeniden üretilecek (§6.2) |
| Feature graphic (1024×500) + ikon (512×512) | ❌ Yok — üretilecek (§6.1, §6.3) |
| Supabase `0027_soft_delete_lots.sql` migration | ❌ Uygulanmadı — **Play "hesap silme" şartını kırar** (§7.1) |

**Kritik yol (bunlar bitmeden yayın yok):** hesap tipi kararı → hesap
doğrulama → keystore → görseller → Console beyanları → kapalı test.

---

## 1. Hesap tipi kararı — ilk ve en pahalı karar

> **✅ KARAR (2026-09-06): Kişisel hesap.** Şirket olmadığı için kuruluş
> hesabı (D‑U‑N‑S zorunlu) bir seçenek değil. Sonuçları:
> **(a)** 12 testçi × kesintisiz 14 gün kapalı test **zorunlu** (§8.2) —
> takvimin en uzun kalemi, testçi toplamaya bugünden başla.
> **(b)** Play'de görünen geliştirici adı gerçek kişi: **Yasin Çıralı**;
> hukuki belgelerdeki veri sorumlusu da bu (§7.2).
> **(c)** Google'ın "finansal ürün/hizmet sağlayanlar kuruluş hesabı
> seçmeli" yönergesi bankacılık, kredi, hisse alım-satımı, yatırım fonu,
> kripto cüzdanı/borsası sayıyor — sandık bunların hiçbirini yapmıyor,
> sadece takip ediyor. Savunulabilir ama garanti değil; Financial features
> beyanında (§5.4) Google karar verecek. Riski düşürmek için sinyal
> uyarılarını görünür tut.

> **Hesap kurulum durumu:** kimlik belgeleri yüklendi, Google doğruluyor
> (birkaç gün). Kalan iki görev: Play Console **mobil uygulamasına** o
> hesapla giriş (cihaz doğrulaması) ve ardından telefon doğrulaması —
> telefon adımı kimlik onayı bitmeden açılmıyor.

Play, uygulamayı **kişisel** ya da **kuruluş (organization)** hesabından
yayınlamana izin veriyor. sandık bir finans uygulaması olduğu için bu karar
tarafsız değil:

| | Kişisel hesap | Kuruluş hesabı |
|---|---|---|
| Ücret | 25 USD tek seferlik | 25 USD tek seferlik |
| Kimlik doğrulama | Ad, adres, telefon, e-posta (+ bazen resmî kimlik) | Yasal şirket bilgisi + **D‑U‑N‑S numarası** |
| D‑U‑N‑S süresi | — | Başvuru **28 güne kadar** sürebilir, ücretsiz |
| Kapalı test şartı | 2023‑11‑13 sonrası açılan hesaplarda **12 test kullanıcısı × 14 gün** zorunlu | Muaf — doğrudan production'a çıkabilir |
| Mağazada görünen ad | Kişi/serbest ad | Şirket adı |

**⚠️ Finans uygulaması notu:** Play'in Financial Services politikası
kapsamındaki uygulamalar için üçüncü taraf kaynaklar "kuruluş hesabı
zorunlu" diyor; Google'ın kendi metninde bu net bir cümle olarak yok, ama
finansal özellik beyanında (bkz. §5.4) "yatırım" kutusunu işaretlediğin an
Console senden ek belge/kuruluş bilgisi isteyebiliyor. **Hesabı açmadan önce
karar ver** — kişisel hesaptan kuruluş hesabına geçiş yapılamıyor, sıfırdan
hesap açmak gerekiyor ve uygulamayı taşımak (transfer) ayrı bir süreç.

**Önerim:**
- Şirketin (şahıs şirketi dahil) varsa → **kuruluş hesabı**. D‑U‑N‑S'yi
  bugün başlat, 28 gün beklerken kalan işleri yaparsın; ayrıca 12 kişi ×
  14 gün kapalı test şartından da muaf olursun.
- Şirket yoksa ve açmayacaksan → kişisel hesap, ama kapalı test şartını
  takvime yaz (§8.2) ve `YAPMAN_GEREKENLER.md` §2.1'deki tüzel kişilik
  kararını da bununla birlikte ver (hukuki belgelerdeki "veri sorumlusu"
  kim olacak sorusu aynı sorudur).

**Yapılacaklar:**
- [ ] Hesap tipine karar ver
- [ ] (Kuruluşsa) D‑U‑N‑S başvurusu yap — dnb.com üzerinden ücretsiz
- [ ] https://play.google.com/console → 25 USD → hesabı aç
- [ ] Kimlik doğrulamayı **hemen** tamamla (doğrulanmamış hesap yayın yapamaz)
- [ ] Ödeme profili: uygulama ücretsiz olduğu için satıcı hesabı gerekmiyor.
      Paywall açılacaksa (§7.4) o zaman gerekecek.

---

## 2. Release keystore — Play yüklemesinin ön şartı

Kod tarafı hazır: `android/app/build.gradle.kts` `key.properties` varsa onu
kullanıyor, yoksa debug imzasına düşüyor. **Play debug imzalı AAB'yi
reddeder**, o yüzden keystore olmadan hiçbir şey yüklenmez.

```bash
cd c:/projects/PortfoyTakip/android
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Ardından `android/key.properties` (git'e girmez, `.gitignore`'da):

```properties
storePassword=<keystore şifresi>
keyPassword=<key şifresi>
keyAlias=upload
storeFile=../upload-keystore.jks
```

Şablon: `android/key.properties.example`.

**Yedek — 3 ayrı yere.** Bu dosyayı kaybedersen Play'e bir daha güncelleme
yükleyemezsin (Play App Signing devredeyse Google upload key sıfırlaması
yapabiliyor ama süreç günler alır ve her zaman garanti değil).
1. Şifreli USB / harici disk (çevrimdışı)
2. Şifre yöneticisi (1Password / Bitwarden) — dosyayı ek olarak
3. Ayrı bir bulut hesabı, şifreli arşiv içinde

**Play App Signing:** Yeni uygulamalarda zorunlu ve varsayılan olarak açık.
Sen "upload key" ile imzalarsın, Google mağaza sürümünü kendi "app signing
key"i ile yeniden imzalar. İlk yüklemede Console sana bunu onaylatır — kabul
et.

**CI için secret'lar** (GitHub → Settings → Secrets and variables → Actions).
`.github/workflows/android-release.yml` bunların **hepsini** arıyor, biri
eksikse iş kırmızıya düşer:

| Secret | İçerik |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` çıktısı |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | key şifresi |
| `ANDROID_STORE_PASSWORD` | keystore şifresi |
| `GOOGLE_SERVICES_JSON_BASE64` | `android/app/google-services.json` base64 |
| `SUPABASE_URL` | Supabase proje URL'i |
| `SUPABASE_ANON_KEY` | Supabase anon key |

Windows'ta base64:
`certutil -encode upload-keystore.jks out.b64` (ilk/son satırları sil, satır
sonlarını birleştir) — ya da Git Bash'te `base64 -w0`.

---

## 3. Yayın öncesi teknik kontrol listesi

### 3.1 Kod tarafında **biten** işler (doğrulandı)

| Şart | Durum | Kanıt |
|---|---|---|
| `targetSdk = 36` (31 Ağu 2026'dan beri zorunlu) | ✅ | `android/app/build.gradle.kts:45` |
| `compileSdk = 36`, Java 17 | ✅ | aynı dosya |
| AGP 8.11.1 (16 KB paketleme için ≥8.5.1 gerekli) | ✅ | `android/settings.gradle.kts:19` |
| R8 + kaynak küçültme + ProGuard kuralları | ✅ | `build.gradle.kts:67-74`, `proguard-rules.pro` |
| Yasaklı/gereksiz izin yok (sadece INTERNET, POST_NOTIFICATIONS) | ✅ | `AndroidManifest.xml` |
| `allowBackup=false` + `dataExtractionRules` | ✅ | `AndroidManifest.xml` |
| Secret'lar `--dart-define` ile, kodda gömülü değil | ✅ | `lib/config/supabase_config.dart` |
| İmzalı AAB üreten CI | ✅ | `.github/workflows/android-release.yml` |
| Dart obfuscation | ✅ (bu turda CI'a eklendi) | aynı workflow, `--obfuscate` |
| MobSF taraması | ✅ | `.github/workflows/mobsf-scan.yml` |

### 3.2 Yayından önce **doğrulaman** gerekenler

- [ ] **16 KB sayfa boyutu.** Native kütüphanesi olan her uygulama için
      zorunlu (Play Console'da bloklayıcı kontrol). Flutter 3.47 + AGP 8.11
      ile büyük ihtimalle sorunsuz, ama üretilen AAB'yi bir kez tara:
      ```bash
      unzip -o build/app/outputs/bundle/release/app-release.aab -d /tmp/aab
      for so in $(find /tmp/aab -name '*.so'); do
        echo "$so"; readelf -lW "$so" | grep -m1 LOAD
      done   # Align değeri 2**14 (16384) olmalı
      ```
      Ya da en kolayı: AAB'yi internal test'e yükle, Console "Uygulama
      paketleri" ekranında 16 KB uyarısı çıkıyor mu bak.
- [ ] **Legal URL'ler canlı mı.** Tarayıcıda tek tek aç (reviewer tıklıyor):
      `…/privacy`, `…/terms`, `…/data-deletion`, `…/legal/kvkk`.
      Uygulama içindeki referans: `lib/screens/legal_doc_screen.dart:30`
      → `yasincirali.github.io/sandikapp`. Console'a **birebir aynı** URL'i
      gir; farklı domain kullanacaksan (`sandik.app`) önce kodu güncelle,
      sonra Console'a gir — ikisi tutarsız olursa red gelir.
- [ ] **Release build gerçek cihazda.** R8 sonrası kırılan bir şey varsa
      ancak burada görünür (emülatör Flutter'ı render etmiyor, bkz.
      `CLAUDE.md`):
      ```bash
      flutter build apk --release --split-per-abi \
        --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
      adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
      ```
      Test edilecekler: kayıt (3 onay kutusu), giriş, varlık ekleme, fiyat
      çekme, performans grafiği, ortaklık daveti, push bildirimi, **hesap
      silme**, çevrimdışı hata mesajları.
- [ ] **AAB'yi cihazda dene** (APK ≠ AAB; Play'in ürettiği bölünmüş paket
      farklı davranabilir):
      ```bash
      bundletool build-apks --bundle=app-release.aab --output=sandik.apks \
        --local-testing --ks=upload-keystore.jks --ks-key-alias=upload
      bundletool install-apks --apks=sandik.apks
      ```
- [ ] **versionCode.** `pubspec.yaml` şu an `1.1.4+7` → versionCode 7. Play
      aynı versionCode'u iki kez kabul etmez; her yüklemede `+8`, `+9` …
      diye artır.

---

## 4. Build'i üret

**Yol A — CI (önerilen).** GitHub → Actions → "Android — Release AAB" →
Run workflow. Ya da sürüm etiketi at:

```bash
git tag v1.1.4 && git push origin v1.1.4
```

İş şunları yapar: analyze → test → imzalı AAB (+ istersen ABI'ye bölünmüş
APK) → artefakt. Artefaktın içinden alacakların:
- `app-release.aab` → Play'e yüklenecek dosya
- `mapping.txt` → Java/Kotlin sembol haritası (AAB içinde de gider; Play
  otomatik okur)
- `symbols/` → **Dart** sembolleri. Obfuscation açık olduğu için Crashlytics'te
  gelen Dart stack trace'lerini ancak bunlarla çözersin:
  `flutter symbolize -i crash.txt -d symbols/app.android-arm64.symbols`
  **Her yayınlanan sürümün symbols klasörünü sakla** (artefakt 30 gün sonra
  siliniyor — indir ve arşivle).

**Yol B — yerel.**
```bash
flutter build appbundle --release \
  --obfuscate --split-debug-info=build/symbols \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

---

## 5. Play Console → "Uygulama içeriği" beyanları

Bunlar formalite değil; **eksik bir beyan yüklemeyi bloklar** ve yanlış bir
beyan (özellikle Data Safety) sonradan uygulamayı askıya aldırır.

### 5.1 Gizlilik politikası
- Privacy policy URL → `https://yasincirali.github.io/sandikapp/privacy`

### 5.2 Uygulama erişimi (App access) — **atlanması en sık red sebebi**
sandık girişsiz kullanılamıyor. Reviewer'a ve otomatik "pre-launch report"
tarayıcısına çalışan bir hesap vermen gerekiyor:
- [ ] Kalıcı bir **demo hesabı** aç (silinmeyecek, şifresi değişmeyecek)
- [ ] İçini 5-6 varlıkla doldur (boş portföy "işlevsiz uygulama" izlenimi verir)
- [ ] Console → App access → "All functionality requires access" → e-posta,
      şifre ve kısa bir açıklama gir (TR/EN: "Kayıt ekranındaki 3 onay
      kutusu işaretlenmeden giriş yapılamaz")

### 5.3 Data safety — hazır, **bir düzeltmeyle**
Kaynak: `store_listing/DATA_SAFETY_FORM.md`. Satırları formdaki kutulara
birebir işaretle. Eksik olan tek şey:

> **⚠️ Advertising ID.** `firebase_analytics` bağımlılığı, birleştirilmiş
> manifest'e `com.google.android.gms.permission.AD_ID` iznini kendiliğinden
> ekliyor. Play, manifest'te bu izin varken Data Safety'de "reklam kimliği
> toplanmıyor" denmesini **uyumsuzluk sayıp reddediyor.**

Önce doğrula:
```bash
flutter build appbundle --release ...
grep -c AD_ID android/app/build/intermediates/merged_manifests/release/AndroidManifest.xml
```
Sonuç 0 değilse iki seçeneğin var:

**(a) İzni kaldır** (reklam yok, attribution'a ihtiyacın yoksa en temizi) —
`android/app/src/main/AndroidManifest.xml` içine:
```xml
<uses-permission android:name="com.google.android.gms.permission.AD_ID"
    tools:node="remove" />
```
(`<manifest>` etiketine `xmlns:tools="http://schemas.android.com/tools"` eklemeyi unutma.)

**(b) Beyan et** — Data Safety → Device or other IDs → "Advertising ID"
kutusunu işaretle, amaç: Analytics.

**✅ Karar verildi (2026-09-06): (a) uygulandı.** iOS tarafında izleme kapalı
(`PrivacyInfo.xcprivacy` → `NSPrivacyTracking=false`), dolayısıyla iki mağazada
aynı beyanı verebilmek için Android'de de reklam kimliği kullanılmıyor.
`AndroidManifest.xml`'e `tools:node="remove"` eklendi; Data Safety'de
**Advertising ID işaretlenmeyecek**. Build sonrası yukarıdaki `grep` ile
iznin gerçekten düştüğünü doğrula.

### 5.4 Financial features declaration — **bu uygulama için zorunlu**
Artık Play'deki *her* uygulama bu formu dolduruyor; finansal özelliği olanlar
ayrıca detay veriyor. sandık için işaretlemen gerekenler ve gerekçeleri:

- **Yatırım/portföy yönetimi:** Evet — portföy takibi var. Ama **işlem
  yapılmıyor**: aracı kurum bağlantısı, emir iletimi, cüzdan, para transferi
  yok. Formda bunu açıkça belirt; "trading" değil "tracking" olduğu
  vurgulanmalı.
- **Kripto alım-satım / cüzdan:** Hayır.
- **Kredi / borç verme:** Hayır.
- **⚠️ Kişiselleştirilmiş yatırım tavsiyesi:** Politikanın kapsamı
  "para/kripto yönetimi veya yatırımı, **kişiselleştirilmiş tavsiye dahil**".
  Uygulamada RSI/MACD/Bollinger tabanlı **"AL / SAT" sinyalleri** ve sinyal
  push bildirimleri var (`lib/models/technical_signal.dart`,
  `TECHNICAL_SIGNALS_IMPLEMENTATION.md`). Bir incelemeci bunu "yatırım
  tavsiyesi" sayabilir; Türkiye'de yatırım danışmanlığı SPK izni gerektirir.
  **Alınacak önlem — üçü birden:**
  1. Sinyal ekranında ve sinyal bildiriminde görünür bir uyarı: "Yatırım
     tavsiyesi değildir; teknik göstergelerin otomatik hesabıdır."
     (`legal/` metinlerindeki disclaimer'ın aynısı, ekranın kendisinde.)
  2. Mağaza açıklamasındaki uyarı satırını koru (şu an `full_description.txt`
     sonunda var ✅).
  3. Formda "kişiselleştirilmiş tavsiye" sorusuna **hayır** derken
     gerekçeni yaz: sinyaller kullanıcı profiline göre değil, kamuya açık
     fiyat verisinden mekanik olarak üretiliyor.
- İstenirse ek belge yüklenecek alan çıkar (lisans, şirket kaydı). Kuruluş
  hesabı kararının (§1) burada karşına çıkacağını hesaba kat.

### 5.5 Diğer beyanlar
| Bölüm | Cevap |
|---|---|
| Ads | Hayır (uygulamada reklam yok) |
| Content rating (IARC anketi) | Finans, şiddet/kumar yok → muhtemelen Everyone / 3+. Ankette **kumar benzeri öğe** sorusuna dikkat: "Yarış" sıralaması ödülsüz ve bahissiz → hayır |
| Target audience | 18+ (yatırım uygulaması; çocuklara hitap etmiyor) |
| News app | Hayır |
| Government app | Hayır |
| Data deletion | In-app: ✅ Profil → Ayarlar → Hesabımı Sil · Web: `…/data-deletion` |
| Health apps / VPN / vs. | Hayır |

---

## 6. Mağaza sayfası (Store listing) — görsel ve metin

Metinler hazır: `store_listing/tr-TR/` ve `store_listing/en-US/`
(title / short_description / full_description / whats_new). Console'a elle
kopyalanır; repo Console'dan okunmaz.

### 6.1 Uygulama ikonu — 512×512, 32-bit PNG
Kaynak: `assets/images/sandik_icon.png` (1024×1024) → 512'ye küçült.
Alfa kanalı olmasın, köşeleri sen yuvarlama (Play kendi maskesini uygular).

### 6.2 Ekran görüntüleri — **mevcutlar Play'e uymuyor**
`store_listing/screenshots/orig/` altındaki 7 görsel **1125×2436** yani
**2,17:1**. Play'in kuralı: her kenar 320–3840 px arasında ve **uzun kenar,
kısa kenarın en fazla 2 katı**. Bu dosyalar yükleme sırasında reddedilir.

Çözüm — `store_listing/build_screenshots.py` bu tur Play hedefi eklenerek
güncellendi:
```bash
# ham telefon görüntülerini store_listing/screenshots/raw/ içine koy
cd store_listing && python build_screenshots.py
# çıktı: screenshots/out/1080x1920/  ← Play'e bunları yükle
```
Kurallar: en az 2 (**pratikte 4-8 kullan**), JPEG veya 24-bit PNG, alfa yok.
Sıralama önemli — arama sonucunda ilk iki görsel görünür; hangisinin önce
geleceği `store_listing/SCREENSHOT_PLAN.md`'de yazılı, ona uy.

Tablet görselleri zorunlu değil ama büyük ekran sıralamasında avantaj
sağlıyor; sonraya bırakılabilir.

### 6.3 Feature graphic — 1024×500, zorunlu
Yok, üretilmeli. İçerik: koyu yeşil marka zemini (#0A1E15), sandık logosu,
kısa bir slogan ("Gerçek kâr/zarar, tek ekranda"). Metni kenarlardan uzak
tut — Play bazı yerleşimlerde kırpıyor. Canva/Figma ile 20 dakikalık iş.

### 6.4 ✅ Metinler App Store ile hizalandı
`store_listing/tr-TR/full_description.txt` artık `APP_STORE_1.1.3.md`
içindeki App Store açıklamasının **aynısı**. Bununla birlikte eski metindeki
"ARAMA" bölümü (Sandık/sandik/SANDIK varyant listesi) de kalktı — Play'in
metadata politikası anahtar kelime tekrarına App Store'dan sert davranıyor,
App Store metnindeki tek satırlık doğal cümle (`Uygulamayı ararken "sandik"
veya "sandık" — ikisi de bizi bulur.`) aynı işi politika riski olmadan
görüyor.

Tek bilinçli fark: App Store metnindeki **sabit satır kırılmaları
kaldırıldı** (paragraflar tek satır). İki mağaza da metni olduğu gibi
basıyor; sabit kırılmalar dar ekranda metni tırtıklı gösteriyor. Kelimeler
birebir aynı. Aynı düzeltmeyi bir sonraki sürümde ASC'de de yapmanı
öneririm.

Detaylı eşleme tablosu: §12.

### 6.5 Mağaza ayarları
- Kategori: **Finans** (App category: Finance)
- Etiketler: portföy, yatırım, finans takibi
- İletişim: destek e-postası + web sitesi + gizlilik politikası URL'i
- Varsayılan dil: Türkçe; ikinci dil olarak İngilizce ekle (`en-US/` metinleri)

---

## 7. Yayından önce kapatılması gereken açıklar

### 7.1 🔴 Supabase migration `0027_soft_delete_lots.sql` — **bloker**
Uygulanmadı. Uygulanmazsa varlık silme UPDATE'i patlıyor. Play'e "kullanıcı
verisini silebiliyor" beyanı verdiğin bir uygulamada silme akışının kırık
olması hem işlevsel hata hem beyan uyumsuzluğu.
```bash
supabase db push   # ya da Dashboard → SQL Editor
```
Ardından gerçek cihazda: hesap aç → varlık ekle → varlığı sil → hesabı sil.

### 7.2 ✅ (KAPANDI) Hukuki belgeler — kodlama onarımı + placeholder'lar
2026-09-06'da iki sorun birden kapatıldı:

1. **Bozuk kodlama.** `legal/tr/` altındaki beş Türkçe belge ve bunlardan
   üretilen yayındaki HTML sayfaları çift kodlanmıştı — "Kişisel Verilerin
   Korunması" yerine "KiÅŸisel Verilerin KorunmasÄ±" görünüyordu. Play
   incelemecisinin tıkladığı gizlilik politikası sayfası buydu. Onarıldı
   (2.121 karakter), `docs/` yeniden üretildi.
2. **Placeholder'lar.** `[ŞİRKET ADI]`, `[AÇIK ADRES]`, `[VERGİ NO]`,
   `[VERBİS NO]`, `[KEP ADRESİ]`, `[İLETİŞİM E-POSTA]`, `[YETKİLİ MAHKEME]`,
   `[WEB SİTESİ]` dolduruldu; yayınlanan sayfalarda görünen "TODO" uyarı
   kutuları kaldırıldı. Kullanılan değerler:

| Alan | Değer |
|---|---|
| Veri sorumlusu | Yasin Çıralı (bireysel geliştirici) |
| Adres | İstanbul, Türkiye |
| E-posta | sandikapp.destek@gmail.com |
| Vergi No / KEP | Yok (bireysel geliştirici) |
| VERBİS | Kayıtlı değil — ticari faaliyet başlangıcında yapılacak |
| Yetkili mahkeme | İstanbul Anadolu Mahkemeleri ve İcra Daireleri |
| Web | https://yasincirali.github.io/sandikapp |
| DPO | Atanmamıştır; veri koruma iletişimi yukarıdaki e-posta |

**🟠 Kalan tek karar — AB temsilcisi (GDPR Md. 27).** `legal/en/GDPR_NOTICE.md`
içinde hâlâ bir placeholder duruyor. Uygulamayı AB ülkelerine de dağıtacaksan
Md. 27 temsilcisi atanması gerekebilir (istisnalar var: arızi işleme, özel
nitelikli veri yok, düşük risk). Play Console'da dağıtımı **yalnızca Türkiye**
seçersen bu satır "AB'de hizmet sunulmamaktadır" olarak kapanır. Hangisi
olduğunu söyle, metni ona göre yazayım.

**Not:** Adres şehir düzeyinde ("İstanbul, Türkiye"). Play, kişisel hesaplarda
geliştirici adresini mağaza sayfasında **herkese açık** gösteriyor; oraya açık
adres girmen istenirse hukuki belgelerdeki adresi de onunla eşitleyelim.

### 7.3 🟡 Firebase Android uygulaması kayıtlı mı
CI `GOOGLE_SERVICES_JSON_BASE64` bekliyor. Firebase Console'da
`com.sandik.app` paket adıyla bir **Android** uygulaması kayıtlı değilse
önce `flutterfire configure` ile ekle. Push bildirimi ve Crashlytics buna
bağlı.

### 7.4 🟢 Paywall kapalı — şimdilik doğru karar
`paywall_enabled = false` (Firebase Remote Config). İlk yayında Console'da
"uygulama içi satın alma: hayır" diyeceksin. Paywall'u açacağın gün: Play
Billing entegrasyonu + Console'da abonelik ürünleri + beyanların
güncellenmesi gerekir (`MONETIZATION_ROADMAP.md`).

---

## 8. Yayın akışı

### 8.1 Internal testing (bugün başlayabilirsin)
Doğrulanmış hesap + AAB varsa yeterli; mağaza sayfası tamamlanmadan da
yüklenebilir. 100 kişiye kadar, dakikalar içinde dağıtılır.
1. Test → Internal testing → Create new release
2. `app-release.aab` yükle, sürüm notlarını `whats_new.txt`'ten kopyala
3. Tester listesi oluştur (kendin + 2-3 kişi) → rollout
4. **Pre-launch report**'u oku (Test → Pre-launch report): Google gerçek
   cihazlarda uygulamayı gezer; çökme, ANR, erişilebilirlik ve güvenlik
   bulgularını orada görürsün. Demo hesabı (§5.2) girilmemişse tarayıcı
   giriş ekranını geçemez ve rapor boş gelir.

### 8.2 Closed testing (kişisel hesapsan **zorunlu**)
- En az **12 test kullanıcısı**, **kesintisiz 14 gün** opt-in
- 2026'dan beri Google testçilerin uygulamayı **gerçekten kullandığını** da
  denetliyor — listeye ekleyip unutulan 12 e-posta yetmez
- 14 gün dolunca Dashboard'dan "production access" başvurusu yapılır,
  incelemesi birkaç gün sürer
- Kuruluş hesabıysan bu adımı atlayabilirsin, ama yine de 1 hafta kapalı
  test önerilir

### 8.3 Production
Kriterler (Console → Vitals'tan izle): çökme oranı < %1, ANR < %0,5,
tester'lardan bloklayıcı geri bildirim yok.
- İlk production incelemesi **birkaç gün – 7 gün** sürebilir
- **Kademeli yayın (staged rollout) %10 ile başla.** Vitals bozulursa
  yayını durdurup düzeltebilirsin; %100'e çıktıktan sonra geri alamazsın
- Yeni sürümde "İnceleniyor" durumu takıldıysa panikleyip yeni sürüm
  yükleme; aynı track'te kuyruk oluşuyor

---

## 9. Yayından sonra

- [ ] Crashlytics ve Play Vitals'ı ilk hafta günlük kontrol et
- [ ] Dart sembollerini (`symbols/`) sürüm bazında arşivle — yoksa obfuscated
      stack trace okunmaz
- [ ] Kullanıcı yorumlarına Console'dan yanıt ver (finans uygulamalarında
      güven sinyali)
- [ ] `whats_new.txt`'i her sürümde güncelle (şu an 1.1.4 içeriğiyle uyumlu)
- [ ] Bir sonraki targetSdk penceresini takvime al — Play her yıl yükseltiyor

---

## 10. Sıra ve süre tahmini

| # | İş | Kim | Süre |
|---|---|---|---|
| 1 | Hesap tipi kararı + (kuruluşsa) D‑U‑N‑S başvurusu | Sen | 1 saat + 28 güne kadar bekleme |
| 2 | Play Console hesabı + kimlik doğrulama | Sen | 1 saat + 1-2 gün onay |
| 3 | Keystore üret, yedekle, GitHub secret'larını gir | Sen | 1 saat |
| 4 | Supabase `0027` migration + hesap silme testi | Sen | 30 dk |
| 5 | Tüzel kişilik → legal placeholder'ları doldur | Sen + ben | 2 saat |
| 6 | Ekran görüntüleri (Play formatı) + feature graphic + 512 ikon | Sen | 3 saat |
| 7 | AAB üret (CI) + gerçek cihazda release testi | Ben + sen | 2 saat |
| 8 | Console: uygulama oluştur, beyanlar, mağaza sayfası | Sen | 4 saat |
| 9 | Internal testing + pre-launch report | Sen | 1 gün |
| 10 | Closed testing (kişisel hesap) | Sen | 14 gün |
| 11 | Production + kademeli yayın | Sen | 3-7 gün inceleme |

**Kuruluş hesabıyla en hızlı senaryo:** ~2 hafta (D‑U‑N‑S beklemesi hariç).
**Kişisel hesapla:** ~4 hafta (14 günlük kapalı test zorunlu).

---

## 11. Bana söylemen gerekenler

Şunları netleştirirsen kalan kod/doküman işlerini tek seferde bitiririm:

1. **12 testçi:** kapalı test için 12 kişilik listeyi kim oluşturacak?
   (Gmail adresleri + Android cihaz; 14 gün kesintisiz opt-in gerekiyor)
2. **Dağıtım ülkeleri:** yalnızca Türkiye mi, AB dahil global mi? (GDPR Md. 27
   temsilcisi satırı buna bağlı — §7.2)
3. **Domain:** `yasincirali.github.io/sandikapp` ile mi devam, yoksa
   `sandik.app` alınacak mı? (Kodda ve Console'da aynı olmalı)
4. **Sinyal uyarısı:** sinyal ekranına/bildirimine görünür "yatırım tavsiyesi
   değildir" satırını ekleyeyim mi? (§5.4)
5. **ASC'deki beyanlar** (§12.4): App Privacy'de işaretli veri tipleri, yaş
   sınırı anket cevapları, subtitle, support URL, demo hesabı ve inceleme
   notu. Bunları söylersen Play formlarını birebir aynı dolduracak şekilde
   hazırlarım ve `PrivacyInfo.xcprivacy`'deki boş beyanı da (§12.5) aynı
   envanterle doldururum.
6. **EN yerelleştirmesi:** App Store'da İngilizce listing var mı? Varsa
   `en-US/full_description.txt`'i de onunla hizalayayım.

> ✅ Şu iki soru "App Store ile birebir olsun" kararınla kapandı:
> **AD_ID** izni manifest'ten düşürüldü (iOS'ta izleme kapalı olduğu için) ve
> TR açıklama App Store metniyle değiştirildi ("ARAMA" bölümü kalktı).

---

## 12. App Store ↔ Play birebir eşleme

**Kural:** App Store Connect'te (ASC) ne beyan edildiyse Play'de de aynısı
beyan edilir. İki mağazanın aynı uygulama için farklı şey söylemesi hem
politika riski (bir mağazadaki beyan diğerinde delil olur) hem de bakım
yükü.

**Ama "birebir" her alanda mümkün değil** — iki mağaza aynı soruları
sormuyor. Üç grup var:

### 12.1 Aynen kopyalanacak alanlar

| App Store Connect | Play Console | Değer / kaynak |
|---|---|---|
| App Name (30) | Store listing → App name (30) | `Sandık: Portföy Takibi` — `store_listing/tr-TR/title.txt` |
| Description (4000) | Full description (4000) | ✅ **Bu tur hizalandı:** `store_listing/tr-TR/full_description.txt` artık `APP_STORE_1.1.3.md`'deki metnin aynısı |
| What's New (4000) | What's new (**500**) | İçerik aynı, Play'de kısaltılmış: `whats_new.txt` |
| Support URL | Store settings → Web sitesi | ASC'deki URL'in aynısı |
| Privacy Policy URL | App content → Privacy policy | `…/sandikapp/privacy` |
| Primary Category: Finance | App category: **Finans** | Aynı |
| Sign-in required + demo hesabı | App access | **Aynı demo hesabı, aynı şifre** (§5.2) |
| In-App Purchases: yok | Uygulama içi satın alma: hayır | `paywall_enabled=false` |
| Copyright / geliştirici adı | Developer name | Tüzel kişilik kararıyla aynı (§1) |

### 12.2 Soru farklı, cevap aynı olmalı — taksonomi eşlemesi

**Apple App Privacy (nutrition label) → Play Data Safety.**
ASC'de işaretlenen her veri tipinin Play karşılığı:

| Apple veri tipi | Play veri tipi | Not |
|---|---|---|
| Contact Info → Email Address | Personal info → Email address | Zorunlu, hesap yönetimi |
| Contact Info → Name | Personal info → Name | Ortak sıralamasında görünen ad |
| Identifiers → User ID | Personal info → User IDs | Supabase UUID |
| Financial Info → Other Financial Info | Financial info → Other financial info | Portföy kayıtları |
| Usage Data → Product Interaction | App activity → App interactions | Firebase Analytics |
| Diagnostics → Crash Data | App info & performance → Crash logs | Crashlytics |
| Diagnostics → Performance Data | App info & performance → Diagnostics | — |
| User Content → Other User Content | App activity → Other user-generated content | Varlık notları |
| Identifiers → Device ID | Device or other IDs | FCM push token |
| **Tracking: No** (`NSPrivacyTracking=false`) | **Data shared with third parties: No** + reklam kimliği yok | ✅ Bu tur manifest'ten `AD_ID` izni düşürüldü — artık iki mağaza aynı şeyi söylüyor |

Play'in Apple'da karşılığı olmayan **üç ek sorusu** var, cevapları:
- *Veriler aktarımda şifreleniyor mu?* → **Evet** (TLS 1.2+)
- *Kullanıcı verisinin silinmesini isteyebiliyor mu?* → **Evet**, uygulama içi + `…/data-deletion`
- *Veri toplama zorunlu mu / isteğe bağlı mı?* → Çekirdek veriler zorunlu; Yarış **opt-in**

Apple'ın "Linked to You / Not Linked to You" ayrımının Play'de karşılığı
yok — Play "collected" ve "shared" diye sorar; her satırda **collected: evet,
shared: hayır** işaretlenir (üçüncü taraflar işleyen/processor konumunda,
`DATA_SAFETY_FORM.md`'de listeli).

**Yaş sınırı.** Apple'da tek bir etiket seçilir; Play'de IARC anketi
doldurulur ve etiketi anket üretir. Etiketler aynı çıkmayabilir — **doğru
olan, anket cevaplarının ASC'de verilen cevaplarla tutarlı olması**:
- Kumar / gerçek para oyunu: **hayır** ("Yarış" ödülsüz ve bahissiz)
- Şiddet, cinsellik, madde: **hayır**
- Kısıtlanmamış web erişimi: **hayır** (uygulama içi tarayıcı yok)
- Kullanıcılar arası iletişim: ortak daveti var → ASC'de ne dendiyse aynısı
- Target audience: **18+** (ASC'de 17+/18+ seçildiyse karşılığı budur)

### 12.3 Karşılığı olmayan alanlar (Play'de girilmez)

| App Store Connect | Play'de durumu |
|---|---|
| Keywords (100 karakter) | **Yok.** Play açıklamayı indeksler. `sandik` yazımı, açıklamanın son satırındaki doğal cümleyle karşılanıyor — ayrıca anahtar kelime listesi **eklenmez** (§6.4) |
| Promotional Text (170) | Yok. En yakın alan Short description (80) ama işlevi farklı |
| Subtitle (30) | Short description (80) — birebir değil; ASC'deki subtitle'ı buraya genişleterek yaz |
| Export compliance (`ITSAppUsesNonExemptEncryption=false`) | Play'de form yok; ABD ihracat beyanı yayıncı sözleşmesinde |
| App Review Notes | Play'de karşılığı "App access" açıklaması — ASC'deki notun aynısını yaz |

### 12.4 ASC'den okuyup bana/Console'a taşıman gerekenler

Bunlar repoda yok, yalnızca App Store Connect'te duruyor. Console'a
girmeden önce ASC'yi açıp not al:

- [ ] **App Privacy** bölümündeki işaretli veri tipleri (§12.2 tablosuyla karşılaştır)
- [ ] **Age Rating** anket cevapları
- [ ] **Subtitle** ve **Support/Marketing URL**
- [ ] **App Review** → demo hesabı e-posta/şifre ve inceleme notu
- [ ] **EN yerelleştirmesi var mı** — varsa `store_listing/en-US/full_description.txt`'i de onunla hizalayalım (şu an bağımsız yazılmış bir metin)

### 12.5 ⚠️ Bu tur çıkan tutarsızlık: `PrivacyInfo.xcprivacy`

`ios/Runner/PrivacyInfo.xcprivacy` içinde `NSPrivacyCollectedDataTypes`
**boş bir dizi** — yani "hiçbir veri toplanmıyor" diyor. Oysa uygulama
e-posta, ad, portföy kaydı ve çökme günlüğü topluyor; ASC'deki App Privacy
bölümünde bunlar beyan edilmiş olmalı. Manifest dosyası ile ASC beyanı
çelişiyorsa Apple bunu inceleme sırasında sorabiliyor.

Play tarafını ASC beyanıyla hizalarken bu dosyayı da doldurmak gerekiyor.
`DATA_SAFETY_FORM.md`'deki envanteri kaynak alıp doldurabilirim — ama önce
ASC'de fiilen ne işaretlendiğini söylemen lazım ki üç yer (ASC, xcprivacy,
Play) aynı şeyi söylesin.

---

## Kaynaklar

- [Target API level requirements for Google Play apps](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en) — API 36, 31 Ağustos 2026
- [Meet Google Play's target API level requirement](https://developer.android.com/google/play/requirements/target-sdk)
- [Support 16 KB page sizes](https://developer.android.com/guide/practices/page-sizes)
- [Prepare your apps for Google Play's 16 KB page size compatibility requirement](https://android-developers.googleblog.com/2025/05/prepare-play-apps-for-devices-with-16kb-page-size.html)
- [App testing requirements for new personal developer accounts](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en) — 12 testçi × 14 gün
- [Verify your developer identity information](https://support.google.com/googleplay/android-developer/answer/10841920?hl=en) — D‑U‑N‑S, kimlik doğrulama
- [Financial Services policy](https://support.google.com/googleplay/android-developer/answer/9876821?hl=en)
- [Provide information for the Financial features declaration](https://support.google.com/googleplay/android-developer/answer/13849271?hl=en)
- [Google Play screenshot sizes 2026](https://appradar.com/blog/android-app-screenshot-sizes-and-guidelines-for-google-play) — 2:1 en-boy sınırı, 320–3840 px

---

**Son güncelleme:** 2026-09-05
