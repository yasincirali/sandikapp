# Ekran Görüntüsü Planı — sandık

Mağazada **ilk iki görsel** dönüşümün neredeyse tamamını belirler:
arama sonuç listesinde kullanıcı sadece o ikisini görür, açıklamayı
okumadan karar verir. Geri kalanı ancak galeriyi kaydıranlar görür.

Bu yüzden sıralama, "uygulamayı gezdirme" mantığıyla değil, **en güçlü
iddia önce** mantığıyla kurulmalı.

---

## Önerilen sıra (6 görsel)

### 1 — Ana ekran, dolu portföy · **EN KRİTİK**
**Neden ilk:** Kategori beklentisini tek bakışta karşılar; kullanıcı
"bu benim aradığım tür uygulama" der. Toplam değer + yeşil kâr rakamı +
varlık listesi aynı karede.

**Başlık metni:** `Tüm yatırımların tek ekranda`

**Kurulum:**
- 5–6 varlık, **karışık türler** (hisse, fon, altın, döviz) — çeşitliliği
  göstersin
- Portföy **kârda** olsun, ama abartısız (%8–15 arası inandırıcı;
  %300 sahte durur)
- Bakiye gizleme **kapalı** — rakamlar görünsün
- En az bir varlık zararda: gerçekçilik katar, "her şey pembe" izlenimi
  vermez

---

### 2 — Performans grafiği · **İKİNCİ KRİTİK**
**Neden ikinci:** Rakiplerden görsel olarak ayrıştığınız yer burası.
Grafik ekranı "ciddi bir araç" izlenimi verir ve liste ekranından sonra
en çok tıklanan karedir.

**Başlık metni:** `Zaman içinde ne kazandın, gör`

**Kurulum:**
- **En az 6 aylık** veri — kısa geçmiş grafiği zayıf gösterir
- Yukarı eğilimli ama dalgalı çizgi (düz yükseliş sahte görünür)
- Periyot seçici görünür olsun (1A / 3A / 1Y)
- Mümkünse crosshair açık bir noktada dursun — etkileşimi ima eder

---

### 3 — Gerçek kâr/zarar: komisyon + temettü · **FARKLILAŞTIRICI**
**Neden burada:** Bu sizin **tek gerçek rakip farkınız**. Çoğu uygulama
"alış − güncel fiyat" yapıp kâr diyor. Bunu görselleştirmezseniz kimse
fark etmez.

**Başlık metni:** `Komisyon ve temettü dahil — gerçek rakam`

**Kurulum:** Varlık detay ekranı; maliyet kırılımında komisyonun ve
temettü kaydının ikisi de görünsün. Temettü satırı tarihiyle birlikte.

> Not: Bu ekran görsel olarak en zayıfı ama iddiası en güçlüsü.
> Başlık metni burada görselden daha çok iş yapar — metni büyük yazın.

---

### 4 — Dağılım grafiği
**Başlık metni:** `Ağırlığın nerede, tek bakışta`

Renkli donut/pasta — galeride **renk çeşitliliği** sağlar, kaydırmayı
teşvik eder. Kategoriler dengeli dağılsın (tek varlık %90 olmasın).

---

### 5 — Ortak portföy
**Başlık metni:** `Eşinle, ortağınla aynı portföy`

Gerçek bir ihtiyaca değiyor ve rakiplerde seyrek. "Birlikte" sekmesi,
her ortağın katkısı ayrı görünsün.

**Dikkat:** Sahte isim kullanın (`Ayşe`, `Mehmet`), gerçek kişi adı ve
e-posta **kesinlikle görünmesin**.

---

### 6 — Yarış (opsiyonel, en sonda)
**Başlık metni:** `İstersen sıralamada yerini gör`

**Neden en sonda:** Rekabet unsuru bazı kullanıcıyı çeker, bazısını
iter ("verim paylaşılıyor mu?" endişesi). Öne alırsanız gizlilik
kaygısı olan kullanıcıyı kaybedebilirsiniz.

**Zorunlu:** Anonimlik görünür olsun — takma adlar, TL tutarı yok.
Gizlilik vaadiyle çelişen tek kare bile güven kırar.

---

### 7 — Yatay tam ekran grafik ve çizim (1.1.7 ile, Ar-Ge 2026-10-24 §3)
**Başlık metni:** `Telefonu yan çevir, kendi çizgini çiz`
**Alt satır:** `Trend, yatay seviye, dikdörtgen · ücretsiz`

