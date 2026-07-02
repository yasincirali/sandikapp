# KVKK Aydınlatma Metni — sandık

**Yürürlük tarihi:** 11 Mayıs 2026
**Sürüm:** 1.0

> **TODO:** `[ŞİRKET ADI]`, `[ADRES]`, `[VERGİ NO]`, `[VERBİS NO]`, `[KEP ADRESİ]`, `[İLETİŞİM E-POSTA]`, `[TELEFON]` alanlarını gerçek değerlerle doldurun. Bireysel girişimci/şirketsiz iseniz, KVKK Madde 16 muafiyet eşiklerini (yıllık ciro 100M TL veya çalışan sayısı 50 altı için VERBİS muaf olabilir) kvkk.gov.tr üzerinden kontrol edin.

---

## 1. Veri Sorumlusunun Kimliği

6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") Madde 10 uyarınca, kişisel verilerinizin işlenmesine ilişkin olarak veri sorumlusu sıfatıyla aşağıdaki bilgilendirmeyi yaparız.

| Bilgi | Detay |
|---|---|
| Veri Sorumlusu | `[ŞİRKET ADI]` |
| Adres | `[AÇIK ADRES]` |
| Vergi No | `[VERGİ NO]` |
| VERBİS No | `[VERBİS NO]` |
| KEP Adresi | `[KEP ADRESİ]` |
| E-posta | `[İLETİŞİM E-POSTA]` |
| Telefon | `[TELEFON]` |

---

## 2. İşlenen Kişisel Veri Kategorileri

### 2.1 Kimlik Verisi
- E-posta adresi
- Görünen ad (display name)

### 2.2 İletişim Verisi
- Bildirim için kayıtlı cihaz token'ı (push)

### 2.3 Müşteri İşlem Verisi
- Portföy varlık kayıtları (sembol, miktar, alış fiyatı, tarih, not)
- Snapshot geçmişi (toplam değer, getiri yüzdesi)
- Ortaklık bağlantıları ve davet kodları

### 2.4 İşlem Güvenliği Verisi
- Şifre (bcrypt hash — geri çevrilemez)
- Oturum tokenı (JWT)
- Cihaz IP adresi (oturum açma anında)
- Cihaz modeli, OS sürümü, uygulama sürümü

### 2.5 Hukuki İşlem Verisi
- Disclaimer (yatırım tavsiyesi reddi) onay zamanı, sürümü, platformu, IP'si

---

## 3. Kişisel Verilerin İşlenme Amaçları

| Amaç | Veri kategorileri |
|---|---|
| Hesap oluşturma ve oturum yönetimi | 2.1, 2.4 |
| Portföy takibi (uygulamanın ana işlevi) | 2.3 |
| Performans grafiklerinin hesaplanması | 2.3 |
| Ortaklık özelliği (kullanıcılar arası paylaşım) | 2.1, 2.3 |
| Push bildirim gönderimi | 2.2 |
| Yasal yükümlülüklerin yerine getirilmesi (disclaimer onayı, mahkeme/savcılık talepleri) | 2.5, 2.4 |
| Hata teşhisi ve uygulama güvenliği | 2.4 |
| Kötüye kullanım, sahtekarlık ve siber saldırı tespiti | 2.4 |

---

## 4. Kişisel Verilerin Toplanma Yöntemi ve Hukuki Sebebi

### 4.1 Toplanma Yöntemi
- **Doğrudan kullanıcıdan:** Kayıt formu, varlık ekleme, profil ayarları
- **Otomatik:** Oturum açma anında IP/cihaz bilgisi, push token kaydı, hata logları

### 4.2 Hukuki Sebep (KVKK Madde 5 ve 6)

