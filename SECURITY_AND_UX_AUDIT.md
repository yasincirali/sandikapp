# sandık — Güvenlik & UX Audit Raporu

**Tarih:** 2026-05-12
**Tarafından:** Application Security Engineer + Senior UX Engineer (paralel audit)
**Kapsam:** Kullanıcı mağduriyetine yol açabilecek güvenlik açıkları + mantıksız UX akışları

---

## 🔥 YAYINI ENGELLEYEN KRİTİK BULGULAR

### Güvenlik — Zincirleme Saldırı Vektörü (A1+A2+A3)

Bir saldırgan, **hiçbir onay almadan** herhangi bir kullanıcının portföyünü okuyabilir. Zincirleme:

1. **A1 — Davet okuma sızıntısı:** `partner_invites` tablosunun `invites_redeem_select` policy'si herhangi bir authenticated kullanıcının **tüm aktif davet kayıtlarını listelemesine** izin veriyor (`code`, `from_user_id`, `requester_name`, `payload` dahil). Sınırlama yok — `to_user_id` veya `code` filtresi yok.

2. **A7 — Payload zayıf şifreleme:** Davet `payload` sadece statik 7-byte XOR ile obfuscate edilmiş; anahtar APK'da plaintext. Saldırgan listelediği davetleri çözüp tüm kullanıcı UUID'lerini elde eder.

3. **A3 — Doğrudan partnership ekleme:** `partnerships_insert` policy'si `auth.uid() = user_id_1 OR auth.uid() = user_id_2` diyor — yani saldırgan bilinen herhangi bir UUID ile `INSERT INTO partnerships` çağırarak **onay almadan** kendisini ortak yapabilir.

4. **A2 — Davet ele geçirme:** `invites_claim_update` policy'si `to_user_id IS NULL` olan davetlere `UPDATE` izin veriyor; saldırgan kendi UUID'sini yazıp daveti çalabilir.

5. **Sonuç:** `assets_partner_read` policy'si artık saldırgana **mağdurun tüm portföyünü okuma** yetkisi verir.

**Etki:** KVKK Madde 12 (veri güvenliği) + GDPR Art. 32 ağır ihlali. Play Store reddinin ötesinde KVK Kurulu para cezası (azami 100M ₺/2024 tarifesi).

### UX — Onboarding Atlanıyor

**A1 (UX):** `LoginScreen._login()` başarılı olunca **kendi başına** `pushAndRemoveUntil` ile yönlendirme yapıyor. AuthGate de aynı işi yapıyor. İkili yönlendirme yarışında onboarding `_onboardingDone` kontrolü tamamlanmadan ekran değişiyor → **yeni kullanıcı onboarding'i hiç görmüyor**.

### UX — "Açık tema" Ölü Doğmuş Özellik

Settings'te tema seçici 3 chip gösteriyor (Sistem / Açık / Koyu), ama `SandikApp.build` `theme: _buildTheme(), darkTheme: _buildTheme()` — ikisi de aynı dark theme. Açık seçilince hiçbir şey olmaz, sadece "deneyseldir" yazıyor. Yarım iş.

---

## 1) GÜVENLİK AUDIT

### KRİTİK (4)

| # | Konum | Sorun | Mağduriyet |
|---|---|---|---|
| **A1** | `supabase_schema.sql:135-140` | `invites_redeem_select` policy filtresiz tüm davetleri okutuyor | Saldırgan tüm aktif davet kodlarını dökerek mağdurun ortağı olur |
| **A2** | `supabase_schema.sql:142-152` | `invites_claim_update` policy davet ele geçirmeye izin veriyor | Saldırgan başkasının davetini kendine atfeder |
| **A3** | `supabase_schema.sql:176-177` | `partnerships_insert` davet/onay olmadan satır eklemeye izin veriyor | UUID bilinince **doğrudan** ortak olunur |
| **A7** | `auth_service.dart:464-470` | Davet payload XOR ile obfuscate; anahtar APK'da | A1+A3 ile zincirleme UUID elde edilir |

### YÜKSEK (4)

| # | Konum | Sorun | Mağduriyet |
|---|---|---|---|
| **A5** | `db_logger.dart:97-117` | `response_json` (hata gövdesi) maskelenmiyor | Hata mesajındaki PII (email, JWT) db_logs'ta sızıntı |
| **E4** | `AndroidManifest.xml` | `allowBackup` default = true | Google Drive yedeği → session token + saved_email başka cihazda |
| **B1** | `auth_service.dart:66-68` | Şifre min 6 karakter, complexity yok | Credential stuffing / weak password attack |
| **B5** | `delete-account/index.ts` | Edge function password'ü tekrar doğrulamıyor | Çalıntı cihazda kilidi açıkken hesabı doğrudan sil |

### ORTA (9)

