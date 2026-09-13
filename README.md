# sandık

Kişisel portföy takibi — hisse (BIST), TEFAS fonu, döviz, altın, vadeli mevduat.
Flutter (Riverpod) istemci + Supabase (Postgres, RLS, Edge Functions, pg_cron) arka uç.
Android ana ekran widget'ı, iOS widget + Live Activity, FCM/APNs push.

**Sürüm:** `pubspec.yaml` · **Paket:** `portfoy_takip` · **Dil:** Türkçe (arayüz), TR/EN yasal metinler.

## Nereden başlanır

| Ne arıyorsun | Dosya |
|---|---|
| Geliştirme kuralları, komutlar, proje yapısı | [`CLAUDE.md`](CLAUDE.md) |
| Bugünkü durum: artılar, eksiler, güvenlik bulguları, yol haritası | [`docs/DEGERLENDIRME_VE_YOL_HARITASI_2026_09.md`](docs/DEGERLENDIRME_VE_YOL_HARITASI_2026_09.md) |
| Yol haritasında nerede kalındı | [`docs/YOL_HARITASI_ILERLEME.md`](docs/YOL_HARITASI_ILERLEME.md) |
| Senin elinden geçmesi gereken deploy / hukuki / mağaza işleri | [`YAPMAN_GEREKENLER.md`](YAPMAN_GEREKENLER.md) |
| Ertelenmiş kod kararları (borç defteri) | [`TECHNICAL_DEBT.md`](TECHNICAL_DEBT.md) |
| Güvenlik denetimi (Ağustos 2026) | [`SECURITY_AUDIT_2026_08.md`](SECURITY_AUDIT_2026_08.md) |
| Play Store yayın rehberi | [`PLAY_STORE_YAYIN_REHBERI.md`](PLAY_STORE_YAYIN_REHBERI.md) |
| Ücretli katman planı | [`MONETIZATION_ROADMAP.md`](MONETIZATION_ROADMAP.md) |
| Bildirim / geri dönüş stratejisi | [`RETENTION_STRATEJISI.md`](RETENTION_STRATEJISI.md) |
| iOS kurulum notları, SMTP, App Group, Live Activity | [`docs/`](docs/) |
| Eski raporlar ve tamamlanmış faz kayıtları | [`docs/archive/`](docs/archive/) |

## Hızlı komutlar

```bash
flutter pub get
flutter analyze lib/ test/
flutter test                       # 155 dosya; tek dosya: flutter test test/<ad>_test.dart
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

Supabase tarafı:

```bash
supabase db push                   # supabase/migrations/ tek doğruluk kaynağı
supabase functions deploy <ad>     # supabase/functions/<ad>/
deno test --allow-all supabase/tests/
```

Gizli anahtarlar `--dart-define` ile gelir; repoda `google-services.json`,
`GoogleService-Info.plist`, `key.properties`, keystore **yoktur** ve olmamalıdır.
CI (`.github/workflows/`) bunları secret'lardan yazar.

## Dizin yapısı

```
lib/
  config/       dart-define okuyan Supabase yapılandırması
  models/       Asset, Position, AssetType, kategori/alt tür enum'ları
  providers/    Riverpod: auth, portfolio, preferences, watchlist, signal, bulk cart
  screens/      Ekranlar (ana, portföy, performans, profil, ayarlar, ekleme akışları…)
  services/     Supabase erişimi, fiyat kaynakları, geçmiş/özet hesapları, push, widget
  theme/        sandik.dart — renk/tipografi/spacing/radius/motion token'ları
  utils/        tr_format, friendly_error, grafik yardımcıları
  widgets/      Paylaşılan bileşenler (grafikler, kartlar, şeritler, diyaloglar)
test/           Birim + widget + parite/değişmez testleri
supabase/
  migrations/   0007…  sıralı şema (tek kaynak)
  functions/    Edge Functions (+ _shared/)
  tests/        Deno testleri
android/ ios/   Platform kodu; ios/SandikWidget/ Live Activity + widget
tool/           Yerel betikler (emülatör dağıtımı, ikon üretimi)
store_listing/  Mağaza metinleri ve ekran görüntüsü üretimi
legal/          KVKK, gizlilik, kullanım koşulları (tr/en)
```
