# daily-brief — Sabah Brifingi

Hafta içi TR 09:45'te her kullanıcıya, kendi portföyüne dair tek cümlelik
bir bildirim gönderir.

## Ne söyler

> ▲ ASELS son kapanışta %4,2 yükseldi
> Portföyünde en çok hareket eden hisse. Portföyündeki diğer 3 hisse daha
> var. Yatırım tavsiyesi değildir.

## v1 neden yalnızca hisse

"Portföyün %X arttı" DEMİYOR. Sebebi doğruluk:

- Portföy yüzdesi için her varlığı TRY'ye çevirmek gerekir; canlı kur
  sunucuda yok (`assets.purchase_fx_rate` alış anının kurudur).
- Altın serisi `GC=F` (ons/USD) olarak çözülür. Onun günlük yüzdesi TRY gram
  altının yüzdesi **değildir** — arada USD/TRY hareketi var. Aynı sorun döviz
  ve emtiada da geçerli.
- Yanlış bir yüzde, hiç bildirim göndermemekten kötüdür: kullanıcı sayıyı
  uygulamadakiyle karşılaştırır ve güvenini kaybeder.

BIST hissesinde bu tuzak yok: Yahoo serisi de holding de TRY.
Kapsamı genişletmek önce sunucu tarafına kur modeli koymayı gerektirir.

## Neden "son kapanışta"

09:45'te BIST açılmamıştır ve `price_history_cache` günlük kapanış tutar;
serinin son noktası bir önceki **işlem günü**dür. "Dün" demek pazartesi
yanlış olurdu (son kapanış cuma). "Son kapanışta" her gün doğrudur.

## Bildirim bütçesi

- Hareket eşiği **%1,5** (`min_move_pct` ile geçersiz kılınabilir). Altındaki
  günlerde bildirim gitmez — "%0,3 yükseldi" haftalık 5 bildirimlik bütçeyi
  hiçbir şey söylemeden harcar.
- `daily_brief_log` tablosu aynı güne ikinci bildirimi engeller.
- Ayrı Android kanalı (`brief_channel`): kullanıcı brifingi kapatıp
  sinyalleri açık tutabilir.

## Secret'lar

| Ad | Nerede | Not |
|---|---|---|
| `FCM_PROJECT_ID` | Edge Function secret | `analyze-signals` ile aynı |
| `FCM_SERVICE_ACCOUNT_JSON` | Edge Function secret | `analyze-signals` ile aynı |
| `DAILY_BRIEF_CRON_SECRET` | Edge Function secret | Vault'taki `daily_brief_cron_secret` ile **birebir aynı** |

`SUPABASE_URL` ve `SUPABASE_SERVICE_ROLE_KEY` platform tarafından otomatik
enjekte edilir; elle eklenemez.

## Kurulum

```bash
# 1) Fonksiyonu dağıt
supabase functions deploy daily-brief

# 2) Secret'ları ver (FCM ikilisi analyze-signals'takiyle aynı)
supabase secrets set DAILY_BRIEF_CRON_SECRET="<rastgele-uzun-string>"

# 3) Vault'a AYNI string'i yaz (Supabase Dashboard → Vault)
#    name: daily_brief_cron_secret

# 4) Migration'ı çalıştır (tablo + cron + tetikleyici)
#    supabase/migrations/0044_daily_brief.sql
```

## Doğrulama

```bash
# Push GÖNDERMEDEN çalıştır — kaç kişiye gideceğini söyler
curl -X POST "https://<proje>.supabase.co/functions/v1/daily-brief" \
  -H "Authorization: Bearer $DAILY_BRIEF_CRON_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"dry_run": true}'
```

Dönen alanlar: `sent` (gidecek bildirim), `skipped_quiet` (eşiğin altında
kaldığı için elenen), `candidates` (hisse hareketi hesaplanabilen kullanıcı).

```bash
# Saf yardımcıların testleri
deno test supabase/tests/daily_brief_test.ts
```

## Bilinen eksikler

- `collapseTokens`, `analyze-signals` içindeki `dedupeTokensByDevice` ile aynı
  işi yapıyor. İkisi `_shared/`e taşınmalı (bkz. TECHNICAL_DEBT.md).
- `analyze-signals` hâlâ kendi FCM/JWT kopyasını kullanıyor; `_shared/fcm.ts`
  bu fonksiyon için çıkarıldı, oraya taşınması bir sonraki dokunuşta.
