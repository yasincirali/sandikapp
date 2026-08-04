# App Store Metinleri — sandık 1.1.3

Önceki yayın: **1.1.1 (1784145177)**

> Bu dosya App Store Connect'e elle kopyalanır. Google Play metinleri
> `tr-TR/` ve `en-US/` altındadır (farklı karakter limitleri).

---

## Promotional Text (170 karakter)

App Store'da açıklamanın **üstünde** görünür ve **yeni sürüm yayınlamadan
değiştirilebilir** — kampanya/sezon mesajı için buraya oynayın.

```
Altın mı, dolar mı, hisse mi kazandırdı? Hepsi tek ekranda, gerçek kâr/zarar
ile. Komisyon ve temettü dahil — gördüğün rakam gerçek rakam.
```
(148 karakter)

**Alternatif — merak/rekabet yönü:**
```
Portföyün gerçekten kazanıyor mu? Komisyon ve temettü dahil net getirini gör,
istersen sıralamada yerini keşfet.
```
(126 karakter)

---

## Description

İlk iki satır kritik: App Store gerisini "daha fazla" arkasına saklar.

```
Altın mı, dolar mı, hisse mi daha çok kazandırdı? sandık hepsini tek ekranda
toplar ve sana tek bir şeyi net söyler: gerçekte ne kadar kazandın.

Çoğu takip uygulaması alış fiyatını bugünkü fiyattan çıkarır ve buna "kâr"
der. sandık komisyonu maliyete ekler, aldığın temettüyü kazanca yazar.
Gördüğün rakam, cebindeki rakamdır.


NE TAKİP EDEBİLİRSİN

• Hisse senedi ve yatırım fonu
• Döviz — USD, EUR, GBP
• Altın ve gümüş
• Emtia
• Fiyatlar otomatik güncellenir; istersen kendi fiyatını girersin


GERÇEK KÂR/ZARAR

• Alım komisyonu maliyete dahil edilir
• Nakit temettüler kazanca yazılır
• Geçmiş tarihli alımları girebilirsin — portföyün doğru tarihten başlar
• Döviz varlıklarda alım günündeki kur kullanılır


PERFORMANS

• Portföy geçmişini profesyonel grafikle incele — pinch zoom, crosshair
• Gün, hafta, ay, yıl — istediğin aralıkta getiri
• Hangi varlık ne kadar katkı yaptı, tek tek gör
• Dağılım grafiğiyle ağırlığını dengele


ORTAK PORTFÖY

• Eşinle, ailenle veya iş ortağınla aynı portföyü takip et
• Herkesin katkısı ve getirisi ayrı ayrı hesaplanır
• İstediğin an ortaklığı sonlandır


YARIŞ (isteğe bağlı)

• Ortaklarınla getiri sıralamasında yarış
• Anonim genel sıralamada yerini gör
• Kimlik, tutar ve TL bilgisi asla paylaşılmaz
• Tamamen opt-in — istediğin zaman kapat


GİZLİLİK

• Verilerin şifreli olarak saklanır
• Uygulama görev yöneticisinde otomatik gizlenir
• Bakiyeni tek dokunuşla gizle
• Hesabını ve tüm verini istediğin an sil
• KVKK ve GDPR uyumlu


Sandığını aç, ne kazandığını gör.

---
sandık yatırım tavsiyesi vermez. Gösterilen veriler bilgi amaçlıdır;
yatırım kararlarınızda profesyonel danışmanlık alınız.
```

---

## What's New in This Version

```
Bu sürüm doğruluk ve kararlılık üzerine.

GERÇEK KÂR/ZARAR
• Alım komisyonu artık maliyete dahil — kârın olduğundan yüksek görünmüyor
• Nakit temettü takibi geldi: aldığın temettüyü tarihiyle birlikte gir,
  getirine yansısın

ORTAK PORTFÖYDE DOĞRU HESAP
• "Birlikte" sekmesindeki kâr/zarar artık tekil sekmelerle tutarlı.
  İki ortak da kârdaysa birlikte görünümü de kârda gösteriyor

KÜÇÜK EKRANLARDA OKUNAKLILIK
• Varlık isimleri artık her ekran genişliğinde tam okunuyor
• Portföy hareketleri, performans ve ana ekrandaki taşmalar giderildi
• Kaydırma aksiyonlarının görselleri düzeltildi

BAĞLANTI
• İnternet kesildiğinde oturumun kapanmıyor; bağlantı gelince kaldığın
  yerden devam ediyorsun
• Yazı tipi uygulamayla birlikte geliyor — ilk açılış artık internete
  bağlı değil

HIZ
• Açılış hızlandırıldı, fiyat sorguları önbelleğe alındı
• Arka planda gereksiz ağ trafiği durduruldu — pil dostu

Tarih seçici uygulama genelinde tek tip oldu.
```

---

## Keywords (100 karakter, virgülle, boşluksuz)

Başlıkta geçen kelimeleri tekrarlamayın — App Store zaten indeksliyor.
"portföy" ve "sandık" başlıkta olduğu için listede yok.

```
borsa,hisse,yatırım,altın,döviz,fon,bist,kâr,temettü,birikim,finans,varlık,kur,gümüş,bütçe,tasarruf
```
(99 karakter)

**Neden bunlar:**
- `borsa`, `hisse`, `bist` — en yüksek hacimli arama terimleri
- `altın`, `döviz`, `kur` — TR'de en çok aranan yatırım araçları
- `temettü` — rakiplerin çoğunda yok, düşük rekabet
- `kâr` — "kâr zarar hesaplama" aramalarını yakalar
- `birikim`, `varlık` — niyet bazlı, daha az rekabetli

**Not:** Apple keyword alanında Türkçe karakterleri ayrı indeksler.
`kâr` yazdım; `kar` (kar yağışı) ile karışmaması için doğrusu bu.

---

## Yayın öncesi kontrol

- [ ] `pubspec.yaml` sürümü artırıldı (şu an `1.1.3+6`)
- [ ] Ekran görüntüleri 6.7" ve 6.5" için güncel
- [ ] Promotional Text kampanyaya göre gözden geçirildi
- [ ] Yaş sınırı ve Data Safety formu değişmediyse dokunma
