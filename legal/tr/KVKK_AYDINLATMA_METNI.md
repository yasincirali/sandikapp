# KVKK AydÄ±nlatma Metni â€” sandÄ±k

**YÃ¼rÃ¼rlÃ¼k tarihi:** 11 MayÄ±s 2026
**SÃ¼rÃ¼m:** 1.0

> **TODO:** `[ÅÄ°RKET ADI]`, `Türkiye`, `[VERGÄ° NO]`, `[VERBÄ°S NO]`, `[KEP ADRESÄ°]`, `[Ä°LETÄ°ÅÄ°M E-POSTA]`, `E-posta ile iletişim: sandikapp.destek@gmail.com` alanlarÄ±nÄ± gerÃ§ek deÄŸerlerle doldurun. Bireysel giriÅŸimci/ÅŸirketsiz iseniz, KVKK Madde 16 muafiyet eÅŸiklerini (yÄ±llÄ±k ciro 100M TL veya Ã§alÄ±ÅŸan sayÄ±sÄ± 50 altÄ± iÃ§in VERBÄ°S muaf olabilir) kvkk.gov.tr Ã¼zerinden kontrol edin.

---

## 1. Veri Sorumlusunun KimliÄŸi

6698 sayÄ±lÄ± KiÅŸisel Verilerin KorunmasÄ± Kanunu ("KVKK") Madde 10 uyarÄ±nca, kiÅŸisel verilerinizin iÅŸlenmesine iliÅŸkin olarak veri sorumlusu sÄ±fatÄ±yla aÅŸaÄŸÄ±daki bilgilendirmeyi yaparÄ±z.

| Bilgi | Detay |
|---|---|
| Veri Sorumlusu | `[ÅÄ°RKET ADI]` |
| Adres | `[AÃ‡IK ADRES]` |
| Vergi No | `[VERGÄ° NO]` |
| VERBÄ°S No | `[VERBÄ°S NO]` |
| KEP Adresi | `[KEP ADRESÄ°]` |
| E-posta | `[Ä°LETÄ°ÅÄ°M E-POSTA]` |
| Telefon | `E-posta ile iletişim: sandikapp.destek@gmail.com` |

---

## 2. Ä°ÅŸlenen KiÅŸisel Veri Kategorileri

### 2.1 Kimlik Verisi
- E-posta adresi
- GÃ¶rÃ¼nen ad (display name)

### 2.2 Ä°letiÅŸim Verisi
- Bildirim iÃ§in kayÄ±tlÄ± cihaz token'Ä± (push)

### 2.3 MÃ¼ÅŸteri Ä°ÅŸlem Verisi
- PortfÃ¶y varlÄ±k kayÄ±tlarÄ± (sembol, miktar, alÄ±ÅŸ fiyatÄ±, tarih, not)
- Snapshot geÃ§miÅŸi (toplam deÄŸer, getiri yÃ¼zdesi)
- OrtaklÄ±k baÄŸlantÄ±larÄ± ve davet kodlarÄ±

### 2.4 Ä°ÅŸlem GÃ¼venliÄŸi Verisi
- Åifre (bcrypt hash â€” geri Ã§evrilemez)
- Oturum tokenÄ± (JWT)
- Cihaz IP adresi (oturum aÃ§ma anÄ±nda)
- Cihaz modeli, OS sÃ¼rÃ¼mÃ¼, uygulama sÃ¼rÃ¼mÃ¼

### 2.5 Hukuki Ä°ÅŸlem Verisi
- Disclaimer (yatÄ±rÄ±m tavsiyesi reddi) onay zamanÄ±, sÃ¼rÃ¼mÃ¼, platformu, IP'si

---

## 3. KiÅŸisel Verilerin Ä°ÅŸlenme AmaÃ§larÄ±

