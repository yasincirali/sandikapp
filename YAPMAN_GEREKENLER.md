# sandık — Senin Yapman Gerekenler (Detaylı Rehber)

**Tarih:** 2026-05-11 · **Son ek:** 2026-09-14 (#24: 0000 işaretleme + 0063 + observe-tefas-nav)
> **📱 Android/Play tarafı için güncel dosya:**
> [`PLAY_STORE_YAYIN_REHBERI.md`](PLAY_STORE_YAYIN_REHBERI.md) (2026-09-05).
> Aşağıdaki §4 (keystore) ve §6 (Play Console) bölümleri 2026-05 tarihli;
> Play'in kuralları o tarihten sonra değişti (targetSdk 36, 16 KB sayfa
> boyutu, finansal özellik beyanı, geliştirici doğrulama). Çakışma olursa
> yeni rehber geçerlidir.

**Kapsam:** Yayın öncesi senin elden yapman gereken işler. Kod tarafı (Faz 1) tamam; bu liste deploy + hukuki + ticari adımları içerir.

---

## 🧭 2026-09-21 sadeleştirme turu — TestFlight testi + video/ekran görüntüsü kaydı

Kod: `feat/sadelestirme-2026-09-21`. Hiçbir özellik silinmedi; yer ve sıra
değişti. Plan ve yerleşim: https://claude.ai/artifact/7aCK2SKzeCF5Yrnn9DYoif

### Cihazda (10 dk)
1. **Ana ekran** — sıra: piyasa bandı → toplam kartı → Bugün kartı → dağılım
   → hareketler. Ayrı reel getiri / yüzdelik / haftalık şeritleri YOK; reel
   getiri ("+31,5 puan enflasyonun önündesin · yıllık") ve haftalık özet
   (Pzt–Sal sabit, sonra dönüşümlü) Bugün kartının satırları. Satıra dokun →
   Performans › Özet ilgili dönemde (1Y / 1H).
2. **Görünüm çipi** — ortağın varsa toplam kartının başlığında "Ben ▾" çipi;
   dokun → Ben / Ayşe / Birlikte sayfası. Ortak seçince eski şeritler o
   görünümde yine görünür (kart kişisel olduğu için ortak görünümünde yok).
3. **Performans › Özet** — üç başlık: BU DÖNEM, VARLIKLAR, DERİNLİK. Derinlik
   ileri seviyede açık, diğerinde katlı; dokununca açılır. Grafik'te
   Gerçek/Simülasyon anahtarı aynen duruyor.
4. **Profil** — Yarış kartının altında yüzdelik dilim şeridi (opt-in + 8 kişi
   dolunca görünür; şimdilik boş olması normal).
5. **Çan sayfası** — başlıkta "Alarmlarım" düğmesi → alarm listesi.
6. **Ayarlar** — Görünüm'de hedef satırı yok (Bugün kartından); Bildirimler'de
   "Sinyal ayarları" tek satır, sağında anahtar.

### Video ve mağaza görseli (senden kayıt, ~10 dk)
Önizleme videosunun 1. ve 2. sahnesi ve `set_c` 1. ekran görüntüsü eski
ana ekranı gösteriyor. Yeni build'de iPhone'da kaydet (Ayarlar › Kontrol
Merkezi › Ekran Kaydı, ses kapalı, dikey):
- **kayit_ana.mov** — ana ekran, 6 sn sabit: piyasa bandı akarken, Bugün
  kartında reel getiri satırı görünür olsun (portföy "Ben" görünümünde).
- **kayit_ozet.mov** — Performans › Özet › 1Y, 6 sn: BU DÖNEM başlığı ve
  reel getiri kartı ekranda.
- **ss_1.png** — ana ekranın ekran görüntüsü (aynı kare) → `set_c` 1. kare.
Dosyaları `store_listing/preview_video/raw/` altına koy ve söyle; Remotion
kurgusunu (altyazı/ses aynı) ben yeniden render ederim.

---

## 📲 2026-09-20 günlük giriş turu — TestFlight'ta test edeceklerin

