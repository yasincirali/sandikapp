# Cron yetkilendirmesi — `x-cron-secret` deseni

Cron ile tetiklenen her edge function bu deseni kullanır. Sapma, **sessiz**
bir arızaya yol açar — nasıl olduğu aşağıda.

## Desen

```
Authorization: Bearer <service_role JWT>   → API gateway'i geçer
x-cron-secret: <rastgele uzun string>      → fonksiyon doğrular
```

İki ayrı kapı, iki ayrı sır. Fonksiyon tarafında tek satır:

```ts
import { cronYetkisiVarMi } from '../_shared/cron_auth.ts';

const yetkisiz = cronYetkisiVarMi(request, cronSecret);
if (yetkisiz) return yetkisiz;
```

SQL tarafında tek çağrı:

```sql
perform net.http_post(
  url     := '.../functions/v1/<fonksiyon>',
  headers := public.cron_headers('<vault_secret_adi>'),
  body    := '{}'::jsonb,
  timeout_milliseconds := 60000   -- ⚠️ ASLA atlanmaz, bkz. aşağıda
);
```

## ⚠️ Neden `Authorization`'a cron secret'ı KONULMAZ

Supabase API gateway, isteği fonksiyona iletmeden **önce** `Authorization`
header'ını JWT olarak ayrıştırır. Rastgele hex bir string JWT biçiminde
olmadığı için gateway isteği **fonksiyona hiç ulaştırmadan** reddeder:

```json
401 {"code":"UNAUTHORIZED_INVALID_JWT_FORMAT","message":"Invalid JWT"}
```

Bu arıza 2026 Mayıs–Eylül arası **dört ay** fark edilmedi. `daily_brief_log`
boştu: sabah brifingi hiç gönderilmemişti. Fark edilmemesinin sebebi
görünmezliği:

| Nereye bakılırsa | Ne görünür |
|---|---|
| `cron.job` | iş kurulu, zamanlama doğru ✓ |
| `cron.job_run_details` | koşu başarılı ✓ (pg_net isteği **kuyruğa aldı**) |
| Edge function logları | **boş** — fonksiyon hiç çalışmadı |
| `net._http_response` | 401 — **tek görünür yer** |

`live-activity-refresh`'in çalışmasının tek sebebi, Vault'undaki
`live_activity_cron_secret` değerinin rastgele bir string değil, gerçek bir
service_role JWT'si olmasıydı. Yani tek çalışan iş, yanlışlıkla doğru
header'ı taşıyordu.

## Reddedilen iki alternatif

**`verify_jwt = false`** — gateway katmanı tamamen kalkar, fonksiyonlar
internete yalnızca secret korumasıyla açılır. İki katmandan biri feda
edilir.

**Vault'a cron secret'ı olarak service_role JWT yazmak** — kod hiç
değişmeden çalışır (`live-activity`'nin bugünkü hâli), ama fonksiyon başına
izolasyon kaybolur: tek sızıntı tüm DB'yi açar. Ayrıca "cron secret'ı"
adında bir yerde service_role key tutmak, bir sonraki okuyanı yanıltır.

## Kurulum

### 1) Gateway JWT'si — Vault'ta BİR KEZ

`0054` bunu yazamaz (service_role key'i SQL içinden okuyamaz ve repoya
girmemeli). Dashboard → SQL Editor:

```sql
select vault.create_secret(
  '<service_role JWT>',   -- Settings → API → service_role (secret)
  'cron_gateway_jwt',
  'API gateway JWT dogrulamasini gecmek icin — cron tetikleyicileri'
);
```

Yedi tetikleyicinin hepsi bunu okur. Tek yerde durması kasıtlı: key
rotasyonu yedi ayrı Vault kaydına dokunmak olmasın.

**Yoksa `0054` açık hatayla durur** — sessiz düşmemesi kasıtlı, bu arızanın
ilk hâli tam olarak sessizliğinden dolayı dört ay yaşadı.

### 2) Fonksiyon başına cron secret'ı — iki yerde aynı

| Function secret (env) | Vault adı |
|---|---|
| `ANALYZE_SIGNALS_CRON_SECRET` | `analyze_signals_cron_secret` |
| `DAILY_BRIEF_CRON_SECRET` | `daily_brief_cron_secret` |
| `WEEKLY_SUMMARY_CRON_SECRET` | `weekly_summary_cron_secret` |
| `INFLATION_FETCH_CRON_SECRET` | `inflation_fetch_cron_secret` |
| `CALENDAR_NUDGE_CRON_SECRET` | `calendar_nudge_cron_secret` |
| `PRICE_ALERTS_CRON_SECRET` | `price_alerts_cron_secret` |
| `TEFAS_NAV_CRON_SECRET` | `tefas_nav_cron_secret` |
| `live_activity_cron_secret` | *(fonksiyon doğrulamıyor — yalnız Vault)* |

Her biri için **farklı** bir string üret (`openssl rand -hex 32`). Aynı sırrı
iki fonksiyona vermek çalışır ama biri sızarsa ikisi birden düşer.

### 3) Sıra ÖNEMLİ

```
fonksiyonları dağıt  →  migration'ı koş
```

`cron_auth.ts` geriye dönük uyumlu (`Authorization: Bearer <secret>` hâlâ
kabul edilir), yani bu sırada arada kalan çağrı kaybolmaz. **Ters sırada**
— migration önce koşarsa — eski fonksiyon `x-cron-secret`'ı tanımaz ve
gönderim bir tur atlar.

## `timeout_milliseconds` neden her zaman verilir

`0040_cron_http_timeout.sql`'in bulgusu: pg_net'in varsayılanı **5
saniye**dir ve süre aşımında pg_net yalnızca **yanıtı beklemeyi** bırakır —
fonksiyon sunucuda çalışmaya devam eder ve işini yapar. Sonuç: sistem
"bazen çalışıyor" gibi görünür, `net._http_response` timeout yazar, hiçbir
şey teşhis edilemez. `0054` öncesi dört tetikleyici bu bayrağı hiç almamıştı.

## Doğrulama

```sql
-- 1) Hiçbir tetikleyicide eski desen kaldı mı? (0 dönmeli)
select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.proname like 'trigger_%'
  and pg_get_functiondef(p.oid) ~ 'Bearer.*cron_secret';

-- 2) Elle tetikle ve YANITA bak — asıl kapı bu
select public.trigger_daily_brief();
select id, status_code, left(content,200) from net._http_response
order by id desc limit 1;
```

`status_code` **200** olmalı. `401` + `UNAUTHORIZED_INVALID_JWT_FORMAT`
görürsen `cron_gateway_jwt` ya yok ya JWT değil. `401` +
`Yetkisiz cron cagrisi` görürsen Vault'taki cron secret'ı fonksiyonun env
secret'ıyla eşleşmiyor.

```bash
deno test --allow-read --allow-net supabase/tests/cron_auth_test.ts
```

## Yeni bir cron fonksiyonu eklerken

1. `cronYetkisiVarMi` kullan, elle `Authorization` kontrolü **yazma**.
2. CORS `Access-Control-Allow-Headers`'a `x-cron-secret` ekle.
3. Tetikleyicide `public.cron_headers('<secret_adi>')` çağır.
4. `timeout_milliseconds` ver.
5. `cron_auth_test.ts` içindeki `SECRET_DOGRULAYAN` ve `TETIKLEYICILER`
   listelerine ekle — kapı yalnızca listedeki fonksiyonları koruyor.
