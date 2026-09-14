# fetch-inflation — TÜFE Endeksi Otomatik Çekimi

Her ayın 3'ünde (ve gerekirse 4'ünde) TCMB EVDS'den TÜFE endeksini çeker ve
`inflation_index` tablosunu doldurur.

İki açık borcu birden kapatır (`TECHNICAL_DEBT.md`):

1. **"TÜFE endeksi elle dolduruluyor"** — unutulduğunda reel getiri rozeti
   sessizce eskiyordu. Yanlış sayı göstermiyordu (hesap son *açıklanmış* aya
   dayanıyor) ama pencere geriye kayıyordu.
2. **"Takvim kancasında gönderim defteri yok"** — `calendar-nudge`'ın ayın
   4'ündeki ikinci turu, çift bildirim riski yüzünden kapalı bırakılmıştı.
   Defter geldi, tur açıldı.

## ⏰ SAAT SIRASI — en kritik parça

`calendar-nudge` ayın 3'ünde **TR 10:15**'te koşuyor ve tabloda **bu ayın**
satırını arıyor; yoksa sessizce hiçbir şey göndermiyor.

Çekim bu yüzden **TR 10:05**'e kuruldu — nudge'dan 10 dakika önce:

```
TÜİK 10:00 açıklar → 10:05 çekim → 10:15 bildirim
```

Borç kaydı `0 8 3 * *` (TR 11:00) öneriyordu. **O sıra yanlıştı:** nudge hep
bayat veriyle karşılaşır ve o ayın kancası kaçardı — otomatikleştirmenin asıl
kazancı kaybolurdu. Migration bu sırayı kendi kendine doğruluyor; ikisi aynı
saate kurulursa yüksek sesle patlıyor.

## Neden EVDS

TCMB EVDS `TP.TUKFIY2025.GENEL` serisi = TÜFE genel endeks (**2025=100**).
Tabloya `TUIK-TP.TUKFIY2025.GENEL` olarak yazılır — `source` kolonu baz
yılını ayırt etmenin tek kanıtı.

> **2026-09-14:** önceki kod `TP.FG.J0` (2003=100) idi. TÜİK Ocak 2026'da
> baz yılını değiştirdi ve o seri orada **sona erdi**; tablo dolu görünmeye
> devam ederken Şubat–Ağustos 2026 hiç gelmiyordu. Aynı turda EVDS adresi de
> `evds2` → `evds3` taşınmıştı ve eski yol API yerine HTML döndürüyordu.
> Yeni seri kodu katalogdan **okundu**, tahmin edilmedi (aşağıdaki
> "Katalog keşfi" bölümü).

**Anahtar ŞART.** Anahtar yoksa fonksiyon `no_api_key` döner ve **hiçbir şey
yazmaz** — yarım bir entegrasyonla tabloyu bozmak, elle girişten kötü olurdu
(borç kaydının erteleme gerekçesi de tam olarak buydu).

## Endeks DEĞERİ saklanır, yüzde değil

`0045_inflation_index.sql`'in kararı: iki tarih arası enflasyon tek bölmeyle
çıkar (`sonEndeks / ilkEndeks − 1`). Yüzde saklansaydı aradaki bütün ayları
çarpmak gerekirdi ve her ay bir yuvarlama hatası eklenirdi.

## ⚠️ Baz yılı değişimi — sessiz tehlike

TÜİK zaman zaman baz yılını değiştirir (ör. 2003=100 → 2025=100). Baz
değişince endeks **sıfırlanır** ve eski satırlarla yeni satırlar doğrudan
karşılaştırılamaz: bölme anlamsız bir sonuç verir ("−%95 enflasyon").

Fonksiyon bunu sezgisel olarak yakalar: ardışık iki ay arasında endeks
**%15'ten fazla düşerse** baz kırılması varsayılır ve **yazma reddedilir**
(`base_year_break`, HTTP 409). Türkiye'de aylık deflasyon tarihsel olarak hiç
bu boyutta olmadı.

Bu durumda **insan müdahalesi gerekiyor**: yeni seri adı ne, eski satırlar ne
olacak — bunlar ürün kararı, otomatik çözülmez.

### ⚠️ Daha sinsi hâli: seri SESSİZCE durur

