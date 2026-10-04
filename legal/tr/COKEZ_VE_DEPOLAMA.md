# Çerez ve Yerel Depolama Politikası — sandık

**Yürürlük tarihi:** 4 Ekim 2026
**Sürüm:** 1.1

---

## 1. Genel

**sandık** mobil bir uygulamadır ve geleneksel web çerezleri (HTTP cookies) **kullanmaz**. Bu politika, uygulamanın cihazınızda kullandığı yerel depolama mekanizmalarını ve uygulamadaki ölçüm araçlarını açıklar; KVKK, GDPR ve ePrivacy Direktifi (2002/58/EC) kapsamındaki bilgilendirme amacını taşır.

---

## 2. Kullanılan Yerel Depolama Türleri

### 2.1 Güvenli Anahtar Deposu (iOS Keychain / Android Keystore)

Oturum token'ları (Supabase Auth) burada saklanır:

- **Erişim token'ı (JWT):** 1 saat geçerli
- **Yenileme token'ı:** her yenilemede değişir
- Uygulama 10 dakikadan uzun arka planda kalırsa uygulama kilidi açıksa kilitlenir, değilse oturum kapanır

Bu token'lar oturum açma için **zorunludur** (sözleşmenin ifası — KVKK 5(2)(c) / GDPR 6(1)(b)).

### 2.2 SharedPreferences (Android) / NSUserDefaults (iOS)

İşletim sisteminin sağladığı küçük anahtar-değer deposu. İçinde tutulanlar:

| İçerik | Amaç | Saklama süresi |
|---|---|---|
| Kayıtlı e-posta ("Beni hatırla" seçerseniz ya da kayıttan sonra) | Giriş ekranını doldurmak | "Beni hatırla" seçilmeden giriş yapılana ya da uygulama silinene kadar |
| Tema, dil, yazı boyutu, görünüm tercihleri | Arayüz ayarları | Uygulama silinene kadar |
| Bildirim, uygulama kilidi ve gizlilik (tutarları gizle) tercihleri | Kullanıcı tercihi | Uygulama silinene kadar |
| Yasal metin ve yatırım uyarısı onay durumu (yerel kopya) | Onayı tekrar sormamak | Metnin sürümü değişene kadar |
| Rastgele cihaz numarası ve kurulum numarası | Kayıtlı cihazlar ve kayıt hunisi | Uygulama silinene kadar |

### 2.3 Önbellek

Çevrimdışı açılış ve hız için cihazda tutulur:

- Son portföy kaydı (hesabınıza ait varlık listesi)
- Fiyat ve grafik serisi önbelleği
- Son baktığınız varlıklar

Asıl veri Supabase'dedir; çıkış yaptığınızda hesabınıza ait önbellek silinir.

### 2.4 Ana Ekran Widget'ı ve Kilit Ekranı

Ana ekran widget'ı için portföy özeti (toplam değer ve günlük değişim; "tutarları gizle" açıksa maskeli) iOS'ta uygulama grubunda, Android'de uygulama verisinde tutulur. iOS kilit ekranı canlı etkinliği açarsanız aynı özet Apple Push Notification service ile güncellenir. Çıkış yaptığınızda widget verisi temizlenir ve canlı etkinlik kapanır.

### 2.5 Push Notification Token (FCM)

Firebase Cloud Messaging, cihazınıza özel bir token üretir. Bu token:

- Yalnızca bildirim göndermek için kullanılır
- İşletim sisteminin bildirim izni verildiğinde Supabase'e kaydedilir
- Çıkış yapıldığında silinir; uygulama silinirse bir sonraki gönderimde geçersiz bulunup silinir

---

## 3. Ölçüm Araçları ve Kullanılmayan Mekanizmalar

Uygulamada şu Google Firebase araçları **bulunur** (ayrıntı: Gizlilik Politikası §3.5):

- **Firebase Analytics:** kullanım istatistikleri (ekranlar, özellik kullanım olayları); tutar, miktar ve e-posta gönderilmez
- **Firebase Crashlytics:** hata ve çökme raporları
- **Firebase Remote Config:** özelliklerin uzaktan açılıp kapatılması

Aşağıdakileri **kullanmıyoruz**:

- HTTP çerezleri (cookies)
- Web tracking pixel'leri
- Üçüncü taraf reklam SDK'ları (Google AdMob, Facebook Audience, AppLovin, vb.)
- Firebase dışındaki analitik / atıf SDK'ları (Mixpanel, Amplitude, Segment, Adjust, AppsFlyer, vb.)
- Reklam kimliği ve uygulamalar arası izleme (IDFA, GAID); Android'de reklam kimliği izni uygulamadan çıkarılmıştır, iOS'ta izleme beyanı kapalıdır
- Web view içinde üçüncü taraf içerik

---

## 4. ePrivacy Direktifi ("Cookie Yasası")

ePrivacy Direktifi (2002/58/EC) ve Türkiye Elektronik Haberleşme Kanunu Madde 51 kapsamında, "kesinlikle gerekli olmayan" izleme/depolama için **kullanıcı rızası** gerekir.

Oturum token'ı, önbellek ve tercihler hizmetin sağlanması için gereklidir ya da sizin seçiminizle (tema, "Beni hatırla", bildirim) etkinleşir. Firebase Analytics ve Crashlytics için yurt dışı aktarım, kayıt sırasında onayladığınız Açık Rıza Metni kapsamındadır.

---

## 5. Verilerinizi Cihazdan Silme

### 5.1 Uygulama İçinden
- **Çıkış:** Profil → Ayarlar → Çıkış Yap (oturum token'ı, hesabınıza ait önbellek ve tercihler ile widget verisi silinir)
- **Hesap silme:** Profil → Ayarlar → Hesabımı Sil (sunucudaki verileriniz hemen silinir, yasal saklama süreleri hariç; cihazdaki oturum kapanır)

### 5.2 İşletim Sistemi Üzerinden
- **Android:** Ayarlar → Uygulamalar → sandık → Depolama → Verileri Temizle
- **iOS:** Ayarlar → Genel → iPhone Depolama → sandık → Uygulamayı Sil

Uygulamayı kaldırmak cihaz üzerindeki **tüm yerel depolamayı siler**. Ancak sunucudaki verileriniz durur; onu silmek için hesap silme akışını kullanın.

---

## 6. Değişiklikler

Bu politikada değişiklik yapılırsa "Sürüm" numarası artırılır ve güncel metin bu adreste yayımlanır.

---

## 7. İletişim

Yerel depolamayla ilgili sorular için: `sandikapp.destek@gmail.com`
