# Gizlilik Politikası — sandık

**Yürürlük tarihi:** 11 Mayıs 2026
**Son güncelleme:** 11 Mayıs 2026
**Sürüm:** 1.0

> **TODO (yayın öncesi doldurulacak):** `[ŞİRKET ADI]`, `[ADRES]`, `[VERGİ NO]`, `[KEP ADRESİ]`, `[VERBİS NUMARASI]`, `[İLETİŞİM E-POSTA]`, `[WEB SİTESİ]` alanlarını gerçek değerlerle değiştirin. Bireysel geliştirici iseniz "şirket" yerine ad-soyad ve T.C. kimlik gizleyerek iletişim adresi bırakabilirsiniz; ancak ticari faaliyet yapıyorsanız KVKK Madde 16 uyarınca VERBİS kaydı zorunludur (yıllık ciro/çalışan eşikleri için kvkk.gov.tr).

---

## 1. Veri Sorumlusu

Bu uygulamayı (**sandık**, "Uygulama") `[ŞİRKET ADI]` ("biz", "Şirket") işletmektedir.

- **Adres:** `[AÇIK ADRES]`
- **E-posta:** `[İLETİŞİM E-POSTA]`
- **Web:** `[WEB SİTESİ]`
- **VERBİS:** `[NUMARA]` (uygulanabilirse)

KVKK Madde 3(1)(ı) uyarınca veri sorumlusu sıfatıyla hareket ediyoruz.

---

## 2. Bu Politikanın Kapsamı

Bu politika, Uygulamayı indirip kullandığınızda hangi kişisel verilerinizi topladığımızı, neden topladığımızı, kimlerle paylaştığımızı, ne kadar sakladığımızı ve yasal haklarınızı açıklar.

Politika; KVKK (6698 sayılı Kişisel Verilerin Korunması Kanunu), GDPR (EU 2016/679), Apple App Store Privacy Guidelines ve Google Play Data Safety gerekliliklerini karşılayacak şekilde hazırlanmıştır.

---

## 3. Topladığımız Veriler

### 3.1 Hesap Verileri (zorunlu)
| Veri | Amaç | Hukuki dayanak |
|---|---|---|
| E-posta adresi | Hesap oluşturma, oturum açma, şifre sıfırlama | KVKK 5(2)(c) — sözleşme; GDPR 6(1)(b) |
| Şifre (hash) | Kimlik doğrulama | KVKK 5(2)(c); GDPR 6(1)(b) |
| Görünen ad (display name) | Ortaklık özelliğinde diğer kullanıcılara isim göstermek | KVKK 5(2)(c); GDPR 6(1)(b) |

### 3.2 Uygulama İçeriği Verileri (kullanıcı tarafından girilir)
| Veri | Amaç |
|---|---|
| Varlık kayıtları (sembol, miktar, alış fiyatı, tarih, not) | Portföy takibi (Uygulamanın ana işlevi) |
| Portföy snapshot geçmişi | Performans grafikleri |
| Ortaklık davet kodları ve karşılıklı bağlantılar | Çoklu kullanıcı paylaşımı özelliği |

### 3.3 Cihaz ve Bildirim Verileri
| Veri | Amaç |
|---|---|
| Push bildirim token'ı (FCM) | Ortaklık daveti ve sinyal bildirimleri |
| Cihaz modeli, OS sürümü, uygulama sürümü | Hata teşhisi (yalnızca disclaimer onayı sırasında) |
| Yerel ayar (locale) | Dil/tarih formatı |

### 3.4 Yasal Onay Kayıtları
| Veri | Amaç | Hukuki dayanak |
|---|---|---|
| Disclaimer onay zamanı, IP, sürüm, platform | Yatırım danışmanlığı reddi onayının kanıtı | KVKK 5(2)(a) — kanunda öngörülmesi; SPK mevzuatı |

### 3.5 Otomatik Toplanan Veriler
| Veri | Amaç |
|---|---|
| Hata raporları (Crashlytics) | Çökme teşhisi (kişisel veri içermez, anonim cihaz id) |
| Yapısal log kayıtları | Yalnızca üretimde **hata** durumunda; hassas alanlar (e-posta, şifre, token) maskelenir |

