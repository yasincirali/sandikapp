# Faz A — Yayın Öncesi Bloker'ları Tamamlandı

**Tarih:** 2026-05-12
**Build durumu:** ✅ `flutter analyze` temiz · `flutter build apk --debug` başarılı

---

## 🔒 Güvenlik Düzeltmeleri (8 madde)

### A1+A2+A3: Davet RLS Açıkları (KRİTİK — zincirleme saldırı vektörü kapatıldı)

**Önce:**
- `invites_redeem_select` policy filtresiz — saldırgan tüm aktif davetleri okuyabiliyordu
- `invites_claim_update` policy davet ele geçirmeye izin veriyordu
- `partnerships_insert` policy onaysız ortaklık kurmayı sağlıyordu
- Sonuç: saldırgan **hiçbir onay almadan** mağdurun portföyünü okuyabilirdi

**Sonra:**
- [supabase/migrations/0008_harden_invite_rls.sql](supabase/migrations/0008_harden_invite_rls.sql) — 4 policy DROP edildi
- [supabase/functions/redeem-invite-code/](supabase/functions/redeem-invite-code/) — kod doğrulama service-role
- [supabase/functions/accept-invite/](supabase/functions/accept-invite/) — partnership creation service-role
- [lib/services/auth_service.dart](lib/services/auth_service.dart) — `submitPartnerCode`, `acceptInvite`, `rejectInvite` Edge Function'lara yönlendi

### A7: Davet Payload PII Sızıntısı

**Önce:** Payload statik 7-byte XOR ile obfuscate edilmiş (`{i: UUID, n: name, e: email}`); APK'da plaintext anahtar
**Sonra:** Payload yalnızca timestamp içeriyor — UUID, isim, email kaldırıldı. XOR fonksiyonları silindi. Server `code` üzerinden bilgiyi kendi tablosundan çeker.

### A5: db_logger PII Sanitizasyonu

**Önce:** `response_json` hata gövdesindeki email, JWT, UUID, IP loglara plaintext yazılıyordu
**Sonra:** [lib/services/db_logger.dart](lib/services/db_logger.dart) `_sanitizeMessage()` — regex ile JWT, Bearer, email, UUID, IPv4 maskelendi

### A6: db_logs Insert User_ID Check

**Önce:** Saldırgan başka kullanıcı UUID'siyle log enjekte edebilirdi (audit bozma)
**Sonra:** Migration 0008 — `WITH CHECK (user_id IS NULL OR user_id = auth.uid())`

### B5: delete-account Password Re-Auth

**Önce:** Edge Function yalnızca JWT doğruluyordu — çalıntı cihazda kilit açıkken saldırgan REST client ile hesabı silebilirdi
**Sonra:** [supabase/functions/delete-account/index.ts](supabase/functions/delete-account/index.ts) — body'den `password` alıyor, `signInWithPassword` ile server-side doğruluyor. Flutter tarafında client-side re-auth kaldırıldı (bypass riski).

### B1: Şifre Politikası Sıkılaştırma

**Önce:** Min 6 karakter, complexity yok ("123456" geçerdi)
**Sonra:** [auth_service.dart::validatePassword](lib/services/auth_service.dart) — min 8 + en az 1 harf + en az 1 rakam. Register validator hem client'ta hem server-side check'te kullanılır.

### E4: Android Backup Disabled

**Önce:** `allowBackup` default `true` — Google Drive yedeği üzerinden session token + saved_email başka cihaza taşınabilirdi
**Sonra:**
- [AndroidManifest.xml](android/app/src/main/AndroidManifest.xml) `android:allowBackup="false"` + `fullBackupContent="false"` + `dataExtractionRules="@xml/data_extraction_rules"`
- [data_extraction_rules.xml](android/app/src/main/res/xml/data_extraction_rules.xml) — tüm domain'leri cloud-backup + device-transfer dışı

### C1: handle_new_user search_path

**Önce:** SECURITY DEFINER trigger `search_path` set edilmemiş — pg_temp privilege escalation riski
**Sonra:** Migration 0008 — `SET search_path = public, pg_temp`

