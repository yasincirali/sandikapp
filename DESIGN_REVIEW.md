# Sandık — Tasarım & Hareket Denetimi

**Tarih:** 2026-08-06 · **Kapsam:** `lib/` (24 ekran, 16 widget, 21k satır ekran kodu)
**Referans:** `.claude/skills/` altına kurulan [emilkowalski/skills](https://github.com/emilkowalski/skills) —
`emil-design-eng`, `review-animations/STANDARDS.md`, `apple-design`, `find-animation-opportunities`.

Skill'ler web/CSS diliyle yazılmış; bulgular Flutter karşılıklarına çevrildi
(`transition-timing-function` → `curve:`, `:active` → `onTapDown`, `prefers-reduced-motion`
→ `MediaQuery.disableAnimationsOf`).

---

## Uygulama durumu (2026-08-06)

P0'ın tamamı ve P2'nin risksiz kalemleri **uygulandı**. Tümü görsel katmanda;
hiçbir iş mantığı, veri akışı veya koşul değişmedi. `flutter analyze` 13 → 13
(baseline ile aynı, sıfır regresyon), `flutter test` 172/172 geçti.

| # | Madde | Durum |
| --- | --- | --- |
| 1 | 16 `AnimatedContainer` → `SandikMotion.enter` | ✅ |
| 2 | `easeIn` → `easeOut`, 420ms → 240ms | ✅ |
| 3 | Haptic altyapısı + 6 kritik nokta | ✅ |
| 8 | Login toggle 400ms → 180ms | ✅ |
| 7 | `SandikErrorView` fade-in + basma geri bildirimi | ✅ |
| 13/14 | Radius ölçek düzeltmeleri (12→md, 18→lg) | ✅ |
| 4,5,6,9,10,11,12 | Stagger, skeleton, boş durumlar, splash, Hero, toast | ⏳ sonraki tur |

**Yeni kalıcı yapı** — `sandik.dart` içinde:
- `SandikMotion` — süre + eğri sabitleri. Bundan sonra `duration:` yazılan her
  yerde `curve:` de verilmeli; eğri artık "unutulabilir parametre" değil.
- `SandikHaptic` — dört kademeli dokunsal ölçek (`none`/`selection`/`medium`/`heavy`),
  `SandikTappable`, `SandikAsyncButton` ve `SandikAsyncTap` üzerinden otomatik.

Haptic yerleşimindeki iki incelik: yutulan ikinci dokunuş titreşim **vermez**
(aksi halde kullanıcı isteğin gittiğini sanar), ve aynı sekmeye tekrar dokunmak
bir durum değişimi olmadığı için geri bildirim üretmez.

**SnackBar → marka toast (#11) bilinçli olarak ertelendi:** 30 çağrı yeri dağınık,
merkezi yardımcı yok; tek tek dönüştürmek bu turun "sıfır fonksiyonel değişiklik"
sözleşmesini riske atardı.

---

## Özet

Proje denetimin beklediği hataların çoğunu **zaten yapmıyor**. `sandik.dart` gerçek bir
tasarım sistemi: üç kademeli radius ölçeği, 8'lik boşluk ızgarası, tabular figür sayı
stilleri, hareket-azaltma desteği olan `SandikTappable`, tek tarih seçici, çift-push
koruması. Tipografi tema üzerinden çözülüyor (401 `context.t.` çağrısına karşılık 16
hardcoded `GoogleFonts`). Süreler disiplinli: en sık kullanılan değerler 180ms ve 220ms,
UI hareketlerinin neredeyse tamamı 300ms altında. `_AnimatedIndexedStack`'in neden
`AnimatedSwitcher` olmadığı yorumda gerekçelendirilmiş — bu, kod tabanının niyetli
olduğunun işareti.

Bu yüzden aşağıdaki liste "yeniden tasarla" değil, **kalibrasyon** listesi. En büyük
bulgu tek bir eksik parametre ve uygulamanın tamamına yayılmış durumda.

---

## P0 — Tek satırlık, en yüksek getirili

### 1. 18 `AnimatedContainer`'ın 16'sı `Curves.linear` ile çalışıyor

Flutter'da `AnimatedContainer.curve` varsayılanı `Curves.linear`. Doğrusal hareket
fiziksel dünyada yoktur; gözü rahatsız eder ama kullanıcı sebebini adlandıramaz —
skill'in "unseen details compound" dediği şeyin tam örneği. Süreleri (180/200/220ms)
zaten doğru seçilmiş; eksik olan yalnızca eğri.

| Önce | Sonra | Neden |
| --- | --- | --- |
| `AnimatedContainer(duration: 180ms)` — [add_asset_screen.dart:554](lib/screens/add_asset_screen.dart#L554) | `curve: Curves.easeOut` ekle | Çip seçimi bir durum geçişi; `ease-out` anında tepki hissi verir |
| `AnimatedContainer(duration: 180ms)` — [all_transactions_screen.dart:166](lib/screens/all_transactions_screen.dart#L166) | `curve: Curves.easeOut` | Aynı — filtre çipi |
| `AnimatedContainer(duration: 180ms)` — [paywall_screen.dart:392](lib/screens/paywall_screen.dart#L392) | `curve: Curves.easeOut` | Paket seçimi; dönüşüm ekranı, cilalı hissetmeli |
| `AnimatedContainer(duration: 200ms)` — [performance_screen.dart:675](lib/screens/performance_screen.dart#L675), [:2111](lib/screens/performance_screen.dart#L2111) | `curve: Curves.easeOut` | Sekme seçimi |
| `AnimatedContainer` — [signal_settings_screen.dart:435](lib/screens/signal_settings_screen.dart#L435), [register_screen.dart:577](lib/screens/register_screen.dart#L577), [charts_screen.dart:541](lib/screens/charts_screen.dart#L541), [add_deposit_screen.dart:402](lib/screens/add_deposit_screen.dart#L402), [portfolio_performance_screen.dart:676](lib/screens/portfolio_performance_screen.dart#L676), [disclaimer_acceptance_screen.dart:134](lib/screens/disclaimer_acceptance_screen.dart#L134), [onboarding_screen.dart:310](lib/screens/onboarding_screen.dart#L310), [leaderboard_screen.dart:1421](lib/screens/leaderboard_screen.dart#L1421) | `curve: Curves.easeOut` | Hepsi giriş/durum geçişi |

Doğru yapılmış iki örnek referans olarak duruyor:
[home_screen.dart:589](lib/screens/home_screen.dart#L589) (`easeOut`) ve
[leaderboard_screen.dart:435](lib/screens/leaderboard_screen.dart#L435) (`easeOutCubic`).

**Kalıcı çözüm:** `sandik.dart`'a hareket sabitleri ekle, böylece eğri "unutulabilir bir
parametre" olmaktan çıkar:

```dart
/// Marka hareket dili — süre ve eğri birlikte seçilir, ayrı ayrı değil.
abstract final class SandikMotion {
  /// Basma geri bildirimi (110ms) — SandikTappable kullanır.
  static const Duration press = Duration(milliseconds: 110);
  /// Durum geçişi: çip, sekme, seçim (180ms).
  static const Duration state = Duration(milliseconds: 180);
  /// Giren/çıkan yüzey: sheet, dialog (240ms).
  static const Duration surface = Duration(milliseconds: 240);

  /// Giren/çıkan her şey. Flutter varsayılanı linear'dır — asla ona güvenme.
  static const Curve enter = Curves.easeOutCubic;
  /// Ekranda yer değiştiren/biçim değiştiren.
  static const Curve move = Curves.easeInOutCubic;
}
```

### 2. `Curves.easeIn` — [main.dart:733](lib/main.dart#L733)

`switchOutCurve: Curves.easeIn`, splash → ana ekran geçişinde. Standart net:
*"Never `ease-in` on UI."* `ease-in` yavaş başlar; kullanıcının en dikkatli baktığı
ilk anı geciktirir.

| Önce | Sonra | Neden |
| --- | --- | --- |
| `switchOutCurve: Curves.easeIn` | `switchOutCurve: Curves.easeOut` | Çıkan katman da hemen hareket etmeli; `ease-in` uygulamayı ağır hissettirir |
| `duration: 420ms` ([main.dart:731](lib/main.dart#L731)) | `260–300ms` | UI hareketi 300ms altında kalmalı; bu geçiş her açılışta görülüyor |

### 3. Uygulamada hiç dokunsal geri bildirim yok

`HapticFeedback` çağrısı **0 adet**. Mobilde dokunsal geri bildirim, web'deki `:active`
scale'in karşılığıdır — hareketin ulaşamadığı bir kanal. Finansal bir uygulamada
"işlem gerçekten kaydedildi" hissi için özellikle değerli.

Nereye, hangi yoğunlukta:

| Yer | Çağrı | Neden |
| --- | --- | --- |
| FAB → varlık ekle ([main_navigation_screen.dart:205](lib/screens/main_navigation_screen.dart#L205)) | `HapticFeedback.mediumImpact()` | Ana eylem |
| Sekme değişimi ([main_navigation_screen.dart:163](lib/screens/main_navigation_screen.dart#L163)) | `selectionClick()` | Günde onlarca kez — en hafif ton |
| Çip/filtre seçimi (yukarıdaki 16 yer) | `selectionClick()` | Seçim değişti |
| Varlık kaydedildi / silindi | `mediumImpact()` | Kalıcı sonuç doğrulaması |
| Hata SnackBar'ı (30 kullanım) | `heavyImpact()` | Bakmıyorken bile fark edilir |

En temiz yol: `SandikTappable`'a opsiyonel `haptic` parametresi eklemek — 10 kullanım
yerinin tamamı tek noktadan kazanır.

---

## P1 — Hissedilir kazanç, sınırlı iş

### 4. Liste girişlerinde kademeleme (stagger) yok

Portföy listesi, işlem listesi ve leaderboard aynı anda "pat" diye beliriyor.
Standart 30–80ms aralıkla kademelemeyi öneriyor. Dikkat: bu **dekoratiftir** —
etkileşimi engellememeli ve `disableAnimationsOf` açıkken atlanmalı.

Sadece **ilk yüklemede** uygulanmalı; her `setState`'te tekrarlanırsa fiyat
yenilendikçe liste titrer. Fiyat güncellemesi listeyi yeniden animasyonlamamalı.

### 5. Grafik ekranlarında iskelet (skeleton) yerine spinner

33 `CustomLoadingIndicator` kullanımı var. Marka GIF'i güzel ama tam sayfa yükleme
için kullanıldığında algılanan bekleme süresini uzatıyor. `charts_screen` ve
`performance_screen` gibi düzeni önceden bilinen ekranlarda kart hatlarını taşıyan
gri bloklar (shimmer) daha hızlı hissettirir — sayfa "gelmek üzere" görünür.

Ana sayfa hero kartı ve satır listesi bunun en net adayı: yükseklikler zaten sabit.

### 6. Boş durumlar sadece metin

34 boş-durum metni var ("Henüz…", "bulunamadı") ama görsel/eylem eşliği belirsiz.
Boş durum, bir kullanıcının ürünle ilk karşılaştığı ekran — en yüksek getirili
tasarım yüzeyi ve genelde en ihmal edileni. Her boş duruma: soluk bir ikon,
tek cümlelik açıklama, ve **tek bir birincil eylem** (örn. "İlk varlığını ekle" →
doğrudan `AddAssetScreen`).

### 7. `SandikErrorView` sessiz — [sandik_error_view.dart](lib/widgets/sandik_error_view.dart)

Hata görünümü belirirken hiç animasyon yok, "Tekrar Dene" düz `TextButton`
(basma geri bildirimi yok). Hata anı, arayüzün en çok güven vermesi gereken andır.

| Önce | Sonra | Neden |
| --- | --- | --- |
| Anında beliren `Center(Column(...))` | 200ms `easeOut` fade + `translateY(8px)` | Ani değişim "bozuldu" hissi verir |
| `TextButton('Tekrar Dene')` | `SandikTappable` sarmalı veya `SandikAsyncButton` | Her basılabilir eleman basıldığını hissettirmeli |

### 8. 400ms `animationDuration` — [login_screen.dart:212](lib/screens/login_screen.dart#L212)

"Beni hatırla" toggle'ı 400ms. Toggle bir buton geri bildirimidir; 150–200ms bandına
ait. 400ms burada anahtarı ağır hissettiriyor.

### 9. 1800ms splash gecikmesi — [main.dart:530](lib/main.dart#L530)

`Future.delayed(1800ms)` sabit bekleme. Veri hazır olsa bile kullanıcı bekliyor.
Öneri: minimum görünürlük süresini 800–1000ms'e indir ve **veri hazırsa** hemen geç
(sabit bekleme yerine `Future.wait([minDelay, dataReady])` deseni). Her açılışta
görülen bir maliyet — algılanan performansın en pahalı kalemi.

---

## P2 — Cila

**10. `Hero` geçişi hiç kullanılmıyor.** Kodda `Hero(` eşleşmeleri var ama hepsi
`_totalHero`, `_OptInHero` gibi *isim*; gerçek `Hero` widget'ı yok. Varlık satırı →
`AssetDetailScreen` geçişinde varlık ikonu/adı için `Hero` mekânsal süreklilik kurar:
kullanıcı nereden nereye gittiğini kaybetmez. Detay ekranına giden en sık yol bu.

**11. 30 `SnackBar` — marka dışı.** Material varsayılan SnackBar'ı koyu yeşil/amber
dilin dışında duruyor. Tek bir `showSandikToast()` yardımcısı (üstten giren, marka
yüzeyli, `easeOut`) hem tutarlılık hem de bottom bar ile çakışmama kazandırır.

**12. Onboarding 320ms.** [onboarding_screen.dart:177](lib/screens/onboarding_screen.dart#L177)
sınırın hemen üstünde — ama onboarding "nadir/ilk kez" kategorisinde, burada biraz
uzun olması **kabul edilebilir**. Değiştirme gereği yok; bilinçli bırakıldığı not edilsin.

**13. `inputDecoration` radius'u ölçek dışı.** [sandik.dart:424](lib/theme/sandik.dart#L424)
ve devamında `BorderRadius.circular(12)` altı kez geçiyor; ölçek `sm=8 / md=14 / lg=20`.
12 hiçbirine ait değil. `SandikRadius.md` (14) yapılmalı — aynı formda input ve buton
yan yana geldiğinde yuvarlaklıklar uyuşmuyor.

**14. `glassDecoration` varsayılan radius'u 18.** ([sandik.dart:347](lib/theme/sandik.dart#L347))
Yine ölçek dışı; `lg` (20) olmalı.

---

## Yapılmaması gerekenler

Skill `find-animation-opportunities` kadar *neyi animasyonlamamak* gerektiğini de
söylüyor. Bu projede özellikle:

- **Fiyat güncellemelerini animasyonlama.** Fiyatlar sık yenileniyor; her rakam
  değişiminde sayaç animasyonu listeyi huzursuz eder. `TweenAnimationBuilder` ile
  akan çubuk ([home_screen.dart:691](lib/screens/home_screen.dart#L691), 520ms) sınırda
  ama tek bir çubuk olduğu için kabul edilebilir — bu deseni satırlara yayma.
- **Bottom bar sekme geçişini süsleme.** 260ms çapraz sönümleme yeterli; kaydırma
  veya ölçek eklenmesi günde onlarca kez görülen bir hareketi yorucu yapar.
- **Grafiklere giriş animasyonu eklememe.** `fl_chart`'ın çizim animasyonu finansal
  veride yanıltıcıdır — kullanıcı gerçek değeri görmeden önce sahte bir ara değer görür.

---

## Önerilen sıra

| Adım | İş | Etki |
| --- | --- | --- |
| 1 | `SandikMotion` sabitlerini ekle, 16 `AnimatedContainer`'a `curve` ver, `easeIn`'i düzelt | Tüm uygulamada hissedilir; ~1 saat |
| 2 | `SandikTappable`'a haptic ekle + 5 kritik noktaya bağla | Mobil his sıçraması; ~1 saat |
| 3 | Splash 1800ms → veri-hazır deseni | Algılanan açılış hızı; ~1 saat |
| 4 | Boş durumlar + `SandikErrorView` cilası | İlk izlenim; ~2 saat |
| 5 | Hero geçişi (varlık → detay), skeleton yükleme | Cila; ~3 saat |
| 6 | Radius ölçek düzeltmeleri (12→14, 18→20), SnackBar → marka toast | Tutarlılık; ~2 saat |

---

## Kurulan skill'ler

`.claude/skills/` altına 9 skill eklendi: `emil-design-eng`, `animate`,
`review-animations`, `improve-animations`, `find-animation-opportunities`,
`animation-vocabulary`, `apple-design`, `pick-ui-library`, `prototype`.

`pick-ui-library` React/web ekosistemine özgü — bu Flutter projesinde karşılığı yok,
diğerleri platformdan bağımsız ilkeler taşıyor ve çeviriyle uygulanabilir.
