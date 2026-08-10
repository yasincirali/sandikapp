# Sandık — Animasyon İnceleme Raporu

**Tarih:** 2026-08-09
**Ölçütler:** `flutter-animations` skill'i (Im5tu/claude) + iOS HIG (`ui-ux-pro-mcp`, Motion & Accessibility kategorileri)
**Kapsam:** `lib/` altındaki 40 animasyon örneği, 21 dosya
**Not:** Bu rapor yalnızca inceleme — kodda değişiklik yapılmadı.

---

## Özet

Kod tabanı animasyon açısından **beklenenden disiplinli**. Curve/duration seçimleri
tutarlı, sayfa geçişleri platforma uyarlanmış, sparkline gibi sıcak yollar
`CustomPainter` + `RepaintBoundary` ile doğru yazılmış.

Tek **yüksek öncelikli** bulgu var: erişilebilirlik kapsamı (reduce-motion).
Gerisi düşük/orta öncelikli tutarlılık işleri.

| # | Bulgu | Önem | Durum |
|---|---|---|---|
| 1 | Reduce-motion kapsamı %15 | **YÜKSEK** | ✅ **ÇÖZÜLDÜ** — %100 |
| 2 | ~~3 `AnimatedSwitcher` curve'süz~~ | — | ❌ **GEÇERSİZ** — hatalı tespit |
| 3 | Splash 1800ms sabit gecikme | ORTA | Açık — ürün kararı bekliyor |
| 4 | ~~Duration ölçeği dağınık~~ | — | ❌ **GEÇERSİZ** — token zaten var |
| 5 | Hiç `Hero` yok | DÜŞÜK | Açık — opsiyonel |

> **Düzeltme (2026-08-10):** İlk taramada 2 ve 4 numaralı maddeler yanlış
> tespit edildi. Uygulama sırasında koda bakınca ikisinin de gerçek olmadığı
> görüldü; aşağıda her biri açıklandı. Rapor, hatalı maddeler silinmek yerine
> işaretlenerek bırakıldı — neyin neden elenmiş olduğu izlenebilir kalsın.

---

## 1. Reduce-motion kapsamı — YÜKSEK ✅ ÇÖZÜLDÜ

**Sonuç:** 40/40 animasyon korumalı (%15 → **%100**).
Uygulama: [theme/sandik.dart](lib/theme/sandik.dart) içine `SandikMotion.of()`
+ `pressOf/stateOf/surfaceOf` kısayolları eklendi; 19 dosyada 33 çağrı yeri
bunlara bağlandı. Regresyon koruması:
[test/reduce_motion_coverage_test.dart](test/reduce_motion_coverage_test.dart)
— 4 davranış testi + 1 kaynak taraması (yeni korumasız `Animated*` eklenirse
test kırmızı yanar; kanarya ile doğrulandı).

Aşağıdaki tespit, düzeltme öncesi durumu belgeler.

---


**HIG:** Pattern #103 & #77, Category: Accessibility/Animation, **Severity: High**
> Do: "Provide static alternatives to animations"
> Don't: "Ignore motion preferences causing discomfort"
> `Flutter_Equiv: MediaQuery.disableAnimationsOf(context)`

**Durum:** Doğru API zaten kullanılıyor — ama yalnızca 3 dosyada.