### Bonus: Disclaimer Immutability + Asset Constraints

- `disclaimer_acceptances` `FORCE ROW LEVEL SECURITY` — owner bypass'ı engelle
- `assets` CHECK constraint — quantity/purchase_price/current_price negatif/sınırsız değer engeli
- `profiles.display_name` CHECK — 1-60 karakter (push body taşması engeli)

### E3: Export Dosyası Cleanup

**Önce:** [data_export_service.dart](lib/services/data_export_service.dart) — JSON dosyası share sonrası geçici klasörde kalıyordu; root erişiminde veya yedek üzerinden okunabilirdi
**Sonra:** `try/finally` ile share sonrası `file.delete()`

---

## 🎨 UX Düzeltmeleri (5 madde)

### UA1: LoginScreen Çift Yönlendirme

**Önce:** `LoginScreen._login()` `pushAndRemoveUntil` ile elle navigate ediyordu; aynı anda AuthGate kendi yönlendirmesini yapıyordu. Yarış sonucu **yeni kullanıcı onboarding'i hiç görmüyordu**.
**Sonra:** [login_screen.dart](lib/screens/login_screen.dart) — manuel yönlendirme silindi. AuthGate disclaimer/onboarding/main akışını kendi başına yönetir.

### UA2: RegisterScreen popUntil

**Önce:** Register başarısı `Navigator.popUntil((r) => r.isFirst)` ile LoginScreen'e dönüyordu; AuthGate'in onboarding kontrolüyle yarışıyordu.
**Sonra:** [register_screen.dart](lib/screens/register_screen.dart) — popUntil silindi. AuthGate yeni kullanıcıyı OnboardingScreen'e götürür.

### UH1: "Açık Tema" Ölü Seçenek Kaldırıldı

**Önce:** Settings'te 3 chip (Sistem/Açık/Koyu); ama `theme: _buildTheme(), darkTheme: _buildTheme()` ikisi de aynı. "Açık seçince deneyseldir" notu güveni sarsıyordu.
**Sonra:** Tema seçici kaldırıldı; `themeMode: ThemeMode.dark` sabitlendi. Light theme implementasyonu Faz 3'te eklenirse seçici geri gelecek.

### UK3: Sahte Performans Simülasyonu Kaldırıldı

**Önce:** [portfolio_detail_screen.dart](lib/screens/portfolio_detail_screen.dart) `_getSimulatedPrice` — hisse %70, fon %50, döviz %20 yıllık return varsayarak **sahte** geçmiş grafik üretiyordu. Yatırım uygulamasında yanıltıcı + yasal risk.
**Sonra:** `HistoryService.getPortfolioHistory` ile gerçek snapshot verisi. Yetersiz veriyse "Yeterli veri yok — birkaç günlük veri biriktikten sonra grafiğin oluşacak" empty state.

### UC1: Register 4 Checkbox → 2'ye

**Önce:** 4 ayrı yasal checkbox (Disclaimer + KVKK + 18+ + Açık Rıza) — toplam 8 zorunlu etkileşim
**Sonra:** 2 checkbox:
1. **Yasal Koşullar** (Disclaimer + KVKK aydınlatma + 18+ yaş + Kullanım Koşulları + Gizlilik Politikası birleşik)
2. **Açık Rıza** (yurt dışı veri aktarımı) — KVKK Madde 9(1) zorunluluğu nedeniyle ayrı kalır

Linkler `_showLegalLinks()` ile tek dialog'da 3 belge URL'i listelenir.

---

## 📦 Yeni / Değişen Dosyalar

### Yeni dosyalar
- `supabase/migrations/0008_harden_invite_rls.sql`
- `supabase/functions/redeem-invite-code/index.ts`
- `supabase/functions/accept-invite/index.ts`
- `android/app/src/main/res/xml/data_extraction_rules.xml`
- `FAZ_A_COMPLETE.md` (bu dosya)

