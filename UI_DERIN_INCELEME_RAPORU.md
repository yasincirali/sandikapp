# Sandık — UI Derin İnceleme Raporu

**Tarih:** 2026-08-10
**Kapsam:** `lib/` altındaki 25 ekran (23.177 satır) + 16 widget (3.622 satır)
**Yöntem:** Kaynak taraması + **çalıştırılarak ölçüm** (widget testi ile
gerçek yerleşim, gerçek metin ölçekleri)

> Bu rapordaki her sayı ölçülmüştür. "Muhtemelen taşar" demiyorum —
> taşıyorsa kaç piksel taştığını, taşmıyorsa taşmadığını yazıyorum.
> Yanlış çıkan iki kendi tahminimi de bıraktım (bkz. §7).

---

## Özet

| # | Bulgu | Önem | Kanıt |
|---|---|---|---|
| 1 | **Büyük metin ayarında taşma** — 2 ekran | 🔴 YÜKSEK | Ölçüldü: 1.5×'te 61px, 3×'te 415px |
| 2 | Boşluk ölçeği fiilen kullanılmıyor (%92 ham sayı) | 🟠 ORTA | 493 ham / 44 token |
| 3 | 66 kart kabuğu elle kuruluyor — ortak komponent yok | 🟠 ORTA | Sayıldı |
| 4 | 6 ekranda taşma testi yok | 🟠 ORTA | 5 test / 11 büyük ekran |
| 5 | Sabit yükseklikli butonlar (≤42pt) büyük fontta kırpar | 🟡 DÜŞÜK | Eşik ölçüldü: 2.5× |
| 6 | `boldText` sistem ayarı yok sayılıyor | 🟡 DÜŞÜK | Kaynak |
| 7 | Ölü ekran (`asset_detail_screen`) | 🟡 DÜŞÜK | 0 çağrı yeri |

**En önemlisi 1. madde.** Diğerleri bakım/tutarlılık borcu; 1. madde
**kullanıcının şu anda göremediği** gerçek bir kırılma.

---

## 1. 🔴 Büyük metin ayarında taşma — İKİ EKRAN

iOS'ta metin boyutu ayarı (Dynamic Type) **sık kullanılan** bir ayardır;
1.5× "olağandışı" değil, gözü yorulan herkesin açtığı kademedir.

`PortfolioPerformanceScreen` ve `ChartsScreen` bu ayarda taşıyor:

### PortfolioPerformanceScreen

| Genişlik | 1.0× | 1.5× | 2.0× | 3.0× |
|---|---|---|---|---|
| 320pt | temiz | **116px** | **234px** | **470px** |
| 375pt | temiz | **61px** | **179px** | **415px** |
| 430pt | temiz | **5.6px** | **124px** | **360px** |