Kod: `feat/gunluk-giris-2026-09-20`. Beş özellik: piyasa şeridi, takip
listesi hareketi push'u, TÜFE günü push'u, varlık eklerken alarm önerisi,
brifing saati (sabah/akşam). Sunucu: migration `0068` + `check-price-alerts`,
`daily-brief`, `fetch-inflation` fonksiyonları (deploy'u Claude koşar).

### Cihazda (TestFlight, 10 dk)
1. **Piyasa bandı** — ana ekranda hero kartın ÜSTÜNDE 30pt'lik kayan bant:
   Dolar · Euro · Gram altın · BIST 100, fiyat + günlük yüzde (▲ yeşil /
   ▼ kırmızı), soldan sağa sürekli akar (~17 sn'de bir tur). Dokun → durur
   ve elle kaydırılır; tekrar dokun → akar. iOS Ayarlar › Erişilebilirlik ›
   Hareket › "Hareketi azalt" açıkken bant durağan olmalı. Bant hiç yoksa
   fiyat kaynağı düşmüş demektir, söyle. Ayarlar › Tanıtım turunu yeniden
   izle → "Piyasa bir bakışta" adımı gelmeli (YENİ rozeti).
2. **Alarm önerisi** — + ile bir hisse/altın ekle ve kaydet. Portföy'e
   dönerken altta "X eklendi. Fiyatı izlemek için alarm kur?" bildirimi ve
   "Alarm kur" eylemi görünmeli; dokununca alarm sayfası o varlıkla açılmalı.
   Manuel fiyatlı varlıkta öneri gelmez (doğru davranış).
3. **Brifing saati** — Ayarlar › Bildirimler'de "Brifing saati" satırı,
   Sabah 09:45 / Akşam 18:30 seçici. Akşamı seç, uygulamayı kapat-aç,
   seçim kalmalı (sunucuya yazıyor).
4. **Takip listesi hareketi** — Portföy › Takip listesine oynak bir hisse
   ekle. İlk push hafta içi 18:25'te, yalnızca ±%5 üstü hareket varsa.
   Dokununca Portföy sekmesi açılmalı; çanda "TAKİP" rozeti.
5. **TÜFE günü** — ilk gerçek push 3 Ekim ~10:05 ("Eylül enflasyonu %x").
   Dokununca Özet açılmalı; çanda "TÜFE" rozeti. Öncesinde test etmek
   istersen söyle: `fetch-inflation`'ı kuru koşuyla değil, `inflation_push_log`
   satırını silip tetiklemek gerekir — bunu Claude yapar.

### Sunucu doğrulaması (Claude koşar, sen sonucu görürsün)
`cron.job`'da `watchlist-moves` = `25 15 * * 1-5`, `daily-brief-evening` =
`30 15 * * 1-5`; `profiles.brief_slot` sütunu; `app_notifications` CHECK
kısıtında `watchlist_move` ve `inflation_day`.

---

## 🚀 2026-09-20 büyüme turu — senin paralelde yapacakların

Kod tarafı bitti (`feat/buyume-turu-2026-09-20`): paylaşım/davet metninde
indirme bağlantısı + UTM, web sayfasında Safari akıllı banner + mağaza
düğmeleri, `/indir/` kapısı, Bugün kartı ölçümü, 5 adımlık ilk tur, boş
portföyde "ekstreden yapıştır", aylık özet push'u (0067), kısmi kanarya,
yarış havuzu sayısı, `unawaited` süpürmesi. Aşağıdakiler kod dışı.

### A. Android imzalı AAB provası — 4 GitHub secret + keystore (30 dk)

`android-release.yml` hiç koşmadı çünkü secret'lar yok (`gh secret list`:
ANDROID_* ve GOOGLE_SERVICES_JSON_BASE64 eksik). Play kapalı testine
girmeden bir kuru koşu şart.

1. Keystore (bir kez, §4.1 ile aynı; **yedekle** — kaybedersen Play'e
   güncelleme yükleyemezsin):
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 \
     -validity 10000 -alias upload
   ```
2. Secret'ları GitHub'a yaz (repo → Settings → Secrets → Actions, ya da CLI).
   Değerleri Claude'a YAZMA; komutları sen koş:
   ```bash
   gh secret set ANDROID_KEYSTORE_BASE64 --body "$(base64 -w0 upload-keystore.jks)"
   gh secret set ANDROID_KEY_ALIAS --body upload
   gh secret set ANDROID_KEY_PASSWORD        # sorunca yapıştır
   gh secret set ANDROID_STORE_PASSWORD
   gh secret set GOOGLE_SERVICES_JSON_BASE64 --body "$(base64 -w0 android/app/google-services.json)"
   ```
   (`google-services.json` Firebase Console › Project settings › Android
   uygulaması › indir; repoya KOYMA.)
3. Prova: Actions › "Android — Release AAB" › Run workflow (`build_apk`
   kapalı). Yeşilse artefakttan `symbols/` klasörünü indirip sakla.
   Kırmızıysa log'u Claude'a ver.

### B. Universal Links için alan adı kararı (10 dk karar, 1 gün yayılma)

Paylaşılan bağlantı `yasincirali.github.io/sandikapp/indir/`. Uygulamayı
doğrudan açması için AASA dosyası alan adının KÖKÜNDE olmalı; alt yolda
çalışmaz. İki seçenek:
- **`sandik.app` gibi özel alan adı** (yıllık ~1.000 ₺): GitHub Pages ›
  Custom domain'e yaz, DNS'te CNAME → `yasincirali.github.io`. Sonra
  Claude AASA + entitlements + manifest'i yapar (TECHNICAL_DEBT "Universal
  Links").
- **`yasincirali.github.io` kök reposu**: `yasincirali/yasincirali.github.io`
  adlı repo aç, `.well-known/` oraya gider. Ücretsiz ama marka dışı adres.
Kararı söyle; Apple Developer › Identifiers › `com.sandik.app` ›
**Associated Domains** yeteneğini de sen açarsın (match profil yeniler).

### C0. Küresel sıralama parametrik KAPALI (2026-09-21)
Uygulama varsayılanı `global_leaderboard_enabled=false` ve
`percentile_strip_enabled=false`: yüzdelik dilim, en çok kazandıranlar, solo
panel, Özet'teki benchmark kartı görünmez; ortaklar arası yarış açık.
Havuz 8'i geçince Remote Config'de iki anahtarı `true` yapıp Publish —
sürüm gerekmez. "N kişi yarışta" satırı kalktı (sayı yanlış anlaşılıyordu).

### C. Firebase Remote Config — iki parametre (5 dk)

Console › Remote Config › Add parameter (yoksa uygulama varsayılanı
kullanır, ama kapatma düğmesi elinde olsun):
- `review_prompt_enabled` = `true` (Boolean)
- `review_prompt_soft_gate` = `true` (Boolean)
- (var olmalı) `paywall_enabled` = `false`
Publish changes. İlk mağaza yorumları olumsuz gelirse `review_prompt_enabled`
→ `false` anında susturur.

### D. Aylık özet — ilk kuru koşu (deploy sonrası, 2 dk)

Main'e merge + `supabase-deploy` (migrations + `weekly-summary
check-price-alerts`) sonrası, gerçek gönderim OLMADAN:
```bash
gh workflow run supabase-deploy.yml -f migrations=false -f functions=none \
  -f sql="select jobname, schedule, active from cron.job where jobname in ('monthly-summary','weekly-summary','daily-brief') order by 1"
```
Üç satır, `monthly-summary` = `30 6 1 * *`, `active = t` olmalı. Gerçek ilk
gönderim 1 Ekim 09:30 (TR). O sabah çan sayfasında "AYLIK" rozeti +
push'a dokununca Özet › 1A açılmalı.

### E. TestFlight cihaz testi — bu turun görünen kısmı (15 dk)

Emülatör render etmiyor; gerçek cihazda:
1. Yeni hesapla giriş → tur **5 kart** olmalı, sonuncusu "Hazırsın" ve
   Varlık Ekle açık kalmalı. Ayarlar › Tanıtım turunu yeniden izle → tam tur.
2. Boş portföyde "Ekstreden / CSV'den yapıştır" düğmesi + alt ipucu görünmeli.
3. Performans › Özet › Paylaş → metin **son satırda bağlantı** taşımalı; bağlantıya
   dokununca `/indir/` sayfası açılmalı (iOS'ta 0,6 sn sonra App Store).
4. Profil › Ortak kodu paylaş → mesajda bağlantı `?kod=XXXX`; sayfa kodu
   büyük yazmalı.
5. Ana ekran Yarış kartı → "N kişi katıldı · sıralama 8 kişide açılır".
6. Firebase › Analytics › DebugView (cihazı debug moda al) → `today_row_shown`,
   `today_row_tapped`, `goal_set` düşmeli.

### F. Web sayfası (otomatik, kontrol 1 dk)

Merge'den 1–2 dk sonra https://yasincirali.github.io/sandikapp/ — iPhone
Safari'de üstte "sandık — App Store'da aç" şeridi, sayfada App Store düğmesi;
https://yasincirali.github.io/sandikapp/indir/?kod=TEST kod kutusunu göstermeli.

---

## 📣 YENİ: "Yenilikler" (What's New) — her sürümde yapman gereken TEK iş

**Kullanıcı isteği.** Güncelleme sonrası neyin değiştiği uygulama içinde
görünüyor; ana özellikler tanıtım turuna da giriyor.

### Her yeni sürümde: `lib/config/surum_notlari.dart`

Listenin **başına** yeni bir `SurumNotu` ekle. Tek kaynak orası; başka
hiçbir yere dokunmana gerek yok.

```dart
SurumNotu(
  surum: '1.1.6',          // YAYINLANACAK sürüm (pubspec'i ELLE bump etme)
  tarih: 'Ekim 2026',
  onemli: true,            // true → güncelleme sonrası KENDİLİĞİNDEN açılır
  baslik: 'Tek cümlelik özet',
  yenilikler: [
    Yenilik(
      ikon: YenilikIkonu.bildirim,
      baslik: 'Kısa başlık',
      aciklama: 'Kullanıcının fark edeceği şey, somut ve kısa.',
    ),
  ],
),
```

⚠️ **`surum` pubspec ile eşleşmezse not HİÇ gösterilmez** (sessiz). Ama
pubspec'i elle bump etme — fastlane CI'da yapıyor. Buraya **yayınlanacak**
sürümü yaz; pubspec o değere CI'da ulaşır. Bugün `1.1.5` yazılı (pubspec
`1.1.4+7`), yani not bir sonraki yayınla görünür hale gelecek.

⚠️ **`onemli: false` kullan** yama sürümlerinde — iki satırlık düzeltme için
kullanıcının önüne modal koymak, üçüncü seferde kapatılan bir şeye dönerdi.
Notu yine yazılır, yalnızca otomatik açılmaz (Ayarlar'dan görünür).

### Gösterim kuralları (hepsi test edilmiş)

| Durum | Davranış |
|---|---|
| İlk kurulum | Gösterilmez — yeni kullanıcı tanıtım turunu görüyor |
| Aynı sürüm 2. açılış | Gösterilmez |
| 1.0 → 1.3 atlandı | 1.1, 1.2, 1.3 **birikir**, hepsi gösterilir |
| Çalışan sürümün notu yazılmamış | Hiçbir şey gösterilmez (yanlış bilgi vermek yerine sus) |
| Hiçbiri `onemli` değil | Otomatik açılmaz |

### Ana özellikler tanıtım turuna

`onemli` bir özellik uygulamanın ana yüzeylerinden birini değiştiriyorsa
tura adım ekle (`onboarding_screen.dart` → `_adimlariKur`). Bu turda
**bildirim merkezi** adımı eklendi (`rozet: 'YENİ'`) — yeni kullanıcı
yalnızca eski sürümde var olanları öğrenip en yenisini kaçırmamalı.

⚠️ Yeni `TourTarget` eklersen onu bir ekranda `TourAnchor` ile
**işaretlemelisin** — `onboarding_tour_test` işaretlenmemiş hedefi yakalar.

### Yan düzeltme: Ayarlar'daki sürüm bayattı

"sandık — sürüm 1.0.0" yazıyordu (gerçek 1.1.4). Elle yazılan sabit
fastlane bump'ıyla ayrışmıştı; artık `package_info_plus` ile kurulu sürüm
okunuyor.

**Yeni bağımlılık:** `package_info_plus: ^8.0.0`.

---

## 🔴 DÜZELTME: altın ayarı yanlış eşlendi — alarm ERKEN tetiklendi (2026-09-15, 2. tur)

**Kullanıcı bildirdi:** "eşik 6270 idi ama gram altın 6700 oldu diye bildirim
geldi; varlık ekranında o değere gelmediğini gördüm."

**Haklıydı — hata bendeydi.** İlk truncgil düzeltmesinde `ALTIN_GRAM` → `GRA`
eşlemesi yapılmıştı. `GRA`'nın adı `GRAMALTIN` ama içeriği **24 ayar has**
altındır (`HAS`/`GRAMHASALTIN` ile arasında yalnızca %0,5 fark var).
Uygulamanın `ALTIN_GRAM`'ı ise **22 ayar**: `asset_categories.dart` onu
'22 Ayar Gram Altın' diye adlandırıyor, `_goldLabel` 'Gram Altın (22K)'
yazıyor ve `_goldWeights` ağırlıkları 22 ayar cinsinden.

Sonuç: sunucu %8 yüksek fiyat (6.710) okudu, kullanıcı ekranda 6.277 gördü,
6.270 hedefli alarm erken tetiklendi.

**Doğru anahtar `YIA`** (`22AYARBILEZIK`). Ada değil ÖLÇÜYE bakılarak
bulundu — çapraz doğrulama (canlı veri 2026-09-15 17:42):

| Sembol | truncgil | ÷ ağırlık = gram eşdeğeri | `YIA` farkı |
|---|---|---|---|
| Çeyrek | 10.723,78 | 6.127,87 | %+0,25 |
| Yarım | 21.380,54 | 6.108,73 | %−0,06 |
| Cumhuriyet | 44.436 | 6.157,98 | %+0,74 |
| Ata / Reşat | 44.235,61 | 6.130,21 | %+0,29 |
| **`YIA`** | **6.112,56** | — | — |
| `GRA` | 6.687,88 | — | **%+8,4** ✗ |

Ailenin tamamı 22 ayar kote edildiği için tek tutarlı seçim `YIA`.

**Regresyon testi eklendi** (`price_alert_test.ts`): çeyrek ve yarım altının
gram eşdeğeri, `ALTIN_GRAM` fiyatıyla %2 içinde uyuşmalı. `GRA`'ya geri
çevrilerek testin gerçekten kırıldığı doğrulandı. Artık bu hata sessizce
geçemez.

> **Ders:** truncgil anahtarının ADI ayarı söylemiyor ('GRAMALTIN' 22 ayar
> sanmaya davet ediyor). Doğru yöntem, aynı ailedeki başka bir üründen GRAM
> EŞDEĞERİ hesaplayıp karşılaştırmak.

**Senin yapacağın:**
1. Actions → Supabase deploy → `functions=check-price-alerts`, `migrations=false`
2. Uygulamayı yeniden derle (istemci tarafı da aynı hatayı taşıyordu)
3. ⚠️ **Mevcut alarmlarını gözden geçir** — 6.270 gibi hedefler 22 ayar
   ölçeğinde doğru; sunucu artık aynı ölçekte okuyacak, yeniden kurman
   gerekmiyor. Ama önceki turda ERKEN tetiklenip sönen alarm varsa
   (`triggered_at` dolu) onu yeniden kurman gerekir.

---

## 🔔 YENİ: Fiyat alarmları bildirim listesinde + tıklayınca varlığa gider (2026-09-15)

**Kullanıcı isteği.** İki parça vardı, ikisi de yapıldı.

### 1. Bildirime tıklanınca varlık ekranı, GÜNLÜK sekmesinde açılıyor

Önceki davranış bilinçliydi (kod yorumunda gerekçesiyle duruyordu): alarm
bildirimi ana ekranda bırakılıyordu çünkü "kullanıcı fiyatı öğrenmek için
geliyor, alarm listesini yönetmek için değil". Gerekçenin ilk yarısı doğru,
çıkarımı yanlıştı — doğru varış yeri alarm listesi değil ama ana ekran da
değil, alarmın konusu olan **varlık**. Karar değiştirildi, eski gerekçe
kod yorumunda korunuyor.

⚠️ **Sembol → varlık eşlemesi:** alarm payload'ı `asset_id` TAŞIMAZ
(`price_alerts` sembol üstünden kurulur, sunucu hangi lot'tan geldiğini
bilmez). Eşleme istemcide `alarmSembolu()` ile yapılır — alarm kurarken
hangi kural uygulandıysa aynısı tersine çevrilir. İki yönün AYNI fonksiyonu
kullanması şart; ayrışırsa alarm kurulabilen ama bildirimi açılamayan bir
varlık ortaya çıkar.

### 2. Alarmlar artık çan sayfasında görünüyor (0065)

`signal_notifications`'a **sadece** `analyze-signals` yazıyordu; fiyat
alarmı tetiklendiğinde push gidiyor ama uygulama içinde iz kalmıyordu.
Push'u kaçıran kullanıcı için "alarm kurmuştum, çalıştı mı?" sorusunun
cevabı yoktu.

**Ayrı tablo** (`price_alert_notifications`), çünkü `SignalAlert` teknik
sinyale özgü (`buy_count`, `sell_count`, `confidence`) ve alarmda hiçbirinin
karşılığı yok. Birleştirme istemcide, zaman sırasına göre (`bildirimAkisi`).

Kayıt push'un sonucundan **bağımsız** yazılır: bildirim izni kapalı ya da
token bayat olsa bile alarmın çalıştığı uygulamada görünmeli.

**Senin yapacağın — İKİ adım:**

1. Actions → Supabase deploy → `migrations=true`, `functions=check-price-alerts`
2. Uygulamayı yeniden derle (istemci tarafı)

Doğrulama: bir alarmı tetikle → çan rozetinde sayı artmalı, sayfada "ALARM"
rozetli satır çıkmalı, satıra dokununca varlık GÜNLÜK sekmesinde açılmalı.

> `price_alert_notifications` tablosunda istemcinin **INSERT yetkisi yok**
> (bilinçli): satırı yalnızca edge function yazar. Kullanıcının kendi adına
> sahte "alarm tetiklendi" kaydı yazabilmesi için sebep yok.

Testler: `bildirim_akisi_test.dart` (7 test — sıralama, tür ayrımı, kararlı
sıra), tam paket 2165 test yeşil.

---

## ✅ KAPANDI: truncgil v4 API'si değişti — fiyat alarmları ölüydü (2026-09-15)

**Teşhis tamamlandı.** `net._http_response` okundu: **401/503/500 YOK,
hepsi 200.** Yani yetki zinciri (gateway JWT + cron secret + FCM secret)
baştan sona SAĞLAM — aranan arıza orada değildi.

> **✅ CANLIDA DOĞRULANDI (2026-09-15 14:00):**
> ```json
> {"ok":true,"checked":1,"priced":1,"triggered":1,"sent":2,
>  "skipped_quiet_hours":0,"dry_run":false}
> ```
> `priced:1` fiyatın çekildiğini, `sent:2` bildirimin GİTTİĞİNİ söyler.
> Düzeltme `c0e4cbb` ile main'e girdi ve deploy edildi.
>
> ⚠️ **Deploy tuzağı (bu turda yaşandı):** ilk deploy denemesi eski kodu
> dağıttı — düzeltme henüz commit EDİLMEMİŞTİ. Actions repodan checkout
> yapar; `main`'de olmayan kod deploy edilemez. Edge function düzeltmesi
> yaptıysan **önce commit + push, sonra Actions.**

### Arıza 1 — `check-price-alerts` her turda "Fiyat alinamadi." (GERÇEK ARIZA, düzeltildi)

30 dakikada bir, istisnasız: `{"ok":true,"reason":"Fiyat alinamadi.","sent":0}`.
Aktif alarm VAR (o dal geçilmiş), ama tek bir fiyat bile çekilemiyordu →
**fiyat alarmı özelliği tümüyle ölüydü.**

**Sebep:** `finans.truncgil.com/v4/today.json` yanıt biçimini değiştirmiş.
Canlı yanıtla doğrulandı (2026-09-15 16:37):

| | Kodun beklediği | API'nin döndürdüğü |
|---|---|---|
| Altın anahtarı | `'Gram Altın'`, `'Ata Altını'` | `'GRA'`, `'ATAALTIN'` |
| Alan adı | `'Alış'` / `'Satış'` | `'Buying'` / `'Selling'` |
| Sayı tipi | String `"5.412,37"` | Gerçek number `6710.67` |

Üçü birden değişince `data[key]` her sembolde `undefined` döndü, map boş
kaldı. **HTTP 200 olduğu için hiçbir yerde hata görünmedi** — 0054'ün
sessiz arıza deseninin aynısı, bu sefer veri katmanında.

**Düzeltildi:**
- `supabase/functions/_shared/live_prices.ts` — anahtarlar + `Buying`/`Selling` + number tipi
- `lib/services/price_service.dart` — **aynı hata istemcide de vardı**

> ⚠️ **İstemci tarafı ayrıca önemli:** uygulama altın fiyatlarını sessizce
> Yahoo `GC=F` + ons/gram çevrimi olan YEDEĞE düşürüyordu (`_goldWeights`).
> Yedek çalıştığı için belirti yoktu ama gösterilen sayı truncgil'inkiyle
> tutmuyordu. Alarm, uygulamada GÖRÜNEN sayı üzerinden tetiklenmeli —
> bu yüzden iki taraf birlikte düzeltildi ve `GOLD_KEYS` ↔
> `_truncgilGoldKeys` birebir aynı kalmalı.

Regresyon testi: `supabase/tests/price_alert_test.ts` — v4 biçimi için üç
yeni test, eski biçim uyumu korunuyor (17/17 geçiyor).

**Senin yapacağın:** Actions → Supabase deploy → `functions=check-price-alerts`.
İstemci tarafı bir sonraki uygulama derlemesiyle gider.

Doğrulama: deploy sonrası `select public.trigger_check_price_alerts();` →
birkaç saniye sonra `net._http_response`'ta artık `"Fiyat alinamadi."`
GÖRMEMELİSİN.

### Arıza 2 — `analyze-signals` `passed_threshold: 0` (muhtemelen NORMAL)

```json
{"slot":"hourly","users":1,"assets":12,"positions":5,"evaluated":5,
 "passed_threshold":0,"sent":0,"failed":0,
 "skipped_by_dedup":0,"skipped_by_frequency":0}
```

Zincir **kusursuz çalışıyor**: 5 pozisyon değerlendirildi, de-dup engeli
yok, sıklık engeli yok, hata yok. Hiçbir hisse eşiği geçmedi — yani
teknik analiz "bugün söyleyecek bir şey yok" dedi.

**Bu büyük olasılıkla arıza DEĞİL.** Ama "hiç sinyal gelmiyor" şikayeti
sürüyorsa eşik fazla yüksek olabilir; karar senin:

```sql
select asset_type, threshold, indicators, signals_enabled, frequency,
       window_start, window_end, notify_hours, last_notified_at
  from signal_preferences where user_id = auth.uid();
```

`threshold` değerini düşürüp bir tur bekleyerek sınayabilirsin.

### Bu turda ayrıca: canlı etkinlik push'u ÇALIŞIYOR

`{"sent":9,"removed":0,"total":9}` — 5 dakikada bir, düzenli. Yani
FCM/APNs boru hattı ayakta. "Hiçbiri çalışmıyor" hissinin kaynağı
büyük ihtimalle Arıza 1 (alarmlar) + Arıza 2 (sinyal eşiği) birleşimi.

---

## 🔔 AÇIK: "Push'ların hiçbiri çalışmıyor" teşhisi (2026-09-15)

**Durum:** Kod zincirinin tamamı okundu; **yapısal bir arıza bulunamadı.**
İstemci kaydı, FCM gönderimi, cron header deseni, alıcı filtreleri ve
zamanlamalar tutarlı. Yani arıza koddaysa bile bu turda görünmüyor —
**canlı veriden okunması gerekiyor.** Aşağıdaki sıra onu söyler.

Bu turda kapatılan şey **teşhis körlüğüydü** (aşağıda §B).

### A. Önce şunu koş — hangi halkanın koptuğunu SÖYLER

SQL Editor'da, sırayla:

```sql
-- 1) Cron'lar kurulu ve koşuyor mu? (0064 sonrası hepsi görünür)
select jobname, schedule, active from cron.job order by jobname;

