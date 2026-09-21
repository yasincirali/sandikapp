# Push doğrulama rehberi — her push türü için "gerçekten gidiyor mu?" testi

**Tarih:** 2026-09-21 · Yazan: Claude · Kime: geliştirici (Supabase SQL Editor +
telefon elinde)

Bu rehber "bir push gelmedi" dendiğinde arıza mı, tasarım mı ayırmak ve her
türü tek tek kanıtlamak içindir. Üç katman ayrı ayrı denetlenir; biri
yeşilken diğeri kırmızı olabilir:

1. **Üretim** — fonksiyon o push'u üretti mi? (`net._http_response` yanıtı)
2. **Gönderim** — FCM kabul etti mi? (`sent`/`failures`; `sent` teslimat
   DEĞİLDİR, "APNs/FCM'e ilettim" demektir)
3. **Teslimat** — telefona düştü mü? (yalnızca gözle; uygulama ARKA PLANDA
   olmalı, iOS ön planda banner göstermez)

Ön koşul (bir kez): `user_push_tokens`'ta cihazının satırı bugünün damgasını
taşımalı:

```sql
select platform, left(device_id,8) as cihaz, updated_at
from user_push_tokens where user_id = '<senin id>' order by updated_at desc;
```

Satır yoksa uygulamayı tamamen kapatıp aç; `db_logs`'ta
`source='SupabaseService.upsertPushToken'` için `is_error=false` gör.
`42501` görüyorsan 0069 canlıda değil, `PGRST202` görüyorsan build sunucudan
yeni.

## Tetikleme kalıbı

Bütün cron fonksiyonları aynı şekilde elle çağrılır (SQL Editor; cron
secret'ı Vault'tan `cron_headers` alır, elle kopyalanmaz):

```sql
select net.http_post(
  url := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/<FONKSIYON>',
  headers := public.cron_headers('<VAULT_ADI>'),
  body := '<GÖVDE>'::jsonb,
  timeout_milliseconds := 60000);
-- dönen sayı istek id'sidir; 10 sn sonra:
select content from net._http_response where id = <ISTEK_ID>;
```

`net._http_response` yaklaşık 6 saat saklanır; sabahki koşunun yanıtını
akşam arama.

Önce **`"dry_run": true`** ile prova yap: kim ne alacak listelenir, hiçbir
şey gönderilmez ve defterlere yazılmaz. Sonra `dry_run`'ı kaldır.

