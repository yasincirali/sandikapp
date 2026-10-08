# Veri Silme Talep Formu / Data Deletion Request Form

<!-- Bu dosya docs/_build_legal.py ile data-deletion/ ve data-request/
     sayfalarına basılır; buraya yazılan her satır Play incelemecisinin
     tıkladığı halka açık sayfada görünür. Yayın notu legal/README.md'de.
     2026-10-04: metin uygulamanın gerçek davranışına uyduruldu (silme
     anında; saklama süreleri Gizlilik Politikası §7 ile aynı). Önceki
     sürümdeki "önerilen HTML form" kod bloğu geliştirici notuydu ve
     halka açık sayfada görünüyordu; kaldırıldı. -->

---

## 🇹🇷 Türkçe

### sandık — Hesap ve Veri Silme Talebi

Hesabınızı silmek için iki seçeneğiniz var:

**Seçenek 1 — Uygulama İçinden (önerilen):**
1. sandık uygulamasını açın
2. Profil sekmesine gidin
3. Ayarlar → "Hesabımı Sil" butonuna tıklayın
4. Şifrenizle (Apple veya Google ile açılmış hesapta sağlayıcınızla) kimliğinizi doğrulayıp işlemi onaylayın
5. Hesabınız ve verileriniz **hemen** kalıcı olarak silinir

**Seçenek 2 — E-posta İle:**
Aşağıdaki bilgileri hesabınızın e-posta adresinden `sandikapp.destek@gmail.com` adresine gönderin:

```
Konu: Hesap Silme Talebi

Ad-Soyad: ___________________
Hesap E-postası: ___________________
Talep Tarihi: ___________________
Açıklama (opsiyonel): ___________________
```

Talebiniz **30 gün** içinde işleme alınır. İşlem öncesi e-posta adresinizden onay isteriz (kimlik doğrulama).

Silmeden önce verilerinizin bir kopyasını almak isterseniz: Profil → Ayarlar → "Verilerimi İndir" (JSON dosyası).

### Silinen Veriler
- Hesap bilgileriniz (e-posta, kullanıcı adı)
- Tüm portföy varlık kayıtlarınız, mevduat ve BES sözleşme bilgileriniz
- Performans geçmişiniz, Yarış ve Zirvedeki Portföyler ölçümleriniz ve Zirve rıza kaydınız
- Takip listesi, fiyat alarmları, bildirim tercihleri ve bildirim kayıtlarınız
- Ortaklık bağlantılarınız (karşı tarafın hesabından da çıkarılırsınız)
- Kayıtlı cihazlarınız ve push bildirim token'ınız
- Cihazdaki oturum ve hesabınıza ait önbellek (uygulamayı kaldırınca bütün yerel veriler)

### Silmeden Sonra Kalan Kayıtlar
- **Yasal metin onay kayıtları** (Kullanım Koşulları, Gizlilik Politikası, KVKK Aydınlatma Metni, Açık Rıza Metni, yatırım uyarısı): TBK Madde 146 zamanaşımı uyarınca silmeden sonra **3 yıl** saklanır; yalnızca yasal kanıt için tutulur, uygulamada kimseye görünmez
- **Hata kayıtları:** hesabınızla bağı kaldırılarak en geç 30 gün içinde silinir
- **Kayıt hunisi adımları:** hesabınızla bağı kaldırılarak, rastgele kurulum numarasıyla en geç 400 gün içinde silinir
- **Firebase'deki hata raporları ve kullanım istatistikleri:** kendi saklama süreleri sonunda (hata raporları 90 gün, kullanım istatistikleri en fazla 14 ay) silinir
- **Anonim silme kaydı:** hesap kimliğinizin tek yönlü özeti ve e-posta adresinizin alan adı (ör. gmail.com); silmeden sonra **3 yıl** saklanır, süresi dolunca otomatik silinir
- **Oturum açma güvenlik kaydı** (IP, cihaz/tarayıcı): Supabase Auth güvenlik kaydında tutulur; 90 günden eski kayıtlar her gün otomatik silinir

Ayrıntı: Gizlilik Politikası §7.

### Soru?
`sandikapp.destek@gmail.com` adresinden bize ulaşın.

---

## 🇬🇧 English

### sandık — Account and Data Deletion Request

You have two options to delete your account:

**Option 1 — In-App (recommended):**
1. Open the sandık app
2. Go to the Profile tab
3. Settings → "Delete Account"
4. Verify your identity with your password (or with Apple / Google for accounts created that way) and confirm
5. Your account and data are permanently deleted **immediately**

**Option 2 — Via Email:**
Send the following from your account email to `sandikapp.destek@gmail.com`:

```
Subject: Account Deletion Request

Full name: ___________________
Account email: ___________________
Request date: ___________________
Notes (optional): ___________________
```

Your request will be processed within **30 days**. We will send a verification email before processing (identity verification).

To keep a copy of your data before deleting: Profile → Settings → "Download My Data" (JSON file).

### Data That Will Be Deleted
- Account information (email, username)
- All your portfolio asset records, deposit and pension (BES) contract details
- Your performance history, Race and Top Portfolios measurements and your Top Portfolios consent record
- Watchlist, price alerts, notification preferences and notification records
- Partnership links (you'll also be removed from your partner's account)
- Registered devices and push notification token
- The session and your cached data on the device (all local data when you uninstall)

### Records Kept After Deletion
- **Legal acceptance records** (Terms of Service, Privacy Policy, KVKK Disclosure, Explicit Consent Notice, investment disclaimer): kept for **3 years** after deletion under the Turkish Code of Obligations Art. 146 limitation period, solely as legal evidence; not visible to anyone in the app
- **Error logs:** unlinked from your account and deleted within 30 days at the latest
- **Sign-up funnel steps:** unlinked from your account, kept under a random installation number and deleted within 400 days at the latest
- **Crash reports and usage statistics in Firebase:** deleted at the end of their own retention periods (crash reports 90 days, usage statistics at most 14 months)
- **Anonymous deletion record:** a one-way hash of your account ID and the domain of your email address (e.g. gmail.com); kept for **3 years** after deletion, then deleted automatically
- **Sign-in security log** (IP, device/browser): kept in the Supabase Auth security log; entries older than 90 days are deleted automatically every day

Details: Privacy Policy §7.

### Questions?
Contact us at `sandikapp.destek@gmail.com`.
