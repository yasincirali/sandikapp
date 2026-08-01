# Supabase Custom SMTP — Resend Kurulumu

> Supabase default SMTP 4 email/saat ile sınırlı ve prod için desteklenmez. Bu rehber Resend'i (3000 mail/ay ücretsiz, developer-friendly) Supabase ile bağlar. Kurulum ~10 dk.

## 1. Resend Hesabı

1. https://resend.com → **Sign up** (`sandikapp.destek@gmail.com` ile)
2. Email doğrulama → dashboard aç

## 2. API Key Al

1. Sol menü **API Keys** → **Create API Key**
2. Name: `supabase-auth-emails`
3. Permission: **Sending access** → tüm domain'ler
4. **Create API Key** → uzun bir `re_...` string kopyala (bir daha görünmez, kaydet)

## 3. Domain Seçenekleri

**Seçenek A (hızlı, brand'siz):** Domain kaydetme, `onboarding@resend.dev` adresinden gönder. Setup bitti, Adım 4'e geç.

**Seçenek B (önerilen, kendi domain):** Domain sende varsa Resend'de doğrula (24 saat DNS propagation). Sonra `noreply@yasincirali.dev` gibi kendi adresinden mail gider. Şimdilik A ile başlayalım, ileride B'ye geçersin.

## 4. Supabase Custom SMTP Config

1. Supabase Dashboard → **Project Settings** → **Auth** → **SMTP Settings**
2. **"Enable Custom SMTP"** toggle → aç
3. Aşağıdaki değerleri gir:

| Alan | Değer |
|---|---|
| Sender email | `onboarding@resend.dev` (Seçenek A) veya `noreply@yasincirali.dev` (Seçenek B) |
| Sender name | `sandık` |
| Host | `smtp.resend.com` |
| Port | `465` |
| Username | `resend` |
| Password | Adım 2'de kopyaladığın `re_...` API key |
| Minimum interval between emails | `1` (saniye, default) |

4. **Save changes**

## 5. Email Template'i Türkçeleştir (opsiyonel)

Supabase → **Auth** → **Email Templates** → **Confirm signup**:

Subject (Turkish):
```
sandık - E-postanı doğrula
```

Body:
```html
<h2>sandık'a hoş geldin!</h2>
<p>E-posta adresini doğrulamak için 6 haneli kodu uygulamada gir:</p>
<h1 style="font-size: 32px; letter-spacing: 8px; color: #F5A623;">{{ .Token }}</h1>
<p>Kod 10 dakika geçerli. Bu talebi sen yapmadıysan bu mail'i görmezden gelebilirsin.</p>
<p style="color: #666; font-size: 12px; margin-top: 40px;">— sandık ekibi</p>
```

**Kritik:** Template'te `{{ .ConfirmationURL }}` yerine **`{{ .Token }}`** kullan — bizim akışımız link tıklama değil, kod girme.

## 6. Test

Save sonrası Supabase Dashboard'da **Auth → Users → Invite user** ile kendine test mail'i at. Gelmezse:
- Resend Dashboard → **Emails** → son gönderim listesi ve status'u gör
- Spam klasörüne bak (özellikle Seçenek A `resend.dev` domain'inde)

## 7. Rate limit ayar (opsiyonel)

Supabase → Auth → Rate limits → "Email OTP" değerini `10 per hour per user` → daha esnek. Default 4/saat çok kısıtlı.

---

## Troubleshooting

**"Mail hâlâ gelmiyor"** → Supabase Auth → Logs → son signup satırının response'una bak. `email_delivery_failed` görüyorsan SMTP config yanlış (host/port/password).

**"Spam'e düşüyor"** → Seçenek B'ye geç (kendi domain + SPF/DKIM/DMARC). Resend UI'da her domain için otomatik DNS kayıt önerileri gösterir.

**"Rate limited"** → Bir kullanıcı çok sık kod istiyor. `resendRegistrationOtp` client tarafında 60 sn cooldown var, buraya güvenebilirsin.
