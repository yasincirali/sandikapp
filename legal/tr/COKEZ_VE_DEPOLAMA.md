# Ã‡erez ve Yerel Depolama PolitikasÄ± â€” sandÄ±k

**YÃ¼rÃ¼rlÃ¼k tarihi:** 11 MayÄ±s 2026
**SÃ¼rÃ¼m:** 1.0

---

## 1. Genel

**sandÄ±k** mobil bir uygulamadÄ±r ve geleneksel web Ã§erezleri (HTTP cookies) **kullanmaz**. Bu politika, uygulamanÄ±n cihazÄ±nÄ±zda kullandÄ±ÄŸÄ± yerel depolama mekanizmalarÄ±nÄ± aÃ§Ä±klar ve KVKK + GDPR + ePrivacy Direktifi (2002/58/EC) uyumluluÄŸunu saÄŸlar.

---

## 2. KullanÄ±lan Yerel Depolama TÃ¼rleri

### 2.1 SharedPreferences (Android) / NSUserDefaults (iOS)

Ä°ÅŸletim sisteminin saÄŸladÄ±ÄŸÄ± kÃ¼Ã§Ã¼k key-value deposu. Ä°Ã§inde tutulan veriler:

| Anahtar | Ä°Ã§erik | AmaÃ§ | Saklama sÃ¼resi |
|---|---|---|---|
| `last_login_email` | KullanÄ±cÄ± isterse kayÄ±tlÄ± e-posta | "Beni hatÄ±rla" Ã¶zelliÄŸi | KullanÄ±cÄ± silene kadar |
| `theme_mode` | Tema tercihi (dark/light/system) | UI ayarÄ± | Uninstall'a kadar |
| `disclaimer_accepted_v1.0` | Disclaimer onay durumu | Tekrar gÃ¶stermemek | Disclaimer sÃ¼rÃ¼mÃ¼ deÄŸiÅŸene kadar |
| `notification_enabled` | Bildirim aÃ§Ä±k/kapalÄ± | KullanÄ±cÄ± tercihi | Uninstall'a kadar |

**KiÅŸisel veri iÃ§ermez** veya yalnÄ±zca kullanÄ±cÄ±nÄ±n aÃ§Ä±kÃ§a izin verdiÄŸi e-posta'yÄ± iÃ§erir.

### 2.2 Supabase Auth Session Token

Supabase SDK, oturum tokenlarÄ±nÄ± otomatik olarak gÃ¼venli bir ÅŸekilde saklar:

- **JWT access token:** 1 saat geÃ§erli
- **Refresh token:** 7 gÃ¼n geÃ§erli, otomatik yenilenir
- **Saklama yeri:** Android'de `EncryptedSharedPreferences`, iOS'ta Keychain

Bu token'lar oturum aÃ§ma iÃ§in **zorunludur** (sÃ¶zleÅŸmenin ifasÄ± â€” KVKK 5(2)(c) / GDPR 6(1)(b)). KullanÄ±cÄ± izni gerektirmez.

### 2.3 SQLite Yerel VeritabanÄ± (sqflite cache)

Performans iÃ§in bazÄ± veriler cihaz Ã¼zerinde Ã¶nbelleÄŸe alÄ±nÄ±r:

- Son fiyat bilgileri (geÃ§ici cache)
- GÃ¶rsel asset'ler

**HiÃ§bir kiÅŸisel veri** SQLite'da kalÄ±cÄ± saklanmaz; tÃ¼m asÄ±l veri Supabase'dedir.

### 2.4 Push Notification Token (FCM)

Firebase Cloud Messaging, cihazÄ±nÄ±za Ã¶zel bir token Ã¼retir. Bu token:

- YalnÄ±zca bildirim gÃ¶ndermek iÃ§in kullanÄ±lÄ±r
- KullanÄ±cÄ±nÄ±n **aÃ§Ä±k rÄ±za** vermesiyle Supabase'e kaydedilir
- Logout veya uninstall'da silinir

---

## 3. KullanÄ±lmayan Mekanizmalar

AÅŸaÄŸÄ±dakileri **kullanmÄ±yoruz**:

- âŒ HTTP Ã§erezleri (cookies)
- âŒ Web tracking pixel'leri
- âŒ ÃœÃ§Ã¼ncÃ¼ taraf reklam SDK'larÄ± (Google AdMob, Facebook Audience, AppLovin, vb. â€” yok)
- âŒ ÃœÃ§Ã¼ncÃ¼ taraf analitik SDK'larÄ± (Mixpanel, Amplitude, Segment, Adjust, AppsFlyer, vb. â€” yok)
- âŒ Cross-app tracking (IDFA, GAID kullanÄ±mÄ± yok)
- âŒ Web view iÃ§inde third-party content

---

## 4. ePrivacy Direktifi ("Cookie YasasÄ±")

ePrivacy Direktifi (2002/58/EC) ve TÃ¼rkiye Elektronik HaberleÅŸme Kanunu Madde 51 kapsamÄ±nda, "kesinlikle gerekli olmayan" izleme/depolama iÃ§in **kullanÄ±cÄ± rÄ±zasÄ±** gerekir.

sandÄ±k'Ä±n kullandÄ±ÄŸÄ± tÃ¼m yerel depolama mekanizmalarÄ± **hizmetin saÄŸlanmasÄ± iÃ§in kesinlikle gereklidir** veya kullanÄ±cÄ±nÄ±n aÃ§Ä±k tercihiyle (theme, "Beni hatÄ±rla", notification) etkinleÅŸtirilir. Bu nedenle ek bir "Ã§erez bildirimi banner'Ä±" gerekmez.

---

## 5. Verilerinizi Cihazdan Silme

### 5.1 Uygulama Ä°Ã§inden
- **Logout:** Profile â†’ Ã‡Ä±kÄ±ÅŸ Yap (oturum tokenÄ± silinir; yerel cache temizlenir)
- **Hesap silme:** Profile â†’ Ayarlar â†’ HesabÄ±mÄ± Sil (tÃ¼m yerel + sunucu verisi silinir)

### 5.2 Ä°ÅŸletim Sistemi Ãœzerinden
- **Android:** Ayarlar â†’ Uygulamalar â†’ sandÄ±k â†’ Depolama â†’ Verileri Temizle
- **iOS:** Ayarlar â†’ Genel â†’ iPhone Depolama â†’ sandÄ±k â†’ UygulamayÄ± Sil

Uninstall, cihaz Ã¼zerindeki **tÃ¼m yerel depolamayÄ± siler**. Ancak Supabase'deki sunucu verisi durur â€” onu silmek iÃ§in ayrÄ±ca hesap silme akÄ±ÅŸÄ±nÄ± kullanÄ±n.

---

## 6. DeÄŸiÅŸiklikler

Bu politikada deÄŸiÅŸiklik yapÄ±lÄ±rsa "SÃ¼rÃ¼m" numarasÄ± artÄ±rÄ±lÄ±r ve uygulama iÃ§i bildirim gÃ¶sterilir.

---

## 7. Ä°letiÅŸim

Yerel depolamayla ilgili sorular iÃ§in: `[Ä°LETÄ°ÅÄ°M E-POSTA]`

