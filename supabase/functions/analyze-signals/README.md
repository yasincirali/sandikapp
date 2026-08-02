# analyze-signals Edge Function

Kullanıcıların portföyünü **sunucuda** analiz eder ve eşiği geçen sinyaller için
**gerçek push notification** gönderir. Uygulama kapalı olsa da bildirim gelir.

## Neden değişti (önemli)

Önceki sürüm "hibrit" idi: cron yalnızca data-only bir tetik atıyor, teknik
analizi client yapıyor ve bildirimi `flutter_local_notifications` ile
gösteriyordu. Bu tasarım pratikte **hiç çalışmıyordu**:

- Local notification, Dart kodunun çalışmasını gerektirir. Uygulama kapalıyken
  arka plan handler'ı yalnızca Firebase'i başlatıp çıkıyordu → bildirim yok.
- Analizi tetikleyen callback yalnızca `FirebaseMessaging.onMessage` içindeydi;
  o da sadece uygulama **ön plandayken** çalışır.
- iOS'ta `content-available` sessiz mesajları zaten garanti edilmez.

Ayrıca `summarize().confidence` 0..1 oranı dönerken eşikler 50/70/85 yüzde
ölçeğindeydi — `confidence < threshold` **her zaman** doğru oluyor, yani hiçbir
sinyal eşiği geçemiyordu. Bu hata `technical_analysis_service.dart` içinde
düzeltildi ve `test/signal_threshold_test.dart` ile kilitlendi.

## Akış

```
pg_cron  →  analyze-signals
              ├─ push token'ı olan kullanıcıları çek
              ├─ varlıkları çek (buy lot, manuel fiyatlı olmayan)
              ├─ signal_preferences oku (eşik + göstergeler)
              ├─ fiyat serilerini yükle (sembol başına TEK çekim + cache)
              ├─ TA çalıştır → summarize → eşik/nötr/de-dup filtresi
              ├─ signal_notifications tablosuna yaz
              └─ FCM notification payload → cihaz bildirimi
```

## Maliyet — neden ücretsiz katmanda kalır

Kritik tasarım kararı: **fiyat çekimi sembol başına tek sefer** yapılır ve
`price_history_cache` üzerinden tüm kullanıcılar arasında paylaşılır.

| | Naif yaklaşım | Bu yaklaşım |
|---|---|---|
| 1000 kullanıcı × 10 varlık | 10.000 Yahoo isteği | ~300-500 istek (benzersiz sembol) |
| Aynı gün 2. cron turu | 10.000 istek daha | **0** istek (cache TTL 12 saat) |
| Function süresi | dakikalarca | saniyeler |

İstek sayısı **kullanıcı sayısıyla değil portföy çeşitliliğiyle** ölçeklenir.
BIST'te ~500 sembol vardır; 10 kullanıcı da olsa 10.000 kullanıcı da olsa üst
sınır aynıdır.

**Kullanılan servisler ve ücretsiz limitler:**

| Servis | Ücretsiz limit | Bu özelliğin kullanımı |
|---|---|---|
| Supabase Edge Functions | 500K çağrı/ay | Günde 2 = **60/ay** |
| Supabase DB | 500 MB | cache + tercihler: birkaç MB |
| pg_cron / pg_net | dahil | 2 job |
| FCM | **sınırsız, ücretsiz** | gönderilen push sayısı |
| Yahoo Finance | resmi limit yok | cache ile minimize |

Ek ücret **yok**. Cron sıklığı artırılsa bile (saatlik = 720 çağrı/ay) 500K
limitinin çok altında kalır — sınır Yahoo'nun toleransıdır, Supabase değil.

## Kurulum

### 1. Migration

```bash
supabase db push     # 0015 + 0016
```

- **0015** — `signal_preferences` (kullanıcı × varlık türü: eşik, göstergeler,
  nötr) ve `price_history_cache` (sembol → kapanış serisi).
- **0016** — `signal_notifications` ve `user_push_tokens` tablolarını garantiye
  alır. Bunlar canlı veritabanında **eksikti**: 0010 bir noktada uygulanmadan
  atlanmış, `user_push_tokens` ise repoda hiç migration'ı olmayıp yalnızca
  dashboard'da elle oluşturulmuştu. Bu iki tablo olmadan push akışı çalışmaz
  (token yazılamaz, de-dup sorgusu patlar).

