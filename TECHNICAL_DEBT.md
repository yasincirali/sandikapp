# sandık — Teknik Borç Defteri

Ertelenmiş **kod** kararları. Kullanıcının elden yapacağı işler
`YAPMAN_GEREKENLER.md`'de; burası yalnızca kod tabanına dair borç.

Her madde: neden ertelendi, ertelemenin maliyeti ne, ne zaman ele alınmalı.

**Son güncelleme:** 2026-08-03

---

## ⏸️ ERTELENDİ — Dev ekranları parçala

**Karar tarihi:** 2026-08-03 · **Karar:** kullanıcı, başka bir zamana bırakıldı

Beş ekran dosyası toplam **10.744 satır** — kod tabanının %31'i:

| Dosya | Satır |
|---|---|
| `lib/screens/add_asset_screen.dart` | 2.627 |
| `lib/screens/performance_screen.dart` | 2.553 |
| `lib/screens/portfolio_performance_screen.dart` | 2.209 |
| `lib/screens/charts_screen.dart` | 1.690 |
| `lib/screens/leaderboard_screen.dart` | 1.665 |

**Ertelemenin maliyeti — teorik değil, ölçüldü:**
2026-08-03'te ortak kâr/zarar hatası **üç ekrana birden** yayılmıştı, çünkü
ortak filtreleme mantığı (`_view` == '' / null / uuid ayrımı) bu dosyalara
kopyalanmıştı. Tek bir hata üç ayrı yerde düzeltildi. Aynı kopyalama
`portfolio_performance_screen` ile `charts_screen` arasında hâlâ duruyor.

**Ele alınma zamanı:** Tek seferlik büyük bir refactor olarak DEĞİL — o
riskli ve test kapsamı buna yetmiyor. Bu ekranlardan birine iş düştükçe,
o dokunuşta ortak parçayı çıkar:
- Ortak/partner sekmesi + `ownerLots` kurulumu (3 ekranda tekrar ediyor)
- Tür filtresi chip satırı
- Periyot seçici + simülasyon toggle

**Ön koşul:** Widget testi olmadan bu ekranları bölmek riskli. Aşağıdaki
"widget test kapsamı" maddesi bundan önce gelmeli.

---

## 🟠 AÇIK — Widget test kapsamı (kısmen kapandı)

**2026-08-04 durumu:** 162 testin 46'sı gerçek widget testi:
- `transaction_row_overflow_test.dart` — `TransactionRow` (11 senaryo)
- `asset_card_overflow_test.dart` — `ChartsScreen` (8 senaryo)
- `leaderboard_overflow_test.dart` — `LeaderboardScreen`, opt-in açık/kapalı
  iki hâl (8 senaryo)
- `performance_screen_overflow_test.dart` — `PerformanceScreen` (8 senaryo)
- `home_screen_overflow_test.dart` — `HomeScreen`, boş/dolu portföy
  (11 senaryo)

Hepsi çok genişlikli tarama yapıyor (320–430pt).

**Bulunan gerçek hatalar:** bu testler yazılırken **beş** taşma ortaya çıktı,
hiçbiri gözle görülmüyordu:
| Yer | Taşma | Sebep |
|---|---|---|
| `TransactionRow` satış satırı | 19px yatay | "Çıkarıldı" etiketi "Eklendi"den uzun, 116pt kolona sığmıyor |
| `performance_screen` TOPLAM MİKTAR | 105px yatay | etiket + değer ikisi de sınırsız |
| `performance_screen` TEKNİK ANALİZ başlığı | — | başlık + sayaç ayar bağlantısını itiyor |
| `performance_screen` grafik lejantı | 15px yatay | uzun ticker rozetleri |
| `performance_screen` DEĞİŞİM kartı | 54px @320pt | etiket tam genişliği alıyor, değer taşıyor |

