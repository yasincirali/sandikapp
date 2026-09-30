# KAP bildirimleri — yasal veri yolu ve lisans talebi (karar 7.1 / 7.4)

**Tarih:** 2026-09-30 · **Kullanıcı notu (7.4):** "datayı çekebilmek için
legal bir yol düşün." KAP sitesinden izinsiz veri çekmek (kazıma) bu yüzden
**yok**; aşağıdaki yollar lisanslı.

## Bugün uygulamada ne var (`263cddc`)

Hisse ekranında "KAP bildirimleri ↗": şirketin KAP sayfası tarayıcıda
açılır. Uygulama bildirim OKUMAZ. Adres için KAP'ın şirket arama ucuna
dokunuş başına tek istek atılır (kullanıcının sitede arama yapmasıyla
aynı); yalnız tek sonuçta şirket sayfası, aksi hâlde bildirim sorgu sayfası.

> ⚠️ Bu arama ucu KAP'ın belgelenmiş bir API'si değil, sitenin kendi
> arayüzünün kullandığı uç. Bildirim verisi çekilmediği için lisans
> kapsamına girmediğini düşünüyoruz; KAP/Borsa İstanbul görüşmesinde
> **bunu da sor** (aşağıdaki yazıda madde 6). Olumsuz cevap gelirse bağlantı
> doğrudan bildirim sorgu sayfasına çevrilir (tek satır).

## Yasal yollar

| Yol | Nasıl | Artı | Eksi |
|---|---|---|---|
| **1. Doğrudan: Borsa İstanbul + MKK** | Borsa İstanbul ile **Veri Dağıtım Sözleşmesi** → MKK sistemde yetkilendirir → **KAP Veri Yayın Servisi** (REST, MKK API Portal; "uygulama ücretsiz") ([BIST SSS](https://www.borsaistanbul.com/sss/veri-dagitim-ve-endeks-lisanslama), [MKK API Portal](https://www.mkk.com.tr/haberler/mkk-api-portal-yayinda), [KAP servis belgesi](https://kap.org.tr/tr/api/about/content-file/8a019492945fbe080194b26d8bed4873)) | Birinci el, anlık, tam kapsam | Sözleşme + lisans ücreti (bilinmiyor); tüzel kişilik gerekebilir |
| **2. Lisanslı veri dağıtıcısı** | KAP verisini zaten BIST lisansıyla dağıtan kurumdan API: Matriks ([veri servisleri](https://www.matriksdata.com/website/urunlerimiz/kurumsal-hizmet-ve-servisler/veri-ve-icerik-saglayici-servisler)), Foreks, Rasyonet, Finnet… ([BIST veri dağıtıcı listesi](https://www.borsaistanbul.com/en/data/data-dissemination/data-vendors-directory)) | Tek sözleşme, teknik destek, fiyat verisini de aynı yerden alma fırsatı (bugünkü Yahoo/truncgil lisans riskini de çözer) | Aracı maliyeti; son kullanıcıya yeniden dağıtım ayrıca lisanslanır |
| 3. Kazıma | — | — | **Yapılmaz** (kullanım şartları, yatırım incelemesinde kırmızı bayrak) |

**Öneri:** 1 ve 2'ye **aynı anda** yaz, fiyat teklifini karşılaştır. Yol 2,
fiyat verisi lisansını da (yatırımcı sunumundaki "veri lisansı" başlığı)
tek sözleşmede çözebilir.

Sözleşme gelince yapılacak kod (7.3, "Sonra"): `kap-bildirim` edge function
(5 dk'da bir, `lastDisclosureIndex`), `kap_bildirimleri` tablosu (herkese
okunur, yazma servis rolü), bildirim merkezi yeni tür, kullanıcı tercihi,
sessiz saatler, günlük tavan — 5–7 gün, iki sunucuya birlikte.

## Talep yazısı taslağı (7.1)

Gönderen bilgileri `[köşeli]` — tüzel kişilik kararı (YAPMAN_GEREKENLER)
netleşince doldurulur. Alıcılar: Borsa İstanbul Veri Dağıtım birimi
(iletişim: borsaistanbul.com › Veri Yayını) ve bilgi için MKK KAP Destek
(`kapdestek@mkk.com.tr`). Veri dağıtıcılarına aynı metin, "KAP Veri Yayın
Servisi" yerine "KAP bildirim verisi API'niz" diye.

---

**Konu:** KAP Veri Yayın Servisi — veri dağıtım lisansı ve koşullar hakkında bilgi talebi

Sayın Yetkili,

[Ad Soyad / Unvan] olarak geliştirdiğimiz **sandık** (iOS ve Android),
bireysel yatırımcıların hisse, fon, döviz ve altın varlıklarını tek yerden
takip ettiği bir portföy takip uygulamasıdır. Uygulama alım-satım aracılığı
yapmaz, yatırım tavsiyesi vermez.

Kullanıcılarımıza, portföylerinde veya takip listelerinde bulunan şirketlerin
KAP bildirimlerini uygulama içinde ve anlık bildirim (push) olarak iletmek
istiyoruz. Bu amaçla KAP Veri Yayın Servisi'ne erişim ve gerekli veri
dağıtım lisansı hakkında bilgi rica ederiz.

**Kullanmak istediğimiz veri:** bildirim başlığı, bildirim türü, şirket
(BIST) kodu, yayın zamanı ve bildirimin KAP'taki bağlantısı. Bildirim
eklerinin ve tam metninin uygulamada yeniden yayımlanması **planlanmıyor**;
kullanıcı ayrıntı için KAP sayfasına yönlendirilir.

**Kullanım şekli:** yalnızca uygulama kullanıcılarına, kendi portföy ve
takip listelerindeki şirketlerle sınırlı bildirim. Tahmini kullanıcı
sayısı: [sayı]. Toplu veri satışı veya üçüncü kişilere aktarım yoktur.

Aşağıdaki konularda bilgi rica ederiz:

1. Bu kullanım için gereken sözleşme / lisans türü ve ücretlendirme esası
   (sabit, kullanıcı sayısına göre, kademeli).
2. Anlık ve gecikmeli veri arasında lisans veya ücret farkı.
3. Başvuru için gereken belgeler; gerçek kişi başvurusu mümkün mü,
   tüzel kişilik şart mı.
4. Sözleşme sonrası MKK yetkilendirmesinin süresi ve test ortamı
   (sandbox) bulunup bulunmadığı.
5. Kaynak gösterme / atıf ve verinin saklanma süresi koşulları.
6. Uygulamamızda hisse ekranından şirketin KAP sayfasına bağlantı
   veriyoruz; bağlantı adresini bulmak için KAP sitesinin şirket arama
   ucunu kullanıcı dokunuşu başına bir kez çağırıyoruz (bildirim verisi
   alınmıyor). Bu kullanımın uygun olup olmadığını teyit etmenizi rica
   ederiz.

Görüşme için uygun olduğunuz bir zamanı bildirirseniz memnun oluruz.

Saygılarımızla,
[Ad Soyad]
[Unvan / Şirket]
[E-posta] · [Telefon]
sandık — [web adresi]

---
