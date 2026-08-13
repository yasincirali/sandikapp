# Sandık — Marka Referansı (Live Activity / Dynamic Island brief)

Bu doküman, **iOS Live Activity + Dynamic Island** tasarımı yaptırmak
için hazırlanmış bağımsız bir brief'tir. Tüm değerler
`lib/theme/sandik.dart` içindeki gerçek üretim token'larından
alınmıştır — tahmin veya yaklaşık değer yoktur.

---

## 1. Ürün ve marka

| | |
|---|---|
| **Ürün adı** | Sandık (iOS görünen ad: `Sandık`) |
| **Bundle** | `com.sandik.app` |
| **Ne yapar** | Kişisel portföy takibi — hisse, fon, döviz, altın |
| **Kime** | Yatırım uzmanı olmayan, pratik finansal görünürlük isteyen beyaz yaka çiftler |
| **Motto** | *"Paranızı bir arada tutar."* |

**İsmin anlamı:** "Sandık" hem değerli şeylerin saklandığı kutu, hem de
iki parçayı birbirine kilitleyen metal parça çağrışımı taşır. Ürün
kimliği bu ikiliğin üstüne kurulu: **koruma + birliktelik**.

**Tasarım felsefesi:** Sıcak ama güvenilir. Erişilebilir ama ciddiye
alınabilir. *Bloomberg değil, birlikte büyüyen bir çiftin dijital not
defteri.*

> Live Activity için önemli sonuç: agresif "trading terminali" estetiği
> **marka dışıdır**. Kırmızı-yeşil yanıp sönen, yoğun veri kusan bir
> yüzey istemiyoruz. Sakin, sıcak, tek bir soruyu yanıtlayan bir yüzey.

---

## 2. Renk paleti (üretim değerleri)

### Dark mode — birincil kimlik

Marka koyu yeşil zemin üstüne amber/altın vurgu ile tanımlıdır.
Live Activity çoğunlukla bu modda görünecektir.

| Rol | Hex | Kullanım |
|---|---|---|
| `background` | `#0A1E15` | Seviye 0 — ekran zemini (en koyu yeşil) |
| `surface1` | `#112E28` | Seviye 1 — kart, liste satırı |
| `surface2` | `#1A3D2E` | Seviye 2 — hero kart, elevated yüzey |
| `brown` ("orman") | `#2D7A60` | Yardımcı yeşil, ayraç/aksan |
| **`amber`** | **`#F5A623`** | **Ana marka rengi** — CTA, aktif durum, logo ikonu |
| **`gold`** | **`#F5C842`** | Display sayılar, logo wordmark |
| `gain` | `#3DB77F` | Artış / kâr (kontrast 5.73:1) |
| `loss` | `#FF6B52` | Düşüş / zarar (kontrast 5.17:1) |
| `danger` | `#EF4444` | Yıkıcı eylem / hata |
| `info` | `#4EA8DE` | Bilgilendirme / nötr vurgu |

**Metin tonları (beyaz üstü alfa):**

| Token | Değer | Kullanım |
|---|---|---|
| `text90` | `#FFFFFF` @ 88% | Ana başlık, birincil sayı |
| `text58` | `#FFFFFF` @ 55% | İkincil etiket |
| `text36` | `#FFFFFF` @ 58% | Yardımcı metin (5.17:1) |
| `text20` | `#FFFFFF` @ 42% | Devre dışı |

> ⚠️ **Token adları alfa değeriyle uyuşmuyor.** `text36` aslında %58,
> `text20` ise %42 alfadır — erişilebilirlik için yükseltilmişler ama
> isimleri eski kalmış. Yani `text36`, `text58`'den **daha soluk
> değildir** (neredeyse aynı). Hiyerarşi kurarken isme değil,
> **yukarıdaki gerçek değerlere** bakın. Pratikte kullanılabilir üç
> kademe vardır: %88 → %55-58 → %42.

### Light mode

| Rol | Hex | Not |
|---|---|---|
| `background` | `#F4F1EA` | Sıcak kırık beyaz — saf beyaz **değil** |
| `surface1` | `#FBFAF6` | Kart |
| `surface2` | `#FFFFFF` | Elevated |
| `text90` | `#12241E` | 15.50:1 |
| `text58` | `#4A5B54` | 6.90:1 |
| `gain` | `#0F7A4E` | 5.14:1 |
| `loss` | `#C0341F` | 5.36:1 |
| `amberFill` | `#F5A623` | **Marka — her iki modda aynı** |
| `amberText` | `#4A3618` | Amber'in *metin* hali; light'ta koyulaşır |
| `gold` | `#4A3618` | Display sayı tonu |
| `onAmber` | `#12241E` | Amber zemin üstündeki metin (7.99:1) |

### ⚠️ Renk kullanımında iki kritik kural

**1. Amber asla metin rengi olarak doğrudan kullanılmaz.**
`#F5A623` beyaz/açık zeminde yalnızca **1.94:1** kontrast verir —
okunmaz. Amber bir **zemin** rengidir; üstüne koyu metin (`onAmber`
`#12241E`) gelir. Metin olarak amber gerekiyorsa light modda
`amberText` (`#4A3618`) kullanılır.

**2. Kazanç/kayıp rengi tek başına anlam taşımamalı.**
Renk körlüğü için yön her zaman bir işaretle (▲ ▼ veya +/−)
desteklenir. Live Activity'de bu özellikle önemli: küçük yüzeyde
renk tek sinyal olamaz.

