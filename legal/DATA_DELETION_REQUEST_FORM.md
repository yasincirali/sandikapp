# Veri Silme Talep Formu / Data Deletion Request Form

> **NOT:** Bu sayfayı `https://yasincirali.github.io/sandikapp/data-deletion` URL'inde halka açık bir HTML formu olarak yayınlayın. Google Play hesap silme zorunluluğu için **Web URL** istemektedir; uygulama içi akışa ek olarak halka açık bir web sayfası gerekir.

---

## 🇹🇷 Türkçe

### sandık — Hesap ve Veri Silme Talebi

Hesabınızı silmek için iki seçeneğiniz var:

**Seçenek 1 — Uygulama İçinden (önerilen):**
1. sandık uygulamasını açın
2. Profile sekmesine gidin
3. Ayarlar → "Hesabımı Sil" butonuna tıklayın
4. Onay dialog'unda işlemi onaylayın
5. Hesabınız 30 gün içinde kalıcı olarak silinir

**Seçenek 2 — Bu Form İle:**
Aşağıdaki bilgileri `sandikapp.destek@gmail.com` adresine gönderin:

```
Konu: Hesap Silme Talebi

Ad-Soyad: ___________________
Hesap E-postası: ___________________
Talep Tarihi: ___________________
Açıklama (opsiyonel): ___________________
```

Talebiniz **30 gün** içinde işleme alınır. İşlem öncesi e-posta adresinizden onay isteriz (kimlik doğrulama).

### Silinen Veriler
- Hesap bilgileriniz (e-posta, display name)
- Tüm portföy varlık kayıtlarınız
- Performans snapshot geçmişiniz
- Ortaklık bağlantılarınız (karşı tarafın hesabından da çıkarılırsınız)
- Push bildirim token'ınız
- Yerel cihaz cache'iniz (uninstall ile)

### Yasal Saklama Süresi Olan Veriler
- **Disclaimer onay logu:** TBK Madde 146 zamanaşımı uyarınca silmeden sonra **3 yıl** anonim formda saklanır
- **Hata logları:** 90 gün sonra otomatik silinir

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
4. Confirm in the dialog
5. Your account is permanently deleted within 30 days

**Option 2 — Via This Form:**
Send the following to `sandikapp.destek@gmail.com`:

```
Subject: Account Deletion Request

Full name: ___________________
Account email: ___________________
Request date: ___________________
Notes (optional): ___________________
```

Your request will be processed within **30 days**. We will send a verification email before processing (identity verification).

### Data That Will Be Deleted
- Account information (email, display name)
- All your portfolio asset records
- Your performance snapshot history
- Partnership links (you'll also be removed from your partner's account)
- Push notification token
- Local device cache (after uninstall)

### Data With Legal Retention
- **Disclaimer acceptance log:** Anonymized form retained for **3 years** under Turkish CO Art. 146 statute of limitations
- **Error logs:** Auto-deleted after 90 days

### Questions?
Contact us at `sandikapp.destek@gmail.com`.

---

## Suggested HTML Form (deploy at `https://yasincirali.github.io/sandikapp/data-deletion`)

```html
<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <title>Hesap Silme — sandık</title>
  <meta name="viewport" content="width=device-width,initial-scale=1">
</head>
<body style="font-family:system-ui;max-width:640px;margin:40px auto;padding:0 16px;line-height:1.6">
  <h1>Hesap Silme Talebi — sandık</h1>
  <p>Hesabınızı silmek için aşağıdaki formu doldurun. 30 gün içinde işleme alınacaktır.</p>

  <form action="mailto:sandikapp.destek@gmail.com" method="post" enctype="text/plain">
    <p>
      <label>Ad-Soyad:<br>
        <input type="text" name="name" required style="width:100%;padding:8px">
      </label>
    </p>
    <p>
      <label>Hesap E-postası:<br>
        <input type="email" name="email" required style="width:100%;padding:8px">
      </label>
    </p>
    <p>
      <label>Açıklama (opsiyonel):<br>
        <textarea name="notes" rows="4" style="width:100%;padding:8px"></textarea>
      </label>
    </p>
    <p>
      <label>
        <input type="checkbox" required>
        Hesabımın ve verilerimin silineceğini, disclaimer onay logumun
        3 yıl anonim formda saklanacağını anladım.
      </label>
    </p>
    <button type="submit" style="background:#F5A623;color:#fff;border:0;padding:12px 24px;border-radius:8px;font-size:16px;cursor:pointer">
      Hesap Silme Talebimi Gönder
    </button>
  </form>

  <hr style="margin:40px 0">
  <p><small>
    sandık — <a href="/privacy">Gizlilik Politikası</a> ·
    <a href="/terms">Kullanım Koşulları</a> ·
    <a href="/legal/kvkk">KVKK Aydınlatma Metni</a>
  </small></p>
</body>
</html>
```

> Production'da `mailto:` yerine bir backend endpoint (örn. Supabase Edge Function veya basit bir web form servisi) kullanın ki spam'e karşı korunabilesiniz ve talep otomatik kuyruğa girsin.
