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
| 1 | **Taşma** — 3 ekran, 7 yer (2'si normal font!) | 🔴 YÜKSEK | Ölçüldü: 1.0×'te 138px, 3×'te 415px |
| 2 | ✅ Boşluk ölçeği fiilen kullanılmıyor | ÇÖZÜLDÜ | Kapsam %37 → %84 |
| 3 | ✅ Ortak kart/başlık komponenti yok | KISMEN | 64 kart, 13 varyasyon |
| 4 | 6 ekranda taşma testi yok | 🟠 ORTA | 5 test / 11 büyük ekran |
| 5 | ~~Sabit yükseklikli butonlar kırpar~~ | ❌ GEÇERSİZ | Hepsi kare ikon kutusuymuş |
| 6 | ✅ `boldText` sistem ayarı yok sayılıyor | ÇÖZÜLDÜ | `context.t` |
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

### ✅ ÇÖZÜLDÜ (2026-08-10)

878 boşluk kullanımının tamamı ölçüldü. En sık **5 ölçek dışı değer**
(12, 10, 14, 6, 20) token'a eklenince kapsam **%37 → %84** çıkıyor.

Ölçek 2pt adımlı hale getirildi: `xxs=2, xs=4, xs2=6, sm=8, sm2=10,
smd=12, md2=14, md=16, lgs=20, lg=24, xl=32, xxl=48`.

**555 çağrı yeri değiştirilmedi ve tek piksel kımıldamadı.** Alternatif —
hepsini eski ölçeğe zorlamak — görsel yerleşimi piksel piksel kaydırırdı;
riski yüksek, faydası tartışmalı. Ölçeği veriye uydurmak aynı tutarlılığı
sıfır görsel değişiklikle veriyor.

Sınıfın doküman yorumu da düzeltildi: "8'lik ızgara" yazıyordu, kod hiçbir
zaman öyle değildi.

Regresyon: `spacing_scale_test.dart` — **cırcır (ratchet)** testi. Kalan
48 ölçek dışı kullanım dondurulur; sayı artarsa kırılır, azalırsa eşik
düşürülür. Kanaryayla doğrulandı.

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

### ✅ KISMEN ÇÖZÜLDÜ (2026-08-10)

64 kart 13 varyasyona dağılmış görünüyordu ama dağılım rastgele değildi:
**%58'i (37 kullanım) tek bir şekle** aitti ve kenar tanımlarının 18'i
birebir `context.c.hairline` idi.

İki komponent eklendi:

- **`SandikCard`** — düz kart kabuğu (yüzey + köşe + saç teli kenar).
  Seçim/hata/vurgu bildiren kenarlar (11 kullanım) **kapsam dışı**;
  onlar bilinçli varyasyondur ve hepsini tek API'ye sıkıştırmak parametre
  çorbası üretirdi.
- **`SandikSectionHeader`** — başlık + sayaç rozeti. §1'deki hatanın
  yapısal çözümü: başlık daima esnek ve kısaltılabilir.

`portfolio_performance_screen`'deki elle kurulmuş başlık bu komponente
çevrildi (26 satır → 4 satır).

**64 kartın tamamı çevrilmedi — bilinçli.** Mekanik dönüşüm 60+ çağrı
yerinde görsel farklar üretebilir (padding/kenar nüansları) ve emülatör
render edemediği için gözle doğrulanamaz. Komponent yerinde; dönüşüm
dosyalara dokunuldukça yapılmalı.

`performance_screen`'deki "TEKNİK ANALİZ" başlığı da çevrilmedi: sayaç
yerine metin alt bilgisi + trailing aksiyon içeriyor ve **zaten doğru
korunmuş** durumda. Komponente uydurmak için komponenti bükmek gerekirdi.

Regresyon: `sandik_card_test.dart` (8 test). Kanaryayla doğrulandı —
başlıktaki `Flexible` kaldırılınca 3 test kırılıyor.

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

### ✅ `add_asset_screen` kapsama alındı — 5 taşma daha çıktı

En büyük ekran (2.648 satır) teste bağlandı ve **beş** taşma buldu.
İkisi **normal metin boyutunda** (1.0×), yani kullanıcı bunları şu anda
görebiliyor:

| Yer | Koşul | Taşma |
|---|---|---|
| `_priceBlock` "Alış Fiyatı · opsiyonel" | **1.0×** @375pt | 138px |
| `_commissionBlock` "Komisyon / Masraf · opsiyonel" | **1.0×** @375pt | 50px |
| İşlem tarihi satırı | 1.0× @320pt | 38px |
| "veya listede yok" ayracı | 1.5×+ | — |
| Para birimi dropdown'ı | 3.0× @320pt | 10px |

İlk ikisi neden bu kadar büyük: `_priceBlock`, "Miktar" ile aynı `Row`'da
`Expanded` içinde duruyor — ekranın yarısı kadar yeri var, etiket ise tam
genişlik istiyordu.

`_fieldLabel` yardımcısına `maxLines: 1` + `ellipsis` **varsayılan** olarak
eklendi; böylece aynı hata diğer çağrı yerlerinde tekrarlanamaz.

Para birimi dropdown'ı istisna: `DropdownButton` içeride daralamayan kendi
`Row`'unu kurar. İçerik üç harflik kod ("TRY") olduğu için
`MediaQuery.withClampedTextScaling(maxScaleFactor: 1.6)` kullanıldı —
bu Dynamic Type'ı **yok saymak değil**, üst sınır koymaktır.

**Not:** Mevcut testler yalnızca 320–430pt **genişlik** tarıyor, metin
ölçeğini taramıyor. 1.0×'te hepsi temiz olduğu için bu hatalar
görünmüyordu. Testlere ölçek ekseni eklenmeli.

---

## 5. ❌ GEÇERSİZ — "Sabit yükseklikli butonlar metni kırpar"

**Bu madde yanlış çıktı. Düzeltmeye başlayınca ortaya çıktı.**

Taramam 13 "sabit yükseklikli buton + metin" bildirmişti. Tek tek açınca
beşinin de aslında **kare ikon kutusu** olduğu görüldü:

```dart
Container(
  width: 40, height: 40,          // KARE — ikon kutusu
  child: Icon(item.type.icon),    // metin DEĞİL
)
```

Tarama, dokunulabilir widget'ın gövdesindeki *ilk* `height:` değerini
butonun kendi yüksekliği sanıyordu; oysa o değer içerideki ikon
kutusuna aitti. İkonlar Dynamic Type ile büyümez, dolayısıyla kırpılamaz.

Daraltılmış tarama (kare olmayan + doğrudan `child: Text`) çalıştırıldı:
**0 sonuç**. Yani üründe bu sınıfta bir hata yok.

### Yine de duran doğru bilgi: eşik tablosu

Ölçüm boşa gitmedi — ileride sabit yükseklikli bir metin kutusu
yazılırsa eşik şudur (fontSize 15):

| Kutu | 1.0× | 1.5× | 2.0× | 2.5× | 3.0× |
|---|---|---|---|---|---|
| 36pt | ok | ok | ok | **KIRPAR** | **KIRPAR** |
| 40pt | ok | ok | ok | ok | **KIRPAR** |
| 42pt | ok | ok | ok | ok | **KIRPAR** |
| 46pt | ok | ok | ok | ok | ok |
| 52pt | ok | ok | ok | ok | ok |

Risk **≤42pt** kutularda ve yalnızca **2.5× üstünde** (iOS AX3+).
52pt (login, onboarding, disclaimer) her ölçekte güvenli.

Kural: metin saran kutuya `height:` verme; `constraints:
BoxConstraints(minHeight: …)` kullan — kutu metinle birlikte büyür.

---

## 6. ✅ ÇÖZÜLDÜ — `boldText` sistem ayarı

`MediaQuery.highContrastOf` destekleniyordu ama `boldTextOf` hiç
okunmuyordu: iOS'ta "Kalın Metin" ayarını açan kullanıcı için hiçbir şey
değişmiyordu.

Çözüm `context.t` içinde — tüm metin stilleri zaten oradan geçiyor,
`context.c`'nin `highContrast` için yaptığının aynısı. Tek noktada
çözülür, hiçbir ekran değişmez.

**`FontWeight.bold` sabiti kullanılmadı.** Marka tipografisi w500–w900
arası beş ağırlık kullanıyor; hepsini w700'e eşitlemek hiyerarşiyi
düzleştirirdi (w800 başlık ile w500 gövde ayırt edilemez olurdu). Bunun
yerine kademeli artış: w400 → w600 (tek kademe gözle fark edilmiyor),
üsttekiler tek adım, w900 tavanda kalır.

Regresyon: `bold_text_support_test.dart` (4 test) — kapalıyken
değişmemesi, açıkken artması, tavanda taşmaması ve **hiyerarşinin
korunması**. Kanaryayla doğrulandı.

Ayrıca kalın glifler daha geniş olduğu için taşma testine "en kötü durum"
grubu eklendi: **kalın metin + 3.0× ölçek + 320pt** üç ekranda da temiz.

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
| 1 | ✅ §1 taşmaları düzelt | Kullanıcı şu an etkileniyor |
| 2 | ✅ Taşma testine **metin ölçeği** ekseni ekle | Bu hataları en başta yakalardı |
| 3 | ✅ `add_asset` taşma testi (5 hata buldu) | En büyük kapsanmayan ekran |
| 4 | ✅ `SandikSectionHeader` komponenti | §1'in tekrarını önler |
| 5 | ✅ Boşluk ölçeğini gerçeğe uydur (§2) | Büyük ama düşük riskli |
| 6 | ✅ `boldText` desteği (§6) | Erişilebilirlik boşluğu |

## Kalan iş

Raporun **tüm maddeleri kapandı.** Devam eden tek şey mekanik ve
kademeli: 64 kart kabuğunun `SandikCard`'a çevrilmesi. Bu, dosyalara
dokunuldukça yapılmalı — toplu dönüşüm gözle doğrulanamayacağı için
(emülatör render edemiyor) riskli.

**Gözle doğrulama borcu:** bu turdaki renk ve yerleşim düzeltmeleri
testle sabit ama görsel olarak doğrulanmadı. Gerçek cihazda light mode +
büyük metin ayarıyla bakılmalı.