| Dosya | Animasyon | Reduce-motion |
|---|---:|---|
| [main_navigation_screen.dart](lib/screens/main_navigation_screen.dart) | 3 | ✅ VAR |
| [theme/sandik.dart](lib/theme/sandik.dart) | 3 | ✅ VAR |
| [sandik_error_view.dart](lib/widgets/sandik_error_view.dart) | — | ✅ VAR |
| [add_asset_screen.dart](lib/screens/add_asset_screen.dart) | 4 | ❌ |
| [charts_screen.dart](lib/screens/charts_screen.dart) | 4 | ❌ |
| [leaderboard_screen.dart](lib/screens/leaderboard_screen.dart) | 3 | ❌ |
| [performance_screen.dart](lib/screens/performance_screen.dart) | 3 | ❌ |
| [portfolio_performance_screen.dart](lib/screens/portfolio_performance_screen.dart) | 3 | ❌ |
| [onboarding_screen.dart](lib/screens/onboarding_screen.dart) | 2 | ❌ |
| [modern_tab_selector.dart](lib/widgets/modern_tab_selector.dart) | 2 | ❌ |
| [signal_settings_screen.dart](lib/screens/signal_settings_screen.dart) | 2 | ❌ |
| …ve 11 dosya daha (1'er animasyon) | 11 | ❌ |

**40 animasyonun 6'sı korumalı — %15.**

Mevcut doğru desen ([main_navigation_screen.dart:296](lib/screens/main_navigation_screen.dart#L296)):

```dart
final reduceMotion = MediaQuery.disableAnimationsOf(context);
...
duration: reduceMotion ? Duration.zero : _duration,
```

**Öneri:** Bu deseni her seferinde elle tekrarlamak yerine `theme/sandik.dart`
içine tek bir yardımcı koyup çağrı yerlerini ona bağlamak. Örneğin:

```dart
/// Reduce-motion açıkken süreyi sıfırlar — animasyon anında tamamlanır.
/// HIG Accessibility #103: hareket tercihi yok sayılmamalı.
Duration sandikDuration(BuildContext context, Duration d) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
```

Böylece 34 çağrı yerinde `duration: SandikMotion.fast` yerine
`duration: sandikDuration(context, SandikMotion.fast)` yeterli olur ve
yeni animasyon eklendiğinde koruma unutulmaz.

**Öncelik gerekçesi:** Bu yatırım uygulaması; kullanıcı sık sık sekme değiştirip
grafik açıyor. Hareket duyarlılığı olan kullanıcı için en yoğun animasyonlu
ekranlar (charts, performance, portfolio) tam da korumasız olanlar.

---

## 2. ~~Curve'süz `AnimatedSwitcher`~~ — ❌ GEÇERSİZ TESPİT

İlk taramada 3 `AnimatedSwitcher`'ın curve'süz olduğu bildirilmişti. **Yanlış.**

Sebep: tarama `curve:` alt dizesini arıyordu, ama `AnimatedSwitcher` bu
parametreyi almaz — `switchInCurve:` ve `switchOutCurve:` kullanır. Üç konumun
üçünde de bunlar zaten tanımlıydı:

```dart
// lib/widgets/sandik_async_button.dart:85
AnimatedSwitcher(
  duration: SandikMotion.stateOf(context),
  switchInCurve: SandikMotion.enter,
  switchOutCurve: SandikMotion.enter,
```

Widget tipine göre doğru parametre adıyla yeniden tarandığında:
**40 animasyonun 40'ında da curve tanımlı.** Yapılacak iş yok.

---

## 3. Splash 1800ms sabit gecikme — ORTA

[main.dart:609](lib/main.dart#L609):

```dart
Future.delayed(const Duration(milliseconds: 1800), () {
  if (mounted) setState(() => _splashDone = true);
});
```

Bu, veri hazır olsa bile **koşulsuz** 1.8 saniye bekletir. Uygulamadaki en uzun
ikinci animasyonun 3 katından fazla.

**Skill/HIG ölçütü:** Geçişler <400ms hedeflenir; 1800ms marka gösterimi için
bilinçli bir karar olabilir ama veri hazırsa kullanıcıyı bekletmenin
işlevsel karşılığı yok.

**Öneri:** Sabit süre yerine **alt sınır** yap — "en az 600ms göster, ama veri
hazırsa hemen geç". Böylece splash flash etmez, hazır veri de beklemez.
Bunun `_veriHazir()` mantığıyla birleştirilmesi gerekir (bkz.
[splash_single_load_test.dart](test/splash_single_load_test.dart) — mevcut
değişmez korunmalı).

### ✅ ÇÖZÜLDÜ (2026-08-10, `168a263`)

Alt sınır **600 ms**'ye indirildi ve sihirli sayı `initState`ten çıkarılıp
`_splashMinimum` sabitine alındı.

Kod okununca tespit doğrulandı: `_splashDone` gerçekten `_veriHazir()`'dan
**bağımsız bir taban** olarak çalışıyordu (`if (!_splashDone || ...)`), yani
veri 400 ms'de gelse bile 1.8 sn bekleniyordu. Veri `_warmUpData()` ile
splash sırasında paralel çekildiğinden bu süre yavaş ağı telafi etmiyor,
yalnızca hızlı durumu yavaşlatıyordu.

Veri bekleme kapısı ve 6 sn'lik emniyet supabı **korundu** —
[splash_single_load_test.dart](test/splash_single_load_test.dart)
değişmezi hâlâ geçiyor.

**Ölçüm notu (dürüstlük payı):** `am start -W` yalnızca ilk frame'e
(splash'in kendisine) kadar ölçüyor; splash → ana ekran geçişini
kapsamıyor. Uygulama bu geçiş için zaman damgası basmadığından **kazanç
logcat'ten sayısal olarak doğrulanamadı**. Emülatörde çökme/hata olmadığı
doğrulandı; gerçek kazanç cihazda gözle görülmeli.

---

## 4. ~~Duration ölçeği dağınık~~ — ❌ GEÇERSİZ TESPİT

İlk raporda "motion token'ı yok, `SandikSpace`/`SandikRadius` desenine
uyulmamış" denmişti. **Yanlış.**

`SandikMotion` sınıfı [theme/sandik.dart:163](lib/theme/sandik.dart#L163)
adresinde **zaten mevcut**, dokümante edilmiş ve yaygın kullanılıyor:

| Token | Değer | Kullanım |
|---|---|---|
| `SandikMotion.press` | 110ms | 1 |
| `SandikMotion.state` | 180ms | 23 |
| `SandikMotion.surface` | 240ms | 2 |
| `SandikMotion.enter` | `easeOutCubic` | 38 |
| `SandikMotion.move` | `easeInOutCubic` | 2 |

**Toplam 66 kullanım.** Sınıfın kendi dokümantasyonu, bu işin daha önce bir
denetimle yapıldığını da anlatıyor ("denetim öncesi projedeki 18
`AnimatedContainer`'ın 16'sı eğri vermiyordu").

Geriye kalan ham `Duration` değerleri (150/160/200/220) token'a çekilebilir
ama bu kozmetik bir iş; ölçek zaten kurulu. Bu turda hepsi
`SandikMotion.of(context, ...)` ile sarıldığı için reduce-motion açısından
farkları kalmadı.

---

## 5. Hiç `Hero` animasyonu yok — DÜŞÜK

Doğrulandı: uygulamada **tek bir Flutter `Hero` widget'ı yok**. ("Hero" geçen
yerler `_OptInHero`, `leaderboard_hero_card` gibi kart isimleri.)

**Skill:** Hero, "kullanıcı öğenin rotalar arası uçmasını beklediğinde" kullanılır.

Sandık'ta doğal aday: **varlık satırı → varlık detay/performans ekranı**.
Kullanıcı listede bir hisseye dokunuyor, detay ekranı açılıyor; ticker/tutar
bloğu iki ekranda da var.

**Ama bu bilinçli bir tercih olabilir.** `adaptiveRoute` ile iOS'ta
`CupertinoPageRoute` kullanılıyor ve HIG #80 "sistem geçiş stillerine uy" diyor —
Cupertino'nun kendi kaydırma geçişi zaten güçlü bir mekân hissi veriyor.
Hero eklemek onunla çakışabilir.

**Öneri:** Zorunlu değil. Denemek istersen tek bir ekranda prototiplenip
gerçek cihazda değerlendirilmeli.

### ❌ KAPATILDI — dayanağı geçersiz (2026-08-10)

Uygulamaya geçmeden önce iki uç incelendi ve **öneri kendi varsayımında
hatalı çıktı**:

1. **Raporun "detay ekranı" dediği yer ölü kod.**
   [asset_detail_screen.dart](lib/screens/asset_detail_screen.dart) hiçbir
   yerden `push` edilmiyor — sınıfa yapılan tek referans kendi tanımı.
   Gerçek hedef `PerformanceScreen`.

2. **Paylaşılan görsel öğe yok.** Raporda "ticker/tutar bloğu iki ekranda da
   var" yazıyordu; doğru değil. `PerformanceScreen` varlığı yalnızca
   **AppBar başlığı** olarak gösteriyor (ikon/logo/kart yok). Hero, iki
   ekranda da bulunan somut bir nesnenin uçması demektir; liste satırındaki
   metni AppBar başlığına uçurmak Cupertino'nun kaydırma geçişiyle çakışır
   ve HIG #80'e ters düşer.

Yani Hero için ortada **uçacak bir şey yok**. Bu madde, önce paylaşılan bir
görsel kimlik (varlık ikonu/logosu) tasarlanırsa yeniden değerlendirilebilir
— o zaman gerçek bir aday olur.

---

## Doğru yapılmış olanlar

Bunlar rapordan çıkarılmamalı — mevcut kalitenin kaydı:

- **Sparkline** ([asset_sparkline.dart](lib/widgets/asset_sparkline.dart)):
  `fl_chart` yerine `CustomPainter` + `RepaintBoundary`. 20 satırlık listede
  doğru karar; dosyada gerekçesi de yazılı.
- **Curve tutarlılığı:** `easeOutCubic`(6) / `easeOut`(5) / `easeInOutCubic`(2) —
  giren öğelerde decelerate ailesi, HIG #75'e uygun.
- **Sayfa geçişleri:** `adaptiveRoute` ile iOS→Cupertino, Android→Material.
  HIG #80 "match system transition styles" tam karşılığı.
- **Loading davranışı:** Spinner yerine boş alan/skeleton tercihleri
  (`asset_sparkline`, `leaderboard_hero_card`) — layout shift'i önlüyor.
- **`AnimationController` dispose'ları:** 2 kullanımın ikisinde de doğru.

---

## Yapılanlar (2026-08-10)

1. ✅ **Reduce-motion koruması** — `SandikMotion.of/pressOf/stateOf/surfaceOf`
   eklendi, 19 dosyada 33 çağrı yerine uygulandı. Kapsam %15 → %100.
2. ✅ **Regresyon testi** — `test/reduce_motion_coverage_test.dart` (5 test).
   Kaynak taraması yeni korumasız animasyonu yakalıyor; kanarya ile doğrulandı.
3. ❌ Madde 2 ve 4 geçersiz çıktı (yukarıda açıklandı) — iş yapılmadı.

**Doğrulama:** `flutter analyze` 13 → 5 issue (yeni `const` fırsatları da
temizlendi), 295 test geçiyor, emülatörde çalışıyor.

## Açık kalanlar

**Yok — rapor kapandı (2026-08-10).**

| # | Madde | Sonuç |
|---|---|---|
| 1 | Reduce-motion kapsamı | ✅ Çözüldü (%100) |
| 2 | `AnimatedSwitcher` curve | ❌ Hatalı tespit |
| 3 | Splash 1800 ms | ✅ Çözüldü → 600 ms (`168a263`) |
| 4 | Duration ölçeği | ❌ Hatalı tespit |
| 5 | Hero animasyonu | ❌ Dayanağı geçersiz — uçacak paylaşılan öğe yok |

Beş maddenin **üçü** (2, 4, 5) incelendiğinde geçersiz çıktı. Bunları
silmek yerine gerekçesiyle bırakıyorum: aynı yanlış tespitin ileride
tekrar önerilmesini engeller.

### Bu raporun dışında kalan iş

- **Ölü kod:** [asset_detail_screen.dart](lib/screens/asset_detail_screen.dart)
  hiçbir yerden çağrılmıyor. Silinmesi ayrı bir karar (kullanıcı onayı
  gerektirir) — buraya değil `TECHNICAL_DEBT.md`'ye yazılmalı.
