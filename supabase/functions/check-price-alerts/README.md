# check-price-alerts — Fiyat Alarmları

Kullanıcının kurduğu fiyat hedeflerini sunucuda değerlendirir ve tetiklenince
push gönderir.

## Neden sunucuda

Uygulama açıkken çalışan bir alarm **geri getirme kanalı değildir** — sadece
bir ekran öğesidir. Alarmın değeri, uygulama kapalıyken çalmasında.

## Kaynaklar istemciyle aynı

| Sembol ailesi | Kaynak |
|---|---|
| `ALTIN_*`, `USDTRY=X`, `EURTRY=X`, `GBPTRY=X` | finans.truncgil.com |
| Geri kalan (`THYAO.IS`, `GC=F`…) | Yahoo chart, `interval=5m&range=1d` |

Bu bir tercih değil zorunluluk: alarm, uygulamada **görünen** sayı üzerinden
tetiklenmeli. Farklı kaynak kullansaydık kullanıcı ekranda 5.401 görürken
5.400 alarmının çalışmadığını fark eder ve haklı olarak "bozuk" derdi.

`price_history.ts` kullanılmadı — o modül günlük kapanış tutuyor ve 12 saatlik
cache'i var; "gram altın 5.400 olunca" diyen kullanıcı ertesi günü beklemez.

## Zamanlama

`*/30 5-18 * * *` (UTC) = **TR 08:00–21:30, yarım saatte bir.**

Pencere sessiz saatlere göre seçildi (TR 22:00–08:00 bildirim yasak).
Hafta sonu da koşar: altın ve döviz BIST saatlerine bağlı değil.

## Tek atış

Alarm tetiklenince `triggered_at` damgalanır ve `enabled=false` olur.
Hedefin etrafında salınan bir fiyat, tekrar eden alarmda yarım saatte bir
bildirim üretirdi. Kullanıcı "Yeniden kur"a basarak canlandırabilir.

**Damga bildirimden ÖNCE yazılır.** Ters sırada, push gidip damga
yazılamazsa kullanıcı her turda aynı bildirimi alırdı — geri alınamaz olan bu.
Damga yazılıp push başarısız olursa alarm yalnızca bir kez kaçar.

## Secret'lar

| Ad | Not |
|---|---|
| `FCM_PROJECT_ID` | `analyze-signals` ile aynı |
| `FCM_SERVICE_ACCOUNT_JSON` | `analyze-signals` ile aynı |
| `PRICE_ALERTS_CRON_SECRET` | Vault'taki `price_alerts_cron_secret` ile birebir aynı |

## Kurulum

```bash
supabase functions deploy check-price-alerts
supabase secrets set PRICE_ALERTS_CRON_SECRET="<rastgele-uzun-string>"
# Vault → price_alerts_cron_secret = AYNI string
# Migration: supabase/migrations/0046_price_alerts.sql
```

## Doğrulama

```bash
curl -X POST "https://<proje>.supabase.co/functions/v1/check-price-alerts" \
  -H "Authorization: Bearer $PRICE_ALERTS_CRON_SECRET" \
  -H "Content-Type: application/json" -d '{"dry_run": true}'
```

Dönen alanlar: `checked` (aktif alarm), `priced` (fiyatı alınabilen sembol),
`triggered` (tetiklenen), `sent`.

```bash
deno test supabase/tests/price_alert_test.ts
```