| # | Konum | Sorun |
|---|---|---|
| A6 | `supabase_schema.sql:245-246` | `db_logs_insert` `user_id` check yok — log enjeksiyonu |
| B2 | `auth_service.dart:447-462` | Login rate-limit in-memory, restart ile sıfırlanıyor |
| B3 | `auth_service.dart:88-92` | Email confirmation Supabase Dashboard ayarına bağımlı — server-side check yok |
| C1 | `supabase_schema.sql:273-285` | `handle_new_user` SECURITY DEFINER, `search_path` set edilmemiş |
| E1 | `friendly_error.dart:85-97` | Türkçe karakter heuristic'i raw exception sızdırabilir |
| E2 | `settings_screen.dart:163-169` | `Beklenmedik hata: $e` raw exception gösteriyor |
| E3 | `data_export_service.dart:76-93` | Export JSON share sonrası silinmiyor — cihaz cache'inde kalıyor |
| E5 | `AndroidManifest.xml` | `FLAG_SECURE` yok — recents ekranında portföy görünüyor |
| E6 | `main.dart:43-53` | Crashlytics raw PII içerebilir |
| G1 | `profile_screen.dart:67` | Clipboard'a `code` plain, `EXTRA_IS_SENSITIVE` flag yok |
| H2 | `auth_service.dart:107-110` | "E-posta zaten kayıtlı" → account enumeration |

### DÜŞÜK (5)

C3 disclaimer FORCE RLS, D1 server-side CHECK constraint, D2 displayName length limit, G4 password autocorrect, I2 fiyat sanity check.

---

## 2) UX AUDIT

### KRİTİK (3)

| # | Konum | Sorun |
|---|---|---|
| **UA1** | `login_screen.dart:101-128` + `main.dart:447-477` | Çift yönlendirme — LoginScreen + AuthGate çakışıyor, onboarding atlanıyor |
| **UC1** | `register_screen.dart:295-386` | 4 yasal checkbox + 4 input = **8 zorunlu etkileşim**, dropoff yaratıyor |
| **UH1** | `main.dart:91-99` | Light/dark theme aynı; "Açık tema" seçeneği ölü |

### YÜKSEK (8)

| # | Sorun | Konum |
|---|---|---|
| UA2 | Register sonrası onboarding atlanıyor (`popUntil` yanlış) | `register_screen.dart:170-172` |
| UB1 | Hata gösterimi: SnackBar vs CupertinoDialog vs AlertDialog karışık | 5 farklı ekran |
| UC2 | Disabled submit butonu kullanıcıya neden disable olduğunu söylemiyor | `register_screen.dart:411` |
| UC3 | LoginScreen `_loading` durumunda full splash → form kayboluyor | `login_screen.dart:135` |
| UD1 | `AsyncValue.error` her yerde sadece text, retry yok | 5+ ekran |
| UG1 | Davet kodu — otomatik clipboard + ayrıca share butonu çelişkili | `profile_screen.dart:65-78, 343-349` |
| UG2 | Davet kodu girme: hint "ABCDE-12345" ama klavye `number` | `profile_screen.dart:393-405` |
| UK1 | Portföy gizleme (blur) modu yok — bus'ta açınca komşu görür | tüm ekranlar |

### ORTA (15)

UA3 onboarding key user-bazlı değil; UB2-UB5 logout/loading/period/buton tutarsızlıkları; UB6 pull-to-refresh tutarsız; UC4 email validation 3 farklı; UC5 add asset field görünür/kaybolma kafa karıştırıcı; UD2 boş state'lerde CTA yok; UD3 offline mode yok; UE1 bildirim izni hep istenir; UF1 "JSON" terminolojisi sade değil; UF2 disclaimer reshow Settings'te gereksiz; UG3 polling 3s sürekli; UG4 ortaklık ne paylaşıyor net değil; UI1 5 tab redundancy (Ana vs Portföy ikisi de chart); UI3 geri tuşu tab değil çıkış soruyor; UI4 yasal link dialog → URL, web değil; UJ1 "sen/siz" dil tutarsızlığı; UK2 manuel fiyat güncellenmediği belli değil; UK3 **sahte performans simülasyonu** (`_getSimulatedPrice`) yanıltıcı.

### DÜŞÜK (4)

UH2 GoogleFonts runtime download, UH3 renk körlüğü, UJ2 48dp touch target, UJ3 skeleton loaders.

---

## 3) ÖNERİLEN AKSIYON PLANI

### Faz A — Yayın Öncesi MUTLAKA (1-2 gün kod)

**Güvenlik:**
- [ ] **A1+A2+A3 RLS düzeltmeleri** — davet akışını tamamen Edge Function'a taşı (`accept-invite`, `redeem-invite-code`)
  - `invites_redeem_select` policy'sini sil
  - `invites_claim_update` policy'sini sil
  - `partnerships_insert` policy'sini sil (yalnızca service-role insert eder)