Doğrulama — üçü de `200` veya `[]` dönmeli, `404` dönmemeli:

```bash
URL=<SUPABASE_URL>; KEY=<ANON_KEY>
for t in signal_preferences price_history_cache signal_notifications user_push_tokens; do
  printf '%s -> ' "$t"
  curl -s -o /dev/null -w '%{http_code}\n' \
    "$URL/rest/v1/$t?select=*&limit=1" -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
done
```

### 2. Function deploy

```bash
supabase functions deploy analyze-signals --no-verify-jwt
```

`--no-verify-jwt` gerekli: function pg_cron'dan çağrılıyor, kullanıcı JWT'si
yok. Yetkilendirme `ANALYZE_SIGNALS_CRON_SECRET` header'ı ile.

### 3. Secret'lar

**Elle girilmesi gerekenler yalnızca üç tane:**

| Secret | Nereden |
|---|---|
| `FCM_PROJECT_ID` | Firebase proje id'si (`google-services.json` → `project_info.project_id`) |
| `FCM_SERVICE_ACCOUNT_JSON` | Firebase Console → Proje ayarları → Hizmet hesapları → *Yeni özel anahtar oluştur* |
| `ANALYZE_SIGNALS_CRON_SECRET` | Kendi ürettiğiniz rastgele uzun string |

`SUPABASE_URL` ve `SUPABASE_SERVICE_ROLE_KEY` **girilmez** — Supabase bunları
her edge function'a otomatik enjekte eder. Üstelik `SUPABASE_` öneki
rezervedir; o adla secret oluşturmaya çalışmak `Secret name must not start
with the SUPABASE_ prefix` hatası verir.

Secret'lar **proje geneli**dir, function başına değil. `FCM_PROJECT_ID` ve
`FCM_SERVICE_ACCOUNT_JSON` zaten `send-partner-invite-push` için tanımlıysa
tekrar girmeye gerek yok — yalnızca `ANALYZE_SIGNALS_CRON_SECRET` eklenir.

**CLI ile:**

```bash
supabase secrets set FCM_PROJECT_ID=sandik-4e2f2
supabase secrets set FCM_SERVICE_ACCOUNT_JSON="$(cat ~/Downloads/sandik-firebase-adminsdk.json | tr -d '\n')"
supabase secrets set ANALYZE_SIGNALS_CRON_SECRET="$(openssl rand -hex 32)"

supabase secrets list      # doğrula (değerler görünmez, yalnızca isim + hash)
```

**Dashboard ile:** Project Settings → Edge Functions → Secrets → *Add new secret*.

`FCM_SERVICE_ACCOUNT_JSON` tek satır olmalı — JSON'daki satır sonları
temizlenmeli (`tr -d '\n'`). Dashboard'a yapıştırırken de tek satır olarak
yapıştırın.

Secret değişikliği **anında** geçerlidir, yeniden deploy gerekmez.

### 4. pg_cron

**Durum: kurulu.** Migration `0017_analyze_signals_cron.sql` uzak veritabanına
uygulandı; iki job aktif (TR 11:00 ve 15:00).

Önce Vault'a secret eklenmeli — cron secret'ı SQL'e gömülmez:

```sql
select vault.create_secret('<CRON_SECRET>', 'analyze_signals_cron_secret');
```