**Kaynak:** [portfolio_performance_screen.dart:2262](lib/screens/portfolio_performance_screen.dart#L2262)

```dart
Row(
  children: [
    Text('TEKNİK SİNYALLER', ...),   // Expanded YOK
    const SizedBox(width: 8),
    Container(child: Text('${results.length}')),  // sayaç rozeti
  ],
)
```

Başlık + sayaç rozeti kısıtsız bir `Row`'da. Metin büyüdükçe başlık
genişler, rozeti sağa iter, satır taşar.

**Bu desen daha önce de görüldü.** `TECHNICAL_DEBT.md` `performance_screen`
için aynı hatayı kaydetmiş: *"TEKNİK ANALİZ başlığı — başlık + sayaç ayar
bağlantısını itiyor"*. Orada düzeltildi, **burada tekrar yazıldı**. Sebep
3. madde: ortak bir "bölüm başlığı" komponenti olmadığı için her ekran
kendi versiyonunu kuruyor ve aynı hatayı tekrarlıyor.

### ChartsScreen

| Genişlik | 1.0× | 1.5× | 2.0× | 3.0× |
|---|---|---|---|---|
| 320pt | temiz | temiz | **45px** | **199px** |
| 375pt | temiz | temiz | temiz | **144px** |

**Kaynak:** [charts_screen.dart:550](lib/screens/charts_screen.dart#L550) —
grafik lejantındaki varlık türü çipleri (`Row(mainAxisSize: min)`), etiket
uzayınca sığmıyor.

### ✅ ÇÖZÜLDÜ (2026-08-10)

- `portfolio_performance_screen`: başlık `Flexible` + `ellipsis`. Rozet
  sabit kalır; daralması gereken taraf başlıktır.
- `charts_screen`: lejant etiketi `Flexible` + `ellipsis`.

**Kanarya, fazladan bir düzeltmeyi eledi.** Lejanta önce `LayoutBuilder`
+ `ConstrainedBox(maxWidth:)` eklemiştim. Kanarya testi (kısıtı kaldır →
test kırılmalı) **kırılmadı**: yani o kısıt hiçbir işe yaramıyordu, taşmayı
tek başına `Flexible` çözüyordu. Gereksiz katman geri alındı — kanarya
olmasaydı iki widget'lık ölü karmaşıklık kodda kalacaktı.

Regresyon: `text_scale_overflow_test.dart` (24 senaryo — 3 genişlik ×
4 ölçek × 2 ekran). İki ekran için de kanaryayla doğrulandı.

---

## 2. 🟠 Boşluk ölçeği fiilen kullanılmıyor

`SandikSpace` tanımlı (4/8/16/24/32/48) ama **kullanılmıyor**:

```
SizedBox boşlukları:  ham sayı 493  |  token 44   → %92 ham
EdgeInsets.all():     ham sayı  58  |  token  1   → %98 ham
```

Köşe yarıçapı tam tersi — **61/62 token** (`SandikRadius.md/lg/sm`).
Yani ekip token kullanmayı biliyor; boşlukta alışkanlık oturmamış.

### Ama asıl mesele "ham sayı" değil, ölçek dışılık

Ham değerlerin **%59'u** ölçeğe uymuyor:

| Değer | Kaç kez | Ölçekte mi? |
|---|---|---|
| 12 | 72 | ❌ |
| 6 | 47 | ❌ |
| 10 | 45 | ❌ |
| 14 | 27 | ❌ |
| 2 | 23 | ❌ |

12 ve 6 tek başına **119 kullanım**. Bu rastgelelik değil — pratikte
**2pt adımlı gayriresmî bir ölçek** var ve resmî ölçek (4pt adım) onu
karşılamıyor.

**Öneri:** 493 kullanımı yeniden yazmak yerine **ölçeği gerçeğe uydur**:
`xs=4, sm=8, md=16...` yanına `xxs=2, xs2=6, smd=12` gibi ara adımlar ekle,
sonra en sık 3-4 değeri token'a çevir. Büyük patlama refactor'ı bu iş için
maliyet/fayda açısından yanlış.

---

## 3. 🟠 66 kart kabuğu elle kuruluyor

`BoxDecoration + surface + borderRadius` üçlüsü **66 yerde** elle yazılmış:

| Dosya | Kez |
|---|---|
| `add_asset_screen` | 10 |
| `portfolio_performance_screen` | 9 |
| `leaderboard_screen` | 6 |
| `performance_screen` | 6 |
| `profile_screen` | 6 |

Ortak bir `SandikCard` yok. Sonucu 1. maddede görüldü: aynı yerleşim hatası
iki ekranda ayrı ayrı yazıldı ve biri düzeltilince diğeri düzelmedi.

**Ekran/widget oranı da bunu söylüyor:** 23.177 satır ekran koduna karşılık
yalnızca 3.622 satır paylaşılan widget.

---

## 4. 🟠 Taşma testi olmayan ekranlar

Beş taşma testi var ve **değerini kanıtlamış** — `TECHNICAL_DEBT.md`'ye göre
yazıldıklarında gözle görülmeyen **beş gerçek hata** ortaya çıkarmışlar.

Kapsanan: `home`, `charts` (kart), `leaderboard`, `performance`,
`transaction_row`.

**Kapsanmayan:** `add_asset` (2.648 satır), `portfolio_performance`
(2.509), `profile`, `settings`, `signal_settings`, `charts` (lejant).

Bu boşluk soyut değil: 1. maddedeki iki hata tam olarak kapsanmayan
yerlerde çıktı ve bu incelemede **ilk denemede** bulundu.

**Not:** Mevcut testler yalnızca 320–430pt **genişlik** tarıyor, metin
ölçeğini taramıyor. 1.0×'te hepsi temiz olduğu için bu hatalar
görünmüyordu. Testlere ölçek ekseni eklenmeli.

---

## 5. 🟡 Sabit yükseklikli butonlar

13 buton sabit yükseklikli ve içinde metin var. **Ölçtüm** — hangi
yükseklik hangi ölçekte kırpıyor (fontSize 15):

| Kutu | 1.0× | 1.5× | 2.0× | 2.5× | 3.0× |
|---|---|---|---|---|---|
| 36pt | ok | ok | ok | **KIRPAR** | **KIRPAR** |
| 40pt | ok | ok | ok | ok | **KIRPAR** |
| 42pt | ok | ok | ok | ok | **KIRPAR** |
| 46pt | ok | ok | ok | ok | ok |
| 52pt | ok | ok | ok | ok | ok |

Risk **≤42pt** kutularda ve yalnızca **2.5× üstünde** (iOS AX3+).

Etkilenen: `settings_screen:680` (36pt), `bulk_add_asset:428` (40pt),
`profile_screen:1017` (40pt), `quick_adjust_dialog:183` (40pt),
`add_asset_screen:2582` (42pt).

52pt butonlar (login, onboarding, disclaimer) **güvenli** — ölçüm bunu
gösterdi, ilk tahminim yanlıştı (§7).

**Düzeltme:** `height:` yerine `constraints: BoxConstraints(minHeight: …)`.

---

## 6. 🟡 `boldText` sistem ayarı yok sayılıyor

`MediaQuery.highContrastOf` destekleniyor ([sandik.dart:745](lib/theme/sandik.dart#L745)
→ `highContrast()` paleti). Ama `MediaQuery.boldTextOf` hiç okunmuyor.

iOS'ta "Kalın Metin" ayarı açık olan kullanıcı için yazı ağırlığı artmaz.
Küçük bir eksik; `fontWeight` haritalaması gerekir.

---

## 7. Yanlış çıkan kendi tahminlerim

Rapora güvenilmesi için bunları saklamıyorum:

**a) "52pt butonlar büyük fontta taşar" — YANLIŞ.**
İlk ölçümüm metin yüksekliğini 3×'te tam 52pt gösterdi ve "sınırda" dedim.
Sonra fark ettim ki `SizedBox` içindeki `Text`'i ölçmek yanıltıcı: sıkı
kısıt altında `getSize` gerçek yüksekliği değil, kutuya sığdırılmış hâli
veriyor. Kısıtsız ölçünce doğru sayı çıktı (3×'te 45pt) ve 52pt'nin
**güvenli** olduğu görüldü. Eşik tablosu (§5) bu ikinci ölçüme dayanıyor.

**b) "126 sabit yükseklikli metin kutusu var" — ŞİŞİRİLMİŞ.**
İlk tarama `TextStyle.height: 1.4` (satır yüksekliği) değerlerini kutu
yüksekliği sanıyordu ve aradaki `SizedBox` spacer'ları da sayıyordu.
Gerçek sayı 13.

**c) `ProfileScreen` taşma probu çalışmadı** — `TextField` Material
ata gerektiriyor, benim test iskeletim vermiyordu. Bu bir **ürün hatası
değil, test kurulum eksiği**. Rapora "temiz" diye yazmadım; ölçülemedi.

---

## Önerilen sıra

| Sıra | İş | Gerekçe |
|---|---|---|
| 1 | §1 taşmaları düzelt | Kullanıcı şu an etkileniyor |
| 2 | Mevcut taşma testlerine **metin ölçeği** ekseni ekle | Bu hataları en başta yakalardı |
| 3 | `add_asset` + `portfolio_performance` taşma testi | En büyük kapsanmayan ekranlar |
| 4 | `SandikSectionHeader` komponenti | §1'in tekrarını önler |
| 5 | §5 buton yükseklikleri → `minHeight` | Küçük, mekanik |
| 6 | Boşluk ölçeğini gerçeğe uydur (§2) | Büyük ama düşük riskli |

§3 (SandikCard) ve §6 (boldText) daha büyük kararlar — ayrı ele alınmalı.