- [ ] **A7** — payload'dan UUID ve isim çıkar, sadece kod kalsın; backend zaten id'yi bilir
- [ ] **A5** — db_logger'da `response_json` sanitize (JWT, email, UUID regex temizliği)
- [ ] **B5** — delete-account Edge Function'ında password re-auth (body parameter)
- [ ] **B1** — şifre min 8 + harf/rakam kombinasyonu
- [ ] **E4** — `android:allowBackup="false"` + `dataExtractionRules`
- [ ] **C1** — `handle_new_user` `SET search_path = public, pg_temp` ekle
- [ ] **E3** — export dosyasını share sonrası sil

**UX:**
- [ ] **UA1** — LoginScreen'dan elle navigate kaldır, AuthGate'e bırak (onboarding fix)
- [ ] **UA2** — RegisterScreen sonrası popUntil yerine setState loading false
- [ ] **UH1** — "Açık tema" seçeneğini Settings'ten KALDIR (gerçek implementasyon Faz 3)
- [ ] **UK3** — `_getSimulatedPrice` simülasyonunu KALDIR, "yeterli veri yok" empty state'i göster
- [ ] **UC1** — Register'da 4 checkbox'ı 2'ye birleştir: (a) yasal + 18+ + KVKK aydınlatma, (b) yurt dışı açık rıza

### Faz B — Yayın Sonrası 30 Gün (3-5 gün kod)

**Güvenlik:**
- [ ] A6 db_logs_insert user_id check
- [ ] B2 persistent rate limit (SharedPreferences)
- [ ] B3 email confirmation server-side check
- [ ] E1 friendlyError fallback zorla
- [ ] E2 settings_screen.dart raw exception
- [ ] E5 FLAG_SECURE hassas ekranlarda
- [ ] E6 Crashlytics PII sanitize
- [ ] G1 clipboard sensitive flag + sadece kısa kod
- [ ] H2 register'da generic mesaj

**UX:**
- [ ] UB1 hata gösterimi tek pattern (`showAppError` helper)
- [ ] UC2 disabled buton hint
- [ ] UC3 LoginScreen splash yerine inline spinner
- [ ] UD1 `SandikErrorView(message, onRetry)` widget
- [ ] UG1 davet paylaşımı tek akış
- [ ] UG2 davet kodu klavye `text` + autocapitalize
- [ ] UK1 portföy gizleme toggle (göz ikonu)
- [ ] UI4 yasal link → `url_launcher` ile gerçek tarayıcı

### Faz C — İyileştirme (Faz 2-3)

UA3 onboarding key user-bazlı; UB2-UB6 tutarsızlık temizliği; UC5 add asset field disabled pattern; UD2 empty state CTA; UD3 offline mode; UE1 lazy notification permission; UI1 bottom nav redundancy; UI3 back button tab navigation; UJ1 brand voice; UK2 manuel fiyat banner.

---

## 4) UYGULAMANIN GENEL DURUMU

### Güçlü Yönler ✅
- Hesap silme akışı 2 kademeli + autofocus klavye — iyi
- TEFAS/BIST100 picker `_PickerShell` ile DRY
- `friendlyError` merkezi hata çevirisi var
- Disclaimer cache mantığı çağrı sayısını azaltır
- Push yoksa polling fallback — resilient
- KVKK belgeleri kapsamlı
- ProGuard/R8 + adaptive icon + dart-define hazır
- Hesap silme + veri export KVKK uyumlu

### Zayıf Yönler ❌
- **RLS politikalarında 3 ardışık açık** mağdura toplam portföy okutma riski
- Onboarding ve hesap silme akışları **çift yönlendirme** ile bozuluyor
- "Açık tema" UI'da var ama implementasyon yok
- `_getSimulatedPrice` sahte veri gösteriyor — yatırım uygulamasında yasal sorun
- Register'da bilişsel yük (8 zorunlu etkileşim) yüksek

---

## SONUÇ

Şu an Play Store'a submit edilirse:
- **Otomatik reddedilmez** (Faz 1 bloker'ları çözüldü)
- Ama **3-6 ay içinde KVK Kurulu denetimi olursa** A1+A2+A3 zinciri ortaya çıkar ve ciddi para cezası riski
- **Kullanıcılar onboarding'i hiç görmez** (UX gap)
- **Açık tema seçeneği güveni sarsar**

**Önerim:** Faz A'yı 1-2 gün içinde tamamla, sonra yayına çık. Faz B'yi yayın sonrası ilk ay içinde rollout et.

Şimdi Faz A'ya başlamayı önereyim mi, yoksa belirli bir konuya odaklanmamı ister misin?
