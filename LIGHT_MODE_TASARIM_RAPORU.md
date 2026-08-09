# Light Mode — Komponent Tasarım Raporu

**Tarih:** 2026-08-09
**Kapsam:** sandık için light mode tasarımı — palet, komponent envanteri, mimari
engel analizi ve aşamalı uygulama planı.
**Durum:** Tasarım önerisi. **Kod değiştirilmedi** — onay bekliyor.

Kaynaklar: `ui-ux-pro-mcp` (iOS HIG renk sistemi), `apple-design` skill
(materyal/derinlik/kontrast prensipleri), `sandik.dart` tasarım sistemi.

---

## 0. Yönetici özeti

Üç şey öne çıktı:

1. **Altyapının yarısı zaten hazır.** `themeModeProvider` (light/dark/system)
   yazılmış ve `SharedPreferences`'a kaydediyor — ama `main.dart` `ThemeMode.dark`
   sabitliyor ve `theme:` ile `darkTheme:` slotlarına **aynı** dark temayı veriyor.
   Yani ayar var, bağlanmamış.
2. **Asıl engel token mimarisi.** `Sandik.*` renkleri `static const` — derleme
   zamanında sabit. Light mode `BuildContext`'e bağlı çözümleme ister.
   Bu, tek dosyalık bir değişiklik değil.
3. **Bonus bulgu:** Mevcut **dark** paletindeki `gain` ve `loss` metin olarak
   zaten WCAG AA'yı geçmiyor (4.30:1 ve 3.90:1 — eşik 4.5:1). Light mode
   çalışması bunu da düzeltmek için doğal fırsat.

---

## 1. Mimari engel — neden basit bir renk değişimi değil

### 1.1 Tokenlar derleme-zamanı sabiti

```dart
static const Color background = Color(0xFF0A1E15);  // her zaman koyu
```

`const` olduğu için `Theme.of(context).brightness`'a bakamaz. Light mode
tokenların **context'e duyarlı** hale gelmesini gerektirir.

### 1.2 Ölçülen kullanım hacmi

| Desen | Adet | Light'ta ne olur |
|---|---:|---|
| `Sandik.text90/58/36/20` | 342 | Beyaz opaklıklar — açık zeminde **okunmaz** |
| `Sandik.background/surface1/surface2/dark` | 167 | Koyu yüzeyler — ters çevrilmeli |
| `Colors.white…` (düz: `white`, `white70`, `white12`) | 220 | Açık zeminde **görünmez** |
| `Colors.white.withValues(...)` (yüzey overlay) | 139 | Açık zeminde **etkisiz** |
| `Colors.black.withValues(...)` | 16 | Light'ta fazla sert |
| `BackdropFilter` (glass) | 6 | Tint/border ters çevrilmeli |
| **Toplam renk çağrısı** | **~884** | |

En kritik grup **220 düz `Colors.white`** — bunlar token bile değil, doğrudan
beyaz. Light modda beyaz kartın üstünde beyaz metin demek.

### 1.3 Yüzey mantığı ters

Dark'ta hiyerarşi **beyaz overlay ekleyerek** kuruluyor:

```dart
color: Colors.white.withValues(alpha: 0.045)   // surfaceCard
```

Light'ta bu görünmez. Light'ta yükseklik ters yönde çalışır: yüzey
**daha beyaz + gölge** ile yükselir. `apple-design`'ın "materyal ağırlığı
hiyerarşiyi taşır" kuralı burada yön değiştiriyor:

| | Dark | Light |
|---|---|---|
| Seviye 0 (zemin) | en koyu | en **koyu**(ca) — sıcak kağıt |
| Seviye 1 (kart) | +beyaz overlay | daha **beyaz** + yumuşak gölge |
| Seviye 2 (hero) | ++beyaz overlay | saf beyaz + belirgin gölge |
| Ayırıcı | beyaz %6 | siyah %8 |

---

## 2. Önerilen light paleti