| AmaÃ§ | Veri kategorileri |
|---|---|
| Hesap oluÅŸturma ve oturum yÃ¶netimi | 2.1, 2.4 |
| PortfÃ¶y takibi (uygulamanÄ±n ana iÅŸlevi) | 2.3 |
| Performans grafiklerinin hesaplanmasÄ± | 2.3 |
| OrtaklÄ±k Ã¶zelliÄŸi (kullanÄ±cÄ±lar arasÄ± paylaÅŸÄ±m) | 2.1, 2.3 |
| Push bildirim gÃ¶nderimi | 2.2 |
| Yasal yÃ¼kÃ¼mlÃ¼lÃ¼klerin yerine getirilmesi (disclaimer onayÄ±, mahkeme/savcÄ±lÄ±k talepleri) | 2.5, 2.4 |
| Hata teÅŸhisi ve uygulama gÃ¼venliÄŸi | 2.4 |
| KÃ¶tÃ¼ye kullanÄ±m, sahtekarlÄ±k ve siber saldÄ±rÄ± tespiti | 2.4 |

---

## 4. KiÅŸisel Verilerin Toplanma YÃ¶ntemi ve Hukuki Sebebi

### 4.1 Toplanma YÃ¶ntemi
- **DoÄŸrudan kullanÄ±cÄ±dan:** KayÄ±t formu, varlÄ±k ekleme, profil ayarlarÄ±
- **Otomatik:** Oturum aÃ§ma anÄ±nda IP/cihaz bilgisi, push token kaydÄ±, hata loglarÄ±

### 4.2 Hukuki Sebep (KVKK Madde 5 ve 6)

| Veri | Hukuki sebep |
|---|---|
| E-posta, ÅŸifre, display name | KVKK 5(2)(c) â€” sÃ¶zleÅŸmenin kurulmasÄ± ve ifasÄ± iÃ§in zorunlu |
| PortfÃ¶y verileri | KVKK 5(2)(c) â€” sÃ¶zleÅŸmenin ifasÄ± |
| Push token | KVKK 5(1) â€” aÃ§Ä±k rÄ±za |
| IP, cihaz bilgisi | KVKK 5(2)(f) â€” meÅŸru menfaat (gÃ¼venlik) |
| Disclaimer onayÄ± | KVKK 5(2)(a) â€” kanunlarda Ã¶ngÃ¶rÃ¼lmesi (SPK) |
| Yurt dÄ±ÅŸÄ± aktarÄ±mÄ± (Supabase USA, Firebase) | KVKK 5(1) ve 9(1) â€” aÃ§Ä±k rÄ±za |

---

## 5. KiÅŸisel Verilerin AktarÄ±ldÄ±ÄŸÄ± Taraflar ve AktarÄ±m AmacÄ±

### 5.1 Yurt Ä°Ã§i AktarÄ±m
Mevcut iÅŸleme faaliyetlerinde **yurt iÃ§i Ã¼Ã§Ã¼ncÃ¼ taraf aktarÄ±mÄ± yapÄ±lmamaktadÄ±r** (Åirket Ã§alÄ±ÅŸanlarÄ± ve Åirketin doÄŸrudan denetimindeki teknik destek personeli hariÃ§).

### 5.2 Yurt DÄ±ÅŸÄ± AktarÄ±m

| AlÄ±cÄ± | Ãœlke | Veri | AmaÃ§ | Hukuki sebep |
|---|---|---|---|---|
| Supabase Inc. | ABD | TÃ¼m hesap ve uygulama verileri | VeritabanÄ± ve kimlik doÄŸrulama altyapÄ±sÄ± | KVKK 9(1) â€” aÃ§Ä±k rÄ±za |
| Google LLC (Firebase Cloud Messaging) | ABD / KÃ¼resel | Push token, bildirim iÃ§eriÄŸi | Bildirim teslimi | KVKK 9(1) â€” aÃ§Ä±k rÄ±za |
| Google LLC (Firebase Crashlytics) - **eklendiÄŸinde** | ABD / KÃ¼resel | Cihaz modeli, OS, hata stack trace | Ã‡Ã¶kme teÅŸhisi | KVKK 5(2)(f) ve 9(1) â€” aÃ§Ä±k rÄ±za |

ABD, KiÅŸisel Verileri Koruma Kurulu'nun (KVK Kurulu) ilan ettiÄŸi "yeterli korumaya sahip Ã¼lkeler" listesinde **bulunmamaktadÄ±r**. Bu nedenle yurt dÄ±ÅŸÄ± aktarÄ±mÄ± KVKK Madde 9(1) kapsamÄ±nda **aÃ§Ä±k rÄ±zanÄ±za** dayanmaktadÄ±r.