**Neden:** BIST'le ilgilenen kullanıcı için ayırt edici ve ücretsiz bir
özellik, ama galeride hiç görünmüyor. Galeride tek yatay kare olacağı
için **6. karenin yerine değil, sona** eklenir (Yarış opsiyonel kalır).
Kare özelliği taşıyan sürüm (1.1.7 ya da sonrası) gönderilirken yüklenir;
mağazadaki build'de olmayanı göstermez.

**Kurulum (demo verisi, gerçek hesap DEĞİL):**
- Demo hesabı `demo_portfoy_v4.csv` ile; varlık sayfası **KCHOL** (ya da
  SAHOL), günlük aralık, **mum** görünümü, en az 6 aylık mum.
- Telefonu yan çevir (döndürme kilidi kapalı) → tam ekran grafik.
- **İki çizim:** yükselen bir **trend çizgisi** (iki dip noktası) ve son
  tepeden bir **yatay seviye**. Mıknatıs açık, çizimler mumlara oturmuş.
  Üçüncü bir çizim koyma; kare kalabalıklaşır.
- Bir ortalama (MA20) açık olabilir; imleç (artı) kapalı.
- Durum çubuğunda saat/pil görünür olabilir, bildirim olmasın.
- Dil: yatırım tavsiyesi çağrışımı yok. "Al/sat sinyali" değil, "kendi
  çizgini çiz".

**Üretim:** `build_screenshots.py` bugün yalnız **dikey** çerçeve kuruyor
(1284×2778, 1242×2688, 1080×1920). Bu kare için iki yol:
1. **Önerilen:** ham yatay görüntü (2340×1080) dikey çerçevenin içinde,
   telefon 90° dönmüş olarak; başlık üstte. Galeri tek yönde kalır,
   mağaza boyutları değişmez.
2. Yatay hedef ekle (App Store 2796×1290 / 2778×1284, Play 1920×1080).
   App Store aynı galeride yatay kareyi kabul eder ama arama sonucunda
   dikey karelerin yanında küçük görünür; bu yüzden ikinci tercih.

Ham dosya `screenshots/raw_v3/09_yatay_grafik.jpg`, başlık `CAPTIONS["09"]`.

---

## Neyi koymayın

| Ekran | Neden |
|---|---|
| Giriş / kayıt | Emek ister gibi durur, değer göstermez |
| Boş portföy | "Kurulum gerekiyor" izlenimi, en kötü ilk kare |
| Ayarlar / profil | Kimse ayarlar için uygulama indirmez |
| Onboarding | Değeri değil, süreci gösterir |
| Paywall | `paywall_enabled: false` — kapalı özelliği göstermeyin |
| Vadeli mevduat | Kaldırıldı (2026-09-14) — ekran görüntüsü yok |

---

## Görsel kurallar

**Başlık metni ekleyin.** Ham ekran görüntüsü (çıplak screencap) en
yaygın hatadır. Her karenin üstüne 3–5 kelimelik bir iddia koyun:
telefon çerçevesi + koyu arka plan + kısa metin. sandık'ın amber/koyu
paleti bunun için zaten uygun.

**İlk iki kare metinsiz de anlaşılmalı** — birçok kullanıcı okumadan
kaydırır.

**Veri tutarlı olsun.** Aynı portföy tüm karelerde aynı toplam değeri
göstersin. Farklı rakamlar dikkatli kullanıcıda güven kırar.

**Gerçek veri kullanmayın.** Kendi portföyünüzün ekranı gitmesin;
sahte ama makul bir hesap kurun.

---

## Teknik gereksinimler

| Mağaza | Boyut | Adet |
|---|---|---|
| App Store 6.7" | 1290×2796 | 3–10 (ilk 3 aramada görünür) |
| App Store 6.5" | 1242×2688 | zorunlu değil, 6.7" ölçeklenir |
| Play telefon | min 1080×1920 | 2–8 |
| Play feature graphic | 1024×500 | zorunlu |

**Uyarı — bu makinede otomatik alınamaz:** emülatör Flutter içeriğini
render etmiyor (`dumpsys gfxinfo` → "Total frames rendered: 1"),
`screencap` tek renk PNG üretiyor. `take_screenshots.ps1` bu yüzden
çalışmaz. **Gerçek cihazda alınmalı.**

Ayrıca script'teki dokunma koordinatları (`input tap 324 2260`) 1080×2340
ekrana göre sabit — farklı çözünürlükte yanlış yere basar.