### Toplamadığımız Veriler
- Konum
- Telefon defteri
- Fotoğraf / kamera
- Reklam tanımlayıcısı
- Üçüncü taraf reklam ağı izleme verisi
- Banka hesap bilgileri (uygulama hiçbir banka API'sine bağlanmaz)

---

## 4. Verilerin Kullanım Amaçları

1. Hesabınızı oluşturmak ve oturumunuzu sürdürmek
2. Portföyünüzü yerel cihazınızda ve sunucularımızda saklamak
3. Performans grafiklerinizi hesaplamak
4. Ortaklık davetlerinizi diğer kullanıcılara iletmek
5. Bildirim göndermek (yalnızca açıkça izin verdiyseniz)
6. Yasal yükümlülüklerimizi yerine getirmek (disclaimer kanıtı, yetkili merci talepleri)
7. Hata teşhisi ve servis kalitesinin iyileştirilmesi
8. Kötüye kullanım, sahtekarlık ve siber saldırıların tespiti (KVKK 5(2)(f) meşru menfaat)

---

## 5. Verilerin Paylaşıldığı Üçüncü Taraflar (Veri İşleyenler)

| Hizmet | Sağlayıcı | Veri | Amaç | Yer |
|---|---|---|---|---|
| Backend & veritabanı | Supabase Inc. | Tüm hesap ve uygulama verileri | Saklama, kimlik doğrulama | ABD (AWS) |
| Push bildirimi | Google Firebase Cloud Messaging | Push token, bildirim içeriği | Bildirim teslimi | Küresel (Google) |
| Hata raporu (eklenirse) | Google Firebase Crashlytics | Cihaz modeli, OS, hata stack trace | Çökme teşhisi | Küresel |
| Hisse/fon fiyat bilgisi | Yahoo Finance, TEFAS, finans.truncgil.com | YOK — sadece sembol query'si gönderilir | Fiyat çekme | Küresel |

**Bu sağlayıcılar yalnızca veri işleyen (data processor) sıfatıyla, talimatlarımız doğrultusunda hareket eder. Veri sorumlusu sıfatı tarafımızda kalır.**

---

## 6. Yurt Dışına Veri Aktarımı

Supabase ve Firebase ABD'de barındırıldığı için verileriniz Türkiye dışına aktarılır. KVKK Madde 9 ve GDPR Madde 44-49 uyarınca:

- **AB üyesi kullanıcılar için:** Standart Sözleşme Maddeleri (SCC) ve sağlayıcıların GDPR uyumluluk taahhütleri çerçevesinde aktarım yapılır.
- **Türk kullanıcılar için:** KVKK Madde 9(1) kapsamında **açık rıza** alınmaktadır. Açık rızanızı kayıt sırasında onayladığınız "KVKK Aydınlatma Metni" içerisindeki onay kutusuyla vermektesiniz.

Aktarım yapılan ülke (ABD), KVK Kurulu'nun ilan ettiği "yeterli korumaya sahip ülkeler" listesinde olmadığından, yurt dışı aktarımı **açık rızanıza** dayanmaktadır.

---

## 7. Veri Saklama Süreleri

| Veri | Süre |
|---|---|
| Hesap verileri | Hesap silinene kadar |
| Varlık kayıtları | Hesap silinene kadar |
| Snapshot geçmişi | Son 365 gün rolling (eski kayıtlar otomatik silinir) |
| Disclaimer onay logu | Hesap silindikten sonra **3 yıl** (TBK Madde 146 zamanaşımı) |
| Push token | Cihaz uygulamayı sildiğinde veya logout'ta otomatik silinir |
| Hata raporları | 90 gün |
| db_logs (yalnızca hatalar) | 30 gün |

Hesabınızı sildiğinizde, yukarıda özel saklama süresi belirtilenler hariç tüm verileriniz **30 gün içinde** kalıcı olarak silinir.

---

## 8. Haklarınız (KVKK Madde 11 / GDPR Madde 15-22)

Bize başvurarak şu haklarınızı kullanabilirsiniz:

- **Bilgi alma hakkı:** Hangi verilerinizin işlendiğini öğrenmek
- **Erişim hakkı:** Verilerinizin bir kopyasını talep etmek
- **Düzeltme hakkı:** Yanlış/eksik verinin düzeltilmesi
- **Silme hakkı (right to erasure):** Verilerinizin silinmesi
- **Taşınabilirlik hakkı (GDPR):** Verilerinizi makine-okur formatta (JSON) almak
- **İşlemeye itiraz hakkı (GDPR):** Meşru menfaate dayanan işlemeye itiraz
- **Açık rızanızı geri çekme hakkı:** İlerideki işlemeyi durdurma

**Talep yöntemleri:**
1. **Uygulama içi:** Profil → Ayarlar → "Hesabımı Sil" / "Verilerimi İndir"
2. **E-posta:** `[İLETİŞİM E-POSTA]` adresine kimlik doğrulayıcı bilgilerle başvuru
3. **Web formu:** `[WEB SİTESİ]/data-request`

KVKK Madde 13(2) uyarınca taleplerinize **30 gün** içinde yanıt veririz.

**Şikayet hakkı:** Cevap memnun edici değilse:
- Türkiye: Kişisel Verileri Koruma Kurumu — kvkk.gov.tr
- AB: Yerel veri koruma otoriteniz (DPA)

---

## 9. Çocukların Verileri

Uygulama 18 yaş altı için tasarlanmamıştır. Kayıt sırasında 18 yaş üzeri olduğunuzu beyan edersiniz. 18 yaş altı bir kullanıcının veri girdiğini fark edersek, hesap derhal silinir.

GDPR Madde 8 uyarınca AB içinde 16 yaş altı için ebeveyn rızası gerekir; bu yaş grubunu kabul etmiyoruz.

---

## 10. Veri Güvenliği

Aldığımız teknik ve idari önlemler:

- **Aktarım:** TLS 1.2+ (HTTPS) zorunlu
- **Saklama:** Supabase tarafında at-rest şifreleme (AES-256)
- **Erişim:** Row-Level Security (RLS) ile her kullanıcı yalnızca kendi verisine erişebilir
- **Şifre:** Bcrypt hash (Supabase Auth)
- **Oturum:** JWT, 1 saat erişim + 7 gün yenileme tokenı; uygulama içi 10 dakika boşta kalma timeout'u
- **Loglama:** Üretimde sadece hatalar; hassas alanlar (e-posta, şifre, token) maskelenir
- **Geliştirici erişimi:** Yalnızca destek talebi sırasında ve müşteri onayıyla

KVKK Madde 12 uyarınca veri ihlali tespiti halinde:
- En geç **72 saat** içinde KVK Kurulu'na bildirim
- Etkilenen kullanıcılara doğrudan bildirim
- AB kullanıcıları için GDPR Madde 33-34 uyumlu süreç

---

## 11. Tanımlama Bilgileri (Çerez ve Yerel Depolama)

Uygulama mobil ortamda çalıştığı için web çerezleri **kullanılmaz**. Yerel depolama (SharedPreferences, SQLite cache) yalnızca:

- Oturum tokenı (Supabase Auth)
- Tema/dil tercihi
- Kayıtlı e-posta (kullanıcı isterse)
- Disclaimer onay durumu (yerel kopya)

için kullanılır. Üçüncü taraf takip / analitik / reklam SDK'sı içermez.

---

## 12. Yatırım Tavsiyesi Reddi (Disclaimer)

**sandık** bir portföy takip aracıdır. SPK (Sermaye Piyasası Kurulu) lisanslı bir yatırım danışmanı veya aracı kurum DEĞİLDİR. Uygulamada gösterilen fiyat, performans, sinyal ve grafikler bilgilendirme amaçlıdır ve yatırım tavsiyesi niteliği taşımaz. Yatırım kararlarınızı SPK lisanslı bir danışmana danışarak veriniz.

Bu disclaimer, ilk kullanım sırasında ayrıca onaylatılır ve onay kaydı yasal kanıt olarak saklanır.

---

## 13. Politikada Değişiklikler

Bu politikada değişiklik yaptığımızda:
- Uygulama içinde bildirim gösterilir
- "Son güncelleme" tarihi yenilenir
- Önemli değişikliklerde e-posta gönderilir
- Yeni KVKK aydınlatma metni gerektiren değişikliklerde tekrar onay istenir

30 gün içinde itiraz etmezseniz değişikliği kabul etmiş sayılırsınız.

---

## 14. İletişim

Veri korumayla ilgili tüm soru, talep ve şikayetler için:

- **E-posta:** `[İLETİŞİM E-POSTA]`
- **Adres:** `[AÇIK ADRES]`
- **Veri Koruma Sorumlusu (DPO, varsa):** `[DPO İSİM] — [DPO E-POSTA]`

---

*Bu politika [Türkçe] ve [İngilizce] dillerinde sunulmaktadır. Yorum farklılığı durumunda Türkçe versiyon esas alınır.*
