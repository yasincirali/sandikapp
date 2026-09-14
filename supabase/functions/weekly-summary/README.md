# weekly-summary — Haftalık Özet Push'u

Her Pazartesi TR 09:45'te, kullanıcının **geçen haftasını** tek cümleyle
bildirir ve `Grafik | Özet` sekmesine derin bağlantı verir.

## Pazartesi brifinginin YERİNE geçer, yanına değil

`0052` aynı migration içinde `daily-brief`'i `45 6 * * 1-5`'ten
**`45 6 * * 2-5`**'e çeker. Bildirim bütçesi günde tek proaktif push'a izin
veriyor (`RETENTION_STRATEJISI.md` §7); ikisi birlikte koşsa Pazartesi
sabahı iki bildirim giderdi.

Migration bunu kendi kendine doğruluyor: brifing susturulamazsa
`ayni gun iki push riski` diyerek patlıyor.

## ⚠️ "Katkı varsa GÖNDERME" değişmezi

Bu fonksiyonun en kritik kararı. `snapshots` tablosu portföyün **brüt
değerini** tutuyor — yani para yatırdığında değer artar ama bu **getiri
değildir**. İki snapshot arasındaki farkı yüzdeye çevirip "portföyün %12
arttı" demek, 10.000 TL yatırmış bir kullanıcıya yanlış bir kazanç
bildirmek olurdu.

Çözüm: o hafta içinde **alım ya da satım** yapmış kullanıcıya push
**gönderilmez**. Yanıtta `skipped_flow` olarak sayılır.

```ts
if (akisliKullanicilar.has(uid)) { skippedFlow += 1; continue; }
```

Alternatif — sunucuda akış-düzeltmeli getiri hesaplamak — canlı kur ve tüm
lot geçmişini sunucuya taşımak demekti (`daily-brief`'in v1 kapsamını
hisseyle sınırlayan aynı sebep). Sessizce atlamak, yanlış sayı göndermekten
iyidir.

**Sonuç:** aktif kullanıcıda `sent: 0` **normaldir**, arıza değil.

## Mesaj kuralları

`RETENTION_STRATEJISI.md` §8–§9:

- Kayıp haftasında **uyarı tonu yok** — uzun pencere bağlamı verilir
  ("son 1 ayda hâlâ +%3").
- Kazanç haftasında uzun pencereyle **dengelenmez** — kutlama da yok.
- Emoji yağmuru, seri rozeti, geri sayım, FOMO dili **yok**.
- **Tutar sızmaz** — yalnızca yüzde.
- SPK: durum bildirilir, eylem önerilmez. "Yatırım tavsiyesi değildir."

Bu kuralların her biri `supabase/tests/weekly_summary_test.ts` içinde
testli.

## Kapsama kapısı

İki snapshot da **48 saat tazelik** penceresinde olmalı (`pickEndpoints`).
Bayat uçlarla hesaplanan yüzde, kullanıcının uygulamada gördüğü sayıyla
uyuşmaz ve güveni bozar. Kapsama yoksa `skipped_coverage`.

## Secret'lar

| Ad | Nerede |
|---|---|
| `FCM_PROJECT_ID` | Edge Function secret — `analyze-signals` ile aynı |
| `FCM_SERVICE_ACCOUNT_JSON` | Edge Function secret — `analyze-signals` ile aynı |
| `WEEKLY_SUMMARY_CRON_SECRET` | Vault'taki `weekly_summary_cron_secret` ile **birebir aynı** |

⚠️ Cron secret'ı **`x-cron-secret`** header'ında taşınır, `Authorization`'da
DEĞİL — oraya konulduğunda API gateway isteği fonksiyona hiç ulaştırmadan
401 döndürür ve arıza sessiz olur. Bkz.
[`_shared/CRON_AUTH.md`](../_shared/CRON_AUTH.md).

## Kurulum

```bash
supabase functions deploy weekly-summary
supabase secrets set WEEKLY_SUMMARY_CRON_SECRET="$(openssl rand -hex 32)"
# Vault → weekly_summary_cron_secret = AYNI string
supabase db push   # 0052_weekly_summary.sql + 0054_cron_auth_header.sql
```

## Doğrulama

```bash
# Push GÖNDERMEDEN — kaç kişiye gideceğini ve kimin atlandığını söyler
curl -X POST "https://<proje>.supabase.co/functions/v1/weekly-summary" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "x-cron-secret: $WEEKLY_SUMMARY_CRON_SECRET" \
  -H "Content-Type: application/json" -d '{"dry_run": true}'
```

Dönen alanlar: `sent`, `skipped_flow` (o hafta alım/satım yapmış),
`skipped_coverage` (snapshot bayat/eksik), `skipped_quiet` (sessiz saat),
`skipped_opt_out` (`profiles.weekly_summary_push = false`), `failures`.

```sql
-- Gerçekten gitti mi?
select * from weekly_summary_log order by sent_on desc limit 5;

-- Cron sırası doğru mu? weekly PAZARTESİ, brifing SALI-CUMA olmalı
select jobname, schedule from cron.job
where jobname in ('weekly-summary','daily-brief');
```

```bash
deno test --allow-read --allow-net supabase/tests/weekly_summary_test.ts
```

## Cron

| Job | UTC | TR |
|---|---|---|
| `weekly-summary` | `45 6 * * 1` | Pazartesi 09:45 |
| `daily-brief` | `45 6 * * 2-5` | Salı–Cuma 09:45 *(Pazartesi susturuldu)* |
| `weekly-summary-cleanup` | `20 22 * * 0` | Pazar 01:20 |
