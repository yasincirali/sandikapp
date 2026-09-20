# App Store / Play Önizleme Videosu — Çekim Senaryosu

Bu dosya **telefonda yapacağın ham ekran kaydını** anlatır. Kurgu, geçişler,
metin overlay'leri ve ses sonra Remotion'da üstüne konur.

**Güncelleme 2026-09-16:** Senaryo kritiklik sırasına göre yeniden kuruldu.
Neyin "en kritik" olduğu değişti — gerekçesi §1'de.

**Güncelleme 2026-09-21 — ekranlar değişti, eski kayıt/kareler bayat:**

| Ne değişti | Eski kayıtta | Yeni ekranda |
|---|---|---|
| Ana ekran üstü | doğrudan toplam kartı | **piyasa bandı** (Dolar · Euro · Altın · BIST, kayan) → toplam kartı |
| Reel getiri rozeti | toplam kartının altında ayrı şerit | **Bugün kartında** "Enflasyona göre ····· +2,85 puan" satırı (altında "Yıllık getirin ile TÜFE farkı") |
| Bugün kartı | ikonlu 4–5 satır liste | **almanak**: solda büyük gün rakamı, sağda günün hareketi; defter satırları; en altta yaklaşan tarih |
| Haftalık özet çipi | ayrı çip | Bugün kartında "Geçen hafta ····· +%2,10" satırı |
| Ortak seçimi | üstte sekme şeridi (Ben / Ayşe / Birlikte) | toplam kartının başlığında **"Ben ▾" çipi** → alt sayfa |
| Performans › Özet | tek liste | üç başlık: **BU DÖNEM / VARLIKLAR / DERİNLİK** (Derinlik katlanır) |

