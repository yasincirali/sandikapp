# sandık — Senin Yapman Gerekenler (Detaylı Rehber)

**Tarih:** 2026-05-11
**Kapsam:** Yayın öncesi senin elden yapman gereken işler. Kod tarafı (Faz 1) tamam; bu liste deploy + hukuki + ticari adımları içerir.

---

## 📊 GENEL DURUM

✅ **Bende biten kod işleri:**
- Marka: `com.sandik.app`, label "sandık"
- Güvenlik: yasaklı izin silindi, db_logs PII maskeleme, secrets → dart-define, ProGuard/R8 aktif
- Hesap silme akışı: UI + AuthService + Edge Function + SQL migration
- 6 adet P0 crash fix
- Supabase timeout (15sn)
- friendlyError helper + 8 yerde uygulama
- Register'a KVKK + Açık Rıza checkbox'ları
- 9 adet hukuki belge (TR + EN)

---

## 💰 MONETİZASYON: `paywall_enabled` bayrağı (2026-07-13)

**Şu an durum:** Paywall UI iskeleti hazır ama **Firebase Remote Config** üzerinden `paywall_enabled = false` ile kapalı. Kullanıcı hiçbir premium/ödeme ekranı görmüyor.

**Açman gerekli olduğunda sıra:**

1. **App Store Connect + Google Play Console** — 2 subscription ürünü oluştur (aynı product ID'ler):
   - `sandik_premium_monthly`
   - `sandik_premium_yearly`
2. **RevenueCat Dashboard:** proje aç → iOS/Android app'leri bağla → `premium` entitlement + `default` offering tanımla → iOS/Android API key'lerini al
3. Bana bildir → RevenueCat SDK entegrasyonunu yaparım ([paywall_screen.dart:120, :140](lib/screens/paywall_screen.dart) TODO'ları)
4. **Firebase Console → Remote Config → `paywall_enabled` → `true` → Publish**
5. Uygulama açılışında UI otomatik gelir, kod push'una gerek yok

Detay: [MONETIZATION_ROADMAP.md](MONETIZATION_ROADMAP.md#-master-kill-switch-paywall_enabled-2026-07-13)

---

❌ **Senin yapacakların — 7 ana başlık, 4-6 iş günü:**

| Sıra | İş | Tahmini süre | Bloker? |
|---|---|---|---|
| 1 | Marka kararları (logo, domain, e-posta) | 1 gün | Evet — diğer her şey buna bağlı |
| 2 | Tüzel kişilik & hukuki TODO'ları doldur | 1-2 gün | Evet — yayın bloker |
| 3 | Web sayfası (hukuki + hesap silme) | 1 gün | Evet — Play Store bloker |
| 4 | Release keystore oluştur | 30 dk | Evet — Play upload bloker |
| 5 | Supabase deploy (migration + Edge Function) | 30 dk | Evet — hesap silme bloker |
| 6 | Google Play Console hesap ve listing | 1 gün | Evet |
| 7 | Manuel test (özellikle hesap silme) | 4 saat | Evet |

---

## 1. 🎨 MARKA KARARLARI (önce bu)

Bunlar sonraki her şeyin temeli. Önce karar verelim ki ben de URL'leri / e-posta'ları kodda yerine koyabileyim.

### 1.1 Domain Adı

İhtiyacın olan: Web sitesi için bir domain (hukuki belgeleri + hesap silme formunu host edeceksin).

**Öneri:** `sandik.app` veya `sandik.com.tr` veya `sandikapp.com`

- **Nereden alınır:** namecheap.com, godaddy.com, isimtescil.net (TR)
- **Tahmini maliyet:** Yıllık ~$15-100 (uzantıya göre)
- **Süreç:** Whois bilgisi gizli olsun (privacy protection — çoğu kayıtçıda ücretsiz)

⚠️ **Karar al ve bana söyle.** Şu an kodda `https://sandik.app/...` placeholder var; başka bir domain seçersen değiştireceğim.

### 1.2 İletişim E-posta

İhtiyacın olan: Destek + KVKK başvuruları + Apple/Google reviewer için.

**Öneri:** `destek@sandik.app` veya `info@sandik.app`

- **Nereden alınır:** Google Workspace ($6/ay/kullanıcı), Zoho Mail (ücretsiz tier var), domain sağlayıcının mail servisi
- **Asgari:** Spam dolu kişisel Gmail değil, domain'inin mail'i.
- **Önerilen:** Ayrıca `kvkk@sandik.app` ve `privacy@sandik.app` alias'ları aç (KVKK başvuruları + GDPR requests için ayrı kanal).

Şu an kodda `destek@sandik.app` placeholder var.

### 1.3 App Store / Play Store Görünen İsim

**Karar verildi: "Sandık" (büyük S, dotless ı).** Arama bulunabilirliği için
tüm yüzeylerde tek yazım kullanılıyor:

- Android `strings.xml` → `Sandık` ✅ (kodda güncellendi)
- iOS `CFBundleDisplayName` → `Sandık` ✅ (eski değer `SANDIK` idi, düzeltildi)
- `store_listing/tr-TR/title.txt` → `Sandık — Portföy Takibi` ✅ (27/30 karakter)
- `store_listing/en-US/title.txt` → `Sandık — Portfolio Tracker` ✅

**⚠️ SENİN YAPMAN GEREKEN — Play Console'daki başlık repodan okunmaz.**
Store listing metinleri Console'a elle girilir; repodaki `store_listing/`
dosyaları yalnızca kaynak metindir. "Sandık" araması sonuç vermiyorsa asıl
sebep büyük ihtimalle Console'daki başlığın hâlâ eski yazımda olmasıdır.

Play Console → Grow → Store presence → Main store listing:
1. **App name** alanına `Sandık — Portföy Takibi` yaz
   (`store_listing/tr-TR/title.txt` içeriğiyle birebir aynı)
2. **Short description** → `store_listing/tr-TR/short_description.txt`
3. **Full description** → `store_listing/tr-TR/full_description.txt`
4. Kaydet → yayına alınması genelde birkaç saat, arama indeksine tam
   yansıması **birkaç güne kadar** sürebilir. Hemen sonuç bekleme.

**Not:** Play Store'un arama indeksi Türkçe diakritiklerde tam eşleşmeye
yakın davranıyor; bu yüzden `full_description.txt` içine "Sandık / sandık /
SANDIK / Sandik / sandik" varyantlarını içeren bir ARAMA bölümü eklendi.
Anahtar kelime doldurma (keyword stuffing) sayılmaması için varyantlar tek
bir doğal cümlede tutuldu — bu bölümü şişirme, politika ihlali riski var.

### 1.4 Logo & Görsel Asset'ler

Şu anda mevcut: `assets/images/sandik_icon.png` (launcher), `sandik_logo.svg`, `loading.gif`.

**Eksik / iyileştirilmeli:**
- **Adaptive icon foreground** (Android 8+): `assets/images/sandik_icon_fg.png` — saydam arkaplanlı, kenarlardan %33 boşluk bırakılmış (Android masking için). 1024x1024 PNG.
- **Adaptive icon background**: tek renk (`#0A1E15` — Sandik.background) yeterli.
- **Monochrome icon** (Android 13+ themed icons): siyah-beyaz silüet, 1024x1024.
- **Feature graphic** (Play Store): 1024x500 PNG/JPG. Logo + tagline.
- **Screenshot setleri** (en az 2, max 8):
  - Telefon: 1080x1920 minimum (örn. portföy listesi, varlık ekleme, performans grafiği, ortaklık, settings).
  - 7" tablet: opsiyonel ama önerilir.

**Maliyet seçenekleri:**
- Kendin yap: Figma ücretsiz, Canva $0-12/ay.
- Freelancer: fiverr.com ~$50-200, upwork.com daha pahalı ama kaliteli.
- Bir tasarımcı arkadaş varsa o ☺

---

## 2. 📜 HUKUKİ TODO'LAR (yayın bloker)

`legal/` klasöründeki 9 belgenin içinde `[ŞİRKET ADI]`, `[ADRES]` gibi placeholder'lar var. Hepsini gerçek değerle değiştirmen gerek.

### 2.1 Tüzel Kişilik Kararı (KRİTİK)

**Üç senaryo var, hangisi sende?**

#### Senaryo A — Bireysel girişimci (şirket yok)
- Veri sorumlusu: **Sen, ad-soyad** ile.
- Adres olarak ev adresi vermek istemiyorsan: sanal ofis hizmeti (~₺500/ay) veya muhasebecinin adresi.
- **VERBİS:** Bireysel veri işleyici muafiyet eşikleri var (yıllık ciro <100M TL VE çalışan <50 olanlar muaf olabilir). kvkk.gov.tr/Icerik/2030 → Verbis Hakkında. Muaf olsan bile KVKK Madde 10 aydınlatma yükümlülüğü devam eder.
- **Vergi:** Yıllık geliri ₺580.000 üstüne çıkarsa (2025 sınırı, yıllık güncelleniyor) basit usul vergi mükellefi ol.
- **Risk:** Şirketleşmeden uygulamadan gelir elde edersen vergi denetimi açar.

#### Senaryo B — Limited Şirket / Anonim Şirket
- Kuruluş maliyeti: ~₺15-30k (noter, sicil, muhasebeci, ilk ay).
- Aylık sabit gider: muhasebeci ₺2.5-5k.
- **Avantaj:** Vergi planlaması, sorumluluk şirkette, profesyonel görünüm.
- **VERBİS:** Çoğunlukla zorunlu.

#### Senaryo C — Şahıs şirketi (basit)
- Kuruluş ~₺3-5k. Vergiler şahıs üzerinden.
- Limited'in light versiyonu. App'ten ciddi gelir beklemiyorsan başlangıç için OK.

**Benim önerim:** App'i önce yayınla, kullanıcı bul, sonra para kazanmaya başlarken Senaryo C'ye geç. **Yayın için bireysel girişimci olarak başlayabilirsin** — sadece tüm hukuki belgelerde "Şirket" yerine "Veri Sorumlusu" sıfatıyla kendi adın ve sanal ofis adresinle imzala.

⚠️ **Karar al:** A, B veya C? Avukat veya muhasebeciyle 1 saatlik konsültasyon (~₺500-1000) çok mantıklı.

### 2.2 Placeholder'ları Doldur

Aşağıdaki tabloyu doldur, sonra tüm `legal/*.md` dosyalarında bulup değiştir.

| Placeholder | Senin değer |
|---|---|
| `[ŞİRKET ADI]` | (örn. "Yasin Çıralı" veya "Sandık Yazılım Ltd. Şti.") |
| `[AÇIK ADRES]` | (sanal ofis veya gerçek adres) |
| `[VERGİ NO]` | (varsa) |
| `[VERBİS NO]` | (varsa; muafsanız "Muaf — Madde 16") |
| `[KEP ADRESİ]` | (Limited/AŞ ise zorunlu; bireysel iseniz opsiyonel) |
| `[İLETİŞİM E-POSTA]` | (örn. destek@sandik.app) |
| `[TELEFON]` | (opsiyonel; girersen iş telefonu) |
| `[WEB SİTESİ]` | (örn. https://sandik.app) |
| `[YETKİLİ MAHKEME]` | (yerleşim yerin; örn. "İstanbul Anadolu") |
| `[DPO İSİM/E-POSTA]` | (Data Protection Officer — şirketsen ve verişlemen büyükse zorunlu, bireysel için yok) |
| `[EU REPRESENTATIVE]` | (AB pazarına ciddi servis veriyorsan zorunlu — başlangıçta atla) |

**Pratik komut** (placeholder'ı bul):
```bash
grep -rn "\[" legal/ | grep -v "^Binary" | grep -E "\[[A-Z]"
```

### 2.3 Hukuki Onay

Hazırladığım belgeler **kapsamlı şablon**. Ama **bir avukatla** mutlaka iki şeyi onaylat:

1. **Yatırım disclaimer'ı** — SPK avukatına: "Çoklu kullanıcı ortaklık özelliği 'kollektif portföy yönetimi' olarak yorumlanabilir mi?" sorusunu sor. Risk varsa "ortaklık" özelliğini "salt görüntüleme" olarak kısıtla.
2. **KVKK uygulanabilirliği** — KVKK avukatına: tüzel kişilik kararına göre VERBİS zorunlu mu, açık rıza metni yeterli mi.

**Avukat ücreti:** ~₺2-5k tek seferlik review (network'üne sor, KVKK + bilişim hukuku odaklı biri).

---

## 3. 🌐 WEB SAYFASI (Play Store BLOKER)

Google Play, hesap silme için **halka açık bir web URL** istiyor. Ek olarak privacy policy URL'i de zorunlu. Tek bir basit site yetiyor.

### 3.1 En Hızlı Yol: GitHub Pages (ÜCRETSİZ)

1. GitHub'da `sandik-website` adında yeni repo aç (public).
2. Şu dosyaları root'a koy:
   - `index.html` — landing page (logo, "App Store'dan indir" linki, hukuki link'leri)
   - `privacy.html` — `legal/tr/PRIVACY_POLICY.md` Markdown → HTML çeviri
   - `privacy-en.html` — `legal/en/PRIVACY_POLICY.md`
   - `terms.html` — Türkçe Terms
   - `terms-en.html`
   - `kvkk.html` — KVKK Aydınlatma Metni
   - `acik-riza.html` — Açık Rıza Metni
   - `data-deletion.html` — `legal/DATA_DELETION_REQUEST_FORM.md` içindeki HTML form
3. Settings → Pages → Source: `main` branch, `/` (root) → Save.
4. Domain bağla: Settings → Pages → Custom domain → `sandik.app` (DNS A record gerekir).

**Markdown → HTML için:** pandoc, marked-cli, veya en kolayı: https://stackedit.io üzerinde her dosyayı yapıştır + sağ taraftan "Export as HTML" indir.

### 3.2 Daha Profesyonel: Vercel / Netlify (ÜCRETSİZ)

- Next.js veya Astro ile statik site. Hızlı, SEO uyumlu.
- 2-3 saatlik iş.

### 3.3 Minimum Gereksinim

Aşağıdaki URL'ler **çalışır durumda** olmalı (Play Store reviewer click eder):

- `https://sandik.app/privacy` (TR + EN dil seçici)
- `https://sandik.app/terms`
- `https://sandik.app/legal/kvkk`
- `https://sandik.app/data-deletion` (form ile)
- `https://sandik.app/legal/acik-riza`

Tüm bu URL'ler kodda referans veriliyor (`lib/screens/settings_screen.dart` ve `register_screen.dart`).

### 3.4 Data Deletion Form Backend

`data-deletion.html` formunda kullanıcı talep gönderecek. İki seçenek:

**Basit:** Formspree (ücretsiz tier 50 istek/ay) — formu Formspree endpoint'ine post et, email olarak sana gelir.

**Gelişmiş:** Supabase Edge Function ile bir "deletion-request" tablosuna yaz, sana her istek için email bildirimi (kullanıcı uygulama içinden silmek yerine bu yolu seçerse).

---

## 4. 🔐 RELEASE KEYSTORE OLUŞTUR (Play upload BLOKER)

Bu **çok kritik** — keystore'u kaybedersen Play Store'a güncelleme yükleyemez, uygulamayı baştan yeni paket adıyla yayınlamak zorunda kalırsın. **Yedekle.**

### 4.1 Keystore Üret

Bilgisayarında JDK kuruluysa (Android Studio kurduğun için var):

```bash
cd c:/projects/PortfoyTakip/android
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Sorulacaklar:
- **Keystore password:** Güçlü bir şifre seç (16+ karakter). NEVER UNUTMA.
- **Key password:** Aynı şifre olabilir (basitlik için).
- **First/last name:** Ad Soyadın.
- **Organizational unit:** boş geç.
- **Organization:** "sandık" veya şirket adın.
- **City:** İstanbul (veya bulunduğun yer).
- **State:** Türkiye.
- **Country code:** TR.
- "Is this correct?" → yes.

Sonuç: `android/upload-keystore.jks` dosyası oluşur.

### 4.2 key.properties Dosyası

`android/key.properties` (gitignore'da, commit edilmez):

```properties
storePassword=YUKARIDAKI_KEYSTORE_SIFRESI
keyPassword=YUKARIDAKI_KEY_SIFRESI
keyAlias=upload
storeFile=../upload-keystore.jks
```

Şablon var: `android/key.properties.example` — kopyala ve değerleri gir.

### 4.3 YEDEK AL — 3 ayrı yere

Bunlar kaybolursa uygulama "ölür". 3 ayrı yere yedek tut:

1. **Şifreli USB / harici disk** (offline yedek)
2. **Bulut storage** (Google Drive / iCloud / 1Password) — şifreli klasör içinde
3. **Fiziksel kâğıda yaz** (keystore + key alias + şifreler) ve cüzdana/kasaya koy

Yedek dosyalar:
- `upload-keystore.jks`
- `key.properties`
- Bu şifrelerin yazılı olduğu güvenli not

### 4.4 Test Et

```bash
cd c:/projects/PortfoyTakip
flutter build appbundle --release
```

Başarılıysa: `build/app/outputs/bundle/release/app-release.aab` dosyası üretildi → Play Store'a yüklenebilir.

Hata alırsan key.properties yolu yanlış olabilir; `storeFile=../upload-keystore.jks` `app/build.gradle.kts`'in olduğu dizinden bir üst dizine bakıyor demek (yani `android/upload-keystore.jks`).

---

## 5. ☁️ SUPABASE DEPLOY (hesap silme BLOKER)

Hesap silme akışı için backend tarafında 3 şey yapman gerek.

### 5.1 Supabase CLI Kur

```bash
# Windows (Scoop)
scoop install supabase

# veya manuel: https://supabase.com/docs/guides/cli/getting-started
```

### 5.2 Projeye Bağlan

```bash
cd c:/projects/PortfoyTakip
supabase login        # tarayıcı açar, login
supabase link --project-ref <SENIN_PROJECT_REF>
```

`<SENIN_PROJECT_REF>` = Supabase dashboard URL'inden `https://supabase.com/dashboard/project/XXXX` → XXXX kısmı.

### 5.3 Migration'ı Uygula

```bash
supabase db push
```

Bu komut `supabase/migrations/0007_account_deletion_log.sql` dosyasını gerçek DB'ye uygular. Tablo oluşur.

**Eğer "no schema migration" hatası alırsan:** Önce `supabase db pull` ile mevcut şemayı sync et, sonra push et. Veya Supabase Dashboard → SQL Editor'e gir, dosyanın içeriğini yapıştır, Run.

### 5.4 Edge Function Secret Set Et

```bash
# Hash salt — production'da random 64-character olmalı
supabase secrets set DELETION_HASH_SALT="$(openssl rand -hex 32)"
```

openssl yoksa: PowerShell'de `[guid]::NewGuid().ToString() + [guid]::NewGuid().ToString()` ile 64-char random üret.

### 5.5 Edge Function Deploy

```bash
supabase functions deploy delete-account
```

Output: `Function delete-account deployed successfully`.

### 5.6 Test Et

1. Test hesabı oluştur (uygulamadan).
2. Settings → Hesabımı Sil → şifre gir → onayla.
3. Supabase Dashboard → Authentication → Users: kullanıcı silinmiş olmalı.
4. Supabase Dashboard → Table Editor → `account_deletion_log`: 1 satır eklenmiş olmalı (anonim hash + email_domain).
5. Aynı e-posta ile tekrar register dene: "yeni hesap" gibi davranmalı, eski veri gelmemeli.

⚠️ **Eğer hata alırsan:** Edge Function loglarına bak: Supabase Dashboard → Edge Functions → delete-account → Logs.

---

## 6. 📱 GOOGLE PLAY CONSOLE

### 6.1 Hesap Aç

- **URL:** https://play.google.com/console
- **Maliyet:** $25 tek seferlik (lifetime).
- **Gerekli:** Google hesabı, kredi kartı, kimlik (TC kimlik için pasaport scan'i isteyebilir).
- **Süreç:** Genelde 1-2 gün içinde onaylanır.

### 6.2 Uygulama Oluştur

Play Console → Create app:
- **App name:** "sandık" veya "sandık - Portföy Takibi"
- **Default language:** Türkçe
- **App or game:** App
- **Free or paid:** Free
- **Declarations:** Uyguluyor mu uymuyor mu? Hepsi onayla.

### 6.3 Listing Doldur

Şu sekmeleri tamamla:
- **Main store listing:**
  - Short description (80 char): "Hisse, fon, döviz ve altın portföyünüzü kolayca takip edin."
  - Full description (4000 char): Özellikler, hedef kitle, gizlilik vurgusu (KVKK uyumlu). Sana taslak yazayım dersen söyle.
  - Icon: 512x512 PNG (mevcut launcher'ın yüksek çözünürlüklü versiyonu)
  - Feature graphic: 1024x500
  - Screenshots: minimum 2, maksimum 8 (telefon 16:9 oranlı)
- **Store settings:**
  - App category: Finance
  - Tags: portfolio, finance, tracker
  - Contact details: support email + privacy policy URL + website
- **Privacy policy:** `https://sandik.app/privacy` (sayfa hazır olmalı)
- **App content:**
  - Privacy policy URL ✓
  - Ads: No
  - Content rating: IARC questionnaire (~15 soru, ~10 dk). Finance, no violence, no gambling → muhtemelen Everyone / Mature 17+
  - Target audience: 18+ (yatırım uygulaması)
  - News app: No
  - Data safety: KVKK formundan veri envanteri kopyala
  - Government apps: No
  - Financial features: ✓ Manage personal finance / Track investments
- **Account deletion:**
  - In-app deletion: ✓ Available
  - Web URL: `https://sandik.app/data-deletion`

### 6.4 Internal Testing Track

İlk yayında **production'a değil internal test'e** yükle.

1. **Testing → Internal testing → Create new release**
2. Upload `app-release.aab`
3. Release notes (TR + EN): "İlk sürüm"
4. **Testers:** Email listesi oluştur (kendin, eşin, arkadaşların — max 100 kişi).
5. **Save → Review release → Start rollout to internal testing**
6. 2-4 saat sonra tester'lar Play Store'da app'i görebilir (özel link ile).

### 6.5 Production'a Geç

Internal testing 1-2 hafta sorunsuz çalıştıktan sonra:
- Crash rate < %1
- Negatif feedback yok
- ANR (App Not Responding) rate < %0.5

→ **Closed testing → Open testing → Production** kademeli geçiş.

İlk Production yükleme **2-7 gün** review alır (Türk app'lerinde genellikle 1-3 gün).

---

## 7. 🧪 MANUEL TEST PLANI

Yayından önce mutlaka şu akışları **gerçek emülatörde** test et:

### 7.1 Kritik Akışlar
- [ ] Yeni hesap aç (Register) — 3 onay kutusu zorunlu çalışıyor mu?
- [ ] Login → ana ekran → varlık ekle → fiyat çek → performans grafiği
- [ ] Logout → Login → aynı veri geliyor mu
- [ ] Ortak davet üret → ikinci hesapla kabul et → her iki tarafta görünüyor mu
- [ ] Push bildirim geliyor mu (gerçek cihazda — emülatörde FCM token alır ama bildirim deliveri için Firebase config doğru olmalı)
- [ ] **Hesap silme:** test hesabı → Settings → Hesabımı Sil → şifre → 30 sn içinde tamamlandı mı? Supabase'de gerçekten silindi mi?

### 7.2 Hata Senaryoları
- [ ] İnternet kapalıyken Login → "İnternet bağlantını kontrol et" mesajı çıkıyor mu (raw SocketException değil)
- [ ] Yanlış şifre ile login → "E-posta veya şifre hatalı"
- [ ] Yanlış şifre ile hesap sil → "Şifre hatalı"
- [ ] Zayıf internette refreshPrices → 15 sn sonra timeout, donmuyor
- [ ] Boş portföy → boş state ekranı, crash yok
- [ ] Yeni kayıt olunca onay kutusunu işaretlemeden submit → 3 farklı kırmızı uyarı çıkıyor mu

### 7.3 UI Testleri
- [ ] Splash → loading → ana ekran geçişleri akıcı mı
- [ ] Pie chart'a tıkla → kategori filtresi çalışıyor mu
- [ ] Dark theme her ekranda tutarlı mı
- [ ] Tüm modal/dialog'lar geri tuşuyla kapanıyor mu

### 7.4 Release Build Testi

Debug build her zaman çalışır, asıl test **release** build:

```bash
flutter build apk --release
# APK'yı cihaza yükle
adb install build/app/outputs/flutter-apk/app-release.apk
```

ProGuard/R8 sonrası kırılan bir şey varsa burada görünür (Reflection kullanan paketler vs.). Hata olursa `proguard-rules.pro`'ya keep rule ekleriz.

---

## 📋 ÖZET — Şu sıra ile ilerle

**Bu hafta:**
1. Domain al + email kur (1.1, 1.2) → ~1 saat
2. Tüzel kişilik kararı + avukatla 1 saat konuş (2.1, 2.3) → 1-2 gün
3. Hukuki placeholder'ları doldur (2.2) → 2 saat
4. Release keystore üret + yedekle (4.1-4.3) → 1 saat

**Önümüzdeki hafta:**
5. Web sitesi setup (3) → 1 gün
6. Supabase deploy (5) → 1 saat
7. Play Console hesap + listing (6.1-6.3) → 1 gün
8. Manuel test (7) → 4 saat

**3. hafta:**
9. Internal testing → tester feedback'i topla
10. Crashlytics ekleyelim mi karar ver (önerim: evet)
11. Production rollout

---

## ❓ ŞU AN BANA SORMAN GEREKENLER

Bir karara varman gerekirse aşağıdakileri net söyle, ona göre kod ve dokümanları güncelleyeyim:

1. **Domain:** `sandik.app` mı, başka bir şey mi? (URL'leri kodda + 9 hukuki belgede tek seferde değiştiririm)
2. **İletişim e-posta:** Hangi adres? (Belgelerde 3-4 yerde geçiyor)
3. **Tüzel kişilik:** Bireysel mi, şirket mi? (KVKK Aydınlatma Metni'nin tonu değişir)
4. **Faz 1'den kalan UI işleri:** Şu an sıradakiler — hangisinden devam edelim:
   - **Adaptive icon** (~3 saat) — Android 8+ launcher'da daha güzel görünür
   - **Onboarding** (yeni kullanıcıya 3-step tutorial) (~2 gün)
   - **"Verilerimi İndir" JSON export** (GDPR portability hakkı, ~1 gün)
   - **Firebase Crashlytics** entegrasyonu (~4 saat)
   - **Settings'e tema toggle / bildirim toggle** (~3 saat)

Şimdi söyleyebileceğin en yararlı şey: **1, 2, 3 numaralı kararlar.** Onlar olunca placeholder'ları silip tek bir commit ile her şeyi gerçek değerlerle güncellerim.