| Fonksiyon | Vault adı | Gövde alanları |
|---|---|---|
| `analyze-signals` | `analyze_signals_cron_secret` | `slot` (`hourly`/`morning`/…), `dry_run` |
| `check-price-alerts` | `price_alerts_cron_secret` | `dry_run`, `watchlist: true` (takip listesi turu) |
| `daily-brief` | `daily_brief_cron_secret` | `dry_run`, `slot: "evening"`, `min_move_pct` |
| `weekly-summary` | `weekly_summary_cron_secret` | `dry_run`, `period: "month"`, `user_ids: [...]`, `min_move_pct` |
| `fetch-inflation` | `inflation_fetch_cron_secret` | `dry_run` (TÜFE günü push'u bu turda) |
| `calendar-nudge` | `calendar_nudge_cron_secret` | `dry_run` |

`user_ids` yalnızca `weekly-summary`'de var; diğerleri herkese koşar. Gerçek
gönderimde test kullanıcıları da alır; bunu bilerek yap.

## Tür tür

### 1. Al/sat sinyali (`analyze-signals`)

**Ne zaman üretir:** yalnızca kullanıcının `signal_preferences` penceresinde
(`window_start`–`window_end`, varsayılan 10–18 TR; `notify_hours` [11,15]) ve
yalnızca sinyal **değiştiğinde** (`signal_state`).

**Test (pencere içinde, ör. 11:00–17:59 TR):**
1. Uygulama → Ayarlar → Push Teşhisi → "De-dup sıfırla" (signal_state
   temizlenir; aksi halde `skipped_by_dedup`).
2. Aynı ekranda "Gerçek push" (ya da SQL: `analyze-signals`, gövde
   `{"slot":"hourly"}`).
3. Yanıt: `evaluated > 0`, `passed_threshold ≥ 1`, `sent ≥ 1`,
   `failed: 0`. `skipped_by_frequency = tercih sayısı` ise pencere dışısın.
4. Kanıt: `signal_notifications` (`sent_at`, `asset_ticker`, `signal`);
   telefonda bildirim; çan sayfasında satır.

**Eşik geçilmiyorsa** (sinyal var ama güven düşük): geçici olarak
`update signal_preferences set threshold = 40 where user_id = '<id>';`
test bitince eski değere al.

### 2. Fiyat alarmı (`check-price-alerts`)

**Ne zaman üretir:** */30 dk 08–21 TR; alarm `enabled` ve `triggered_at` boş;
fiyat hedefi geçmiş. Tetiklenen alarm **kapanır** (`enabled=false`,
`triggered_at` dolar) — tek atımlık.

**Test:**
1. Uygulamada bir alarm kur; hedef **kesin geçilecek** değerde: "üstüne
   çıkınca" için mevcut fiyatın altı, "altına inince" için üstü.
2. SQL: `check-price-alerts`, gövde `{"source":"manual"}` (prova için
   `{"dry_run":true}`).
3. Yanıt: `checked` = aktif alarm sayısı, `priced` = fiyatlanan **sembol**
   sayısı (alarm değil), `sent ≥ 1`. `priced` sembol sayısından küçükse
   kaynak kısmi (kanarya `db_logs`'a `check-price-alerts` satırı düşer).
4. Kanıt: `price_alerts` satırında `triggered_at` dolu;
   `price_alert_notifications` yeni satır; telefonda bildirim.

### 3. Takip listesi hareketi (aynı fonksiyon, `watchlist: true`)

Pzt–Cu 18:25 TR; takip listesindeki varlık günlük eşiği aşınca. Test: gövde
`{"watchlist":true}`; yanıt `checked`, `sent` ya da
`"reason":"Esigi asan hareket yok."` (o gün büyük hareket yoksa üretilmez —
arıza değil). Kanıt: `watchlist_move_log`.

### 4. Günlük brifing (`daily-brief`)

Sabah Sa–Cu 09:45 TR (`brief_slot='morning'`), akşam Pzt–Cu 18:30 TR
(`'evening'`). **Yalnızca BIST hissesi olanlara** ya da ortağı dün alım
yaptıysa; günde bir kez (`daily_brief_log`).

**Test:**
1. `delete from daily_brief_log where user_id='<id>' and sent_on=current_date;`
2. SQL: `daily-brief`, gövde `{"min_move_pct":0}` (sabah slotu) ya da
   `{"slot":"evening","min_move_pct":0}` — `min_move_pct:0` hareket eşiğini
   kaldırır.
3. Yanıt: `candidates`, `sent`, `skipped_quiet` (eşik altı),
   `skipped_quiet_hours` (sessiz saat), `failures: []`.
4. Kanıt: `daily_brief_log` bugünkü satır; `app_notifications`
   `type='daily_brief'`; telefon.

Hissesi olmayan kullanıcıda `sent: 0` beklenen sonuçtur.

### 5. Haftalık / aylık özet (`weekly-summary`)

Haftalık Pzt 09:45 TR, aylık ayın 1'i 09:30 TR (`period: "month"`).
Atlama sebepleri yanıtta ayrı sayılır: `skipped_flow` (hafta içinde varlık
eklendi → haftalıkta susar), `skipped_quiet` (hareket < %2),
`skipped_coverage` (uçlarda 48 saat içinde snapshot yok),
`skipped_opt_out`, `skipped_quiet_hours`.

**Test (tek kullanıcı, en güvenli uçtan uca test):**

```json
{"source":"manual","period":"month","user_ids":["<senin id>"]}
```

Aylık, kapsam olmasa da "hazır" mesajı gönderir; haftalık için
`{"period":"week","user_ids":["<id>"],"min_move_pct":0}` — akış kapısı
(`skipped_flow`) yine de susturabilir, bu bilinçli. Aynı güne ikinci
gönderim için `weekly_summary_log`'dan bugünkü satırı sil.

### 6. TÜFE günü + takvim (`fetch-inflation`, `calendar-nudge`)

Ayın 3'ü 10:05 / 10:15 TR (4'ünde tekrar). TÜFE push'u yeni endeks değeri
geldiğinde bir kez (`inflation_push_log`, dönem anahtarlı). Test: `dry_run`
ile prova; gerçek koşu yalnızca yeni veri varsa gönderir. Ay ortasında
`sent: 0` beklenen sonuçtur.

### 7. Ortak daveti (`send-partner-invite-push`)

Cron değil; davet gönderince anlık. Test: iki hesapla davet gönder,
karşı tarafta bildirim + çan.

### 8. Kilit ekranı / Live Activity (`push-live-activity`)

5 dakikada bir, APNs'e doğrudan (FCM'den bağımsız). Yanıt
`{"sent":N,"total":N}`; `removed > 0` süresi dolmuş etkinlik. Kilit ekranı
güncelleniyorsa hat sağlam; FCM ölüyken bile çalışır, bu yüzden "push
altyapısı ayakta" kanıtı DEĞİLDİR.