| Veri | Hukuki sebep |
|---|---|
| E-posta, şifre, display name | KVKK 5(2)(c) — sözleşmenin kurulması ve ifası için zorunlu |
| Portföy verileri | KVKK 5(2)(c) — sözleşmenin ifası |
| Push token | KVKK 5(1) — açık rıza |
| IP, cihaz bilgisi | KVKK 5(2)(f) — meşru menfaat (güvenlik) |
| Disclaimer onayı | KVKK 5(2)(a) — kanunlarda öngörülmesi (SPK) |
| Yurt dışı aktarımı (Supabase USA, Firebase) | KVKK 5(1) ve 9(1) — açık rıza |

---

## 5. Kişisel Verilerin Aktarıldığı Taraflar ve Aktarım Amacı

### 5.1 Yurt İçi Aktarım
Mevcut işleme faaliyetlerinde **yurt içi üçüncü taraf aktarımı yapılmamaktadır** (Şirket çalışanları ve Şirketin doğrudan denetimindeki teknik destek personeli hariç).

### 5.2 Yurt Dışı Aktarım

| Alıcı | Ülke | Veri | Amaç | Hukuki sebep |
|---|---|---|---|---|
| Supabase Inc. | ABD | Tüm hesap ve uygulama verileri | Veritabanı ve kimlik doğrulama altyapısı | KVKK 9(1) — açık rıza |
| Google LLC (Firebase Cloud Messaging) | ABD / Küresel | Push token, bildirim içeriği | Bildirim teslimi | KVKK 9(1) — açık rıza |
| Google LLC (Firebase Crashlytics) - **eklendiğinde** | ABD / Küresel | Cihaz modeli, OS, hata stack trace | Çökme teşhisi | KVKK 5(2)(f) ve 9(1) — açık rıza |

ABD, Kişisel Verileri Koruma Kurulu'nun (KVK Kurulu) ilan ettiği "yeterli korumaya sahip ülkeler" listesinde **bulunmamaktadır**. Bu nedenle yurt dışı aktarımı KVKK Madde 9(1) kapsamında **açık rızanıza** dayanmaktadır.

Açık rızanız, kayıt sırasında onayladığınız "Açık Rıza Metni" içerisinde belirli, bilgilendirilmiş ve özgür iradeyle alınmaktadır.

---

## 6. Kişisel Verilerin Saklanma Süresi

| Veri | Saklama süresi | Dayanak |
|---|---|---|
| Hesap verileri (e-posta, display name) | Hesap silinene kadar | Sözleşme süresi |
| Portföy varlık kayıtları | Hesap silinene kadar | Sözleşme süresi |
| Snapshot geçmişi | Son 365 gün rolling | Servis ihtiyacı |
| Push token | Logout veya uninstall'a kadar | Sözleşme süresi |
| Disclaimer onay logu | Hesap silinmesinden sonra **3 yıl** | TBK Madde 146 (zamanaşımı) |
| Oturum logları (IP, cihaz) | 90 gün | KVKK 5(2)(f) meşru menfaat |
| Hata logları (error db_logs) | 30 gün | KVKK 5(2)(f) meşru menfaat |

Saklama süresi sona eren veriler **kalıcı olarak silinir veya anonimleştirilir**.

---

## 7. Kişisel Veri Sahibinin KVKK Madde 11 Hakları

KVKK Madde 11 uyarınca aşağıdaki haklara sahipsiniz:

a) Kişisel verilerinizin işlenip işlenmediğini öğrenme,
b) İşlenmişse buna ilişkin bilgi talep etme,
c) İşlenme amacını ve amacına uygun kullanılıp kullanılmadığını öğrenme,
ç) Yurt içinde veya yurt dışında aktarıldığı üçüncü kişileri bilme,
d) Eksik veya yanlış işlenmişse düzeltilmesini isteme,
e) KVKK 7. madde kapsamında silinmesini veya yok edilmesini isteme,
f) (d) ve (e) bentleri uyarınca yapılan işlemlerin aktarıldığı üçüncü kişilere bildirilmesini isteme,
g) İşlenen verilerin münhasıran otomatik sistemler vasıtasıyla analiz edilmesi suretiyle aleyhinize bir sonucun ortaya çıkmasına itiraz etme,
ğ) Kanuna aykırı işlenmesi sebebiyle zarara uğramanız hâlinde zararın giderilmesini talep etme.