`<CRON_SECRET>`, edge function'daki `ANALYZE_SIGNALS_CRON_SECRET` ile
**birebir aynı** olmalı. Doğrula (uzunluk 64 ve `matches` true olmalı —
PowerShell'den kopyalarken BOM eklenmesi tipik hatadır):

```sql
select length(decrypted_secret), decrypted_secret = '<CRON_SECRET>' as matches
from vault.decrypted_secrets where name = 'analyze_signals_cron_secret';
```

Sonra migration'ı uygula (satır başındaki `--` yorumu bayrak sanıldığı için
SQL'i argüman olarak DEĞİL dosya olarak ver):

```bash
supabase db query --linked --file supabase/migrations/0017_analyze_signals_cron.sql
```

Doğrulama — `net.http_post` asenkrondur, dönen boş sonuç "gönderildi"
anlamına gelmez; gerçek yanıt ayrı tabloda:

```sql
select public.trigger_analyze_signals('manual-test');
-- birkaç saniye sonra:
select status_code, content from net._http_response order by id desc limit 1;
```

`status_code = 200` beklenir. `sent: 0` dönmesi hata değildir: aynı sinyal
daha önce gönderilmişse de-dup tekrar göndermez.

### Daha sık sinyal istenirse

"Sinyal verdiği an" deneyimine yaklaşmak için cron sıklaştırılabilir. Borsa
saatlerinde saat başı:

```sql
select cron.schedule('analyze-signals-hourly', '0 7-15 * * 1-5',
  $$select public.trigger_analyze_signals('hourly')$$);
```

De-dup sayesinde aynı sinyal tekrar gönderilmez; sıklık artışı bildirim
spam'ine dönüşmez. Cache TTL'i (`price_history.ts` → `CACHE_TTL_MS`) saatlik
çalıştırmada 1 saate düşürülmeli, aksi halde gün içi fiyat değişimi görülmez.

## Test

### Dry-run (push göndermeden)

```bash
curl -X POST 'https://<PROJECT_REF>.supabase.co/functions/v1/analyze-signals' \
  -H 'Authorization: Bearer <ANALYZE_SIGNALS_CRON_SECRET>' \
  -H 'Content-Type: application/json' \
  -d '{"slot":"manual","dry_run":true}'
```

Kimin hangi sinyali alacağını **göndermeden** listeler:

```json
{
  "ok": true, "dry_run": true,
  "users": 3, "assets": 18, "symbols": 11, "histories": 11,
  "evaluated": 15, "passed_threshold": 2, "sent": 2, "failed": 0,
  "preview": [
    { "asset": "THYAO", "signal": "sell", "confidence": 80, "threshold": 70 }
  ]
}
```

`histories < symbols` ise bazı semboller için fiyat çekilememiştir.
`evaluated > 0` ama `passed_threshold = 0` ise eşikler yüksek demektir.

### Gerçek gönderim

`dry_run` alanını çıkarın.

### Yerel testler

```bash
# TypeScript portu Dart ile birebir mi (280 gösterge çıktısı)
deno test --allow-read supabase/tests/

# Dart tarafı (eşik ölçeği, altın standart üretimi)
flutter test test/signal_threshold_test.dart test/ta_golden_vectors_test.dart
```

## TA motoru iki dilde — sapma riski

`_shared/technical_analysis.ts`, `lib/services/technical_analysis_service.dart`
dosyasının portudur. **Bir formül değişirse ikisi de değişmeli.**

Güvenlik ağı: `test/ta_golden_vectors_test.dart` Dart çıktısından 35 senaryo ×
8 gösterge = 280 vektör üretir (`GOLDEN=1` ile) ve `supabase/tests/` altına
yazar; Deno testi bunları doğrular.

Sinyal tipi ve açıklama metni **birebir**, sayısal değer 1e-6 göreceli
toleransla karşılaştırılır (IEEE-754 son-bit farkları için).

Testler bilinçli olarak `supabase/functions/**` DIŞINDA tutulur: o dizindeki
her dosya edge function bundle'ına dahil edilir, testler ve 117 KB'lık vektör
dosyası production'a gitmemeli.

Formül değiştirdiğinizde:

```bash
GOLDEN=1 flutter test test/ta_golden_vectors_test.dart   # vektörleri tazele
deno test --allow-read supabase/tests/       # portu doğrula
```

## Bilinen sınırlar

- **Premium göstergeler sunucuda hesaplanmaz.** Premium durumu sunucuda
  güvenilir biçimde bilinmiyor; push temel 5 göstergeyle üretilir. Uygulama içi
  analiz premium göstergeleri göstermeye devam eder.
- **Fon (TEFAS) verisi günlüktür.** Gün içi sinyal üretmez.
- **Altın türleri tek eğriye indirgenir** (`GC=F`). Çeyrek/yarım/ata altın aynı
  orana bağlı olduğu için teknik gösterge sonucu aynıdır; ağırlık çarpanı
  eğrinin şeklini değiştirmez.
- **Cron günde 2 kez** — "sinyal verdiği an" değil. Yukarıdaki sıklaştırma
  bölümüne bakın.
