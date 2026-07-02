# Çerez ve Yerel Depolama Politikası — sandık

**Yürürlük tarihi:** 11 Mayıs 2026
**Sürüm:** 1.0

---

## 1. Genel

**sandık** mobil bir uygulamadır ve geleneksel web çerezleri (HTTP cookies) **kullanmaz**. Bu politika, uygulamanın cihazınızda kullandığı yerel depolama mekanizmalarını açıklar ve KVKK + GDPR + ePrivacy Direktifi (2002/58/EC) uyumluluğunu sağlar.

---

## 2. Kullanılan Yerel Depolama Türleri

### 2.1 SharedPreferences (Android) / NSUserDefaults (iOS)

İşletim sisteminin sağladığı küçük key-value deposu. İçinde tutulan veriler:

| Anahtar | İçerik | Amaç | Saklama süresi |
|---|---|---|---|
| `last_login_email` | Kullanıcı isterse kayıtlı e-posta | "Beni hatırla" özelliği | Kullanıcı silene kadar |
| `theme_mode` | Tema tercihi (dark/light/system) | UI ayarı | Uninstall'a kadar |
| `disclaimer_accepted_v1.0` | Disclaimer onay durumu | Tekrar göstermemek | Disclaimer sürümü değişene kadar |
| `notification_enabled` | Bildirim açık/kapalı | Kullanıcı tercihi | Uninstall'a kadar |

**Kişisel veri içermez** veya yalnızca kullanıcının açıkça izin verdiği e-posta'yı içerir.

### 2.2 Supabase Auth Session Token

Supabase SDK, oturum tokenlarını otomatik olarak güvenli bir şekilde saklar:

- **JWT access token:** 1 saat geçerli
- **Refresh token:** 7 gün geçerli, otomatik yenilenir
- **Saklama yeri:** Android'de `EncryptedSharedPreferences`, iOS'ta Keychain

Bu token'lar oturum açma için **zorunludur** (sözleşmenin ifası — KVKK 5(2)(c) / GDPR 6(1)(b)). Kullanıcı izni gerektirmez.

### 2.3 SQLite Yerel Veritabanı (sqflite cache)

Performans için bazı veriler cihaz üzerinde önbelleğe alınır:

- Son fiyat bilgileri (geçici cache)
- Görsel asset'ler

**Hiçbir kişisel veri** SQLite'da kalıcı saklanmaz; tüm asıl veri Supabase'dedir.

### 2.4 Push Notification Token (FCM)

Firebase Cloud Messaging, cihazınıza özel bir token üretir. Bu token:

- Yalnızca bildirim göndermek için kullanılır
- Kullanıcının **açık rıza** vermesiyle Supabase'e kaydedilir
- Logout veya uninstall'da silinir

---

## 3. Kullanılmayan Mekanizmalar

Aşağıdakileri **kullanmıyoruz**:

- ❌ HTTP çerezleri (cookies)
- ❌ Web tracking pixel'leri
- ❌ Üçüncü taraf reklam SDK'ları (Google AdMob, Facebook Audience, AppLovin, vb. — yok)
- ❌ Üçüncü taraf analitik SDK'ları (Mixpanel, Amplitude, Segment, Adjust, AppsFlyer, vb. — yok)
- ❌ Cross-app tracking (IDFA, GAID kullanımı yok)
- ❌ Web view içinde third-party content

---

## 4. ePrivacy Direktifi ("Cookie Yasası")

ePrivacy Direktifi (2002/58/EC) ve Türkiye Elektronik Haberleşme Kanunu Madde 51 kapsamında, "kesinlikle gerekli olmayan" izleme/depolama için **kullanıcı rızası** gerekir.

sandık'ın kullandığı tüm yerel depolama mekanizmaları **hizmetin sağlanması için kesinlikle gereklidir** veya kullanıcının açık tercihiyle (theme, "Beni hatırla", notification) etkinleştirilir. Bu nedenle ek bir "çerez bildirimi banner'ı" gerekmez.

---

## 5. Verilerinizi Cihazdan Silme

### 5.1 Uygulama İçinden
- **Logout:** Profile → Çıkış Yap (oturum tokenı silinir; yerel cache temizlenir)
- **Hesap silme:** Profile → Ayarlar → Hesabımı Sil (tüm yerel + sunucu verisi silinir)

### 5.2 İşletim Sistemi Üzerinden
- **Android:** Ayarlar → Uygulamalar → sandık → Depolama → Verileri Temizle
- **iOS:** Ayarlar → Genel → iPhone Depolama → sandık → Uygulamayı Sil

Uninstall, cihaz üzerindeki **tüm yerel depolamayı siler**. Ancak Supabase'deki sunucu verisi durur — onu silmek için ayrıca hesap silme akışını kullanın.

---

## 6. Değişiklikler

Bu politikada değişiklik yapılırsa "Sürüm" numarası artırılır ve uygulama içi bildirim gösterilir.

---

## 7. İletişim

Yerel depolamayla ilgili sorular için: `[İLETİŞİM E-POSTA]`
