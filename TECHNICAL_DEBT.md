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

## 🟠 AÇIK — `_buildAssetTile` test edilebilir değil

`lib/screens/home_screen.dart:681` — hareket satırını çizen metot
`_HomeScreenState`'e private ve Riverpod + Supabase + auth istiyor, bu yüzden
doğrudan `pumpWidget` edilemiyor.

`test/transaction_row_overflow_test.dart` bu ağacın **yapısal kopyasını**
test ediyor. Kopya, gerçek widget'ı test etmez: `home_screen.dart` değişip
test dosyası güncellenmezse test yeşil kalırken uygulama taşabilir.

**Çözüm:** Tile'ı `lib/widgets/transaction_row.dart`'a çıkar; veriyi
parametre olarak al (provider okuma çağıran tarafta kalsın). Sonra test
gerçek widget'ı pump eder ve kopya silinir.

**Neden hemen yapılmadı:** 2026-08-03 oturumunda kapsam dışıydı; taşma
düzeltmesi öncelikliydi ve mid-session refactor riski taşıyordu.

---

## 🟠 AÇIK — Widget test kapsamı

101 testin **97'si** saf hesap/model testi. Widget testi yalnızca
`transaction_row_overflow_test.dart` (4 senaryo) ve o da yapısal kopya
üzerinden.

2026-08-03'te çıkan üç arayüz hatası — kaydırma etiketi kırpılması, buton
taşması, dar ekranda isim ezilmesi — hiçbiri mevcut testlerle
yakalanamıyordu. Biri (yatay 161px taşma) yalnızca yeni yazılan widget testi
sayesinde bulundu; gözle görülmüyordu çünkü yalnızca dar ekranda çıkıyor.

**Öneri:** Kritik ekranlar için farklı genişliklerde (320 / 375 / 430 pt)
taşma doğrulayan testler. `tester.takeException()` yeterli — golden test
gerekmiyor.

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

---

## Ölçülemeyenler

Cold start süresi, scroll jank ve bellek profili **ölçülmedi**: geliştirme
emülatörü frame üretmiyor (`dumpsys gfxinfo` → "Total frames rendered: 1").
Gerçek cihazda `flutter run --profile` ile ölçülmeli.