## Hızlı sağlık taraması (her şey için, 30 sn)

```sql
-- son 6 saatin cron yanıtları: 200 olmayan var mı?
select id, status_code, left(content::text,120), created
from net._http_response where status_code <> 200 order by id desc limit 10;

-- token yazım hataları (42501 = hesap değişimi, PGRST202 = 0069 eksik)
select ts, left(user_id::text,8) u, left(response_json::text,100)
from db_logs where source='SupabaseService.upsertPushToken' and is_error
order by id desc limit 10;

-- kanarya (fiyat kaynağı kısmi/boş)
select ts, request_json, response_json from db_logs
where source='check-price-alerts' and is_error order by id desc limit 5;

-- son gönderimler
select 'signal' k, max(sent_at) son from signal_notifications
union all select 'brief', max(created_at) from daily_brief_log
union all select 'weekly', max(created_at) from weekly_summary_log
union all select 'alarm', max(sent_at) from price_alert_notifications;
```

## "Gelmedi" karar ağacı

| Gözlem | Anlamı | Yapılacak |
|---|---|---|
| Yanıtta `sent: 0`, `skipped_*` dolu | Üretilmedi, tasarım | Yukarıdaki kapıyı aç (pencere, eşik, dedup) |
| `sent ≥ 1`, `failures: []`, telefonda yok | FCM aldı, APNs/cihaz düşürdü | Uygulama ön planda mıydı? Bildirim izni? iOS: Firebase APNs anahtarı (`XKLXXKGTX9`) |
| `failures` içinde `UNREGISTERED` | Token bayat | Uygulama açılınca yenilenir; satır otomatik silinir |
| `status_code` 401/503 | Gateway JWT / cron secret | `cron_gateway_jwt` ve ilgili Vault secret'ı |
| `db_logs` 42501 | Aynı telefonda hesap değişimi | 0069 canlıda mı? |
| `db_logs` PGRST202 | Build sunucudan yeni | 0069'u koş; istemci geri dönüşle yine yazar |

İlgili: `supabase/functions/_shared/CRON_AUTH.md`, `YAPMAN_GEREKENLER.md`
(push matrisi 2026-09-21), `docs/IOS_LIVE_ACTIVITY_KURULUM.md`.