-- 2) Her job en son ne zaman ve nasıl bitti?
select coalesce(j.jobname,'(silinmiş #'||d.jobid||')') as job,
       d.status, d.start_time, left(d.return_message,200) as mesaj
  from cron.job_run_details d
  left join cron.job j on j.jobid = d.jobid
 order by d.start_time desc limit 40;

-- 3) Edge function GERÇEKTE ne döndü? (401=yetki, 503=secret yok, 5xx=içeride hata)
select id, status_code, left(content,300) as govde, created
  from net._http_response order by created desc limit 40;

-- 4) Alıcı var mı? Bu sorgu 0 dönerse HİÇBİR push gidemez.
select platform, count(*) from user_push_tokens group by platform;
```

**Okuma kılavuzu — kod bu üç durumu farklı döndürür, karıştırma:**

| Gördüğün | Anlamı | Yapılacak |
|---|---|---|
| `user_push_tokens` **boş** | Zincirin sunucu tarafı sağlam olsa bile gidecek cihaz yok. En olası sebep bu. | Uygulamada Ayarlar → **Push Teşhisi** → "4. CİHAZ TOKEN'I" bölümü; izin/APNs/FCM ayrımını orada oku. |
| HTTP **401** | Gateway JWT'si ya da `x-cron-secret` uyuşmuyor | `cron_gateway_jwt` + ilgili `*_cron_secret` Vault ↔ function secret eşitliği |
| HTTP **503** `cron_secret_missing` | Function secret'ı hiç tanımlı değil | `supabase secrets set <AD>` |
| HTTP **500** `FCM secret'ları eksik` | `FCM_PROJECT_ID` / `FCM_SERVICE_ACCOUNT_JSON` yok | Secret'ları gir (README: analyze-signals) |
| HTTP **200** ama `"sent":0` | Yetki TAMAM; gönderimi bir **iş kuralı** durdurdu | Aşağıdaki §C — gövdedeki sayaçlar sebebi söyler |

⚠️ **`200 {"sent":0}` bir arıza DEĞİLDİR** — çoğu zaman doğru davranıştır
(piyasa kapalı, eşiği geçen hareket yok, de-dup). "Push gelmiyor"u buna
bakarak teşhis etmek, olmayan bir hatayı kovalamak olur.

### B. Bu turda düzeltilen: teşhis ekranı beş cron'u HİÇ göstermiyordu

`push_cron_jobs()` `0021`'den beri `where jobname like 'analyze-signals%'`
filtresi taşıyordu. Sonradan eklenen yedi cron (brifing, haftalık özet,
fiyat alarmı, takvim, enflasyon, canlı etkinlik, TEFAS) ekranda **hiç
görünmüyordu** — "hangi iş çalışmıyor?" sorusu tam da o ekrandan
okunamıyordu. `push_cron_runs` `0022`'de açılmıştı, `push_cron_jobs` geride
kalmıştı.

`0064_push_diagnostics_all_jobs.sql`: filtre kaldırıldı, her job'a
`son_calisma` + `son_durum` eklendi. Ekran artık **kurulu ama hiç koşmamış**
job'u kırmızıyla ayrı bir teşhis olarak söylüyor — `0054`'ün sessiz
arızasının (job aktif görünüyor, gövdesi hiç koşmamış) belirtisi tam buydu
ve `_runs.isEmpty` onu yakalayamıyordu (liste `live-activity` koşularıyla
dolu).

**Deploy:** Actions → Supabase deploy → `migrations=true`, `functions=none`.