### 7.1 Başvuru Yöntemi

KVKK Madde 13 ve "Veri Sorumlusuna Başvuru Usul ve Esasları Hakkında Tebliğ" uyarınca taleplerinizi şu yöntemlerden biriyle iletebilirsiniz:

1. **Uygulama içi:** Profil → Ayarlar → "Hesabımı Sil" / "Verilerimi İndir"
2. **E-posta:** `[İLETİŞİM E-POSTA]` adresine kimlik bilgileri (ad-soyad, T.C. kimlik no veya başka kimlik tanımlayıcı), iletişim bilgileri ve talep konusunu açıkça belirten yazılı başvuru
3. **KEP:** `[KEP ADRESİ]` adresine güvenli elektronik imzalı belge
4. **Posta:** `[AÇIK ADRES]` adresine ıslak imzalı dilekçe

Başvurunuza **30 gün** içinde ücretsiz olarak yanıt veririz. KVK Kurulu'nun belirlediği tarifedeki ücretler haklı sebeplerle istenebilir (Tebliğ Madde 7).

### 7.2 Şikayet Hakkı

Yanıttan memnun kalmazsanız veya 30 gün içinde yanıt alamazsanız, KVKK Madde 14 uyarınca **Kişisel Verileri Koruma Kurulu**'na şikayet edebilirsiniz:

Kişisel Verileri Koruma Kurumu
Nasuh Akar Mah. Ziyabey Cad. 1407. Sok. No: 4 06520 Balgat / Çankaya / ANKARA
Web: www.kvkk.gov.tr
E-posta: kvkk@kvkk.gov.tr

---

## 8. Veri Güvenliği

KVKK Madde 12 uyarınca aldığımız önlemler:

**Teknik Önlemler:**
- TLS 1.2+ ile aktarım şifrelemesi
- AES-256 ile at-rest şifreleme
- Bcrypt ile şifre hash'leme
- Row-Level Security (RLS) ile yetkisiz erişim engeli
- Rate limiting ile brute-force saldırı koruması
- 10 dakika idle session timeout
- Production loglarında PII maskeleme

**İdari Önlemler:**
- Veri işleyenlerle (Supabase, Firebase) yazılı veri işleme sözleşmeleri (DPA)
- Personel için gizlilik taahhütleri
- Erişim yetkisi prensibi (least-privilege)
- Veri ihlali yönetimi süreci (72 saat içinde Kurul'a bildirim)
- Düzenli güvenlik denetimleri ve testler

---

## 9. Veri İhlali Durumunda Bildirim

KVKK Madde 12(5) uyarınca, kişisel verilerinizin yetkisiz kişilerce ele geçirildiğini tespit etmemiz hâlinde:

- En geç **72 saat** içinde KVK Kurulu'na bildirim yaparız
- Etkilenen veri sahiplerine (size) **makul en kısa sürede** doğrudan bildirim yaparız (e-posta + uygulama içi)
- KVK Kurulu'nun ilan ettiği "Veri İhlali Bildirim Formu"nu kullanırız

---

## 10. Politikada Değişiklikler

Bu Aydınlatma Metni'nde değişiklik yaptığımızda:
- Yeni sürüm uygulama içinde gösterilir
- "Sürüm" numarası artırılır
- Önemli değişikliklerde tekrar onay isteriz
- Önceki sürümlere `[WEB SİTESİ]/legal/kvkk-history` adresinden ulaşılabilir

---

*Bu Aydınlatma Metni'ni okuyup anladığınızı, kayıt sırasında ilgili onay kutusunu işaretleyerek beyan etmektesiniz.*

---

**`[ŞİRKET ADI]`**
**`[ADRES]`**
**`[İLETİŞİM E-POSTA]`**