### Değişen dosyalar
- `lib/services/auth_service.dart` (Edge Function entegrasyonu, password politikası, payload temizleme)
- `lib/services/db_logger.dart` (response sanitizasyonu)
- `lib/services/data_export_service.dart` (cleanup)
- `lib/screens/login_screen.dart` (çift yönlendirme silindi)
- `lib/screens/register_screen.dart` (4→2 checkbox, password validator)
- `lib/screens/settings_screen.dart` (tema seçici silindi)
- `lib/screens/portfolio_detail_screen.dart` (gerçek snapshot grafiği)
- `lib/main.dart` (themeMode sabit)
- `supabase/functions/delete-account/index.ts` (password re-auth)
- `android/app/src/main/AndroidManifest.xml` (allowBackup=false)

---

## 🚀 Sen Yapacaksın — Deploy Adımları

Bu fix'lerin etkili olması için **Supabase deploy** zorunlu:

```bash
# 1. Migration uygula (RLS hardening + yeni constraint'ler)
supabase db push

# 2. Yeni Edge Function'ları deploy et
supabase functions deploy redeem-invite-code
supabase functions deploy accept-invite

# 3. Mevcut delete-account function'ı yeniden deploy et (password re-auth)
supabase functions deploy delete-account
```

> ⚠️ Migration 0008 mevcut policy'leri DROP eder. **Deploy edilmeden** uygulamayı production'a göndermeyin — Edge Function'lar olmadan davet akışı çalışmaz.

---

## ✅ Kanıtlama Adımları

Faz A doğrulaması için yapabileceğin manuel testler:

1. **Davet ele geçirme testi (A1+A2):**
   - 2 hesap aç (A ve B)
   - A hesabıyla davet kodu üret
   - C hesabıyla `partner_invites` tablosunu SQL Editor'de select'le → eski şemada A'nın daveti görünürdü; şimdi RLS reddeder.

2. **Şifre politikası testi (B1):**
   - Register'da "12345" gir → "en az 8 karakter" hatası
   - "abcdefgh" → "en az bir rakam"
   - "12345678" → "en az bir harf"
   - "abcd1234" → ✓

3. **Yedek testi (E4):**
   - `adb backup -f test.ab com.sandik.app` → "Backup API not supported" reddedilir

4. **Onboarding testi (UA1):**
   - Yeni hesap aç → register sonrası **OnboardingScreen** görünür
   - Atla → ana ekran. Tekrar login → onboarding görünmez ✓

5. **Sahte grafik testi (UK3):**
   - Bugün varlık ekle, hemen Portfolio Detail aç → "Yeterli veri yok" empty state (eskiden 1Y sahte trend gösterirdi)

---

## 📋 SECURITY_AND_UX_AUDIT.md Maddelerinden Geriye Kalanlar

### Faz B (Yayın sonrası 30 gün)

**Güvenlik:** B2 persistent rate limit, B3 email confirmation server-side, E1 friendlyError fallback, E2 settings_screen raw exception, E5 FLAG_SECURE, E6 Crashlytics PII sanitize, G1 clipboard sensitive flag, H2 register account enumeration

**UX:** UB1 hata pattern, UC2 disabled buton hint, UC3 login splash → inline, UD1 SandikErrorView retry widget, UG1 davet paylaşımı tek akış, UG2 davet klavye fix, UK1 portföy gizleme toggle, UI4 url_launcher

### Faz C (İyileştirme)

UA3 onboarding key user-bazlı, UB2-UB6 tutarsızlık, UC5 add asset disabled pattern, UD2 empty CTA, UD3 offline mode, UE1 lazy notification permission, UI1 bottom nav redundancy, UI3 back button tab, UJ1 brand voice, UK2 manuel fiyat banner

---

**Sonuç:** Faz A tamamlandı. Build temiz, kritik güvenlik açıkları kapatıldı, kullanıcı deneyimini bozan 5 ana mantıksızlık giderildi. Supabase deploy edildiğinde Play Store internal testing'e gönderilebilir.