> ⚠️ **`0064`'ü SQL Editor'dan elle koştuysan ve şu hatayı aldıysan:**
>
> ```
> ERROR: 42P13: cannot change return type of existing function
> DETAIL: Row type defined by OUT parameters is different.
> HINT: Use DROP FUNCTION push_cron_jobs() first.
> ```
>
> **Bu beklenen bir hataydı ve dosya düzeltildi** (2026-09-15). Sebebi:
> Postgres `create or replace` ile bir fonksiyonun **dönüş tipini**
> değiştirmeye izin vermez. `returns table (...)` sütunları OUT parametresi
> sayılır — `son_calisma` + `son_durum` eklemek dönüş tipini değiştirmektir.
> `0021`/`0022`'de yalnızca gövde değiştiği için bu tuzak o turlarda çıkmamıştı.
>
> Migration'a `drop function if exists public.push_cron_jobs();` eklendi.
> **Repodaki güncel `0064`'ü yeniden çek ve tekrar koş** — başka bir şey
> yapman gerekmiyor.
>
> İki nokta, ileride aynı deseni yazarsan:
> - `if exists` şart — taze yığında (CI, `supabase start`) fonksiyon henüz
>   yoktur, çıplak `drop` orada migration'ı kırar.
> - **`drop` GRANT'ları da götürür.** `0064` içindeki `grant execute ... to
>   authenticated` satırı bu yüzden var; silinirse teşhis ekranı
>   "Yetkisiz" der ve bu sefer aracın kendisi kırılır.

### C. `200` ama `sent:0` ise — sebebi sayaçlar söyler

`analyze-signals` kuru koşusu gönderim yapmadan hangi kapının kapattığını
döndürür:

```sql
select public.trigger_analyze_signals('hourly');
-- birkaç saniye sonra:
select left(content,600) from net._http_response order by created desc limit 1;
```

| Sayaç >0 ise | Gönderim neden durdu |
|---|---|
| `skipped_by_dedup` | Aynı sinyal zaten gönderilmiş. Sıfırlamak için: Push Teşhisi → "De-dup sıfırla" |
| `skipped_by_frequency` | Kullanıcının seçtiği sıklık/pencere henüz izin vermiyor |
| `closed_or_deleted_lots` | Pozisyon satılmış/silinmiş — **doğru** davranış |
| `passed_threshold: 0` | Hiçbir hareket eşiği geçmedi — piyasa sakin, arıza değil |
| `passed_threshold > 0` ama `sent: 0` | **Gerçek arıza** — `failed` ve `errors` alanlarına bak |

---

## 🚨 ÖNCE BU: 2026-09-13 güvenlik denetimi sonrası (kod tarafı yapıldı, deploy sende)

Kod değişiklikleri `main`'e merge edildi (2026-09-14, `95b49d9`). Aşağıdakiler
senin elinden geçmeden **canlıda etkili olmaz** ve bazıları için kod tarafı
artık eski davranışa dönmez (fail-closed).

> **✅ 2026-09-14 11:14 — migration ve fonksiyon dağıtımı YAPILDI.**
> Aşağıdaki tablodaki #6, #7, #11, #13, #14, #17 satırlarının deploy ayağı
> kapandı; #19 (GitHub secret'ları) tamamlandı.
>
> - 3 secret girildi: `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`
>   (`ybdbzouzhzwthjgwlbmk` — gizli değil, proje URL'sinin parçası),
>   `SUPABASE_DB_PASSWORD` (sıfırlandı).
> - **Migration defteri onarıldı:** 0050–0060 SQL Editor'dan elle koşulduğu
>   için `supabase_migrations` deftere yazılmamıştı; CLI hepsini
>   "uygulanmamış" görüyordu. `migration repair` ile işaretlendi →
>   `db push --dry-run` artık "Remote database is up to date" diyor.
>   Workflow'a bunun için `repair` input'u eklendi (`a89e6be`).
> - **11 edge function'ın hepsi yeniden dağıtıldı** — `push-live-activity`
>   dahil (hiç dağıtılmamış olduğundan şüphelenilen oydu).
>
> **✅ 2026-09-14 (akşam) — `0061` ve `0062` koşuldu, `analyze-signals`
> yeniden dağıtıldı.** Satır 22 ve 23 TAMAMEN kapandı; sunucu tarafında
> bekleyen migration ya da fonksiyon dağıtımı kalmadı.
>
> Kalan işler secret rotasyonları (#1, #3; #5 tuz 2026-09-14 set edildi), sosyal giriş sağlayıcı
> ayarları (#15, #16) ve cihaz testleri (#12, #18).

| # | İş | Neden | Nasıl |
|---|---|---|---|
| 24 | ✅ **KAPANDI (2026-09-19 23:34 TR)** — function secret'ı sen CLI ile, Vault kaydını SQL Editor'da yazdın; `trigger_observe_tefas_nav()` → `200 {"checked":13,"sightings":13}`, `tefas_nav_gozlem` 13 satır. Cron iş günü 06:00–21:30 TR yarım saatte bir. Uygulamada GÜNLÜK sekmesinde fon basamağı Pazartesi'den itibaren gerçek görülme saatine düşer. — *Aynı gün sabahki durum:* `TEFAS_NAV_CRON_SECRET` function secret'ı YOK, Vault'ta `tefas_nav_cron_secret` YOK, `tefas_nav_gozlem` 0 satır. 0063 ve fonksiyon dağıtıldı, cron `observe-tefas-nav` aktif ama her tur boşa dönüyor (503/Vault hatası). Kalan yalnızca aşağıdaki (2) adımı: `openssl rand -hex 32` → `supabase secrets set TEFAS_NAV_CRON_SECRET=<değer>` + SQL Editor `select vault.create_secret('<aynı değer>', 'tefas_nav_cron_secret');` → doğrulama (4). Claude bunu yapamıyor: otomatik mod secret yazımını reddediyor (2026-09-19). Rapor için Actions → Supabase deploy → `secrets_list=true` ve `sql` girdisi artık var. — Eski başlık: `0000_base_schema.sql`'i deftere İŞARETLE (koşturma), sonra `0063` + `observe-tefas-nav` (2026-09-14) | (a) `0000` taban tabloların (profiles, assets, snapshots, davet, push token, disclaimer, db_logs) migration'ı — 3.16 duman testi ve CI'daki yerel Supabase yığını için. Canlıda bu tablolar zaten var; dosya idempotent (koşsa da hiçbir şeyi değiştirmez) ama CLI onu "0007'den önce eklenmiş" görür ve `db push` `--include-all` ister. **Doğru yol deftere işaretlemek.** (b) `0063_tefas_nav_gozlem.sql`: `tefas_nav_gozlem` + `tefas_nav_tur` tabloları, `observe-tefas-nav` cron'u (iş günü */30 03-18 UTC), temizlik cron'u. (c) `observe-tefas-nav` edge function'ı + secret'ı; secret yoksa fonksiyon 503 (fail-closed), migration'ın tetikleyicisi Vault'ta `tefas_nav_cron_secret` bulamazsa hata basar. Gözlem gelmeden uygulama eskisi gibi 10:00 çapasını kullanır — kırılma yok, yalnızca iyileşme bekler. | **Sıra:** (1) Actions → Supabase deploy → `repair = 0000` (`migration repair --status applied 0000`), `dry_run=true` ile "up to date + 0063 pending" gör. (2) `openssl rand -hex 32` → `supabase secrets set TEFAS_NAV_CRON_SECRET=<değer>` ve SQL Editor'da `select vault.create_secret('<aynı değer>', 'tefas_nav_cron_secret');` (Vault ÖNCE: 0063'ün tetikleyicisi ilk koşuda arayacak). (3) `db push` (0063) + `functions deploy observe-tefas-nav`. (4) Doğrula: `select public.trigger_observe_tefas_nav();` → `net._http_response`'ta `200 {"ok":true,"checked":N,...}`; ertesi iş günü `select * from tefas_nav_gozlem order by ilk_gorulme desc limit 5;` dolu olmalı. Uygulamada GÜNLÜK sekmesinde fon basamağı artık sabah görülen saate düşer. |
| 20 | ✅ **YAPILDI (2026-09-14 16:11)** — `0054` gerçekten uygulandı; 7 cron tetikleyicisi yeni desende | **Canlıda ölçüldü (2026-09-14).** `supabase migration list` `0054`'ü "uygulanmış" gösteriyor **ama gövdesi hiç çalışmamış**: `cron_headers` / `cron_gateway_jwt` / `cron_secret_of` fonksiyonları veritabanında YOK ve yedi tetikleyicinin yedisi de hâlâ eski deseni taşıyor (`Authorization: Bearer <cron_secret>`). Defter `migration repair` ile elle işaretlenmiş olmalı. Sonuç: her cron çağrısı gateway'de **401 UNAUTHORIZED_INVALID_JWT_FORMAT** alıyor — yani `0054`'ün önlemek için yazıldığı sessiz arıza **hâlâ sürüyor**. `net._http_response` kanıtı: id 5023 → 401, id 5021/5022 → 503 `cron_secret_missing`. Vault tarafı SAĞLAM (`cron_gateway_jwt` var, 219 karakter, JWT formatında ✓) ve `EVDS_API_KEY` de girilmiş ✓ — eksik olan yalnızca migration gövdesi. | **Nasıl düzeltildi:** `migration repair --status reverted 0054` ile defter kaydı geri alındı, sonra `db push --include-all`. ⚠️ `--include-all` TEK BAŞINA yetmez — o yalnızca defterde HİÇ bulunmayan sürümleri kapsar, `applied` işaretli olanı atlar (denendi: "up to date" dedi). Sıra: önce `unrepair`, sonra `include_all`. İkisi de Actions → Supabase deploy input'u olarak var. Kalan doğrulama: SQL Editor'da yedi tetikleyicinin `cron_headers` kullandığını gör ve `select public.trigger_fetch_inflation();` ile TÜFE'yi doldur (`select count(*) from inflation_index;` → 24 satır). |
| 21 | ✅ **YAPILDI (2026-09-14)** — TÜFE canlıda çalışıyor; yeni baz yılına geçildi | TÜİK Ocak 2026'da baz yılını `2003=100` → `2025=100` çevirmiş ve eski `TP.FG.J0` serisi orada sona ermişti. Yeni kod EVDS3 kataloğundan **okundu** (tahmin edilmedi): kategori 2005 → grup `bie_tukfiy2025` → **`TP.TUKFIY2025.GENEL`** (01-2005 … 08-2026). Tablo temizlenip yeni bazla dolduruldu: **24 satır, Eylül 2024 – Ağustos 2026**. Aynı turda EVDS adres değişimi (`evds2`→`evds3`, HTML dönüyordu) ve path-style parametre biçimi de düzeltildi. | **Doğrulandı:** yıllık %31,51 ve aylık %1,84 — ikisi de TÜİK'in açıkladığı rakamla birebir. 6 aylık %13,08. Uygulamada Özet → **1A / 6A / 1Y**'de "Reel getiri" kartı görünür (istemci önbelleği 12 saat; uygulamayı yeniden başlat). Bundan sonrası otomatik: cron her ayın 3'ü TR 10:05'te çeker. |
| 22 | ✅ **YAPILDI (2026-09-14)** — `0061_percentile_median.sql` koşuldu | Ana ekrandaki yüzdelik şeridi artık "Getiri sıralaması · medyandan X puan önde/geride" satırını taşıyabilir; `get_percentile_bucket` iki sütun daha dönüyor (`median_roi_pct`, `my_roi_pct`). Havuz, k_min=8 ve Sybil kapısı (0059) aynen. | **Kalan doğrulama (isteğe bağlı):** SQL Editor'da `select * from get_percentile_bucket(30);` → dört sütun. ⚠️ Satırın EKRANDA görünmesi ayrı bir şeye bağlı: havuzda son 24 saatte ≥8 kişi olmalı (k-anonimlik). Tek kullanıcıyla test ederken şerit "Yakında" der — bu doğru davranıştır, migration eksikliği değil. |
| 23 | ✅ **KAPANDI (2026-09-14)** — `0062` koşuldu + `analyze-signals` yeniden dağıtıldı | Sinyal de-dup hafızası lot id'sinden pozisyon anahtarına (`pos:<tür>|<TICKER>`) taşındı; temsilci lot yumuşak silinince gelen fazladan bildirim bitti. Migration kendi sonucunu doğruladı (`raise exception` — hatasız geçtiyse lot anahtarlı satır kalmamıştır). Fonksiyon ayağı Actions → Supabase deploy (`functions deploy analyze-signals`) ile kapandı. | Bekleyen iş YOK. İstersen davranışı görmek için kuru koşu: `analyze-signals` `{"dry_run":true}` → yanıttaki `closed_or_deleted_lots` satılan/silinen yüzünden elenen alım lot'u sayısıdır. |
| 1 | ✅ **YAPILDI (2026-09-14 20:19)** — `daily_brief_cron_secret` döndürüldü | Eski değer `tmp/update_daily_brief_vault.sql` içinde git'e commit'lenmişti (`61a74dc`) ve repo **PUBLIC**; dosya `b140bf3`'te silindi ama geçmişte ve altı uzak dalda (origin/main + 5 `claude/*`) duruyor. Rotasyon yapıldığı için sızan string artık ÖLÜ. | Yeni değer `openssl rand -hex 32` ile üretildi, `supabase secrets set DAILY_BRIEF_CRON_SECRET` + Vault `update_secret` ile İKİ yere yazıldı. **Doğrulandı:** `trigger_daily_brief()` → `200 {"ok":true,"reason":"Brifing icin hisse yok.","sent":0}` — `sent:0` gece yarısı BIST kapalıyken beklenen; yetki kapısının geçildiği `200`'den okunur. ⚠️ Geçmiş temizliği (#2) hâlâ AÇIK ama artık hijyen, acil değil. |
| 2 | **Git geçmişini temizle** (isteğe bağlı ama önerilir) | Repo klonlanmış/fork'lanmışsa eski secret oradan okunabilir; rotasyon yapıldıysa zararsız ama temiz olsun. | `git filter-repo --path tmp/update_daily_brief_vault.sql --invert-paths` + force push; tüm klonlar yeniden çekmeli. |
| 3 | ✅ **YAPILDI (2026-09-14 20:14)** — `LIVE_ACTIVITY_CRON_SECRET` rastgele değerle set edildi, Vault eşitlendi | `push-live-activity` artık `x-cron-secret` doğruluyor. Vault'taki eski 219 karakterlik service_role JWT'si rastgele bir secret'la DEĞİŞTİRİLDİ (JWT'yi function secret'ı olarak kopyalamak tek sızıntıda tüm DB'yi açardı). | **Canlıda doğrulandı:** `trigger_live_activity_push()` → `200 {"sent":5,"removed":1,"total":6}`. Teşhis sırası kayda değer: önce `503 cron_secret_missing` (function secret yok) → `401 Yetkisiz cron cagrisi` (secret var, Vault eşleşmiyor) → `200`. Üç kod üç ayrı eksiği gösterir, karıştırma. |
| 4 | ✅ **YAPILDI (2026-09-14 20:26)** — YEDİ cron secret'ının hepsi canlıda doğrulandı | Fonksiyonlar fail-closed (`cronSecretZorunlu`): secret yoksa 503, Vault ile eşleşmiyorsa 401. Yedi tetikleyicinin yedisi de `200` döndü. `daily_brief` ve `live_activity` bu turda ROTASYONLA, `weekly_summary`+`inflation_fetch` AYRIŞTIRILARAK, `analyze_signals`+`calendar_nudge`+`price_alerts` olduğu gibi doğrulandı. | ⚠️ **Çağrı tuzağı:** `trigger_analyze_signals` parametre alır — `select public.trigger_analyze_signals('hourly');` (geçerli slot'lar: `morning`, `afternoon`, `hourly`). Argümansız çağrı `42883 function does not exist` der; bu YETKİ ya da EKSİKLİK değil, imza uyuşmazlığıdır. Diğer altısı parametresizdir. |
| 5 | ✅ **YAPILDI (2026-09-14)** — `DELETION_HASH_SALT` set edildi; hesap silme akışı canlıda açık | Varsayılan tuz kaldırıldı; set değilse hesap silme 503 dönüyordu. Bir daha DEĞİŞTİRME (eski log kayıtlarıyla eşleşme bozulur). | `supabase secrets set DELETION_HASH_SALT=$(openssl rand -hex 32)` — bir kez set et, bir daha DEĞİŞTİRME (eski log kayıtlarıyla eşleşme bozulur). |
| 6 | **8 edge function'ı yeniden deploy et** | analyze-signals, calendar-nudge, check-price-alerts, daily-brief, fetch-inflation, weekly-summary, push-live-activity, send-partner-invite-push, delete-account (`_shared/cron_auth.ts` yeni). | `supabase functions deploy <ad>` — cron olanlarda da gateway JWT doğrulaması AÇIK kalır (0054 deseni: Authorization'da service_role JWT, `x-cron-secret`'ta secret). |
| 7 | **`0055_is_push_admin_grant.sql`'i koş** | Ayarlar'daki "Push Teşhisi" tile'ı artık `is_push_admin()` RPC'sine bakıyor; GRANT yoksa tile admin'e de görünmez (fonksiyon hata → false). | `supabase db push` ya da SQL Editor. |
| 11 | **`0056_force_rls_and_db_logs_retention.sql`'i koş** | Tüm kullanıcı tablolarında FORCE RLS + db_logs 30 gün saklama cron'u. | `supabase db push` ya da SQL Editor. |
| 13 | **`0057_quiet_hours.sql`'i koş + 4 fonksiyonu yeniden deploy et** | Sessiz saatler: `profiles.quiet_start/quiet_end`; daily-brief, weekly-summary, calendar-nudge, check-price-alerts bunu okuyor. Migration koşulmadan ayar sunucuda 'kolon yok' hatası verir (istemci kapalı gösterir, kırılmaz). | `supabase db push`; `supabase functions deploy daily-brief weekly-summary calendar-nudge check-price-alerts`. |
| 12 | **Biyometrik kilidi cihazda dene** | `local_auth` platform tarafı (FragmentActivity, USE_BIOMETRIC, NSFaceIDUsageDescription) kodda ama gerçek cihazda hiç koşmadı. | Ayarlar → Hesap → Biyometrik kilit'i aç, uygulamayı 30 sn arkaya al, geri dön: kilit ekranı gelmeli. |
| 8 | **Yerel release build için `android/key.properties`** | `key.properties` yoksa release build artık KIRILIR (eskiden debug anahtarıyla sessizce imzalıyordu). | §4 keystore adımları. CI (`android-release.yml`) zaten secret'tan yazıyor, etkilenmez. |
| 10 | **GoTrue rate limit'lerini sabitle** (M12) | Login ve OTP doğrulamada uygulama düzeyi throttle yok; istemci sayacı güvenlik sınırı sayılmaz (S1 dersi). Koruma Supabase Auth'un kendi limitleri. | Dashboard → Authentication → Rate Limits: "Token verifications" ve "Sign-ins/sign-ups" değerlerini gözden geçir, bilinçli bir değere çek ve buraya not düş. |
| 9 | ~~Sybil / k=8 kararı~~ → **`0059_leaderboard_sybil_eligibility.sql`'i koş** (M1) | Yarış ve Paywall kalıyor (karar 2026-09-14). Havuza girmek artık zaman ister: hesap ≥7 gün, son 30 günde ≥5 farklı gün snapshot, ≥2 varlık türü. 7 sahte hesap dakikada değil, bir haftalık düzenli kullanımla kurulabilir. k_min=8 aynen. | `supabase db push`. Yan etki: yeni kullanıcı ilk 7 gün yüzdelik şeridinde "Yakında" görür — beklenen. |
| 14 | **`0058_drop_mevduat_type.sql`'i koş + `delete-account`'u yeniden deploy et** | Vadeli mevduat kaldırıldı; eski `type='mevduat'` satırları 'diger'e döner (silinmez). `delete-account` artık sosyal hesap için `{provider,id_token,nonce}` ile taze kimlik doğruluyor. | `supabase db push`; `supabase functions deploy delete-account`. |
| 15 | ✅ **YAPILDI (2026-09-14)** — Apple ile giriş: App ID yeteneği + Supabase provider açıldı | Kod hazır (`SocialAuthService`, entitlement eklendi). Kalan tek şey TestFlight'ta bir kez denemek (ilk girişte ad gelir, sonrakilerde gelmez — Apple davranışı). | (a) developer.apple.com → Identifiers → App ID `com.sandik.app` → **Sign In with Apple** yeteneğini aç, provisioning profile'ı yenile. (b) Supabase Dashboard → Authentication → Providers → **Apple**: Enable; "Client IDs" alanına `com.sandik.app` (native akışta Services ID gerekmez, secret key gerekmez). (c) TestFlight'ta dene: ilk girişte ad gelir, sonrakilerde gelmez — profil ilk seferde yazılır. |
| 16 | ⏸️ **ERTELENDİ (2026-09-14)** — Google ile giriş; Android SHA-1 adımı yapılamadı | Kod hazır; düğme `GOOGLE_WEB_CLIENT_ID` derlemeye verilmeden **görünmez** — bu bilinçli: Android istemcisi (SHA-1'ler: debug + upload + **Play App Signing**) kurulmadan secret girilirse iOS'ta çalışıp Android'de `DEVELOPER_ERROR` verir. Sıra: önce (a)'daki üç istemci, sonra secret'lar. | (a) Google Cloud Console → APIs & Services → Credentials: **Web** istemci (Supabase için), **Android** istemci (paket `com.sandik.app` + release ve debug SHA-1), **iOS** istemci (bundle `com.sandik.app`). (b) Supabase → Providers → **Google**: Enable, Web client ID + secret; "Authorized Client IDs"e Web + Android + iOS ID'lerini virgülle ekle (aksi hâlde `aud` uyuşmaz, 400). (c) Build: `--dart-define=GOOGLE_WEB_CLIENT_ID=<web>.apps.googleusercontent.com --dart-define=GOOGLE_IOS_CLIENT_ID=<ios>.apps.googleusercontent.com`. **CI tarafı hazır (2026-09-14):** `android-release.yml`, `ios-testflight.yml` ve `mobsf-scan.yml` bu iki define'ı `GOOGLE_WEB_CLIENT_ID` / `GOOGLE_IOS_CLIENT_ID` **GitHub secret'larından** okuyor — senin tek işin iki secret'ı girmek; girilmezse define boş kalır ve düğme görünmez, build kırılmaz. Kimlikleri üretince değerleri Claude'a ver: `gh secret set GOOGLE_WEB_CLIENT_ID` / `GOOGLE_IOS_CLIENT_ID` adımını o koşar (Google Cloud Console adımı senin hesabını ister, CLI'dan yolu yok). (d) iOS `Info.plist` → `CFBundleURLTypes`'a iOS istemcinin **ters** ID'sini (`com.googleusercontent.apps.<id>`) yeni bir dict olarak ekle; repoya kimlik yazmamak için bu adım elle. (e) Android: `google-services.json` zaten CI secret'ından geliyor; ek adım yok. |
| 17 | **`0060_push_admin_by_uuid.sql`'i koş + 8 fonksiyonu yeniden deploy et** | M9: admin yetkisi artık `push_admins` tablosunda (UUID). Migration bugünkü e-postandan bir kez tohumlar; tablo boş kalırsa uyarı basar → SQL Editor'da `insert into push_admins(user_id) values ('<senin uuid>')`. Fonksiyonlar: `redeem-invite-code` (IP sayacı, M7/M8), `accept-invite` (L13), 6 cron fonksiyonu (L4 CORS). | `supabase db push`; `supabase functions deploy redeem-invite-code accept-invite analyze-signals calendar-nudge check-price-alerts daily-brief fetch-inflation weekly-summary`. |
| 18 | **Oturum kasası geçişini cihazda dene** (M2) | Token artık Keychain/Keystore'da; ilk açılışta eski SharedPreferences oturumu taşınır. Beklenen: güncelleme sonrası yeniden giriş İSTENMEZ. | TestFlight/internal build'i mevcut oturumun üstüne kur, uygulamayı aç: doğrudan ana ekran gelmeli. |
| 19 | ✅ **YAPILDI (2026-09-14)** — Supabase dağıtımı için 3 GitHub secret'ı gir; artık migration/function deploy'unu Claude tetikliyor | Claude Code web ortamı Supabase API'sine erişemiyor (ağ politikası) ve kimlik bilgisi taşımıyor; `.github/workflows/supabase-deploy.yml` bu işi Actions'a taşır. Secret'lar girildikten sonra #7, #11, #13, #14, #17 satırlarındaki `supabase db push` / `functions deploy` adımlarını Actions → **Supabase deploy** → Run workflow ile (ya da Claude'a "deploy et" diyerek) koşturursun. | GitHub → Settings → Secrets and variables → Actions: `SUPABASE_ACCESS_TOKEN` (supabase.com → Account → Access Tokens), `SUPABASE_PROJECT_REF` (`https://<ref>.supabase.co` içindeki ref), `SUPABASE_DB_PASSWORD` (Project Settings → Database). İlk koşuyu `dry_run=true` ile yap; plan temizse gerçek koş. |

Tam bulgu listesi: `docs/DEGERLENDIRME_VE_YOL_HARITASI_2026_09.md` §3.
İlerleme: `docs/YOL_HARITASI_ILERLEME.md`.

---

## ✅ UYGULANDI: `0051_percentile_180d.sql` (2026-09-13)

180 günlük yüzdelik dilim kovası **canlıda açık** — doğrulandı
(2026-09-13, uzak veritabanına sorguyla):

| Yer | Durum |
|---|---|
| `user_roi_snapshots` CHECK | `ARRAY[7, 30, 180, 365]` ✅ |
| `get_percentile_bucket` | 180 allowlist'te ✅ |
| `get_top_gainers_allocation` | 180 allowlist'te ✅ |
| Yetkiler | `authenticated` + `service_role`; `anon`/`public` YOK ✅ |
| `search_path` | `public` sabitlenmiş, `SECURITY DEFINER` ✅ |

180 satırının gerçekten yazılabildiği de `rollback`'li bir deneme
insert'iyle doğrulandı — CHECK, RLS ve throttle trigger'ının hepsi
geçildi.

> **⚠️ Migration defteri GÜNCEL DEĞİL.** SQL Editor'den elle koşulduğu
> için `supabase_migrations` tablosuna kaydedilmedi: `supabase migration
> list` çıktısında `0050` ve `0051` için `remote` kolonu BOŞ görünüyor.
> Bir sonraki `supabase db push` ikisini yeniden koşmaya çalışır.
> **Zararsız** (ikisi de idempotent: `add column if not exists`,
> varlık kontrollü `DO` blokları, `CREATE OR REPLACE`) ama defteri
> düzeltmek temiz olur:
>
> ```bash
> supabase migration repair --status applied 0050 0051
> ```

**k-anonimlik değişmedi:** `k_min = 8` ve `n_max = 4` aynen korunuyor.
Yeni bir kova eklendi, eşik matematiğine dokunulmadı.

### Şerit neden HÂLÂ görünmüyor (ve bu neden normal)

Ölçüldü (2026-09-13): son 24 saatte havuzda **tek kullanıcı** var (sen).
Üç kovanın hepsi k=8'in altında, yani ana ekrandaki mevcut
`PercentileStrip` de görünmüyordur. Bu **doğru davranış** — KVKK
k-anonimliği. Tek kullanıcıyla test ederek şeridi göremezsin.

Ayrıca `period_days = 180` satırı henüz HİÇ yok: `_yukleDilim` yalnızca
**Performans → Özet → 6A** sekmesi açıldığında snapshot atıyor. Sekme bu
kodu taşıyan bir derlemede bir kez açılınca satır düşer.

```sql
-- Kova başına havuz durumu
select period_days,
       count(distinct user_id) as kisi_24s,
       case when count(distinct user_id) >= 8 then 'ACIK' else 'KAPALI' end
  from user_roi_snapshots
 where created_at >= now() - interval '24 hours'
 group by period_days order by period_days;
```

**Not:** `uploadRoiSnapshot` hatayı SESSİZCE yutuyor
(`leaderboard_service.dart` `catch (_)`). Migration'dan ÖNCE atılmış bir
180 insert'i CHECK'e takılıp iz bırakmadan kaybolurdu — artık takılmıyor,
ama bu sessizlik ileride benzer bir teşhiste yanıltabilir.

---

## 🎛️ İSTEĞE BAĞLI: `period_summary_enabled` bayrağı (2026-09-13)

Dönem Özeti (Performans → **Grafik | Özet** sekmesi) ve ana ekrandaki
"Bu hafta" kartı geldi. **Tamamen ücretsiz** — paywall'a bağlı değil.

**Elden yapılacak bir şey YOK.** Bayrak varsayılan olarak `true` doğuyor,
yani yeni sürüm çıktığı anda açık. Bu madde yalnızca bayrağın VAR
olduğunu bilmen için:

- Firebase Console → Remote Config → `period_summary_enabled`
- `false` çekersen **yalnızca ana ekran kartı** gizlenir; Performans
  ekranındaki Özet sekmesi kalır (kullanıcının bilinçli olarak girdiği
  bir yer, dikkat bütçesinden yemiyor).

Ölçüm: `period_summary_viewed` olayı (parametre `period`: `gunluk` |
`birHafta` | `birAy` | `altiAy` | `birYil`). **Faz 2 kararı buna
bağlı** — 1H sekmesi hiç açılmıyorsa haftalık push'un gönderilecek bir
karşılığı yok demektir.

Migration yok, vault sırrı yok, edge function yok. Faz 2 (haftalık push)
2026-09-14'te geldi — aşağıdaki maddeye bak.

---

## ✅ KAPANDI: `cron_gateway_jwt` — dört aylık sessiz arıza (2026-09-14)

**Doğrulandı:** Vault kaydı 09:07'de yazıldı; 11:10'daki
`trigger_daily_brief()` çağrısı **200** ve `{"sent":2}` döndürdü. Cron
bildirimleri akıyor. Aşağıdaki anlatı arızanın kaydı olarak duruyor.

> ### ⚠️ Teşhiste tuzak: "function cron_headers does not exist"
>
> SQL Editor'da `public.cron_headers(...)` çağırınca
> `42883: function does not exist` alırsın. **Bu eksiklik DEĞİL, yetki
> kısıtıdır.** `0054` üç yardımcıyı (`cron_gateway_jwt`, `cron_secret_of`,
> `cron_headers`) bilinçli olarak yalnızca `service_role`'e veriyor;
> Postgres, yetkin olmayan fonksiyonu "yok" diye bildirir. Editor'dan
> denemek için `set local role service_role;` ile rol değiştir.
>
> Fonksiyonların gerçekten var olduğunun kanıtı `trigger_*` çağrısının
> 200 dönmesidir — o fonksiyonlar `cron_headers`'ı içeriden çağırır.
>
> Aynı şekilde `net._http_response`'daki eski bir `401` satırı bugünkü
> durumu göstermez: **`created` sütununa bak**, Vault kaydının
> zamanından önceyse tarihî bir kayıttır.

### Ne oldu

Haftalık özeti canlı doğrularken dört aylık **sessiz** bir arıza bulundu:
`daily_brief_log` Mayıs 2026'dan beri BOŞ. Sabah brifingi hiç
gönderilmemişti. Sebep cron'da ya da fonksiyonda değil, **header'da**:

Supabase API gateway, isteği fonksiyona iletmeden önce `Authorization`
header'ını JWT olarak ayrıştırıyor. Tetikleyiciler oraya rastgele hex bir
cron secret koyuyordu; gateway bunu JWT sanıp isteği **fonksiyona hiç
ulaştırmadan** reddediyordu (`401 UNAUTHORIZED_INVALID_JWT_FORMAT`).

Fark edilmemesinin sebebi: her gösterge yeşildi. Cron kurulu ✓, koşu
başarılı ✓, fonksiyon logları boş (çünkü hiç çalışmadı), 401 yalnızca
`net._http_response` içinde.

Kod tarafı düzeltildi ve dağıtıldı (`0054` + `_shared/cron_auth.ts`):
`Authorization` artık service_role JWT'si taşıyor, cron secret'ı
`x-cron-secret` header'ına geçti.

### Senin yapacağın: Vault'a service_role JWT'sini yaz

Migration bunu yazamaz — service_role key'ini SQL içinden okuyamaz ve
repoya girmemeli.

1. **Dashboard → Settings → API → `service_role` (secret)** → kopyala
   *(`anon` DEĞİL — `service_role` olan, `eyJ...` ile başlayan uzun JWT)*
2. **SQL Editor**'de:

```sql
select vault.create_secret(
  '<service_role JWT>',
  'cron_gateway_jwt',
  'API gateway JWT dogrulamasini gecmek icin — cron tetikleyicileri'
);
```

3. Sonra migration'ı koş:

```bash
supabase db push   # 0054_cron_auth_header.sql
```

`0054` kurulum eksikse **açık hatayla durur** (sessiz düşmemesi kasıtlı —
bu arızanın ilk hâli tam olarak sessizliğinden dolayı dört ay yaşadı).
JWT biçimini de denetliyor: oraya hex bir string yazılırsa yine patlar.

Yedi tetikleyicinin hepsi bu tek kaydı okur — key rotasyonu yedi ayrı
Vault kaydına dokunmak olmasın diye.

### Doğrulama — asıl kapı bu

```sql
select public.trigger_daily_brief();
select id, status_code, left(content, 200) from net._http_response
order by id desc limit 1;
```

| Gördüğün | Anlamı |
|---|---|
| `200` | ✅ çalışıyor — dört aylık arıza kapandı |
| `401 UNAUTHORIZED_INVALID_JWT_FORMAT` | `cron_gateway_jwt` yok ya da JWT değil |
| `401 Yetkisiz cron cagrisi` | Vault'taki cron secret'ı fonksiyonun env secret'ıyla eşleşmiyor |

Ayrıntı: [`supabase/functions/_shared/CRON_AUTH.md`](supabase/functions/_shared/CRON_AUTH.md)

### ✅ (KAPANDI 2026-09-14) İkiz cron sırrı ayrıldı

`weekly_summary_cron_secret` ve `inflation_fetch_cron_secret` aynı string'di —
biri sızarsa ikisi birden düşerdi. Her birine ayrı `openssl rand -hex 32`
üretildi, `supabase secrets set` + Vault `update_secret` ile yazıldı.

**Doğrulandı:** `trigger_weekly_summary()` → `200 {"sent":0,...,"failures":[]}`
ve `trigger_fetch_inflation()` → `200 {"written":24,"reason":"no_new_data"}`.
Sıfır sayaçlar Pazar gecesi için beklenen; kapının geçildiği `200`'den okunur.

---

## ✅ UYGULANDI: haftalık özet push'u — Faz 2 (2026-09-14)

Fonksiyon dağıtıldı, secret'lar verildi, Vault yazıldı, `0052` uygulandı.
Cron doğrulandı: `weekly-summary = 45 6 * * 1`,
`daily-brief = 45 6 * * 2-5` (Pazartesi susturulmuş ✓).

⚠️ Ama gönderim **yukarıdaki `cron_gateway_jwt` adımına bağlı** — o
yapılmadan tetikleyici gateway'de 401 alır.

**Migration ne yapıyor:** `weekly_summary_log` defteri,
`profiles.weekly_summary_push` kolonu, `trigger_weekly_summary()`,
cron (`45 6 * * 1` = Pazartesi TR 09:45) ve **`daily-brief`'i `1-5` → `2-5`
daraltma**. Sonunda kendi sonucunu doğruluyor: cron kurulmadıysa ya da
brifing susturulamadıysa YÜKSEK SESLE patlıyor (sessizce uygulanmamış bir
cron, "çalıştığı sanılan ama çalışmayan" en pahalı hata sınıfı).

### Kuru koşu (kimseye bildirim gitmez)

```bash
curl -X POST "https://<proje>.supabase.co/functions/v1/weekly-summary" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "x-cron-secret: $WEEKLY_SUMMARY_CRON_SECRET" \
  -H "Content-Type: application/json" -d '{"dry_run": true}'
```

Dönen alanlar ve **ne anlama geldikleri**:

| Alan | Anlamı |
|---|---|
| `sent` | gidecek bildirim |
| `skipped_flow` | hafta içinde alım/satım yaptığı için elenen — **en önemlisi** |
| `skipped_coverage` | uçları pencere kenarına 48 saatten uzak olan |
| `skipped_quiet` | eşiğin (%2) altında kalan |
| `skipped_opt_out` | `weekly_summary_push = false` |

### ⚠️ `sent: 0` görmek muhtemelen NORMAL

Kendi hesabınla test ederken büyük olasılıkla `skipped_flow` ya da
`skipped_coverage` altında elenirsin:

- **`skipped_flow`** — hafta içinde alım/satım yaptıysan push GİTMEZ. Bu
  bilinçli bir karar: `snapshots` brüt değer tutuyor, para girişi
  ayıklanmıyor ve "+%30 kazandın" gibi yanlış bir rakam göndermek hiç
  göndermemekten kötü. Ayrıntı: `supabase/functions/weekly-summary/README.md`.
- **`skipped_coverage`** — `snapshots` yalnızca uygulamayı açtığında
  yazılıyor. Hafta başında ve sonunda (48 saat içinde) birer snapshot
  yoksa yüzde eksik bir pencereyi anlatırdı.

Zorla bir gönderim görmek istersen: temiz bir hafta (işlem yapılmamış) +
hafta başı/sonu uygulamayı açmış olmak + `{"min_move_pct": 0}` ile kuru
koşu.

### Doğrulama sorguları

```sql
-- Cron'lar doğru kurulmuş mu? (Pazartesi ikisi birden koşmamalı)
select jobname, schedule from cron.job
 where jobname in ('weekly-summary', 'daily-brief', 'weekly-summary-cleanup')
 order by jobname;
-- beklenen: daily-brief = '45 6 * * 2-5', weekly-summary = '45 6 * * 1'

-- Kime gönderilmiş?
select sent_on, count(*) from weekly_summary_log
 group by sent_on order by sent_on desc limit 5;
```

**Ayrıca:** Ayarlar → BİLDİRİMLER → "Haftalık özet" anahtarı eklendi
(`profiles.weekly_summary_push`, varsayılan açık). Android'de ayrı kanal
(`summary_channel`) — kullanıcı haftalık özeti kapatıp sabah brifingini
açık tutabilir.

Ayrıntı: `supabase/functions/weekly-summary/README.md`

---

## ✅ KAPANDI (2026-09-14 toplu dağıtım): satılan/silinen varlık için push (2026-09-07 → 2026-09-10)

> 11 edge function 2026-09-14'te yeniden dağıtıldı (üstteki 🚨 bölüm, #6); `_shared/positions.ts` düzeltmesi canlıda. Aşağısı tarihçe.


**Belirti:** Tamamen SATILMIŞ hisseler için sinyal bildirimi gelmeye devam
ediyordu ("AVOD ve AGHOL varlıklarımda olmamasına rağmen push'ları geliyor").

**Sebep:** `assets` bir lot tablosu; satış alım satırını silmez, `kind='sell'`
ayrı bir satır yazar. Sunucu yalnızca `kind='buy'` filtreliyor, satışları
netlemiyordu — uygulama net 0 pozisyonu portföyden düşürdüğü için kullanıcı
"bende yok" görüyor, sunucu "hâlâ var" sanıyordu.

**Düzeltme kodda** (`supabase/functions/_shared/positions.ts`) ama **Edge
Function'lar yeniden dağıtılmadan etkili olmaz.** Push'lar sunucudan gidiyor;
uygulama güncellemesi bu hatayı düzeltmez.

```bash
supabase functions deploy analyze-signals
supabase functions deploy daily-brief
```

Doğrulama (push göndermez, yalnızca analiz eder):
```bash
curl -X POST "https://<proje>.supabase.co/functions/v1/analyze-signals" \
  -H "Authorization: Bearer <SERVICE_ROLE_KEY>" \
  -H "x-cron-secret: <ANALYZE_SIGNALS_CRON_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"dry_run":true}'
```
Yanıttaki `closed_or_deleted_lots` alanı, **satış ya da silme** yüzünden
elenen alım lot'u sayısıdır. Sıfırdan büyükse düzeltme fiilen çalışıyor
demektir; `preview` listesinde satılmış/silinmiş varlıklar artık
görünmemeli.

**Silme tarafı ayrıca ele alındı.** Silmenin asıl mekanizması `deleted_at`
damgasıdır ve sunucu onu zaten eliyordu; ama istemci önce mezar taşını
(`delete_log`) yazıp SONRA damgayı atıyor — arada bağlantı koparsa lot
sunucuda AKTİF kalır, uygulama ise kendi durumunu iyimser güncellediği için
kullanıcı varlığı silinmiş görür. Artık sunucu mezar taşını da dinliyor:
pozisyonun tamamını silen bir `delete_log`'dan ESKİ alım lot'ları
susturuluyor (sonra tekrar alınmışsa bildirim yine gider).

Bu yüzden `assets` sorgusuna `added_date` ve `ref_asset_id` sütunları
eklendi — deploy edilmeden ikisi de okunamaz.

### 🔁 2026-09-10 — aynı dosyada İKİNCİ düzeltme, deploy hâlâ bekliyor

Kullanıcı bildirimi sürüyordu: "sildiğim varlıkların push'ları gelmeye devam
ediyor." Yukarıdaki mezar taşı savunması **tek lot'lu pozisyonlarda hiç
çalışmıyordu** — yani en yaygın durumda.

Sebep: `ref_asset_id` DOLU mezar taşları tamamen atlanıyordu. Eski gerekçe
("o satır zaten fiziksel silinmiştir") yalnızca `deleteAsset` için doğru.
Normal silme yolu `deletePositionLots` ve o YUMUŞAK siliyor: pozisyon tek
lot'luysa mezar taşına `ref_asset_id` yazıp lot'u `deleted_at` ile
damgalıyor. Damga sunucuya ulaşmazsa lot AKTİF kalıyor, mezar taşı da
atlandığı için bildirim gitmeye devam ediyordu.

Artık o mezar taşı, işaret ettiği lot'u — ve **yalnızca** onu — eliyor;
miktarı netten de düşülüyor. Kardeş lot'lar susmuyor (iki lot'lu bir
varlıkta birini silmek diğerini sessizleştirmemeli).

`_shared/positions.ts` yine değişti, yani **aşağıdaki iki komut hâlâ
koşulmalı.** Uygulama tarafındaki eş düzeltme (`analyzePortfolio` artık ham
ledger yerine yalnızca açık pozisyonları geziyor) TestFlight 1.1.4
(1785274310) içinde — ama cron'dan giden push'lar sunucudan üretiliyor ve
onu ancak deploy düzeltir.

Deploy sonrası dry-run'da `closed_or_deleted_lots` sayısı, önceki turdakine
göre ARTMALI: artık tek lot'lu silmeler de eleniyor.

---

## ✅ KAPANDI (2026-09-14): kilit ekranı teması (2026-09-11)

> `push-live-activity` 2026-09-14'te dağıtıldı ve `trigger_live_activity_push()` canlıda `200 {"sent":5}` döndü (#3). Aşağısı tarihçe.


**Belirti:** "Canlı etkinlikler tema rengi sürekli değişiyor; uygulamayı
kill etsem de son seçilen tema kalmalı."

### 1) Birinci sebep: `push-live-activity` HİÇ DAĞITILMAMIŞ olabilir

Temayı push gövdesine koyan sunucu kodu **2026-09-03**'te eklendi
(commit `b5ce9e4`). 2026-09-07 tarihli `docs/archive/SUPABASE_DEPLOY_ADIMLARI.txt`
yalnızca `analyze-signals` ve `daily-brief`'i listeliyor —
`push-live-activity` hiçbir deploy listesinde geçmiyor.

Dağıtılmadıysa sunucudaki ESKİ sürüm `isLightTheme` alanını **hiç
göndermez**; Swift tarafı eksik alanı `false` = KOYU varsayar
(`SandikAttributes.swift`, bilinçli geri uyumluluk). Sonuç tam olarak
kullanıcının gördüğü şey:

| durum | yüzeyi kim besliyor | palet |
|---|---|---|
| uygulama önplanda | ActivityKit yerel `update` | **doğru** |
| uygulama kapalı / 5 dk'lık cron push | eski edge function | **koyu** |

Yani banner uygulamayı her açıp kapadıkça renk değiştirir. **Uygulama
güncellemesi bunu düzeltmez** — hangi build'i kursan sunucu aynı eksik
gövdeyi göndermeye devam eder.

```bash
supabase functions deploy push-live-activity
```

Doğrulama: komut çıktısındaki sürüm/tarih güncel olmalı; sonra kilit
ekranını 5-10 dakika (bir cron turu) izle — palet artık dönmemeli.

### 2) İkinci sebep: tema özetin içine gömülüydü

**Sebep:** tema yalnızca `live_activity_sessions.summary` JSON'unun içinde
taşınıyordu ve o JSON **yalnızca portföy özeti yazılırken** güncelleniyor.
Uygulama kapalıyken kilit ekranını besleyen tek şey bu satır olduğu için,
özetin tazelenmediği her durumda (tema gösterim penceresi dışında
değiştirildi, oturum satırı yeni açıldı, özet eski şema damgası taşıyor)
sunucu ESKİ paletle push atıyordu. Uygulama açılınca doğru palet basılıyor,
kapanınca geri dönüyordu.

**Düzeltme iki parçalı — uygulama güncellemesi TEK BAŞINA yetmez:**

a) Migration (tek satır, geri alınabilir):
```sql
alter table live_activity_sessions
  add column if not exists is_light_theme boolean not null default false;
```
ya da `supabase db push` (dosya: `0050_live_activity_theme.sql`).

b) Edge function (push içeriğini artık bu sütundan okuyor) — yukarıdaki
(1) ile aynı komut, bir kez koşmak ikisini de kapsar:
```bash
supabase functions deploy push-live-activity
```

**Sıra önemli: ÖNCE migration, SONRA function.** Fonksiyon satırı `select('*')`
ile okuduğu için sütun yokken patlamaz, ama sütun gelene kadar eski
(özet içindeki) yedek değeri kullanmaya devam eder.

Koşulmazsa ne olur: uygulama çökmez, kilit ekranı donmaz — tema yine
özet üzerinden taşınır, yani düzeltmenin **yalnızca** uygulama içi ayağı
çalışır ve "kill edince değişiyor" bulgusu sürer.

**Doğrulama (uygulamadan, kod gerekmez):** Profil → (admin) Push Teşhisi →
**6. CANLI ETKİNLİK / TEMA** bölümü. Üç satırı karşılaştır:
* `Yerel karar` — uygulamanın çözdüğü tema,
* `sütun (is_light_theme)` — sunucunun push'a koyduğu değer,
* `özet (summary.isLightTheme)` — eski yedek yol.

"SÜTUN YOK" yazıyorsa migration koşulmamıştır. `Tercih: Sistem` yazıyorsa
temanın cihazla birlikte değişmesi **normaldir** — sabitlemek için Ayarlar'dan
açıkça Açık ya da Koyu seçilmeli.

---

## ✅ KAPANDI: `0049_partner_activity_push.sql` (2026-09-07)

> Defter 2026-09-14'te onarıldı, `db push --dry-run` "up to date" (#19/#20). Aşağısı tarihçe.


`profiles` tablosuna `partner_activity_push` sütunu ekler. Çalıştırılmazsa:
Ayarlar'daki "Ortak hareketi bildirimleri" anahtarı yazmaya çalışır ve hata
verir; günlük brifing de ortak kolunu hiç açamaz (sorgu düşer, brifing
sessizce hisse mesajına döner).

Tek satır, geri alınabilir:
```sql
alter table public.profiles
  add column if not exists partner_activity_push boolean not null default true;
```

---

## 🔑 VAULT ADIMI — üç cron sırrı (2026-09-07)

Üç Edge Function dağıtıldı ve `supabase secrets` tarafı yazıldı. **Kalan tek
adım Vault.** Cron tetikleyicileri sırrı Vault'tan okuyor; Vault'ta karşılığı
yoksa fonksiyon **401** döner ve hiçbir bildirim gitmez.

> ⚠️ **2026-09-14 güncellemesi:** Bu sırlar artık `Authorization` header'ında
> DEĞİL, `x-cron-secret` header'ında gönderiliyor. `Authorization`'a
> service_role JWT'si gidiyor ve o **`cron_gateway_jwt`** adlı ayrı bir Vault
> kaydından okunuyor — bu dosyanın başındaki 🔴 bölüme bak. Aşağıdaki Vault
> mekaniği aynen geçerli; yalnızca sırrın hangi header'da taşındığı değişti.
>
> Aşağıda uyarılan "mükerrer kayıt / `order by` eksikliği" sorunu da `0054`
> ile kapandı: okuma artık `order by created_at desc` yapıyor ve mükerrer
> kayıt varsa uyarı basıyor.

Sırların gerçek değerleri repoya YAZILMADI (bu dosya git'te izleniyor).
Değerler şurada:
`%LOCALAPPDATA%\Temp\claude\c--projects-PortfoyTakip\<oturum>\scratchpad\`
→ `pa.txt` (price alerts), `cn.txt` (calendar nudge), `db.txt` (daily brief).

Supabase Dashboard → SQL Editor'da, `<...>` yerlerine o dosyaların içeriğini
koyarak çalıştır:

```sql
-- Mükerrer kayıt YARATMA: 0034'te belgelendiği gibi vault.create_secret
-- her çağrıda YENİ satır ekler ve 0046/0048'deki okuma `order by`
-- içermediği için hangisinin okunacağı garanti değildir.
-- Bu blok varsa günceller, yoksa oluşturur.
do $$
declare
  s record;
begin
  for s in
    select * from (values
      ('price_alerts_cron_secret',   '<pa.txt icerigi>'),
      ('calendar_nudge_cron_secret', '<cn.txt icerigi>'),
      ('daily_brief_cron_secret',    '<db.txt icerigi>')
    ) as t(nm, val)
  loop
    if exists (select 1 from vault.secrets where name = s.nm) then
      perform vault.update_secret(
        (select id from vault.secrets where name = s.nm order by created_at desc limit 1),
        s.val, s.nm, null);
    else
      perform vault.create_secret(s.val, s.nm, null);
    end if;
  end loop;
end $$;

-- Doğrulama: her ad için TEK satır olmalı.
select name, count(*) from vault.decrypted_secrets
 where name in ('price_alerts_cron_secret','calendar_nudge_cron_secret',
                'daily_brief_cron_secret')
 group by name;
```

Sonra kuru koşu yap (kimseye bildirim gitmez) — `<secret>` yerine ilgili
dosyanın içeriği:

```bash
curl -X POST "https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/check-price-alerts" \
  -H "Authorization: Bearer <pa.txt>" \
  -H "Content-Type: application/json" -d '{"dry_run": true}'
```

`200` + kaç kişiye gideceği dönerse kurulum tamamdır; `401` dönerse Vault
değeri `supabase secrets` değeriyle eşleşmiyordur.

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

## ✅ (KAPANDI) DM Sans fontları — Xcode adımı GEREKMİYOR

Fontlar `ios/SandikWidget/Fonts/` altına konuldu, `Info.plist`'e
`UIAppFonts` kaydı yapıldı ve **`project.pbxproj` doğrudan düzenlenerek**
SandikWidget hedefinin *Copy Bundle Resources* fazına eklendi.

Yani Xcode açmana gerek yok — GitHub Actions'taki build fontları
kendiliğinden paketleyecek.

**TestFlight'ta doğrulama:** kilit ekranındaki "Sandık" yazısı ve rakamlar
uygulamanın içindeki başlıklarla aynı karakter biçiminde olmalı. Sistem
fontuna (SF Pro) düşmüş görünüyorsa `UIAppFonts` kaydı ya da hedef üyeliği
bozulmuş demektir.

---

## 📅 KISMEN TAMAM: TÜİK Enflasyon Kancası (2026-09-07)

1. ✅ `supabase functions deploy calendar-nudge` — dağıtıldı
2. ✅ `supabase secrets set CALENDAR_NUDGE_CRON_SECRET` — yazıldı
3. ⬜ **KALDI —** Vault → `calendar_nudge_cron_secret` (bkz. aşağıdaki
   "VAULT ADIMI" bölümü; bu yapılmadan cron 401 alır)
4. ✅ Migration `0048_calendar_nudge.sql` — koşuldu

**TÜFE endeksi dolu değilse bildirim gitmez** — endeks artık otomatik
çekiliyor ama EVDS anahtarı gerekiyor (bkz. "TEK ADIM KALDI: TÜFE
otomatik çekimi").

⚠️ **2026-09-14 sonrası:** `0053` bu kancanın ayın 4'ündeki ikinci turunu
açıyor ve fonksiyon gönderim defterini okuyacak şekilde güncellendi.
`supabase functions deploy calendar-nudge` YAPILMADAN migration koşulursa
çift bildirim gider.

Ayrıntı: `supabase/functions/calendar-nudge/README.md`

---

## 🔔 KISMEN TAMAM: Fiyat Alarmları (2026-09-07)

Kod hazır; kullanıcı Ayarlar → "Fiyat alarmları"ndan kurabiliyor ama
**Vault adımı yapılmadan hâlâ hiçbir alarm çalmaz.**

1. ✅ `supabase functions deploy check-price-alerts` — dağıtıldı
2. ✅ `supabase secrets set PRICE_ALERTS_CRON_SECRET` — yazıldı
3. ⬜ **KALDI —** Vault → `price_alerts_cron_secret` (bkz. "VAULT ADIMI")
4. ✅ Migration `0046_price_alerts.sql` — koşuldu

Kuru koşu (kimseye bildirim gitmez):

```bash
curl -X POST "https://<proje>.supabase.co/functions/v1/check-price-alerts" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "x-cron-secret: $PRICE_ALERTS_CRON_SECRET" \
  -H "Content-Type: application/json" -d '{"dry_run": true}'
```

Ayrıntı: `supabase/functions/check-price-alerts/README.md`

---

## 🔑 TEK ADIM KALDI: TÜFE otomatik çekimi — EVDS anahtarı (2026-09-14)

Reel getiri rozeti ("enflasyonun 6,4 puan önündesin") ve Özet sekmesinin
TÜFE satırları `inflation_index` tablosuna bağlı. **Tablo artık ELLE
doldurulmuyor** — `fetch-inflation` edge function'ı her ayın 3'ünde
TCMB EVDS'den çekiyor.

**Aylık bakım BİTTİ.** Yapman gereken tek şey bir kerelik anahtar:

### 1) EVDS anahtarı al (5 dakika, ücretsiz)

evds2.tcmb.gov.tr → üye ol → **Profil → API Anahtarı**

### 2) Dağıt

```bash
# ✅ YAPILDI — fonksiyonlar dağıtıldı, cron secret'ı + Vault yazıldı,
#              0053 uygulandı, calendar-nudge yeniden dağıtıldı.
#              Cron doğrulandı: fetch-inflation 10:05 < nudge 10:15 ✓

# ⬜ KALAN TEK ŞEY — EVDS anahtarı:
supabase secrets set EVDS_API_KEY="<evds-anahtarin>"
```

⚠️ Ayrıca **yukarıdaki `cron_gateway_jwt`** adımı yapılmadan bu tetikleyici
de gateway'de 401 alır (`inflation_index` şu an boş — çekim hiç
çalışmamış olabilir).

### ⚠️ `calendar-nudge` neden yeniden dağıtılmalı

Migration, takvim kancasının **ayın 4'ündeki ikinci turunu açıyor** (veri
bir gün geç yayımlanırsa o ayın kancası kaçmasın diye). Bu tur ancak
fonksiyon **gönderim defterini** okuyorsa güvenli.

Eski sürümde kalırsa: veri 3'ünde zamanında girildiğinde **iki bildirim**
gider — yani `0048`'in ikinci turu kapatma sebebinin aynısı geri gelir.

### Anahtarı almadan ne olur

Hiçbir şey bozulmaz. Fonksiyon `no_api_key` döner ve **tabloya yazmaz**;
tablo boş kaldığı için rozet de görünmez (bugünkü durumun aynısı). Yarım
bir entegrasyonla tabloyu bozmaktansa kapalı kalması tercih edildi.

### Doğrulama

```bash
# Tabloya YAZMADAN — ne çekeceğini söyler
curl -X POST "https://<proje>.supabase.co/functions/v1/fetch-inflation" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "x-cron-secret: $INFLATION_FETCH_CRON_SECRET" \
  -H "Content-Type: application/json" -d '{"dry_run": true}'
```

İlk gerçek koşu **24 ay** geriye gider. Rozet 365 günlük pencere
kullanıyor, yani en az **13 ay** gerekiyor (başlangıç ayı + son açıklanan
ay); 24 ay pencereyi rahatça dolduruyor.

```sql
select count(*) as ay_sayisi, min(period), max(period) from inflation_index;
```

**Sonra:** Remote Config → `real_return_enabled` → `true`. Tablo dolu olsa
bile bu bayrak kapalıysa rozet görünmez.

### 🚨 Bir gün gelecek: baz yılı değişimi

TÜİK baz yılını değiştirdiğinde (ör. 2003=100 → 2025=100) endeks
SIFIRLANIR ve eski satırlarla yeni satırlar karşılaştırılamaz. Fonksiyon
bunu yakalayıp **yazmayı reddediyor** (`base_year_break`, HTTP 409) —
çünkü bölme "−%95 enflasyon" gibi anlamsız bir sonuç verirdi.

O gün geldiğinde bu senin kararın olacak: yeni seriyi ayrı mı tutmak,
eski satırları mı silmek, ikisini bir dönüşüm katsayısıyla mı birleştirmek.
Otomatik çözülmez ve sessizce yanlış yapmasın diye kasten durduruluyor.

Ayrıntı: `supabase/functions/fetch-inflation/README.md`
Migration: `0045_inflation_index.sql` (tablo), `0053_fetch_inflation.sql` (çekim)

---

## 📨 KISMEN TAMAM: Sabah Brifingi (2026-09-07)

**Vault adımı yapılmadan hiçbir kullanıcıya bildirim gitmez.**

1. ✅ `supabase functions deploy daily-brief` — dağıtıldı
2. ✅ `supabase secrets set DAILY_BRIEF_CRON_SECRET` — yazıldı
   (FCM_PROJECT_ID ve FCM_SERVICE_ACCOUNT_JSON zaten vardı)
3. ⬜ **KALDI —** Vault → `daily_brief_cron_secret` (bkz. "VAULT ADIMI")
4. ✅ Migration `0044_daily_brief.sql` — koşuldu

**Önce kuru koşu yap** — kimseye bildirim gitmeden kaç kişiye gideceğini
söyler:

```bash
curl -X POST "https://<proje>.supabase.co/functions/v1/daily-brief" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "x-cron-secret: $DAILY_BRIEF_CRON_SECRET" \
  -H "Content-Type: application/json" -d '{"dry_run": true}'
```

Ayrıntı: `supabase/functions/daily-brief/README.md`

---

## ✅ KAPANDI: `0027_soft_delete_lots.sql` (2026-08-11)

> Canlıda uygulanmış (yumuşak silme aylardır çalışıyor; defter 2026-09-14'te doğrulandı). Aşağısı tarihçe.


**Ne:** `assets` tablosuna `deleted_at TIMESTAMPTZ` sütunu + aktif kayıtlar
için kısmi indeks.

**Neden gerekli:** Silme artık FİZİKSEL değil, YUMUŞAK. Lot'lar yerinde
kalır ve damgalanır; böylece silinen varlığın Alım/Satım/Temettü satırları
"Portföy Hareketleri"nde durmaya devam eder. Toplamlar/grafik/aggregate
damgalı kayıtları eler (`Asset.isActive`).

**Uygulanmazsa ne olur:** Silme UPDATE'i patlar (bilinmeyen sütun) →
kullanıcı varlık silemez. Bloker.

**Nasıl:**
```bash
supabase db push
```
veya Dashboard → SQL Editor → `supabase/migrations/0027_soft_delete_lots.sql`.

**Geriye dönük uyumlu:** Mevcut satırlarda NULL = aktif, davranış değişmez.
Daha önce FİZİKSEL silinmiş kayıtlar geri gelmez (veri yok) — bu migration
öncesi silinen varlıkların geçmişi kurtarılamaz.

---

## ✅ UYGULANDI: `0026_delete_log_count.sql` (2026-08-11)

`assets.deleted_count INTEGER NOT NULL DEFAULT 0` sütunu eklendi. Silme
artık lot başına değil, pozisyon başına TEK kayıt yazıyor ve kaç ledger
satırının silindiğini bu sütunda taşıyor → "Silindi · 3 kayıt".

Eski `delete_log` satırlarında sütun 0 kalır; uygulama 0'ı "sayı bilinmiyor"
sayıp düz "Silindi" gösterir. Bekleyen bir iş yok.

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
- `store_listing/tr-TR/title.txt` → `Sandık: Portföy Takibi` ✅ (22/30 karakter)
- `store_listing/en-US/title.txt` → `Sandık: Portfolio Tracker` ✅ (25/30 karakter)

**Ayraç kararı (2026-08-09):** Başlıkta em dash (`—`) yerine iki nokta (`:`)
kullanılıyor. Bir sonraki release'de App Store Connect'e girilecek isim
budur; repo ile Console'un birebir aynı kalması için buradaki dosyalar da
güncellendi.

**⚠️ SENİN YAPMAN GEREKEN — Play Console'daki başlık repodan okunmaz.**
Store listing metinleri Console'a elle girilir; repodaki `store_listing/`
dosyaları yalnızca kaynak metindir. "Sandık" araması sonuç vermiyorsa asıl
sebep büyük ihtimalle Console'daki başlığın hâlâ eski yazımda olmasıdır.

Play Console → Grow → Store presence → Main store listing:
1. **App name** alanına `Sandık: Portföy Takibi` yaz
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

## 3.5 🛡️ MobSF — Yayın öncesi APK güvenlik taraması (önerilir)

Mağazaya göndermeden önce derlenmiş APK/IPA'yı MobSF ile bir kez tara:
binary'ye sır sızmış mı, manifest/imza sertleştirmesi doğru mu.

- **CI'da otomatik:** `v*` tag push'unda `.github/workflows/mobsf-scan.yml`
  çalışır ve `mobsf-report.json` artefaktını üretir. İstersen Actions
  sekmesinden elle de tetikleyebilirsin (`workflow_dispatch`).
- **İsteğe bağlı secret:** `MOBSF_API_KEY` (yoksa CI-yerel sabit kullanılır).
- **Yerelde çalıştırma ve raporu okuma:** [`docs/security/mobsf.md`](docs/security/mobsf.md).

⚠️ MobSF **Dart iş mantığını okuyamaz** — yalnızca kabuğu (manifest, native
lib, gömülü string) denetler. Kaynak-seviyesi güvenlik incelemesi ayrıdır
(bkz. `SECURITY_AUDIT_2026_08.md`). İkisi birbirini tamamlar.

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
- **App name:** `Sandık: Portföy Takibi` (`store_listing/tr-TR/title.txt` ile birebir)
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


---

## 📹 Anlatımlı önizleme videosu — yükleme ÖNCESİ iki doğrulama (2026-09-17)

**Güncel teslim (2026-09-18):** `store_listing/preview_video/brag-output-2026-09-18-store/brag.mp4`
(aynısı `out/sandik_preview_iphone_aciklamali.mp4`) — seslendirmesiz, açıklamalı; 886×1920,
30 fps, H.264 11 Mbps, AAC 256k, 28,0 sn. Seslendirme olmadığı için aşağıdaki **2. madde bu
sürüm için geçerli değil**; yalnızca müzik lisansı (1) kaldı. Anlatımlı sürüm
(`brag-output/brag.mp4`) yedek olarak duruyor; onu yüklersen 2. madde de gerekir. Apple 2.3.9 "haklar sende"
diyor; iki ses kaynağının hakkı **senin elinle** doğrulanmalı:

1. **Müzik** — ✅ **DOĞRULANDI (2026-09-18):** ende.app tüm parçaları CC BY 4.0 ile
   dağıtıyor, ticari kullanım açıkça serbest, atıf yazar tarafından isteğe bağlı
   bırakılmış, ücret yok. Ayrıntı ve iki yasak (Spotify'a kendi şarkın gibi yükleme,
   Content ID'ye kaydetme): `store_listing/preview_video/SES_LISANS.md`. Yapman
   gereken tek şey isteğe bağlı: oradaki atıf satırını Hakkında/Lisanslar ekranına
   veya mağaza açıklamasına koy.
2. **Anlatım** — edge-tts (Microsoft Edge çevrimiçi neural TTS,
   `tr-TR-AhmetNeural`). Ticari kullanım için Azure Speech'in resmi hizmeti
   önerilir (aynı ses, ücretli ama lisanslı). Kabul etmiyorsan
   `scripts/prep_media.py` içindeki komutla Azure'dan üretilen mp3'leri
   `assets/vo/` altına koy, betiği çalıştır, yeniden render et.

Kalıcı iyileştirme (isteğe bağlı): kayıt hâlâ gerçek hesapla; "Test" ortak adı
videoda "Ayşe" maskesiyle örtülü. Demo hesapla yeniden çekim
(`CEKIM_SENARYOSU.md` §2) maskeyi gereksiz kılar.

## 🔎 ASO — App Store Connect'e girilecekler (2026-09-20)

Metinler, ölçüm ve gerekçe: `store_listing/ios/ASO_2026_09.md`. Sıra:

- [ ] Localizations → **Turkish** ekle, Primary Language = Turkish
- [ ] Ad: `Sandık: Portföy & Hisse Takibi` · Alt başlık: `Fon, Altın, Temettü, Enflasyon` (1.1.5 sürümüyle yayınlanır)
- [ ] Keyword TR: `sandik,borsa,bist,yatırım,döviz,dolar,kur,tefas,kâr,zarar,tüfe,reel,getiri,birikim,varlık,gümüş`
- [ ] Keyword EN (U.S.): `portfoy,hisse takip,fon takip,kar zarar,reel getiri,tufe,gram altin,ons,borsa,yatirim,net worth`
- [ ] Tanıtım metni (aylık, TÜFE'den sonra) + açıklama ikinci satırına "enflasyonu geçip geçmediğini"
- [ ] Önizleme videosu yükle (`brag-output-2026-09-18-store/brag.mp4`)
- [ ] Apple Search Ads marka kampanyası: `sandık` `sandik` `sandık portföy` (namesake "Sandık" uygulaması 30 Ağustos'ta çıktı, 3 puanla)
- [ ] In-App Event "Enflasyon günü" (her ayın 3'ü, 14 gün önce planla)
- [ ] 2 hafta sonra `python tool/aso_siralama.py` → ölçüm defterine yaz

## 📈 Kurulum büyüme planı (2026-09-18)

Plan ve haftalık ölçüm: `docs/KURULUM_BUYUME_PLANI_2026_09.md`, sıralama betiği
`python tool/aso_siralama.py`. Elden yapılacak ilk adımlar (Faz 0, kod yok):

- [ ] App Store Connect → Localizations → **Turkish** ekle; Türkçe metni oraya, `en-US/` metnini İngilizce alana taşı (şu an sayfa "Diller: İngilizce" gösteriyor, ikinci keyword alanı boş)
- [ ] Subtitle: `Hisse, Fon, Altın Takibi`
- [ ] Apple Search Ads marka kampanyası, exact match `sandık` / `sandik` / `sandık portföy` — "sandık" aramasında görünmemenin tek anında çözümü
- [ ] Play Console başlığı `store_listing/tr-TR/title.txt` ile aynı mı kontrol et

## ⭐ Mağaza değerlendirme istemi (2026-09-18) — kod bitti, iki elle iş

Kodda varsayılanlar açık; bunlar yalnızca **uzaktan kapatabilmek** için:

- [ ] Firebase Console → Remote Config → iki boolean parametre ekle:
  `review_prompt_enabled` = true (tamamen kapatır),
  `review_prompt_soft_gate` = true. **Play incelemesi "karttan önce soru
  sormayın" der ve takılırsanız** `soft_gate`'i false yap → ön soru atlanır,
  doğrudan sistem puan kartı açılır; yayın gerekmez.
- [ ] Gerçek cihazda dene (emülatörde Play Store yok → mağaza sayfasına
  düşer): Ayarlar → **sandık'ı değerlendir** satırı mağazayı açmalı.
  Otomatik istemi görmek için kurulumdan ≥3 gün ve ≥3 aktif gün gerekir;
  hemen görmek istersen `ReviewPromptService.instance.sifirla()` yetmez,
  `retention_*` sayaçları da gerekir — TestFlight'ta doğal akışla bekle.
- Ölçüm: Analytics `review_prompt` olayı, `action` = shown/later/feedback/review,
  `moment` = kilometreTasi/paylasim/topluEkleme/settings. Hangi anın puana
  dönüştüğü buradan okunur; dönüşmeyen an kaldırılır.

## 📣 Reklam paketi hazır — yükleme sende (2026-09-19)

`store_listing/reklam/out/`: üç video (Reels 9:16 15 sn · kare 1:1 12 sn ·
YouTube bumper 16:9 6 sn) + beş görsel (kare enflasyon/altın/ortak, hikâye,
1600×900 banner). Kararlar `store_listing/reklam/README.md`.

- [ ] Instagram/TikTok/Shorts'a Reel'i yükle; gönderi metnine *"Örnek portföy;
  yatırım tavsiyesi değildir."* satırını ekle (görsellerdeki getiri demo).
- [ ] X / LinkedIn profil başlığı: `sandik_banner_1600x900.png`.
- [ ] Apple Search Ads "Custom Product Page" için kare görseller kullanılabilir;
  marka kampanyası (KURULUM_BUYUME_PLANI §Faz 0) ile birlikte aç.
- [ ] Android Play'e çıkınca `src/reklam/ui.tsx` → `StoreLine` metnini
  "App Store ve Google Play'de" yap, `node scripts/render_reklam.mjs` ile yeniden üret.
- Müzik CC BY 4.0 (ende.app), atıf isteğe bağlı — `SES_LISANS.md`.