Bayat olanlar: video **1., 2. ve 5. sahne** (ana ekran ×2, Özet) ve
`screenshots/raw_v3/` **01_ana, 02_reel, 03_nereden** kareleri. Diğer
adımlar (Portföy listesi, grafik + crosshair, varlık detayı, Dağılım,
Birlikte) aynı — yeniden çekmek şart değil ama aynı oturumda çekilirse
toplam değer tüm karelerde tutarlı olur (bkz. SCREENSHOT_PLAN "Veri
tutarlı olsun").

Bu güncellemeyle **Adım 1, 2, 5 ve 8** aşağıda yeniden yazıldı; kalanlar
olduğu gibi.

---

## 1. En kritik kare hangisi, neden

Store videosunda izleyicinin **ilk 3 saniyede** kalma kararı verdiği
bilinir. Sıralama "uygulamayı gezdirme" mantığıyla değil, **en güçlü iddia
önce** mantığıyla kurulur.

sandık'ın rakiplerde **olmayan** üç şeyi var. Video bunları göstermezse
sıradan bir portföy listesi uygulaması gibi görünür:

| Sıra | İddia | Neden kritik |
|---|---|---|
| **1** | **Enflasyonu geçtin mi?** | **Tek gerçek ayırt edici.** Türkiye'de portföy uygulaması bolca var; TÜFE'ye göre reel getiri gösteren yok denecek kadar az. Nominal kâr herkeste var, reel kâr bu uygulamada. |
| **2** | Komisyon + temettü dahil gerçek K/Z | Çoğu uygulama "alış − güncel fiyat" yapıp kâr diyor |
| **3** | Ortak portföy | Gerçek ihtiyaç, rakiplerde seyrek |

**Neden #1 enflasyon:** Ekran görüntüsü planı (`SCREENSHOT_PLAN.md`)
yazıldığında ana ekran birinci sıradaydı. Ama o plandan sonra reel getiri
rozeti hem düzeltildi hem demo portföy rozeti **yeşile** çıkaracak şekilde
yeniden kuruldu (`DEMO_PORTFOY.md`). Artık elimizde gösterilecek bir şey
var: **"Enflasyonu 2,85 puan geçtin."**

Bu cümle bir portföy uygulamasının verebileceği en güçlü mesaj — çünkü
kullanıcının gerçek sorusu "param arttı mı" değil, **"param eridi mi"**.

> ⚠️ Rozet **yeşil** olmalı. Kırmızı bir rozetle ("enflasyonun 20 puan
> gerisindesin") video çekilmez. Demo portföy tam bunun için kuruldu.

---

## 2. Çekimden ÖNCE — hazırlık

Bunlar atlanırsa kayıt baştan çöp olur.

### Veri: demo portföyü yükle
- [ ] **Kurgusal hesapla gir.** Apple 2.3.9: gerçek kişinin verisi
      gösterilemez. Ortak adı `Ayşe` / `Mehmet` olsun.
- [ ] `store_listing/demo_portfoy.csv` içeriğini **kopyala**
- [ ] Uygulamada: alt bardaki **+** → **Toplu Ekle** → sağ üstteki
      **pano ikonu** → kutuya **yapıştır** → **Önizle** → **Sepete ekle** →
      **Kaydet**

> Ekranda dosya seçici **yok**, yalnızca yapıştırma alanı var.

- [ ] Yükledikten sonra **rozeti doğrula**: Ana ekranda reel getiri rozeti
      yeşil ve "enflasyonu geçti" diyor mu? Demiyorsa çekme — bana söyle.

### Cihaz
- [ ] **Rahatsız Etme açık** (bildirim banner'ı kayda düşerse o kare çöp)
- [ ] **Pil %80+**, düşük güç modu kapalı (sarı pil ikonu görünmesin)
- [ ] Bakiye gizleme (göz ikonu) **kapalı** — rakamlar görünsün
- [ ] Uygulamayı bir kez açıp **fiyatları çektir** (kayıtta spinner dönmesin)
- [ ] Kayıt mikrofonu **KAPALI** — ses sonra eklenir

> ⚠️ **Emülatörde çekme.** Bu makinedeki emülatörler Flutter'ı render
> etmiyor (ekran siyah çıkıyor). Gerçek cihaz şart.

### Neden bu kadar titiz
Apple 2.3.4: önizleme **yalnızca uygulamanın ekran kaydı** olabilir.
Kurtarıcı stok görüntü yok — kayıt neyse video o.

---

## 3. Çekim — sırayla

**Toplam hedef: 35–45 sn ham kayıt.** (Video 15–30 sn olacak; fazlası
kurguda kırpılır. Fazla çek, az kullan.)

**Genel kural: her dokunuştan sonra 1–2 sn bekle.** Acele scroll kurguda
kullanılamaz.

---

### Adım 1 — Açılış: Bugün kartı · **EN KRİTİK KARE** (≈6 sn)

1. Kaydı **başlat**, 3 sn bekle (kırmızı kayıt çubuğu otursun — kurguda
   kesilecek)
2. Uygulama **Ana** sekmesinde, **"Ben" görünümünde** dursun
3. **Piyasa bandı + toplam kartı + Bugün kartının tamamı** karede olacak
   şekilde konumlan — gerekirse çok az kaydır. Bugün kartında
   "Enflasyona göre ····· +2,85 puan" satırı **yeşil** görünmeli
4. **4 sn hiç dokunmadan bekle** (piyasa bandı bu sırada kendi akar —
   dokunma, dokunursan durur)

> Videonun ilk karesi bu. Aynı karede olması gerekenler:
> **toplam net varlık + yeşil kâr + Bugün kartındaki enflasyon satırı.**
> Satır kırmızıysa ya da yoksa (bayrak/veri) çekme — bana söyle.

---

### Adım 2 — Ana ekranda yavaş scroll (≈5 sn)

5. **Yavaşça** aşağı kaydır: Bugün kartının defter satırları (Geçen hafta,
   Hedef, Artıdaki varlık) ve en alttaki "TÜİK enflasyonu · 3 Ekim ·····
   N gün" ayak notu, sonra varlık dağılımı ve hareketler görünsün
6. 1 sn bekle, **yavaşça** yukarı dön

> Hızlı flick yapma — ani momentum bulanık kare üretir.

---

### Adım 3 — Portföy listesi (≈5 sn)

7. Alt barda **Portföy**'e dokun
8. 2 sn bekle — liste otursun
9. Yavaşça aşağı kaydır

> Karışık türler (altın, fon, hisse, döviz) ve **SAHOL'ün kırmızı −%8'i**
> birlikte görünsün. "Her şey yeşil" kare inandırıcı değil.

---

### Adım 4 — Performans + crosshair · **İKİNCİ KRİTİK** (≈8 sn)

10. Alt barda **Performans**'a dokun
11. 2 sn bekle
12. Periyot seçiciden **1Y** seç — uzun, dalgalı, yukarı eğilimli çizgi
13. 2 sn bekle
14. **Grafiğe parmağını bas ve yavaşça yatay sürükle** — crosshair gezsin,
    tarih/değer baloncuğu değişsin
15. Parmağını kaldır, 1 sn bekle

> "Ciddi araç" izlenimini veren yer. Crosshair hareketi **etkileşimi**
> gösterir — statik ekran görüntüsünün yapamadığı tek şey.

---

### Adım 5 — Özet kartları: reel getiri detayı · **FARKLILAŞTIRICI** (≈6 sn)

16. Performans ekranında **Özet** sekmesine geç, dönem **1Y**
17. 2 sn bekle — üstte **BU DÖNEM** başlığı görünsün
18. Reel getiri / enflasyon karşılaştırma kartında dur, **3 sn bekle**
    (DERİNLİK bölümü katlıysa açma — kare sade kalsın)

> Adım 1'deki rozetin **açıklaması** burada: nominal getiri, TÜFE oranı
> ve puan farkı ayrı ayrı. İddiayı burada kanıtlıyoruz.
> Bu ekran görsel olarak sade ama iddiası en güçlüsü — kurguda metin
> overlay'i büyük gelecek.

---

### Adım 6 — Varlık detayı: komisyon + temettü (≈6 sn)

19. **Portföy** sekmesine dön
20. **Komisyonu ve temettüsü olan** bir hisseye dokun (KCHOL veya SAHOL)
21. 2 sn bekle
22. Maliyet kırılımına kaydır — **komisyon satırı ve temettü satırı ikisi
    de görünsün**
23. 2 sn bekle, geri dön

> Demo CSV'de temettü **yok**. Bu adımdan önce elle bir temettü ekle:
> Portföy → hisseyi **sağa kaydır** → sarı **Temettü** → tutar → Kaydet.
> Eklemezsen bu adımı **atla**, sahte gösterme.

---

### Adım 7 — Dağılım (≈4 sn)

24. Dağılım / pasta grafiğine git
25. 2 sn bekle, bir dilime dokun

> Galeride renk çeşitliliği sağlayan kare. Demo portföyde hiçbir dilim
> %35'i geçmiyor — dengeli görünür.

---

### Adım 8 — Ortak portföy (≈4 sn)

26. Ana ekranda toplam kartının başlığındaki **"Ben ▾" çipine** dokun →
    alt sayfadan **Birlikte** seç (çip yalnızca ortağın varsa görünür)
27. 2 sn bekle — her ortağın katkısı ayrı görünsün

> ⚠️ Kurgusal isimler görünmeli. Gerçek isim/e-posta görünürse bu adımı
> **çekme**, atla.

---

### Adım 9 — Kapanış (≈4 sn)

28. **Ana** sekmesine dön
29. Toplam net varlık + rozet görünürken **3 sn hiç dokunmadan bekle**
30. Kaydı **durdur**

> Son kare burası. Üstüne uygulama adı + kapanış gelecek. Açılışla
> simetrik: video enflasyon rozetiyle başlayıp onunla bitiyor.

---

## 4. Adım öncelikleri — zaman kısıtlıysa

Hepsini çekemezsen **sırayla** feda et:

| Öncelik | Adımlar | Not |
|---|---|---|
| **Vazgeçilmez** | 1, 4, 5 | Enflasyon rozeti + grafik + reel getiri detayı. Bu üçü videonun tamamını taşır. |
| Güçlü | 3, 9 | Liste ve kapanış |
| İyi olur | 2, 7 | Scroll ve dağılım |
| Koşullu | 6, 8 | Temettü yoksa / gerçek isim varsa **atla** |

---

## 5. Çekimden sonra

- [ ] Kaydı izle. Şunlardan biri varsa **tekrar çek**: bildirim banner'ı,
      yükleniyor spinner'ı, gerçek kişi adı, boş ekran, yanlış dokunuş,
      düşük pil ikonu, **kırmızı enflasyon rozeti**
- [ ] Dosyayı `store_listing/preview_video/public/shots/kayit.mov` içine koy
- [ ] Bana "kayıt hazır" de — kurguyu, metinleri, grade'i ve sesi kurup
      886×1920 H.264 master'ı render ederim

---

## 6. Kurgu planı (bende, bilgi olsun diye)

Metin overlay sırası — her biri 2–3 sn:

| Sn | Görüntü | Metin |
|---|---|---|
| 0–4 | Ana ekran, rozet | **Enflasyonu geçtin mi?** |
| 4–8 | Rozet yakın plan | **sandık söyler.** |
| 8–14 | Performans + crosshair | Zaman içinde ne kazandın |
| 14–19 | Özet kartları | Nominal değil, **reel** getiri |
| 19–24 | Varlık detayı | Komisyon ve temettü dahil |
| 24–28 | Ana ekran | **sandık** |

---

## 7. Teknik çerçeve

| Konu | Değer |
|---|---|
| Süre | **15–30 sn** (zorunlu aralık) |
| iPhone çözünürlük | **886×1920** dikey |
| iPad 13" | 1200×1600 (istenirse) |
| FPS | maks 30, progressive |
| Codec | H.264, 10–12 Mbps, .mp4/.mov |
| Ses | Stereo, 44.1/48 kHz, AAC 256 kbps |
| Maks boyut | 500 MB |

Kurgu kuralları:
- **2.3.4** — yalnızca uygulamanın ekran kaydı. Anlatım ve metin overlay
  serbest; stok görüntü, canlı çekim, el görüntüsü **değil**.
- **2.3.7** — videoda **fiyat** geçmez.
- **2.3.10** — Android/Google Play adı, ikonu, görseli **geçmez**.
- **2.3.8** — 4+ yaş derecesine uygun.
- **2.3.9** — haklar sende, **kurgusal hesap verisi**.

---

## 8. Videoya KOYMA

| Ekran | Neden |
|---|---|
| Giriş / kayıt | Emek ister gibi durur |
| Boş portföy | "Kurulum gerekiyor" izlenimi |
| Ayarlar / profil | Kimse ayarlar için indirmez |
| Onboarding turu | Değeri değil süreci gösterir |
| Paywall | `paywall_enabled: false` — kapalı özellik |
| Yarış / leaderboard | Gizlilik kaygısı yaratabilir; videoda riskli |

---

**Not:** Remotion projesi `store_listing/preview_video/` altında hazır
bekliyor. Kayıt `public/shots/kayit.mov`'a düştüğü an kurgu çalışır.