AÃ§Ä±k rÄ±zanÄ±z, kayÄ±t sÄ±rasÄ±nda onayladÄ±ÄŸÄ±nÄ±z "AÃ§Ä±k RÄ±za Metni" iÃ§erisinde belirli, bilgilendirilmiÅŸ ve Ã¶zgÃ¼r iradeyle alÄ±nmaktadÄ±r.

---

## 6. KiÅŸisel Verilerin Saklanma SÃ¼resi

| Veri | Saklama sÃ¼resi | Dayanak |
|---|---|---|
| Hesap verileri (e-posta, display name) | Hesap silinene kadar | SÃ¶zleÅŸme sÃ¼resi |
| PortfÃ¶y varlÄ±k kayÄ±tlarÄ± | Hesap silinene kadar | SÃ¶zleÅŸme sÃ¼resi |
| Snapshot geÃ§miÅŸi | Son 365 gÃ¼n rolling | Servis ihtiyacÄ± |
| Push token | Logout veya uninstall'a kadar | SÃ¶zleÅŸme sÃ¼resi |
| Disclaimer onay logu | Hesap silinmesinden sonra **3 yÄ±l** | TBK Madde 146 (zamanaÅŸÄ±mÄ±) |
| Oturum loglarÄ± (IP, cihaz) | 90 gÃ¼n | KVKK 5(2)(f) meÅŸru menfaat |
| Hata loglarÄ± (error db_logs) | 30 gÃ¼n | KVKK 5(2)(f) meÅŸru menfaat |

Saklama sÃ¼resi sona eren veriler **kalÄ±cÄ± olarak silinir veya anonimleÅŸtirilir**.

---

## 7. KiÅŸisel Veri Sahibinin KVKK Madde 11 HaklarÄ±

KVKK Madde 11 uyarÄ±nca aÅŸaÄŸÄ±daki haklara sahipsiniz:

a) KiÅŸisel verilerinizin iÅŸlenip iÅŸlenmediÄŸini Ã¶ÄŸrenme,
b) Ä°ÅŸlenmiÅŸse buna iliÅŸkin bilgi talep etme,
c) Ä°ÅŸlenme amacÄ±nÄ± ve amacÄ±na uygun kullanÄ±lÄ±p kullanÄ±lmadÄ±ÄŸÄ±nÄ± Ã¶ÄŸrenme,
Ã§) Yurt iÃ§inde veya yurt dÄ±ÅŸÄ±nda aktarÄ±ldÄ±ÄŸÄ± Ã¼Ã§Ã¼ncÃ¼ kiÅŸileri bilme,
d) Eksik veya yanlÄ±ÅŸ iÅŸlenmiÅŸse dÃ¼zeltilmesini isteme,
e) KVKK 7. madde kapsamÄ±nda silinmesini veya yok edilmesini isteme,
f) (d) ve (e) bentleri uyarÄ±nca yapÄ±lan iÅŸlemlerin aktarÄ±ldÄ±ÄŸÄ± Ã¼Ã§Ã¼ncÃ¼ kiÅŸilere bildirilmesini isteme,
g) Ä°ÅŸlenen verilerin mÃ¼nhasÄ±ran otomatik sistemler vasÄ±tasÄ±yla analiz edilmesi suretiyle aleyhinize bir sonucun ortaya Ã§Ä±kmasÄ±na itiraz etme,
ÄŸ) Kanuna aykÄ±rÄ± iÅŸlenmesi sebebiyle zarara uÄŸramanÄ±z hÃ¢linde zararÄ±n giderilmesini talep etme.

### 7.1 BaÅŸvuru YÃ¶ntemi

KVKK Madde 13 ve "Veri Sorumlusuna BaÅŸvuru Usul ve EsaslarÄ± HakkÄ±nda TebliÄŸ" uyarÄ±nca taleplerinizi ÅŸu yÃ¶ntemlerden biriyle iletebilirsiniz:

1. **Uygulama iÃ§i:** Profil â†’ Ayarlar â†’ "HesabÄ±mÄ± Sil" / "Verilerimi Ä°ndir"
2. **E-posta:** `[Ä°LETÄ°ÅÄ°M E-POSTA]` adresine kimlik bilgileri (ad-soyad, T.C. kimlik no veya baÅŸka kimlik tanÄ±mlayÄ±cÄ±), iletiÅŸim bilgileri ve talep konusunu aÃ§Ä±kÃ§a belirten yazÄ±lÄ± baÅŸvuru
3. **KEP:** `[KEP ADRESÄ°]` adresine gÃ¼venli elektronik imzalÄ± belge
4. **Posta:** `[AÃ‡IK ADRES]` adresine Ä±slak imzalÄ± dilekÃ§e