### Madalya renkleri (leaderboard, gerekirse)

| | Ana | Gradient koyu uç |
|---|---|---|
| 1. | `#F5C842` | `#D9A520` |
| 2. | `#E8E8EA` | `#BFC0C4` |
| 3. | `#E0A574` | `#C07E3F` |

---

## 3. Tipografi

**Font ailesi: DM Sans** (tüm arayüz, tek aile).

Finansal sayılarda **tabular figürler zorunlu** —
`FontFeature.tabularFigures()`. Live Activity'de sayı saniyede bir
güncellenirse, tabular olmadan rakamlar yatayda zıplar. Bu marka için
pazarlık konusu değildir.

**Başlıklarda negatif letter-spacing:** display/başlık boyutlarında
`-0.01em` civarı sıkılaştırma kullanılır (ör. 18pt başlıkta `-0.18`).

Live Activity için önerilen hiyerarşi:
- **Birincil sayı** (toplam değer / günlük değişim): en büyük, `w700`, tabular, `text90` veya `gold`
- **Etiket** (ne olduğu): küçük, `w500`, `text58`
- **Yardımcı** (zaman damgası, "son güncelleme"): en küçük, `text36`

---

## 4. Şekil ve boşluk

**Köşe yarıçapı:**

| Token | Değer | Kullanım |
|---|---|---|
| `sm` | 8 | Küçük rozet, chip |
| `md` | 14 | Kart, buton |
| `lg` | 20 | Büyük kart, sheet |

Dialog/modal 20, bottom sheet üst köşeleri yuvarlatılır.

**Yükseklik (elevation):** Dark modda yükseklik **renkle** ifade edilir
(`background` → `surface1` → `surface2` giderek açılır), gölgeyle değil.
Light modda beyaz + yumuşak gölge kullanılır.

**Hairline ayraç:** dark `#FFFFFF` düşük alfa, light `#122419` @ %9.

---

## 5. Logo

Logo, bir kemer sandığı / kıskaç mekanizmasının stilize geometrik
temsilidir. **viewBox 80×50**:

```svg
<rect x="2" y="2" width="76" height="46" rx="10" fill="none" stroke="[RENK]" stroke-width="2.8"/>
<rect x="9" y="10" width="30" height="30" rx="5" fill="none" stroke="[RENK]" stroke-width="2.4"/>
<line x1="48" y1="25" x2="72" y2="25" stroke="[RENK]" stroke-width="4.5" stroke-linecap="round"/>
<circle cx="48" cy="25" r="4.5" fill="[RENK]"/>
```

- İkon rengi: **amber `#F5A623`**
- Wordmark ("sandık", küçük harf) rengi: **gold `#F5C842`**
- Dynamic Island compact alanında yalnızca **ikon** kullanılmalı;
  wordmark o ölçekte okunmaz.

> Not: Uygulama içi yükleme göstergesinde 200×200 tuvalde 150×150
> içerik oranı kullanılıyor (şeffaf kenar dolgusu telafisi). Statik
> logo varlıklarında bu geçerli değil.

---

## 6. Live Activity için tasarım yönergeleri

Bunlar marka tarafından **verilen** kısıtlardır; tasarımcı bunların
içinde serbesttir.

**Ton:** Sakin ve bilgilendirici. Live Activity kilit ekranında saatlerce
durur — yanıp sönen, dikkat çekmeye çalışan bir yüzey marka dışıdır.

**Tek soru kuralı:** Yüzey tek bir soruyu yanıtlamalı — muhtemelen
*"portföyüm bugün ne durumda?"*. İkincil veri Dynamic Island expanded
görünüme veya alt satıra iner.

**Zemin:** `#0A1E15` (background) veya `#112E28` (surface1). Marka
zemini yeşildir; nötr siyah kullanılmamalı.

**Vurgu:** Amber `#F5A623` yalnızca gerçekten vurgulanacak tek bir öğe
için. Her yere amber koymak marka hissini ucuzlatır.

**Sayı biçimi:** Türkçe format — binlik ayracı `.`, ondalık `,`
(ör. `1.234,56 ₺`). Tabular figür zorunlu.

**Dil:** Arayüz Türkçe. Kısa ve sade: "Toplam", "Bugün", "Değişim".

**Erişilebilirlik:** Tüm metin/zemin çiftleri en az **4.5:1**.
Yön bilgisi renkle **birlikte** ok/işaret taşımalı.

### Dynamic Island durumları

| Durum | İçerik önerisi |
|---|---|
| **Compact leading** | Logo ikonu (amber) |
| **Compact trailing** | Günlük değişim %, yön oku ile (`gain`/`loss`) |
| **Minimal** | Yalnızca logo ikonu veya tek yön göstergesi |
| **Expanded** | Toplam değer (büyük, tabular) + günlük değişim + son güncelleme zamanı |

---

## 7. Kaynak dosyalar

| Ne | Nerede |
|---|---|
| Renk/tipografi/şekil token'ları | `lib/theme/sandik.dart` |
| Kapsamlı marka + logo dokümanı | `sandik-design-prompt.md` |
| Uygulama kimliği | `pubspec.yaml`, `ios/Runner/Info.plist` |

**Bu brief'teki tüm renk değerleri üretim kodundan okunmuştur.**
Tasarımcı bunları yeniden yorumlamamalı; palet dışı renk gerekiyorsa
önce onay alınmalı.
