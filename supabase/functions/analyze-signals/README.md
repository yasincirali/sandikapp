# analyze-signals Edge Function

Günde iki kez (TR 11:00 & 15:00) tüm aktif kullanıcıların push token'larına
`signal_analyze_request` tipinde bir **data-only FCM message** atar. Client bu
mesajı yakalar → `analyzePortfolio()` çalıştırır → teknik göstergelerle üretilen
AL/SAT/NÖTR sinyalleri `signal_notifications` tablosuna yazar ve gerçek push'u
local notification olarak gösterir.

## Neden hibrit?

Teknik analiz kodu (RSI, MACD, Bollinger, EMA, Stochastic, ADX, Williams %R,
CCI) ve Yahoo/TEFAS fiyat çekim kodu Dart tarafında `TechnicalAnalysisService`
+ `PriceService`'te. Bu Edge Function sadece **tetikleyici** görevi görür.
Faydaları:

- TA kodu tek yerde (client) kalır → deviation yok
- Yahoo API rate-limit riski server'da patlamaz
- Premium tier "canlı sinyaller" için function saatlik çalıştırılabilir

## Gerekli environment variables

Supabase Dashboard → Edge Functions → analyze-signals → Secrets:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `FCM_PROJECT_ID`
- `FCM_SERVICE_ACCOUNT_JSON` (tam JSON, tek satır)
- `ANALYZE_SIGNALS_CRON_SECRET` (rastgele uzun string — pg_cron auth için)

## Deploy

```bash
supabase functions deploy analyze-signals --no-verify-jwt
```

`--no-verify-jwt` gerekli çünkü function pg_cron'dan çağrılıyor, kullanıcı
JWT'si yok. Yetkilendirme `ANALYZE_SIGNALS_CRON_SECRET` header ile.

## pg_cron kurulumu

Supabase Dashboard → Database → Extensions → `pg_cron` enable.
Sonra SQL editor:

```sql
-- Sadece bir kez: cron veritabanına HTTP çağrısı yapabilmek için pg_net gerekir.
create extension if not exists pg_net;

-- Function'ı çağıran wrapper. Secret ve URL parametreleri Dashboard'daki
-- Vault'ta saklanır (Database → Vault) — düz metin cron entry'sine yazmayın.
create or replace function public.trigger_analyze_signals(slot text)
returns void
language plpgsql
security definer
as $$
declare
  function_url text := 'https://<PROJECT_REF>.supabase.co/functions/v1/analyze-signals';
  cron_secret text;
begin
  select decrypted_secret into cron_secret
  from vault.decrypted_secrets
  where name = 'analyze_signals_cron_secret';

  perform net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || cron_secret
    ),
    body := jsonb_build_object('slot', slot)
  );
end;
$$;

-- Cron schedule (UTC): TR 11:00 = 08:00 UTC, TR 15:00 = 12:00 UTC
select cron.schedule(
  'analyze-signals-morning',
  '0 8 * * *',
  $$select public.trigger_analyze_signals('morning')$$
);

select cron.schedule(
  'analyze-signals-afternoon',
  '0 12 * * *',
  $$select public.trigger_analyze_signals('afternoon')$$
);
```

## Vault'a secret ekleme

Supabase Dashboard → Database → Vault:

- name: `analyze_signals_cron_secret`
- secret: `ANALYZE_SIGNALS_CRON_SECRET` env değeriyle **aynı** rastgele string

## Manuel test

```bash
curl -X POST 'https://<PROJECT_REF>.supabase.co/functions/v1/analyze-signals' \
  -H 'Authorization: Bearer <ANALYZE_SIGNALS_CRON_SECRET>' \
  -H 'Content-Type: application/json' \
  -d '{"slot":"manual"}'
```

Beklenen dönüş:
```json
{ "ok": true, "slot": "manual", "delivered": N, "failed": 0, "total": N }
```