Bu yaklaşımın değeri ölçüldü: gerçek widget'a bağlanan test, ilk çalıştırmada
**daha önce bilinmeyen bir taşmayı** ortaya çıkardı (satış satırında 19px
yatay — "Çıkarıldı" etiketi "Eklendi"den uzun ve 116pt'lik kolona sığmıyordu).
Yapısal kopya bunu yakalayamazdı çünkü kopyada etiket sabitti.

**Ekran-seviyesi test kalıbı (yeni):** `_AssetCard` gibi private ve çok
yardımcılı widget'lar için ayrı dosyaya çıkarmayı BEKLEMEYE gerek yok.
Ekranı `ProviderScope` override'larıyla pump et; iç yapı değil dış davranış
doğrulanır, ekran ileride parçalanınca test yine geçer. Örnek:
`asset_card_overflow_test.dart`.

**Sırada:** `add_asset_screen` (form alanları), `portfolio_performance_screen`.
`tester.takeException()` yeterli, golden test gerekmiyor.

### ✅ `home_screen` widget testi — önce geri alındı, sonra kazanıldı (2026-08-04)

İlk denemede ekran testte izole edilemedi; üç sebep vardı ve üçü de kapandı:
- `signalProvider` → Supabase — `SignalNotifier` override'ıyla çözüldü
- `DbLogger._persistAsync` → her çağrıda bekleyen future kuruyordu; artık
  `DbLogger.silentInTests` ile susturuluyor (varsayılan `false`, üretim yolu
  değişmedi)
- `google_fonts` → DM Sans ağdan çekiliyordu; asset olarak gömüldü

`home_screen_overflow_test.dart` geri getirildi: 11 senaryo, boş ve dolu
portföy hâlleri, 320–430pt tarama. **Sabotajla doğrulandı** — başlıktaki
`Flexible`+`FittedBox` koruması kaldırılınca test her genişlikte düşüyor
(430pt'de 17px, 320pt'de 115px).

**Ders:** "ekran testte izole edilemiyor" çoğu zaman ekranın değil,
bağımlılıkların sorunudur. Testi silmeden önce her bağımlılığı tek tek
sustur.

---

## 🟡 AÇIK — Riverpod ile setState karışımı

Ekranlarda **147 `setState`** çağrısı. Yerel arayüz durumu (açık/kapalı
panel, seçili sekme) için doğru kullanım; veri durumu için Riverpod varken
ikili yönetim gereksiz rebuild ve kafa karışıklığı üretiyor.

**Ele alınma zamanı:** Ekran parçalama işiyle birlikte, ayrı bir tur olarak
değil.

---

## 🟡 AÇIK — Yarım kalan özellikler

İkisi de aynı kararı bekliyor: **ya tamamla ya sil.**

- `deposits_enabled: false` — vadeli mevduat kodu duruyor, kullanıcıya kapalı.
  Faiz/vade hesabı ayrı bir domain; yarım hâlde durması karmaşıklık borcu.
- `paywall_enabled: false` — premium altyapısı (PremiumGate, paywall ekranı,
  Remote Config flag'leri) hazır ama `pubspec.yaml`'da IAP paketi YOK. Flag
  açılsa satın alma çalışmaz. Ayrıntı: `MONETIZATION_ROADMAP.md`.

---

## ✅ KAPANDI

| Tarih | İş | Commit |
|---|---|---|
| 2026-08-03 | Ortak polling'i lifecycle'a bağla (900→240 istek/saat) | `2a956e4` |
| 2026-08-03 | History cache'e LRU + TTL | `2a956e4` |
| 2026-08-03 | Android AAB release pipeline | `b514c5a` |
| 2026-08-03 | PriceService bellek önbelleği | `b514c5a` |
| 2026-08-03 | Açılışta 3 servisi ertele (8→5 bloklayan await) | `fed8c87` |
| 2026-08-03 | Varlık listesi `ListView.builder` | `fed8c87` |
| 2026-08-03 | Ölü kod: SwiftUI prototipi + `DatabaseService` | `cde78d9` |
| 2026-08-03 | Paywall'da var olmayan özellik reklamı | `03f1798` |
| 2026-08-04 | `_buildAssetTile` → `TransactionRow` widget'ı; test yapısal kopyadan gerçek widget'a geçti (+ 19px satış satırı taşması bulundu) | — |
| 2026-08-04 | DM Sans asset olarak gömüldü, `allowRuntimeFetching = false` (P2 kapandı) | — |

### Not: google_fonts çalışma zamanı indirmesi (kapandı 2026-08-04)

`google_fonts` paketi font **dosyalarını içermez** — varsayılan davranışı,
istenen aileyi ilk kullanımda `fonts.gstatic.com`'dan indirip cihaza
cache'lemektir. Sonuç: ilk açılış ağa bağımlıydı, offline'da DM Sans yerine
sistem fontu çiziliyordu.

Altı statik ağırlık (400/500/600/700/800/900 — `lib/` taraması bunları
kullanıyor) `assets/fonts/` altına alındı ve `main()` başında
`allowRuntimeFetching = false` yapıldı.

**Maliyet:** APK içinde sıkıştırılmış **161 KB**. Buna karşılık ağ isteği
sıfır, ilk açılış deterministik.

**Doğrulama tuzağı:** `flutter test` asset/font manifest'ini uygulamadaki
gibi yüklemez — pubspec'teki font kaydını tamamen bozsanız bile
`GoogleFonts.dmSans()` testte sorunsuz döner. Yani "çağrı fırlatmıyor"
biçimindeki bir test **hiçbir şey kanıtlamaz** (önce öyle yazıldı, sabotaj
denemesinde yakalanmadığı görülüp değiştirildi). `bundled_font_test.dart`
bunun yerine pubspec kaydını, dosyaların varlığını ve her TTF'in `OS/2`
`usWeightClass` alanını doğrudan okur; üç sabotaj senaryosuyla (aile adı
bozuk, ağırlık eksik, bayrak silinmiş) düştüğü teyit edildi.

Derlenmiş APK'daki `FontManifest.json` da elle kontrol edildi: aile adı
`"DM Sans"` ve altı ağırlık doğru eşlenmiş durumda.

---

## Ölçülemeyenler

Cold start süresi, scroll jank ve bellek profili **ölçülmedi**: geliştirme
emülatörü frame üretmiyor (`dumpsys gfxinfo` → "Total frames rendered: 1").
Gerçek cihazda `flutter run --profile` ile ölçülmeli.

### Emülatörde Flutter render etmiyor — kapsamı 2026-08-04'te daraltıldı

Bu makinedeki emülatörlerde **hiçbir Flutter build'i** görsel çıktı vermiyor.
Ekran siyah kalıyor, `screencap` ~20 KB tek renk PNG üretiyor.

Elenen ihtimaller (hepsi denendi, sonuç değişmedi):

| Değişken | Denenen | Sonuç |
|---|---|---|
| API seviyesi | 35 ve 36 | ikisinde de 1 frame |
| Build tipi | release (R8'li) ve debug | ikisinde de 1 frame |
| GPU modu | host default ve `swiftshader_indirect` | ikisinde de 1 frame |
| Renderer | Impeller ve `--ez enable-impeller false` | ikisinde de 1 frame |

**Emülatörün kendisi sağlam:** aynı cihazda sistem Ayarlar uygulaması 44
frame üretiyor ve 188 KB'lık dolu bir ekran görüntüsü veriyor. Sorun
Flutter/Impeller ile bu emülatörün GL yığını arasında.

**Uygulama sağlam:** logcat'te `Supabase init completed` görünüyor, süreç
yaşıyor, FATAL/ANR yok. Dart tarafı sonuna kadar çalışıyor — yalnızca
sunum katmanı okunamıyor.

**Sonuç:** Emülatör, görsel doğrulama için kullanılamaz. `uiautomator dump`
da boş dönüyor (Flutter erişilebilirlik ağacını doldurmuyor), yani otomatik
arayüz doğrulaması da bu yoldan yapılamaz. **Yerleşim/taşma doğrulaması
gerçek cihazda veya widget testiyle yapılmalı.**
