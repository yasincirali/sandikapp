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

İki iş, aynı fonksiyon (0168):

| İş | Ritim (UTC) | Gövde | Türler |
|---|---|---|---|
| `check-price-alerts` | `*/30 5-18 * * *` | `{}` | hepsi (eski davranış) |
| `check-price-alerts-hizli` | `5-25/5,35-55/5 5-18 * * *` | `{"turler":["altin","doviz","kripto"]}` | altın, döviz, kripto |

= **TR 08:00–21:30; altın/döviz/kripto 5 dakikada, BIST/fon/emtia 30 dakikada.**
Dakikalar ayrık (hızlı iş :00/:30'da koşmaz); 18:30 UTC sonrası hızlı turlar
sarmalayıcıda erken döner. `turler` yoksa, dizi değilse ya da tanınan ad
içermiyorsa her tür değerlendirilir. Tür filtresi fiyat çekiminden önce
uygulanır: hızlı tur Yahoo/TEFAS'a gitmez.

Pencere sessiz saatlere göre seçildi (TR 22:00–08:00 bildirim yasak).
Hafta sonu da koşar: altın ve döviz BIST saatlerine bağlı değil.

## Tek atış

Alarm tetiklenince `triggered_at` damgalanır ve `enabled=false` olur.
Hedefin etrafında salınan bir fiyat, tekrar eden alarmda her turda (5
dakikada bir) bildirim üretirdi. Damga `triggered_at is null` koşuluyla atılır
ve sonucu okunur: çakışan iki turdan yalnız damgayı atan push gönderir
(`alarmiSondur`, `supabase/tests/alarm_hizli_tur_test.ts`). Kullanıcı "Yeniden kur"a basarak canlandırabilir.

**Damga bildirimden ÖNCE yazılır.** Ters sırada, push gidip damga
yazılamazsa kullanıcı her turda aynı bildirimi alırdı — geri alınamaz olan bu.
Damga yazılıp push başarısız olursa alarm yalnızca bir kez kaçar.

## Secret'lar

| Ad | Not |
|---|---|
| `FCM_PROJECT_ID` | `analyze-signals` ile aynı |
| `FCM_SERVICE_ACCOUNT_JSON` | `analyze-signals` ile aynı |
| `PRICE_ALERTS_CRON_SECRET` | Vault'taki `price_alerts_cron_secret` ile birebir aynı |

⚠️ Cron secret'ı **`x-cron-secret`** header'ında taşınır, `Authorization`'da
DEĞİL — oraya konulduğunda API gateway isteği fonksiyona hiç ulaştırmadan
401 döndürür ve arıza sessiz olur. Bkz.
[`_shared/CRON_AUTH.md`](../_shared/CRON_AUTH.md).

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
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "x-cron-secret: $PRICE_ALERTS_CRON_SECRET" \
  -H "Content-Type: application/json" -d '{"dry_run": true}'
```

Dönen alanlar: `checked` (aktif alarm), `priced` (fiyatı alınabilen sembol),
`triggered` (tetiklenen), `sent`.

```bash
deno test supabase/tests/price_alert_test.ts
```