2026-09-14'te yaşanan buydu ve baz kırılması denetimine **hiç takılmadı**:
TÜİK yeni seriyi AYRI bir kod altında yayımladı, eskisini olduğu yerde
bıraktı. Yani endeks düşmedi — sadece **yeni ay hiç gelmedi**. Fonksiyon
`no_new_data` döndü, tablo dolu göründü, kimse fark etmedi.

İki koruma eklendi:

- **İstemci tarafı:** `InflationService.isStale` — son satır 2 aydan
  eskiyse reel getiri hesaplanmaz, ekran "TÜFE verisi henüz yüklenmedi"
  der. Bayat endeksle yanlış bir yüzde göstermektense hiç göstermemek.
- **Bu README + `TECHNICAL_DEBT.md`** — belirti ("tablo dolu ama aylar
  gelmiyor") ve teşhis yolu yazılı.

### Katalog keşfi — yeni seri kodunu TAHMİN ETME

Seri kodu tahmin edilirse yanlış bir endeks (ör. bir alt harcama kalemi)
sessizce yazılır ve reel getiri yanlış çıkar. Doğru kod EVDS kataloğundan
okunur; anahtar yalnızca sunucuda olduğu için fonksiyonun kendi `catalog`
modu bunun için var:

```sql
-- 1) Kategorilerde ara
select net.http_post(
  url := 'https://<ref>.supabase.co/functions/v1/fetch-inflation',
  headers := public.cron_headers('inflation_fetch_cron_secret'),
  body := jsonb_build_object('catalog','categories','q','TÜKETİCİ'));
--    → 2005 | TÜKETİCİ FİYAT ENDEKSİ (TÜİK)

-- 2) O kategorinin veri gruplarını listele
body := jsonb_build_object('catalog','groups:2005')
--    → bie_tukfiy2025 | Tüketici Fiyat Endeksi (2025=100)

-- 3) Gruptaki genel endeks serisini bul
body := jsonb_build_object('catalog','bie_tukfiy2025','q','GENEL')
--    → TP.TUKFIY2025.GENEL | Genel Endeks | 01-2005 .. 08-2026

-- 4) YAZMADAN dene
body := jsonb_build_object('dry_run', true, 'series','TP.TUKFIY2025.GENEL')
```

Yanıtı `select content from net._http_response order by created desc limit 1;`
ile oku.

`series` gövde parametresi kalıcıdır: aday kodlar `dry_run` ile deploy
gerektirmeden denenebilir. Doğrusu bulununca `EVDS_SERIES` sabitini güncelle.

**Kabul ölçütü — bu adımı atlama:** çekimden sonra yıllık değişim TÜİK'in
açıkladığı rakamla örtüşmeli.

```sql
select round(((select tufe_index from inflation_index where period='2026-08-01')
            / (select tufe_index from inflation_index where period='2025-08-01') - 1) * 100, 2);
-- → 31.51  (TÜİK Ağustos 2026 yıllık TÜFE ile birebir ✓)
```

### Baz değişince eski satırlar

İki bazı aynı tabloda tutma — `changePct` ikisini birbirine böler ve sonuç
anlamsız olur. 2026-09'da izlenen yol: `delete from inflation_index;` sonra
yeni seriyle 24 aylık backfill. Tablo kamuya açık istatistik tutuyor,
kullanıcı verisi değil; silinen her satır yeniden çekilebilir.

## İçinde bulunulan ay YAZILMAZ

`InflationService.inflationForPeriod` "son açıklanmış ay"ı arıyor ve içinde
bulunulan ayın tabloda **olmadığını** varsayıyor (TÜİK bir ayın verisini
ertesi ayın 3'ünde yayımlar). Geçici bir satır o varsayımı kırardı.

## Revizyonlar otomatik yakalanır

Yazma `period` üzerinden **upsert**. TÜİK açıklanmış bir ayı sonradan
düzeltirse bir sonraki tur onu günceller; ayın 4'ündeki ikinci tur da bu
yüzden çift satır üretmiyor.

## Secret'lar

| Ad | Nerede | Not |
|---|---|---|
| `EVDS_API_KEY` | Edge Function secret | evds3.tcmb.gov.tr → üye ol → Profil → API Anahtarı |
| `INFLATION_FETCH_CRON_SECRET` | Edge Function secret | Vault'taki `inflation_fetch_cron_secret` ile **birebir aynı** |

`SUPABASE_URL` ve `SUPABASE_SERVICE_ROLE_KEY` platform tarafından otomatik
enjekte edilir. FCM secret'ları **gerekmez** — bu fonksiyon push göndermiyor,
yalnızca tabloyu dolduruyor.

⚠️ Cron secret'ı **`x-cron-secret`** header'ında taşınır, `Authorization`'da
DEĞİL — oraya konulduğunda API gateway isteği fonksiyona hiç ulaştırmadan
401 döndürür ve arıza sessiz olur. Bkz.
[`_shared/CRON_AUTH.md`](../_shared/CRON_AUTH.md).

## Kurulum

```bash
# 1) Fonksiyonu dağıt
supabase functions deploy fetch-inflation

# 2) EVDS anahtarı
supabase secrets set EVDS_API_KEY="<evds-anahtarin>"

# 3) Cron secret'ı
supabase secrets set INFLATION_FETCH_CRON_SECRET="<rastgele-uzun-string>"

# 4) Vault'a AYNI string'i yaz (Supabase Dashboard → Vault)
#    name: inflation_fetch_cron_secret

# 5) `calendar-nudge`'ı YENİDEN dağıt — defteri okuyan sürüm
supabase functions deploy calendar-nudge

# 6) Migration
supabase db push   # ya da SQL Editor → 0053_fetch_inflation.sql
```

⚠️ **5. adım atlanamaz.** Migration `calendar-nudge`'ın ikinci turunu açıyor;
fonksiyon defteri okumayan eski sürümde kalırsa veri 3'ünde zamanında
girildiğinde **iki bildirim** gider — yani `0048`'in ikinci turu kapatma
sebebinin aynısı geri gelir.

## Doğrulama

```bash
# Tabloya YAZMADAN çalıştır — ne çekeceğini söyler
curl -X POST "https://<proje>.supabase.co/functions/v1/fetch-inflation" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "x-cron-secret: $INFLATION_FETCH_CRON_SECRET" \
  -H "Content-Type: application/json" -d '{"dry_run": true}'
```

Dönen alanlar:

| Alan | Anlamı |
|---|---|
| `fetched` | EVDS'den ayrıştırılan ay sayısı |
| `latest_fetched` | çekilen en son ay |
| `latest_in_table` | tabloda hâlihazırda olan en son ay |
| `has_new_month` | yeni bir ay geldi mi (nudge buna bağlı) |
| `written` | gerçek koşuda yazılan satır |

`reason` alanının olası değerleri: `updated`, `no_new_data`, `no_api_key`,
`no_rows_parsed`, `base_year_break`, `evds_http_error`, `evds_unreachable`.

İlk gerçek koşu **24 ay** geriye gider (reel getiri rozeti 13 ay istiyor:
başlangıç ayı + son açıklanan ay). Farklı bir pencere için
`{"backfill_months": 36}`.

```sql
-- Kaç ay var, en yenisi hangi ay?
select count(*) as ay_sayisi, min(period), max(period) from inflation_index;

-- Kanca bu ay gönderildi mi?
select * from calendar_nudge_log order by period desc limit 3;
```

```bash
deno test --allow-read --allow-net supabase/tests/fetch_inflation_test.ts
```

## Cron

| Job | Zamanlama (UTC) | TR |
|---|---|---|
| `fetch-inflation` | `5 7 3 * *` | ayın 3'ü 10:05 |
| `fetch-inflation-retry` | `5 7 4 * *` | ayın 4'ü 10:05 |
| `calendar-nudge-inflation` | `15 7 3 * *` | ayın 3'ü 10:15 |
| `calendar-nudge-inflation-retry` | `15 7 4 * *` | ayın 4'ü 10:15 *(bu migration'la açıldı)* |
| `calendar-nudge-log-cleanup` | `40 22 * * 0` | Pazar 01:40 |

## Sonrası: `real_return_enabled`

Tablo dolduktan sonra Remote Config → `real_return_enabled` → `true`
olmalı. Tablo dolu olsa bile bu bayrak kapalıysa rozet görünmez
(`onboarding_screen.dart` de aynı bayrağa bakıyor).