BaÅŸvurunuza **30 gÃ¼n** iÃ§inde Ã¼cretsiz olarak yanÄ±t veririz. KVK Kurulu'nun belirlediÄŸi tarifedeki Ã¼cretler haklÄ± sebeplerle istenebilir (TebliÄŸ Madde 7).

### 7.2 Åikayet HakkÄ±

YanÄ±ttan memnun kalmazsanÄ±z veya 30 gÃ¼n iÃ§inde yanÄ±t alamazsanÄ±z, KVKK Madde 14 uyarÄ±nca **KiÅŸisel Verileri Koruma Kurulu**'na ÅŸikayet edebilirsiniz:

KiÅŸisel Verileri Koruma Kurumu
Nasuh Akar Mah. Ziyabey Cad. 1407. Sok. No: 4 06520 Balgat / Ã‡ankaya / ANKARA
Web: www.kvkk.gov.tr
E-posta: kvkk@kvkk.gov.tr

---

## 8. Veri GÃ¼venliÄŸi

KVKK Madde 12 uyarÄ±nca aldÄ±ÄŸÄ±mÄ±z Ã¶nlemler:

**Teknik Ã–nlemler:**
- TLS 1.2+ ile aktarÄ±m ÅŸifrelemesi
- AES-256 ile at-rest ÅŸifreleme
- Bcrypt ile ÅŸifre hash'leme
- Row-Level Security (RLS) ile yetkisiz eriÅŸim engeli
- Rate limiting ile brute-force saldÄ±rÄ± korumasÄ±
- 10 dakika idle session timeout
- Production loglarÄ±nda PII maskeleme

**Ä°dari Ã–nlemler:**
- Veri iÅŸleyenlerle (Supabase, Firebase) yazÄ±lÄ± veri iÅŸleme sÃ¶zleÅŸmeleri (DPA)
- Personel iÃ§in gizlilik taahhÃ¼tleri
- EriÅŸim yetkisi prensibi (least-privilege)
- Veri ihlali yÃ¶netimi sÃ¼reci (72 saat iÃ§inde Kurul'a bildirim)
- DÃ¼zenli gÃ¼venlik denetimleri ve testler

---

## 9. Veri Ä°hlali Durumunda Bildirim

KVKK Madde 12(5) uyarÄ±nca, kiÅŸisel verilerinizin yetkisiz kiÅŸilerce ele geÃ§irildiÄŸini tespit etmemiz hÃ¢linde:

- En geÃ§ **72 saat** iÃ§inde KVK Kurulu'na bildirim yaparÄ±z
- Etkilenen veri sahiplerine (size) **makul en kÄ±sa sÃ¼rede** doÄŸrudan bildirim yaparÄ±z (e-posta + uygulama iÃ§i)
- KVK Kurulu'nun ilan ettiÄŸi "Veri Ä°hlali Bildirim Formu"nu kullanÄ±rÄ±z

---

## 10. Politikada DeÄŸiÅŸiklikler

Bu AydÄ±nlatma Metni'nde deÄŸiÅŸiklik yaptÄ±ÄŸÄ±mÄ±zda:
- Yeni sÃ¼rÃ¼m uygulama iÃ§inde gÃ¶sterilir
- "SÃ¼rÃ¼m" numarasÄ± artÄ±rÄ±lÄ±r
- Ã–nemli deÄŸiÅŸikliklerde tekrar onay isteriz
- Ã–nceki sÃ¼rÃ¼mlere `[WEB SÄ°TESÄ°]/legal/kvkk-history` adresinden ulaÅŸÄ±labilir

---

*Bu AydÄ±nlatma Metni'ni okuyup anladÄ±ÄŸÄ±nÄ±zÄ±, kayÄ±t sÄ±rasÄ±nda ilgili onay kutusunu iÅŸaretleyerek beyan etmektesiniz.*

---

**`[ÅÄ°RKET ADI]`**
**`Türkiye`**
**`[Ä°LETÄ°ÅÄ°M E-POSTA]`**

