# calendar-nudge — TÜİK Enflasyon Günü

Her ayın 3'ünde TR 10:15'te, TÜİK enflasyonu açıkladıktan sonra tek bildirim.

## Neden uydurma bir hatırlatma değil

"sandık'ı açmayı unutma" tipi bir bildirim bilgi taşımaz ve kullanıcı üç
tekrarda kapatır. Buradaki tetikleyici ise ülkenin **zaten baktığı** bir an:
o sabah Türkiye'de milyonlarca kişi "ne kadar oldu?" diye bakıyor. Bildirim
o merakı karşılıyor, üretmiyor.

## Kişiselleştirme neden yok

Bildirim **ulusal** rakamı taşır ("Enflasyon aylık %2,49 · yıllık %40,12"),
kullanıcının kendi reel getirisini değil. Kişiye özel hesap sunucuda yok
(portföy getirisi için canlı kur ve tüm geçmiş gerekir) ve uydurulmuş bir
sayı göndermektense kullanıcıyı uygulamadaki gerçek hesaba çağırmak doğru.
Reel getiri rozeti o açtığında zaten karşılıyor.

## Veri yoksa bildirim yok

`inflation_index` boşsa ya da **beklenen ayın satırı henüz girilmemişse**
fonksiyon sessizce hiçbir şey göndermez. Cron her ayın 3'ünde koşuyor ama
endeks elle dolduruluyor; eski bir rakamı "açıklandı" diye göndermek yanlış
olurdu.

Bkz. `YAPMAN_GEREKENLER.md` → "TÜFE endeksi".

## Bilinen açık

Veri 3'ünde girilmezse o ayın kancası kaçar. Yeniden deneme cron'u yazıldı
ama **kapalı bırakıldı**: gönderim defteri olmadan, veri zamanında
girildiğinde iki bildirim giderdi. Kaçırılan bir kanca, çift bildirimden
ucuz. Bkz. `TECHNICAL_DEBT.md`.

## Secret'lar

`FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_JSON` (diğer fonksiyonlarla aynı) ve
`CALENDAR_NUDGE_CRON_SECRET` (Vault'taki `calendar_nudge_cron_secret` ile
birebir aynı).

## Kurulum ve doğrulama

```bash
supabase functions deploy calendar-nudge
supabase secrets set CALENDAR_NUDGE_CRON_SECRET="<uzun-rastgele>"
# Vault → calendar_nudge_cron_secret = aynı string
# Migration: supabase/migrations/0048_calendar_nudge.sql

curl -X POST "https://<proje>.supabase.co/functions/v1/calendar-nudge" \
  -H "Authorization: Bearer $CALENDAR_NUDGE_CRON_SECRET" \
  -H "Content-Type: application/json" -d '{"dry_run": true}'

deno test supabase/tests/calendar_nudge_test.ts
```
