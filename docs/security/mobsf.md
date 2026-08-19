# MobSF — Yayın Öncesi APK/IPA Güvenlik Taraması

**Amaç:** Mağazaya gönderilecek derlenmiş artefaktı (APK/IPA), içine bir
sır sızıp sızmadığı ve manifest/imza sertleştirmesinin doğru olup olmadığı
açısından son bir kez denetlemek.

MobSF ([Mobile Security Framework](https://github.com/MobSF/Mobile-Security-Framework-MobSF))
statik analizde şunlara bakar:

- **AndroidManifest / Info.plist** — `exported` bileşenler, izinler,
  `allowBackup`, cleartext trafik, `debuggable`.
- **Gömülü sırlar** — binary'ye veya kaynaklara sızmış API anahtarı,
  token, private key.
- **İmza & sertifika** — imza şeması, sertifika geçerliliği.
- **Native kütüphaneler** — bilinen zafiyetli/izleyici (tracker) kütüphaneler.
- **Genel sertleştirme** — eksik güvenlik en iyi uygulamaları.

## ⚠️ Kapsam sınırı — MobSF Dart kodunu okuyamaz

Uygulamanın iş mantığı Flutter AOT derlemesiyle `libapp.so` içinde **makine
kodu** olur. MobSF Java/Kotlin'i decompile eder ama Dart'ı çözemez. Yani bu
tarama **kabuğu** denetler: manifest, native lib, kaynaklar, gömülü string'ler.

Uygulama mantığının (auth akışı, RLS, edge function yetkilendirmesi, PII
işleme) güvenlik incelemesi **ayrıdır** ve kaynak seviyesinde yapılır —
bkz. [`SECURITY_AUDIT_2026_08.md`](../../SECURITY_AUDIT_2026_08.md) ve
[`SECURITY_AND_UX_AUDIT.md`](../../SECURITY_AND_UX_AUDIT.md).

Bu iki katman birbirini tamamlar; biri diğerinin yerine geçmez.

## CI'da nasıl çalışır

[`.github/workflows/mobsf-scan.yml`](../../.github/workflows/mobsf-scan.yml)
`v*` tag push'unda ve elle (`workflow_dispatch`) tetiklenir:

1. Release APK'yı `android-release.yml` ile aynı `--dart-define`'larla üretir.
2. MobSF'i Docker'da ayağa kaldırır (`opensecurity/mobile-security-framework-mobsf`).
3. REST API ile upload → scan → JSON rapor.
4. `security_score` eşiğin (`MOBSF_MIN_SCORE`, varsayılan **60**) altındaysa
   veya (sertleştirildiğinde) HIGH bulgu varsa iş kırılır.
5. `mobsf-report.json` artefakt olarak yüklenir (30 gün).

### Gerekli secret'lar

| Secret | Zorunlu | Açıklama |
|--------|---------|----------|
| `GOOGLE_SERVICES_JSON_BASE64` | ✅ | APK build'i için (mevcut) |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | ✅ | dart-define (mevcut) |
| `MOBSF_API_KEY` | ⭕ | MobSF REST API anahtarı; yoksa CI-yerel sabit kullanılır |

### Kademeli sertleştirme (bilinçli)

İlk turda kapı **yalnızca skoru** zorlar; HIGH bulgular **uyarı** olarak
raporlanır. Gerekçe: mevcut bulguları önce görüp sınıflandırmak, sonra
gürültüsüz bir kapı kurmak. Sınıflandırma bittikten sonra
`Evaluate results` adımındaki ilgili satır `failed = True` yapılarak HIGH
bulgular da kapıya çevrilir.

## Yerelde çalıştırma (Windows / Docker)

```bash
# 1) MobSF'i başlat
docker run --rm -it -p 8000:8000 \
  opensecurity/mobile-security-framework-mobsf:latest
# Tarayıcıda http://localhost:8000 — API anahtarı ilk açılışta görünür.

# 2) Release APK üret (flutter yolu: /c/flutter/bin/flutter)
/c/flutter/bin/flutter build apk --release \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...

# 3) build/app/outputs/flutter-apk/app-release.apk dosyasını web arayüzünden
#    yükle → tarama otomatik başlar → raporu incele.
```

iOS için: `flutter build ipa` çıktısındaki `.ipa`'yı aynı arayüzden yükle.

## Raporu okuma

- **security_score** — 0–100 özet. 60 altı: ele alınması gereken bulgular var.
- **manifest_analysis** — HIGH burada çıkarsa (`exported` bileşen, cleartext,
  `debuggable`) doğrudan aksiyon al. Bu projede beklenen durum:
  `allowBackup=false`, cleartext yok, `debuggable` release'te yok.
- **secrets / possible_hardcoded_secrets** — burada bir Supabase **anon**
  key görülmesi beklenir ve sorun değildir (istemci tanımlayıcısı, RLS ile
  korunur). `service_role`, private key veya parola görülmesi **kritiktir**.
- **trackers** — Firebase/Crashlytics beklenir.

## İlgili

- [SECURITY_AUDIT_2026_08.md](../../SECURITY_AUDIT_2026_08.md) — kaynak-seviyesi audit (S1–S8)
- [YAPMAN_GEREKENLER.md](../../YAPMAN_GEREKENLER.md) — yayın öncesi elle adımlar