Marka kimliği korunur: amber/gold CTA, yeşil-temelli nötrler, DM Sans.
**Nötr gri kullanılmadı** — sandık'ın nötrleri yeşile çalar; light modda saf gri
markayı yabancılaştırırdı. Zemin, var olan `Sandik.adacayi` (#E8EDE5) tonundan
sıcak kağıda türetildi.

### 2.1 Yüzey ve metin

| Token | Light değeri | Rol |
|---|---|---|
| `background` | `#F4F1EA` | Seviye 0 — sıcak kağıt |
| `surface1` | `#FBFAF6` | Seviye 1 — kart |
| `surface2` | `#FFFFFF` | Seviye 2 — hero/elevated |
| `text90` | `#12241E` | Ana metin (koyu marka yeşili, saf siyah değil) |
| `text58` | `#4A5B54` | İkincil etiket |
| `text36` | `#6E7E77` | Üçüncül yardımcı |
| `text20` | `#9AA8A2` | Devre dışı |

### 2.2 Anlamsal renkler — light için koyulaştırıldı

Dark tonları beyaz zeminde okunmuyor (ölçüldü, §3). Aynı **algısal** renk,
farklı aydınlık:

| Token | Dark | Light | Neden |
|---|---|---|---|
| `amber` (metin/ikon) | `#F5A623` | `#8A5A00` | Dark amber beyazda **1.94:1** |
| `gain` | `#2D9E6C` | `#0F7A4E` | Dark yeşil beyazda 3.23:1 |
| `loss` | `#E8503A` | `#C0341F` | Dark kırmızı beyazda 3.57:1 |
| `danger` | `#EF4444` | `#C42B22` | — |
| `info` | `#4EA8DE` | `#1B6FA8` | — |

**Önemli ayrım:** `amber` **dolgu** olarak (CTA butonu zemini) `#F5A623`
kalır — marka rengi orada kimliktir ve üstüne koyu metin gelir (7.99:1).
Koyulaştırılan yalnızca amber'in *metin/ikon* kullanımıdır. Bu ayrım için
ayrı token gerekir: `amberFill` (sabit) ve `amberText` (adaptif).

---

## 3. Kontrast doğrulaması (WCAG)

Hesaplandı ve çalıştırıldı (WCAG 2.1 relative luminance):

### Light — hepsi geçiyor
| Kombinasyon | Oran | Eşik | |
|---|---:|---|---|
| text90 / background | 14.36:1 | 4.5 | ✅ |
| text90 / surface1 | 15.50:1 | 4.5 | ✅ |
| text90 / surface2 | 16.19:1 | 4.5 | ✅ |
| text58 / background | 6.39:1 | 4.5 | ✅ |
| text58 / surface1 | 6.90:1 | 4.5 | ✅ |
| text36 / background | 3.79:1 | 3.0¹ | ✅ |
| gain / surface1 | 5.14:1 | 4.5 | ✅ |
| loss / surface1 | 5.36:1 | 4.5 | ✅ |
| danger / surface1 | 5.41:1 | 4.5 | ✅ |
| info / surface1 | 5.17:1 | 4.5 | ✅ |
| amberText / surface1 | 5.67:1 | 4.5 | ✅ |
| text90 / amber dolgu | 7.99:1 | 4.5 | ✅ |

¹ `text36` yalnızca yardımcı/dekoratif metin için — AA'nın 3:1 büyük-metin
eşiğine göre değerlendirildi. Kritik bilgi bu tonda yazılmamalı.

### Mevcut dark — iki gerçek hata
| Kombinasyon | Oran | |
|---|---:|---|
| gain / surface1 | **4.30:1** | ❌ AA altı |
| loss / surface1 | **3.90:1** | ❌ AA altı |

Kâr/zarar rakamları uygulamanın **en önemli** verisi ve şu an eşiğin altında.
Öneri: dark `gain` → `#3DB77F`, `loss` → `#FF6B52` (aynı karakter, daha parlak).
Bu, light mode'dan bağımsız olarak da yapılmalı.

---

## 4. Komponent envanteri

Light modda **davranışı değişmesi gereken** komponentler. "Otomatik" = token
adaptif olunca kendiliğinden düzelir; "elle" = ayrı light kararı gerekir.

### 4.1 Tema altyapısı — elle
| Komponent | Yapılacak |
|---|---|
| `main.dart:_buildTheme()` | `brightness` parametresi alacak; `theme:`/`darkTheme:` ayrı üretilecek |
| `main.dart:241-243` | `themeMode: ref.watch(themeModeProvider)` — sabit `dark` kalkacak |
| `SystemUiOverlayStyle` (159, 379) | Status bar ikonları light'ta koyulaşmalı — aksi halde beyaz ikon beyaz zeminde kaybolur |
| `ColorScheme` (260-288) | `Brightness.light` varyantı |

### 4.2 `sandik.dart` yardımcıları — elle
| Yardımcı | Sorun | Light karşılığı |
|---|---|---|
| `surfaceCard()` | `Colors.white %4.5` | Beyaz dolgu + `BoxShadow` (yükseklik gölgeyle) |
| `chip()` | `Colors.white %5.5` | Siyah %4 dolgu + accent kenarlık |
| `glassDecoration()` | Beyaz tint, siyah gölge | Beyaz tint %70 + daha yumuşak gölge |
| `glassBox()` | Aynı | `prefers-reduced-transparency` karşılığı da düşünülmeli |
| `inputDecoration()` | `fillColor: black %10`, beyaz kenarlık | Beyaz dolgu + siyah %12 kenarlık |
| `SandikLoadingScreen` | Koyu zemin varsayımı | Light logo varyantı |

### 4.3 Ekran/widget komponentleri
| Komponent | Durum | Not |
|---|---|---|
| `PortfolioSummaryWidget` | **elle** | `BackdropFilter` + `#14332B` sabit hero rengi; light'ta beyaz cam + gölge |
| `leaderboard_hero_card` | **elle** | Madalya gradyanları light'ta parlaklık kaybeder |
| `asset_sparkline` | **elle** | Çizgi/dolgu opaklıkları açık zeminde soluk kalır |
| `zoomable_chart` / `fl_chart` | **elle** | Grid, eksen, tooltip zemini — chart'lar temayı otomatik almaz |
| `custom_loading_indicator` | **elle** | Beyaz varsayımı |
| `modern_tab_selector` | otomatik | Seçili sekme `Colors.black87` → tokena bağlanmalı |
| `transaction_row` | otomatik | |
| `sandik_async_button` | otomatik | |
| `premium_gate` / `paywall_screen` | **elle** | Gradyan + glass yoğun |
| `disclaimer_widget`, `sandik_error_view` | otomatik | |
| 24 ekran | çoğu otomatik | `legal_doc_screen` kendi paletini taşıyor (29 hardcoded renk) |

### 4.4 Platform yüzeyleri — elle
- **Bildirimler** (`notification_service`): `color:` marka amber — sistem
  bildiriminde light/dark'a göre değişmez, sabit kalmalı. Sorun yok, doğrulandı.
- **Uygulama ikonu / splash**: light mode'da değişmez (marka).
- **`adaptiveRoute`**: Cupertino geçişleri temadan brightness alır — otomatik.

---

## 5. Uygulama planı

Tek seferde 884 çağrıyı değiştirmek yüksek riskli. Aşamalı öneri:

### Aşama 1 — Token mimarisini adaptif yap *(temel; davranış değişmez)*
`Sandik.*` sabitlerini koruyup yanına context-duyarlı çözümleyici ekle:

```dart
// Öneri: mevcut sabitleri SİLME (342+167 çağrı kırılır).
// Bunun yerine bir tema uzantısı ekle:
extension SandikColors on BuildContext {
  SandikPalette get c => Theme.of(this).extension<SandikPalette>()!;
}
// kullanım: context.c.surface1, context.c.text90, context.c.gain
```

`ThemeExtension<SandikPalette>` Flutter'ın resmî yolu; `lerp()` sayesinde
tema geçişi de animasyonlu olur (`apple-design`: "ease dark↔light theme changes").
Bu aşamada dark palet aynen kalır — **görsel hiçbir değişiklik olmaz**, sadece
altyapı hazırlanır. Regresyon riski en düşük nokta burası.

### Aşama 2 — Light paletini tanımla + tema anahtarını bağla
`SandikPalette.light` / `.dark` üretilir, `main.dart` iki tema kurar,
`themeMode` provider'a bağlanır, status bar düzeltilir.
Bu noktada light mode **çalışır ama eksik** görünür (henüz migrate edilmemiş
ekranlar kırık kalır) — bu yüzden Aşama 3 ile birlikte sevk edilmeli.

### Aşama 3 — Komponentleri migrate et *(hacimli kısım)*
Öncelik sırası — kullanıcının en çok gördüğü yüzeyden başlayarak:
1. `sandik.dart` yardımcıları (6 metot) — en yüksek kaldıraç, hepsi buradan besleniyor
2. `home_screen` + `PortfolioSummaryWidget` + `main_navigation_screen`
3. `charts_screen`, `performance_screen`, `portfolio_performance_screen` (chart'lar)
4. `leaderboard` + hero card
5. Auth ekranları
6. Kalan ekranlar
7. 220 düz `Colors.white` temizliği

### Aşama 4 — Doğrulama
- `design_token_leak_test.dart`'a **light kontrast testi** eklenir
  (her token çifti için WCAG oranı hesaplanır — bu rapordaki tablo teste dönüşür)
- Her iki modda golden test
- `disableAnimations` + light kombinasyonu

**Not:** Aşama 1 tek başına güvenli ve bağımsız olarak sevk edilebilir.
Aşama 2+3 birlikte gitmeli, aksi halde yarım light mode kullanıcıya ulaşır.

---

## 6. MCP/skill kullanımı — dürüst not

- **`ui-ux-pro-mcp` → iOS HIG (`search_platforms`):** faydalı oldu.
  `systemBackground` / `secondaryLabel` semantik renk yaklaşımı ve
  "hardcode #FFFFFF/#000000 kullanma" kuralı bu tasarımın omurgası.
- **`ui-ux-pro-mcp` → `get_design_system`:** **kullanılmadı.** Flutter +
  light mode sorulmasına rağmen CSS değişkenleri, navbar/footer HTML'i,
  `#FAF9F6` bej palet ve hover efektleri döndü — `SKILLS_README.md`'de
  öngörülen web-çıktısı tuzağı. Önerdiği palet marka kimliğiyle ilgisizdi.
- **`apple-design` skill:** materyal/derinlik (§12), reduced-transparency ve
  tema geçişini yumuşatma kuralları doğrudan uygulandı.
- **`design-system` skill:** üç katmanlı token mimarisi (primitive → semantic →
  component) Aşama 1'deki `ThemeExtension` önerisinin gerekçesi.
- **`codebase-memory-mcp`:** bu turda kullanılmadı; envanter `grep` ile
  çıkarıldı çünkü aranan şey sembol ilişkisi değil, renk **çağrı sayısıydı**.

---

## 7. Karar bekleyen noktalar

1. **Kapsam:** Sadece Aşama 1 (güvenli altyapı) mı, yoksa tam light mode mu?
2. **Dark `gain`/`loss` AA düzeltmesi** ayrı ve öncelikli olarak yapılsın mı?
   (Light mode'dan bağımsız gerçek bir erişilebilirlik hatası.)
3. **Varsayılan mod:** `dark` sabit mi kalsın, yoksa `ThemeMode.system` mi
   olsun? Marka "dark-first" (kod yorumunda yazıyor) — sistem takibi bunu
   değiştirir, ürün kararı.
