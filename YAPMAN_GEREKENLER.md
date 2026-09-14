# sandık — Senin Yapman Gerekenler (Detaylı Rehber)

**Tarih:** 2026-05-11 · **Son ek:** 2026-09-14
> **📱 Android/Play tarafı için güncel dosya:**
> [`PLAY_STORE_YAYIN_REHBERI.md`](PLAY_STORE_YAYIN_REHBERI.md) (2026-09-05).
> Aşağıdaki §4 (keystore) ve §6 (Play Console) bölümleri 2026-05 tarihli;
> Play'in kuralları o tarihten sonra değişti (targetSdk 36, 16 KB sayfa
> boyutu, finansal özellik beyanı, geliştirici doğrulama). Çakışma olursa
> yeni rehber geçerlidir.

**Kapsam:** Yayın öncesi senin elden yapman gereken işler. Kod tarafı (Faz 1) tamam; bu liste deploy + hukuki + ticari adımları içerir.

---

## 🚨 ÖNCE BU: 2026-09-13 güvenlik denetimi sonrası (kod tarafı yapıldı, deploy sende)

Kod değişiklikleri `claude/app-evaluation-roadmap-afnh0f` dalında. Aşağıdakiler
senin elinden geçmeden **canlıda etkili olmaz** ve bazıları için kod tarafı
artık eski davranışa dönmez (fail-closed).

| # | İş | Neden | Nasıl |
|---|---|---|---|
| 1 | **`daily_brief_cron_secret`'ı DÖNDÜR** | Eski değer `tmp/update_daily_brief_vault.sql` içinde git'e commit edilmişti (`61a74dc`). Dosya silindi ama git geçmişinde duruyor. | Yeni bir değer üret (`openssl rand -hex 32`). Vault'ta güncelle (0034'teki deterministic okuma en yeni kaydı alır) VE `supabase secrets set DAILY_BRIEF_CRON_SECRET=<yeni>`. |
| 2 | **Git geçmişini temizle** (isteğe bağlı ama önerilir) | Repo klonlanmış/fork'lanmışsa eski secret oradan okunabilir; rotasyon yapıldıysa zararsız ama temiz olsun. | `git filter-repo --path tmp/update_daily_brief_vault.sql --invert-paths` + force push; tüm klonlar yeniden çekmeli. |
| 3 | **`LIVE_ACTIVITY_CRON_SECRET` function secret'ı** | `push-live-activity` artık `x-cron-secret` doğruluyor (eskiden HİÇ doğrulamıyordu; 0054 tetikleyicisi zaten bu header'ı gönderiyor). Vault'taki `live_activity_cron_secret` ile aynı değer olmalı; yoksa fonksiyon 503 döner ve Live Activity güncellenmez. ⚠️ Vault'taki mevcut değer 219 karakterlik bir service_role JWT (bkz. 0054 notu) — onu rastgele bir secret'la DEĞİŞTİR, JWT'yi function secret'ı olarak kopyalama. | `openssl rand -hex 32` → Vault `live_activity_cron_secret` + `supabase secrets set LIVE_ACTIVITY_CRON_SECRET=<aynı değer>` |
| 4 | **Diğer 6 cron secret'ının SET olduğunu doğrula** | Fonksiyonlar artık fail-closed (`cronSecretZorunlu`): secret yoksa 503. Eskiden secret yoksa herkese açıktı. Yerel geliştirmede `CRON_AUTH_ALLOW_UNSET=1` ile kapı açılır. | `supabase secrets list` → `ANALYZE_SIGNALS_CRON_SECRET`, `CALENDAR_NUDGE_CRON_SECRET`, `PRICE_ALERTS_CRON_SECRET`, `DAILY_BRIEF_CRON_SECRET`, `INFLATION_FETCH_CRON_SECRET`, `WEEKLY_SUMMARY_CRON_SECRET` hepsi listede olmalı ve Vault'takiyle eşleşmeli. |
| 5 | **`DELETION_HASH_SALT` set et** | Varsayılan tuz kaldırıldı; set değilse hesap silme 503 döner. | `supabase secrets set DELETION_HASH_SALT=$(openssl rand -hex 32)` — bir kez set et, bir daha DEĞİŞTİRME (eski log kayıtlarıyla eşleşme bozulur). |
| 6 | **8 edge function'ı yeniden deploy et** | analyze-signals, calendar-nudge, check-price-alerts, daily-brief, fetch-inflation, weekly-summary, push-live-activity, send-partner-invite-push, delete-account (`_shared/cron_auth.ts` yeni). | `supabase functions deploy <ad>` — cron olanlarda da gateway JWT doğrulaması AÇIK kalır (0054 deseni: Authorization'da service_role JWT, `x-cron-secret`'ta secret). |
| 7 | **`0055_is_push_admin_grant.sql`'i koş** | Ayarlar'daki "Push Teşhisi" tile'ı artık `is_push_admin()` RPC'sine bakıyor; GRANT yoksa tile admin'e de görünmez (fonksiyon hata → false). | `supabase db push` ya da SQL Editor. |
| 8 | **Yerel release build için `android/key.properties`** | `key.properties` yoksa release build artık KIRILIR (eskiden debug anahtarıyla sessizce imzalıyordu). | §4 keystore adımları. CI (`android-release.yml`) zaten secret'tan yazıyor, etkilenmez. |
| 10 | **GoTrue rate limit'lerini sabitle** (M12) | Login ve OTP doğrulamada uygulama düzeyi throttle yok; istemci sayacı güvenlik sınırı sayılmaz (S1 dersi). Koruma Supabase Auth'un kendi limitleri. | Dashboard → Authentication → Rate Limits: "Token verifications" ve "Sign-ins/sign-ups" değerlerini gözden geçir, bilinçli bir değere çek ve buraya not düş. |
| 9 | **Sybil / k=8 kararı** (M1) | 7 sahte hesapla bir kullanıcının ROI'si ve dağılımı okunabilir. Kod değişikliği değil, ürün kararı. | Yarış'ı DAU ≥ 16 olana kadar kapalı tut ya da k paydasında yalnızca ≥7 gün geçmişi olan hesapları say (migration gerekir). |

Tam bulgu listesi: `docs/DEGERLENDIRME_VE_YOL_HARITASI_2026_09.md` §3.
İlerleme: `docs/YOL_HARITASI_ILERLEME.md`.

---

## ✅ UYGULANDI: `0051_percentile_180d.sql` (2026-09-13)

180 günlük yüzdelik dilim kovası **canlıda açık** — doğrulandı
(2026-09-13, uzak veritabanına sorguyla):

| Yer | Durum |
|---|---|
| `user_roi_snapshots` CHECK | `ARRAY[7, 30, 180, 365]` ✅ |
| `get_percentile_bucket` | 180 allowlist'te ✅ |
| `get_top_gainers_allocation` | 180 allowlist'te ✅ |
| Yetkiler | `authenticated` + `service_role`; `anon`/`public` YOK ✅ |
| `search_path` | `public` sabitlenmiş, `SECURITY DEFINER` ✅ |

180 satırının gerçekten yazılabildiği de `rollback`'li bir deneme
insert'iyle doğrulandı — CHECK, RLS ve throttle trigger'ının hepsi
geçildi.

> **⚠️ Migration defteri GÜNCEL DEĞİL.** SQL Editor'den elle koşulduğu
> için `supabase_migrations` tablosuna kaydedilmedi: `supabase migration
> list` çıktısında `0050` ve `0051` için `remote` kolonu BOŞ görünüyor.
> Bir sonraki `supabase db push` ikisini yeniden koşmaya çalışır.
> **Zararsız** (ikisi de idempotent: `add column if not exists`,
> varlık kontrollü `DO` blokları, `CREATE OR REPLACE`) ama defteri
> düzeltmek temiz olur:
>
> ```bash
> supabase migration repair --status applied 0050 0051
> ```

**k-anonimlik değişmedi:** `k_min = 8` ve `n_max = 4` aynen korunuyor.
Yeni bir kova eklendi, eşik matematiğine dokunulmadı.

### Şerit neden HÂLÂ görünmüyor (ve bu neden normal)

Ölçüldü (2026-09-13): son 24 saatte havuzda **tek kullanıcı** var (sen).
Üç kovanın hepsi k=8'in altında, yani ana ekrandaki mevcut
`PercentileStrip` de görünmüyordur. Bu **doğru davranış** — KVKK
k-anonimliği. Tek kullanıcıyla test ederek şeridi göremezsin.

Ayrıca `period_days = 180` satırı henüz HİÇ yok: `_yukleDilim` yalnızca
**Performans → Özet → 6A** sekmesi açıldığında snapshot atıyor. Sekme bu
kodu taşıyan bir derlemede bir kez açılınca satır düşer.

```sql
-- Kova başına havuz durumu
select period_days,
       count(distinct user_id) as kisi_24s,
       case when count(distinct user_id) >= 8 then 'ACIK' else 'KAPALI' end
  from user_roi_snapshots
 where created_at >= now() - interval '24 hours'
 group by period_days order by period_days;
```

**Not:** `uploadRoiSnapshot` hatayı SESSİZCE yutuyor
(`leaderboard_service.dart` `catch (_)`). Migration'dan ÖNCE atılmış bir
180 insert'i CHECK'e takılıp iz bırakmadan kaybolurdu — artık takılmıyor,
ama bu sessizlik ileride benzer bir teşhiste yanıltabilir.

---

## 🎛️ İSTEĞE BAĞLI: `period_summary_enabled` bayrağı (2026-09-13)

Dönem Özeti (Performans → **Grafik | Özet** sekmesi) ve ana ekrandaki
"Bu hafta" kartı geldi. **Tamamen ücretsiz** — paywall'a bağlı değil.

**Elden yapılacak bir şey YOK.** Bayrak varsayılan olarak `true` doğuyor,
yani yeni sürüm çıktığı anda açık. Bu madde yalnızca bayrağın VAR
olduğunu bilmen için:

- Firebase Console → Remote Config → `period_summary_enabled`
- `false` çekersen **yalnızca ana ekran kartı** gizlenir; Performans
  ekranındaki Özet sekmesi kalır (kullanıcının bilinçli olarak girdiği
  bir yer, dikkat bütçesinden yemiyor).

Ölçüm: `period_summary_viewed` olayı (parametre `period`: `gunluk` |
`birHafta` | `birAy` | `altiAy` | `birYil`). **Faz 2 kararı buna
bağlı** — 1H sekmesi hiç açılmıyorsa haftalık push'un gönderilecek bir
karşılığı yok demektir.

Migration yok, vault sırrı yok, edge function yok. Faz 2 (haftalık push)
2026-09-14'te geldi — aşağıdaki maddeye bak.

---

## 🔴 TEK ADIM KALDI (HER ŞEYİ BLOKLUYOR): `cron_gateway_jwt` (2026-09-14)

**Bunu yapmadan hiçbir cron bildirimi gitmiyor — bugün de gitmiyordu.**

### Ne oldu

Haftalık özeti canlı doğrularken dört aylık **sessiz** bir arıza bulundu:
`daily_brief_log` Mayıs 2026'dan beri BOŞ. Sabah brifingi hiç
gönderilmemişti. Sebep cron'da ya da fonksiyonda değil, **header'da**:

Supabase API gateway, isteği fonksiyona iletmeden önce `Authorization`
header'ını JWT olarak ayrıştırıyor. Tetikleyiciler oraya rastgele hex bir
cron secret koyuyordu; gateway bunu JWT sanıp isteği **fonksiyona hiç
ulaştırmadan** reddediyordu (`401 UNAUTHORIZED_INVALID_JWT_FORMAT`).

Fark edilmemesinin sebebi: her gösterge yeşildi. Cron kurulu ✓, koşu
başarılı ✓, fonksiyon logları boş (çünkü hiç çalışmadı), 401 yalnızca
`net._http_response` içinde.

Kod tarafı düzeltildi ve dağıtıldı (`0054` + `_shared/cron_auth.ts`):
`Authorization` artık service_role JWT'si taşıyor, cron secret'ı
`x-cron-secret` header'ına geçti.

### Senin yapacağın: Vault'a service_role JWT'sini yaz

Migration bunu yazamaz — service_role key'ini SQL içinden okuyamaz ve
repoya girmemeli.

1. **Dashboard → Settings → API → `service_role` (secret)** → kopyala
   *(`anon` DEĞİL — `service_role` olan, `eyJ...` ile başlayan uzun JWT)*
2. **SQL Editor**'de:

```sql
select vault.create_secret(
  '<service_role JWT>',
  'cron_gateway_jwt',
  'API gateway JWT dogrulamasini gecmek icin — cron tetikleyicileri'
);
```

3. Sonra migration'ı koş:

```bash
supabase db push   # 0054_cron_auth_header.sql
```

`0054` kurulum eksikse **açık hatayla durur** (sessiz düşmemesi kasıtlı —
bu arızanın ilk hâli tam olarak sessizliğinden dolayı dört ay yaşadı).
JWT biçimini de denetliyor: oraya hex bir string yazılırsa yine patlar.

Yedi tetikleyicinin hepsi bu tek kaydı okur — key rotasyonu yedi ayrı
Vault kaydına dokunmak olmasın diye.

### Doğrulama — asıl kapı bu

```sql
select public.trigger_daily_brief();
select id, status_code, left(content, 200) from net._http_response
order by id desc limit 1;
```

| Gördüğün | Anlamı |
|---|---|
| `200` | ✅ çalışıyor — dört aylık arıza kapandı |
| `401 UNAUTHORIZED_INVALID_JWT_FORMAT` | `cron_gateway_jwt` yok ya da JWT değil |
| `401 Yetkisiz cron cagrisi` | Vault'taki cron secret'ı fonksiyonun env secret'ıyla eşleşmiyor |

Ayrıntı: [`supabase/functions/_shared/CRON_AUTH.md`](supabase/functions/_shared/CRON_AUTH.md)

### ⚠️ Ayrıca düzeltmen iyi olur (bloklamıyor)

İki cron sırrı **aynı string**: `weekly_summary_cron_secret` ve
`inflation_fetch_cron_secret` özdeş. Çalışır, ama biri sızarsa ikisi birden
düşer. Her biri için ayrı `openssl rand -hex 32` üretip hem
`supabase secrets set` hem Vault tarafını güncellemek daha doğru.

---

## ✅ UYGULANDI: haftalık özet push'u — Faz 2 (2026-09-14)

Fonksiyon dağıtıldı, secret'lar verildi, Vault yazıldı, `0052` uygulandı.
Cron doğrulandı: `weekly-summary = 45 6 * * 1`,
`daily-brief = 45 6 * * 2-5` (Pazartesi susturulmuş ✓).

⚠️ Ama gönderim **yukarıdaki `cron_gateway_jwt` adımına bağlı** — o
yapılmadan tetikleyici gateway'de 401 alır.

**Migration ne yapıyor:** `weekly_summary_log` defteri,
`profiles.weekly_summary_push` kolonu, `trigger_weekly_summary()`,
cron (`45 6 * * 1` = Pazartesi TR 09:45) ve **`daily-brief`'i `1-5` → `2-5`
daraltma**. Sonunda kendi sonucunu doğruluyor: cron kurulmadıysa ya da
brifing susturulamadıysa YÜKSEK SESLE patlıyor (sessizce uygulanmamış bir
cron, "çalıştığı sanılan ama çalışmayan" en pahalı hata sınıfı).

### Kuru koşu (kimseye bildirim gitmez)

```bash
curl -X POST "https://<proje>.supabase.co/functions/v1/weekly-summary" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "x-cron-secret: $WEEKLY_SUMMARY_CRON_SECRET" \
  -H "Content-Type: application/json" -d '{"dry_run": true}'
```

Dönen alanlar ve **ne anlama geldikleri**:

| Alan | Anlamı |
|---|---|
| `sent` | gidecek bildirim |
| `skipped_flow` | hafta içinde alım/satım yaptığı için elenen — **en önemlisi** |
| `skipped_coverage` | uçları pencere kenarına 48 saatten uzak olan |
| `skipped_quiet` | eşiğin (%2) altında kalan |
| `skipped_opt_out` | `weekly_summary_push = false` |

### ⚠️ `sent: 0` görmek muhtemelen NORMAL

Kendi hesabınla test ederken büyük olasılıkla `skipped_flow` ya da
`skipped_coverage` altında elenirsin:

- **`skipped_flow`** — hafta içinde alım/satım yaptıysan push GİTMEZ. Bu
  bilinçli bir karar: `snapshots` brüt değer tutuyor, para girişi
  ayıklanmıyor ve "+%30 kazandın" gibi yanlış bir rakam göndermek hiç
  göndermemekten kötü. Ayrıntı: `supabase/functions/weekly-summary/README.md`.
- **`skipped_coverage`** — `snapshots` yalnızca uygulamayı açtığında
  yazılıyor. Hafta başında ve sonunda (48 saat içinde) birer snapshot
  yoksa yüzde eksik bir pencereyi anlatırdı.

Zorla bir gönderim görmek istersen: temiz bir hafta (işlem yapılmamış) +
hafta başı/sonu uygulamayı açmış olmak + `{"min_move_pct": 0}` ile kuru
koşu.

### Doğrulama sorguları

```sql
-- Cron'lar doğru kurulmuş mu? (Pazartesi ikisi birden koşmamalı)
select jobname, schedule from cron.job
 where jobname in ('weekly-summary', 'daily-brief', 'weekly-summary-cleanup')
 order by jobname;
-- beklenen: daily-brief = '45 6 * * 2-5', weekly-summary = '45 6 * * 1'

-- Kime gönderilmiş?
select sent_on, count(*) from weekly_summary_log
 group by sent_on order by sent_on desc limit 5;
```

**Ayrıca:** Ayarlar → BİLDİRİMLER → "Haftalık özet" anahtarı eklendi
(`profiles.weekly_summary_push`, varsayılan açık). Android'de ayrı kanal
(`summary_channel`) — kullanıcı haftalık özeti kapatıp sabah brifingini
açık tutabilir.

Ayrıntı: `supabase/functions/weekly-summary/README.md`

---

## 🚨 BEKLEYEN DEPLOY: satılan/silinen varlık için push (2026-09-07 → 2026-09-10)

**Belirti:** Tamamen SATILMIŞ hisseler için sinyal bildirimi gelmeye devam
ediyordu ("AVOD ve AGHOL varlıklarımda olmamasına rağmen push'ları geliyor").

**Sebep:** `assets` bir lot tablosu; satış alım satırını silmez, `kind='sell'`
ayrı bir satır yazar. Sunucu yalnızca `kind='buy'` filtreliyor, satışları
netlemiyordu — uygulama net 0 pozisyonu portföyden düşürdüğü için kullanıcı
"bende yok" görüyor, sunucu "hâlâ var" sanıyordu.

**Düzeltme kodda** (`supabase/functions/_shared/positions.ts`) ama **Edge
Function'lar yeniden dağıtılmadan etkili olmaz.** Push'lar sunucudan gidiyor;
uygulama güncellemesi bu hatayı düzeltmez.

```bash
supabase functions deploy analyze-signals
supabase functions deploy daily-brief
```

Doğrulama (push göndermez, yalnızca analiz eder):
```bash
curl -X POST "https://<proje>.supabase.co/functions/v1/analyze-signals" \
  -H "Authorization: Bearer <SERVICE_ROLE_KEY>" \
  -H "x-cron-secret: <ANALYZE_SIGNALS_CRON_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"dry_run":true}'
```
Yanıttaki `closed_or_deleted_lots` alanı, **satış ya da silme** yüzünden
elenen alım lot'u sayısıdır. Sıfırdan büyükse düzeltme fiilen çalışıyor
demektir; `preview` listesinde satılmış/silinmiş varlıklar artık
görünmemeli.

**Silme tarafı ayrıca ele alındı.** Silmenin asıl mekanizması `deleted_at`
damgasıdır ve sunucu onu zaten eliyordu; ama istemci önce mezar taşını
(`delete_log`) yazıp SONRA damgayı atıyor — arada bağlantı koparsa lot
sunucuda AKTİF kalır, uygulama ise kendi durumunu iyimser güncellediği için
kullanıcı varlığı silinmiş görür. Artık sunucu mezar taşını da dinliyor:
pozisyonun tamamını silen bir `delete_log`'dan ESKİ alım lot'ları
susturuluyor (sonra tekrar alınmışsa bildirim yine gider).

Bu yüzden `assets` sorgusuna `added_date` ve `ref_asset_id` sütunları
eklendi — deploy edilmeden ikisi de okunamaz.

### 🔁 2026-09-10 — aynı dosyada İKİNCİ düzeltme, deploy hâlâ bekliyor

Kullanıcı bildirimi sürüyordu: "sildiğim varlıkların push'ları gelmeye devam
ediyor." Yukarıdaki mezar taşı savunması **tek lot'lu pozisyonlarda hiç
çalışmıyordu** — yani en yaygın durumda.

Sebep: `ref_asset_id` DOLU mezar taşları tamamen atlanıyordu. Eski gerekçe
("o satır zaten fiziksel silinmiştir") yalnızca `deleteAsset` için doğru.
Normal silme yolu `deletePositionLots` ve o YUMUŞAK siliyor: pozisyon tek
lot'luysa mezar taşına `ref_asset_id` yazıp lot'u `deleted_at` ile
damgalıyor. Damga sunucuya ulaşmazsa lot AKTİF kalıyor, mezar taşı da
atlandığı için bildirim gitmeye devam ediyordu.

Artık o mezar taşı, işaret ettiği lot'u — ve **yalnızca** onu — eliyor;
miktarı netten de düşülüyor. Kardeş lot'lar susmuyor (iki lot'lu bir
varlıkta birini silmek diğerini sessizleştirmemeli).

`_shared/positions.ts` yine değişti, yani **aşağıdaki iki komut hâlâ
koşulmalı.** Uygulama tarafındaki eş düzeltme (`analyzePortfolio` artık ham
ledger yerine yalnızca açık pozisyonları geziyor) TestFlight 1.1.4
(1785274310) içinde — ama cron'dan giden push'lar sunucudan üretiliyor ve
onu ancak deploy düzeltir.

Deploy sonrası dry-run'da `closed_or_deleted_lots` sayısı, önceki turdakine
göre ARTMALI: artık tek lot'lu silmeler de eleniyor.

---

## 🚨 BEKLEYEN DEPLOY: kilit ekranı teması (2026-09-11) — EN OLASI SEBEP

**Belirti:** "Canlı etkinlikler tema rengi sürekli değişiyor; uygulamayı
kill etsem de son seçilen tema kalmalı."

### 1) Birinci sebep: `push-live-activity` HİÇ DAĞITILMAMIŞ olabilir

Temayı push gövdesine koyan sunucu kodu **2026-09-03**'te eklendi
(commit `b5ce9e4`). 2026-09-07 tarihli `docs/archive/SUPABASE_DEPLOY_ADIMLARI.txt`
yalnızca `analyze-signals` ve `daily-brief`'i listeliyor —
`push-live-activity` hiçbir deploy listesinde geçmiyor.

Dağıtılmadıysa sunucudaki ESKİ sürüm `isLightTheme` alanını **hiç
göndermez**; Swift tarafı eksik alanı `false` = KOYU varsayar
(`SandikAttributes.swift`, bilinçli geri uyumluluk). Sonuç tam olarak
kullanıcının gördüğü şey:

| durum | yüzeyi kim besliyor | palet |
|---|---|---|
| uygulama önplanda | ActivityKit yerel `update` | **doğru** |
| uygulama kapalı / 5 dk'lık cron push | eski edge function | **koyu** |

Yani banner uygulamayı her açıp kapadıkça renk değiştirir. **Uygulama
güncellemesi bunu düzeltmez** — hangi build'i kursan sunucu aynı eksik
gövdeyi göndermeye devam eder.

```bash
supabase functions deploy push-live-activity
```

Doğrulama: komut çıktısındaki sürüm/tarih güncel olmalı; sonra kilit
ekranını 5-10 dakika (bir cron turu) izle — palet artık dönmemeli.

### 2) İkinci sebep: tema özetin içine gömülüydü

**Sebep:** tema yalnızca `live_activity_sessions.summary` JSON'unun içinde
taşınıyordu ve o JSON **yalnızca portföy özeti yazılırken** güncelleniyor.
Uygulama kapalıyken kilit ekranını besleyen tek şey bu satır olduğu için,
özetin tazelenmediği her durumda (tema gösterim penceresi dışında
değiştirildi, oturum satırı yeni açıldı, özet eski şema damgası taşıyor)
sunucu ESKİ paletle push atıyordu. Uygulama açılınca doğru palet basılıyor,
kapanınca geri dönüyordu.

**Düzeltme iki parçalı — uygulama güncellemesi TEK BAŞINA yetmez:**

a) Migration (tek satır, geri alınabilir):
```sql
alter table live_activity_sessions
  add column if not exists is_light_theme boolean not null default false;
```
ya da `supabase db push` (dosya: `0050_live_activity_theme.sql`).

b) Edge function (push içeriğini artık bu sütundan okuyor) — yukarıdaki
(1) ile aynı komut, bir kez koşmak ikisini de kapsar:
```bash
supabase functions deploy push-live-activity
```

**Sıra önemli: ÖNCE migration, SONRA function.** Fonksiyon satırı `select('*')`
ile okuduğu için sütun yokken patlamaz, ama sütun gelene kadar eski
(özet içindeki) yedek değeri kullanmaya devam eder.

Koşulmazsa ne olur: uygulama çökmez, kilit ekranı donmaz — tema yine
özet üzerinden taşınır, yani düzeltmenin **yalnızca** uygulama içi ayağı
çalışır ve "kill edince değişiyor" bulgusu sürer.

**Doğrulama (uygulamadan, kod gerekmez):** Profil → (admin) Push Teşhisi →
**6. CANLI ETKİNLİK / TEMA** bölümü. Üç satırı karşılaştır:
* `Yerel karar` — uygulamanın çözdüğü tema,
* `sütun (is_light_theme)` — sunucunun push'a koyduğu değer,
* `özet (summary.isLightTheme)` — eski yedek yol.

"SÜTUN YOK" yazıyorsa migration koşulmamıştır. `Tercih: Sistem` yazıyorsa
temanın cihazla birlikte değişmesi **normaldir** — sabitlemek için Ayarlar'dan
açıkça Açık ya da Koyu seçilmeli.

---

## 🗄️ BEKLEYEN MIGRATION: `0049_partner_activity_push.sql` (2026-09-07)

`profiles` tablosuna `partner_activity_push` sütunu ekler. Çalıştırılmazsa:
Ayarlar'daki "Ortak hareketi bildirimleri" anahtarı yazmaya çalışır ve hata
verir; günlük brifing de ortak kolunu hiç açamaz (sorgu düşer, brifing
sessizce hisse mesajına döner).

Tek satır, geri alınabilir:
```sql
alter table public.profiles
  add column if not exists partner_activity_push boolean not null default true;
```

---

## 🔑 VAULT ADIMI — üç cron sırrı (2026-09-07)

Üç Edge Function dağıtıldı ve `supabase secrets` tarafı yazıldı. **Kalan tek
adım Vault.** Cron tetikleyicileri sırrı Vault'tan okuyor; Vault'ta karşılığı
yoksa fonksiyon **401** döner ve hiçbir bildirim gitmez.

> ⚠️ **2026-09-14 güncellemesi:** Bu sırlar artık `Authorization` header'ında
> DEĞİL, `x-cron-secret` header'ında gönderiliyor. `Authorization`'a
> service_role JWT'si gidiyor ve o **`cron_gateway_jwt`** adlı ayrı bir Vault
> kaydından okunuyor — bu dosyanın başındaki 🔴 bölüme bak. Aşağıdaki Vault
> mekaniği aynen geçerli; yalnızca sırrın hangi header'da taşındığı değişti.
>
> Aşağıda uyarılan "mükerrer kayıt / `order by` eksikliği" sorunu da `0054`
> ile kapandı: okuma artık `order by created_at desc` yapıyor ve mükerrer
> kayıt varsa uyarı basıyor.

Sırların gerçek değerleri repoya YAZILMADI (bu dosya git'te izleniyor).
Değerler şurada:
`%LOCALAPPDATA%\Temp\claude\c--projects-PortfoyTakip\<oturum>\scratchpad\`
→ `pa.txt` (price alerts), `cn.txt` (calendar nudge), `db.txt` (daily brief).

Supabase Dashboard → SQL Editor'da, `<...>` yerlerine o dosyaların içeriğini
koyarak çalıştır:

```sql
-- Mükerrer kayıt YARATMA: 0034'te belgelendiği gibi vault.create_secret
-- her çağrıda YENİ satır ekler ve 0046/0048'deki okuma `order by`
-- içermediği için hangisinin okunacağı garanti değildir.
-- Bu blok varsa günceller, yoksa oluşturur.
do $$
declare
  s record;
begin
  for s in
    select * from (values
      ('price_alerts_cron_secret',   '<pa.txt icerigi>'),
      ('calendar_nudge_cron_secret', '<cn.txt icerigi>'),
      ('daily_brief_cron_secret',    '<db.txt icerigi>')
    ) as t(nm, val)
  loop
    if exists (select 1 from vault.secrets where name = s.nm) then
      perform vault.update_secret(
        (select id from vault.secrets where name = s.nm order by created_at desc limit 1),
        s.val, s.nm, null);
    else
      perform vault.create_secret(s.val, s.nm, null);
    end if;
  end loop;
end $$;

-- Doğrulama: her ad için TEK satır olmalı.
select name, count(*) from vault.decrypted_secrets
 where name in ('price_alerts_cron_secret','calendar_nudge_cron_secret',
                'daily_brief_cron_secret')
 group by name;
```

Sonra kuru koşu yap (kimseye bildirim gitmez) — `<secret>` yerine ilgili
dosyanın içeriği:

```bash
curl -X POST "https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/check-price-alerts" \
  -H "Authorization: Bearer <pa.txt>" \
  -H "Content-Type: application/json" -d '{"dry_run": true}'
```

`200` + kaç kişiye gideceği dönerse kurulum tamamdır; `401` dönerse Vault
değeri `supabase secrets` değeriyle eşleşmiyordur.

---

## 📊 GENEL DURUM

✅ **Bende biten kod işleri:**
- Marka: `com.sandik.app`, label "sandık"
- Güvenlik: yasaklı izin silindi, db_logs PII maskeleme, secrets → dart-define, ProGuard/R8 aktif
- Hesap silme akışı: UI + AuthService + Edge Function + SQL migration
- 6 adet P0 crash fix
- Supabase timeout (15sn)
- friendlyError helper + 8 yerde uygulama
- Register'a KVKK + Açık Rıza checkbox'ları
- 9 adet hukuki belge (TR + EN)

---

## ✅ (KAPANDI) DM Sans fontları — Xcode adımı GEREKMİYOR

Fontlar `ios/SandikWidget/Fonts/` altına konuldu, `Info.plist`'e
`UIAppFonts` kaydı yapıldı ve **`project.pbxproj` doğrudan düzenlenerek**
SandikWidget hedefinin *Copy Bundle Resources* fazına eklendi.

Yani Xcode açmana gerek yok — GitHub Actions'taki build fontları
kendiliğinden paketleyecek.

**TestFlight'ta doğrulama:** kilit ekranındaki "Sandık" yazısı ve rakamlar
uygulamanın içindeki başlıklarla aynı karakter biçiminde olmalı. Sistem
fontuna (SF Pro) düşmüş görünüyorsa `UIAppFonts` kaydı ya da hedef üyeliği
bozulmuş demektir.

---

## 📅 KISMEN TAMAM: TÜİK Enflasyon Kancası (2026-09-07)

1. ✅ `supabase functions deploy calendar-nudge` — dağıtıldı
2. ✅ `supabase secrets set CALENDAR_NUDGE_CRON_SECRET` — yazıldı
3. ⬜ **KALDI —** Vault → `calendar_nudge_cron_secret` (bkz. aşağıdaki
   "VAULT ADIMI" bölümü; bu yapılmadan cron 401 alır)
4. ✅ Migration `0048_calendar_nudge.sql` — koşuldu

**TÜFE endeksi dolu değilse bildirim gitmez** — endeks artık otomatik
çekiliyor ama EVDS anahtarı gerekiyor (bkz. "TEK ADIM KALDI: TÜFE
otomatik çekimi").

⚠️ **2026-09-14 sonrası:** `0053` bu kancanın ayın 4'ündeki ikinci turunu
açıyor ve fonksiyon gönderim defterini okuyacak şekilde güncellendi.
`supabase functions deploy calendar-nudge` YAPILMADAN migration koşulursa
çift bildirim gider.

Ayrıntı: `supabase/functions/calendar-nudge/README.md`

---

## 🔔 KISMEN TAMAM: Fiyat Alarmları (2026-09-07)

Kod hazır; kullanıcı Ayarlar → "Fiyat alarmları"ndan kurabiliyor ama
**Vault adımı yapılmadan hâlâ hiçbir alarm çalmaz.**

1. ✅ `supabase functions deploy check-price-alerts` — dağıtıldı
2. ✅ `supabase secrets set PRICE_ALERTS_CRON_SECRET` — yazıldı
3. ⬜ **KALDI —** Vault → `price_alerts_cron_secret` (bkz. "VAULT ADIMI")
4. ✅ Migration `0046_price_alerts.sql` — koşuldu

Kuru koşu (kimseye bildirim gitmez):

```bash
curl -X POST "https://<proje>.supabase.co/functions/v1/check-price-alerts" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "x-cron-secret: $PRICE_ALERTS_CRON_SECRET" \
  -H "Content-Type: application/json" -d '{"dry_run": true}'
```

Ayrıntı: `supabase/functions/check-price-alerts/README.md`

---

## 🔑 TEK ADIM KALDI: TÜFE otomatik çekimi — EVDS anahtarı (2026-09-14)

Reel getiri rozeti ("enflasyonun 6,4 puan önündesin") ve Özet sekmesinin
TÜFE satırları `inflation_index` tablosuna bağlı. **Tablo artık ELLE
doldurulmuyor** — `fetch-inflation` edge function'ı her ayın 3'ünde
TCMB EVDS'den çekiyor.

**Aylık bakım BİTTİ.** Yapman gereken tek şey bir kerelik anahtar:

### 1) EVDS anahtarı al (5 dakika, ücretsiz)

evds2.tcmb.gov.tr → üye ol → **Profil → API Anahtarı**

### 2) Dağıt

```bash
# ✅ YAPILDI — fonksiyonlar dağıtıldı, cron secret'ı + Vault yazıldı,
#              0053 uygulandı, calendar-nudge yeniden dağıtıldı.
#              Cron doğrulandı: fetch-inflation 10:05 < nudge 10:15 ✓

# ⬜ KALAN TEK ŞEY — EVDS anahtarı:
supabase secrets set EVDS_API_KEY="<evds-anahtarin>"
```

⚠️ Ayrıca **yukarıdaki `cron_gateway_jwt`** adımı yapılmadan bu tetikleyici
de gateway'de 401 alır (`inflation_index` şu an boş — çekim hiç
çalışmamış olabilir).

### ⚠️ `calendar-nudge` neden yeniden dağıtılmalı

Migration, takvim kancasının **ayın 4'ündeki ikinci turunu açıyor** (veri
bir gün geç yayımlanırsa o ayın kancası kaçmasın diye). Bu tur ancak
fonksiyon **gönderim defterini** okuyorsa güvenli.

Eski sürümde kalırsa: veri 3'ünde zamanında girildiğinde **iki bildirim**
gider — yani `0048`'in ikinci turu kapatma sebebinin aynısı geri gelir.

### Anahtarı almadan ne olur

Hiçbir şey bozulmaz. Fonksiyon `no_api_key` döner ve **tabloya yazmaz**;
tablo boş kaldığı için rozet de görünmez (bugünkü durumun aynısı). Yarım
bir entegrasyonla tabloyu bozmaktansa kapalı kalması tercih edildi.

### Doğrulama

```bash
# Tabloya YAZMADAN — ne çekeceğini söyler
curl -X POST "https://<proje>.supabase.co/functions/v1/fetch-inflation" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "x-cron-secret: $INFLATION_FETCH_CRON_SECRET" \
  -H "Content-Type: application/json" -d '{"dry_run": true}'
```

İlk gerçek koşu **24 ay** geriye gider. Rozet 365 günlük pencere
kullanıyor, yani en az **13 ay** gerekiyor (başlangıç ayı + son açıklanan
ay); 24 ay pencereyi rahatça dolduruyor.

```sql
select count(*) as ay_sayisi, min(period), max(period) from inflation_index;
```

**Sonra:** Remote Config → `real_return_enabled` → `true`. Tablo dolu olsa
bile bu bayrak kapalıysa rozet görünmez.

### 🚨 Bir gün gelecek: baz yılı değişimi

TÜİK baz yılını değiştirdiğinde (ör. 2003=100 → 2025=100) endeks
SIFIRLANIR ve eski satırlarla yeni satırlar karşılaştırılamaz. Fonksiyon
bunu yakalayıp **yazmayı reddediyor** (`base_year_break`, HTTP 409) —
çünkü bölme "−%95 enflasyon" gibi anlamsız bir sonuç verirdi.

O gün geldiğinde bu senin kararın olacak: yeni seriyi ayrı mı tutmak,
eski satırları mı silmek, ikisini bir dönüşüm katsayısıyla mı birleştirmek.
Otomatik çözülmez ve sessizce yanlış yapmasın diye kasten durduruluyor.

Ayrıntı: `supabase/functions/fetch-inflation/README.md`
Migration: `0045_inflation_index.sql` (tablo), `0053_fetch_inflation.sql` (çekim)

---

## 📨 KISMEN TAMAM: Sabah Brifingi (2026-09-07)

**Vault adımı yapılmadan hiçbir kullanıcıya bildirim gitmez.**

1. ✅ `supabase functions deploy daily-brief` — dağıtıldı
2. ✅ `supabase secrets set DAILY_BRIEF_CRON_SECRET` — yazıldı
   (FCM_PROJECT_ID ve FCM_SERVICE_ACCOUNT_JSON zaten vardı)
3. ⬜ **KALDI —** Vault → `daily_brief_cron_secret` (bkz. "VAULT ADIMI")
4. ✅ Migration `0044_daily_brief.sql` — koşuldu

**Önce kuru koşu yap** — kimseye bildirim gitmeden kaç kişiye gideceğini
söyler:

```bash
curl -X POST "https://<proje>.supabase.co/functions/v1/daily-brief" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "x-cron-secret: $DAILY_BRIEF_CRON_SECRET" \
  -H "Content-Type: application/json" -d '{"dry_run": true}'
```

Ayrıntı: `supabase/functions/daily-brief/README.md`

---

## 🗄️ BEKLEYEN MIGRATION: `0027_soft_delete_lots.sql` (2026-08-11)

**Ne:** `assets` tablosuna `deleted_at TIMESTAMPTZ` sütunu + aktif kayıtlar
için kısmi indeks.

**Neden gerekli:** Silme artık FİZİKSEL değil, YUMUŞAK. Lot'lar yerinde
kalır ve damgalanır; böylece silinen varlığın Alım/Satım/Temettü satırları
"Portföy Hareketleri"nde durmaya devam eder. Toplamlar/grafik/aggregate
damgalı kayıtları eler (`Asset.isActive`).

**Uygulanmazsa ne olur:** Silme UPDATE'i patlar (bilinmeyen sütun) →
kullanıcı varlık silemez. Bloker.

**Nasıl:**
```bash
supabase db push
```
veya Dashboard → SQL Editor → `supabase/migrations/0027_soft_delete_lots.sql`.

**Geriye dönük uyumlu:** Mevcut satırlarda NULL = aktif, davranış değişmez.
Daha önce FİZİKSEL silinmiş kayıtlar geri gelmez (veri yok) — bu migration
öncesi silinen varlıkların geçmişi kurtarılamaz.

---

## ✅ UYGULANDI: `0026_delete_log_count.sql` (2026-08-11)

`assets.deleted_count INTEGER NOT NULL DEFAULT 0` sütunu eklendi. Silme
artık lot başına değil, pozisyon başına TEK kayıt yazıyor ve kaç ledger
satırının silindiğini bu sütunda taşıyor → "Silindi · 3 kayıt".

Eski `delete_log` satırlarında sütun 0 kalır; uygulama 0'ı "sayı bilinmiyor"
sayıp düz "Silindi" gösterir. Bekleyen bir iş yok.

---

## 💰 MONETİZASYON: `paywall_enabled` bayrağı (2026-07-13)

**Şu an durum:** Paywall UI iskeleti hazır ama **Firebase Remote Config** üzerinden `paywall_enabled = false` ile kapalı. Kullanıcı hiçbir premium/ödeme ekranı görmüyor.

**Açman gerekli olduğunda sıra:**

1. **App Store Connect + Google Play Console** — 2 subscription ürünü oluştur (aynı product ID'ler):
   - `sandik_premium_monthly`
   - `sandik_premium_yearly`
2. **RevenueCat Dashboard:** proje aç → iOS/Android app'leri bağla → `premium` entitlement + `default` offering tanımla → iOS/Android API key'lerini al
3. Bana bildir → RevenueCat SDK entegrasyonunu yaparım ([paywall_screen.dart:120, :140](lib/screens/paywall_screen.dart) TODO'ları)
4. **Firebase Console → Remote Config → `paywall_enabled` → `true` → Publish**
5. Uygulama açılışında UI otomatik gelir, kod push'una gerek yok

Detay: [MONETIZATION_ROADMAP.md](MONETIZATION_ROADMAP.md#-master-kill-switch-paywall_enabled-2026-07-13)

---

❌ **Senin yapacakların — 7 ana başlık, 4-6 iş günü:**

| Sıra | İş | Tahmini süre | Bloker? |
|---|---|---|---|
| 1 | Marka kararları (logo, domain, e-posta) | 1 gün | Evet — diğer her şey buna bağlı |
| 2 | Tüzel kişilik & hukuki TODO'ları doldur | 1-2 gün | Evet — yayın bloker |
| 3 | Web sayfası (hukuki + hesap silme) | 1 gün | Evet — Play Store bloker |
| 4 | Release keystore oluştur | 30 dk | Evet — Play upload bloker |
| 5 | Supabase deploy (migration + Edge Function) | 30 dk | Evet — hesap silme bloker |
| 6 | Google Play Console hesap ve listing | 1 gün | Evet |
| 7 | Manuel test (özellikle hesap silme) | 4 saat | Evet |

---

## 1. 🎨 MARKA KARARLARI (önce bu)

Bunlar sonraki her şeyin temeli. Önce karar verelim ki ben de URL'leri / e-posta'ları kodda yerine koyabileyim.

### 1.1 Domain Adı

İhtiyacın olan: Web sitesi için bir domain (hukuki belgeleri + hesap silme formunu host edeceksin).

**Öneri:** `sandik.app` veya `sandik.com.tr` veya `sandikapp.com`

- **Nereden alınır:** namecheap.com, godaddy.com, isimtescil.net (TR)
- **Tahmini maliyet:** Yıllık ~$15-100 (uzantıya göre)
- **Süreç:** Whois bilgisi gizli olsun (privacy protection — çoğu kayıtçıda ücretsiz)

⚠️ **Karar al ve bana söyle.** Şu an kodda `https://sandik.app/...` placeholder var; başka bir domain seçersen değiştireceğim.

### 1.2 İletişim E-posta

İhtiyacın olan: Destek + KVKK başvuruları + Apple/Google reviewer için.

**Öneri:** `destek@sandik.app` veya `info@sandik.app`

- **Nereden alınır:** Google Workspace ($6/ay/kullanıcı), Zoho Mail (ücretsiz tier var), domain sağlayıcının mail servisi
- **Asgari:** Spam dolu kişisel Gmail değil, domain'inin mail'i.
- **Önerilen:** Ayrıca `kvkk@sandik.app` ve `privacy@sandik.app` alias'ları aç (KVKK başvuruları + GDPR requests için ayrı kanal).

Şu an kodda `destek@sandik.app` placeholder var.

### 1.3 App Store / Play Store Görünen İsim

**Karar verildi: "Sandık" (büyük S, dotless ı).** Arama bulunabilirliği için
tüm yüzeylerde tek yazım kullanılıyor:

- Android `strings.xml` → `Sandık` ✅ (kodda güncellendi)
- iOS `CFBundleDisplayName` → `Sandık` ✅ (eski değer `SANDIK` idi, düzeltildi)
- `store_listing/tr-TR/title.txt` → `Sandık: Portföy Takibi` ✅ (22/30 karakter)
- `store_listing/en-US/title.txt` → `Sandık: Portfolio Tracker` ✅ (25/30 karakter)

**Ayraç kararı (2026-08-09):** Başlıkta em dash (`—`) yerine iki nokta (`:`)
kullanılıyor. Bir sonraki release'de App Store Connect'e girilecek isim
budur; repo ile Console'un birebir aynı kalması için buradaki dosyalar da
güncellendi.

**⚠️ SENİN YAPMAN GEREKEN — Play Console'daki başlık repodan okunmaz.**
Store listing metinleri Console'a elle girilir; repodaki `store_listing/`
dosyaları yalnızca kaynak metindir. "Sandık" araması sonuç vermiyorsa asıl
sebep büyük ihtimalle Console'daki başlığın hâlâ eski yazımda olmasıdır.

Play Console → Grow → Store presence → Main store listing:
1. **App name** alanına `Sandık: Portföy Takibi` yaz
   (`store_listing/tr-TR/title.txt` içeriğiyle birebir aynı)
2. **Short description** → `store_listing/tr-TR/short_description.txt`
3. **Full description** → `store_listing/tr-TR/full_description.txt`
4. Kaydet → yayına alınması genelde birkaç saat, arama indeksine tam
   yansıması **birkaç güne kadar** sürebilir. Hemen sonuç bekleme.

**Not:** Play Store'un arama indeksi Türkçe diakritiklerde tam eşleşmeye
yakın davranıyor; bu yüzden `full_description.txt` içine "Sandık / sandık /
SANDIK / Sandik / sandik" varyantlarını içeren bir ARAMA bölümü eklendi.
Anahtar kelime doldurma (keyword stuffing) sayılmaması için varyantlar tek
bir doğal cümlede tutuldu — bu bölümü şişirme, politika ihlali riski var.

### 1.4 Logo & Görsel Asset'ler

Şu anda mevcut: `assets/images/sandik_icon.png` (launcher), `sandik_logo.svg`, `loading.gif`.

**Eksik / iyileştirilmeli:**
- **Adaptive icon foreground** (Android 8+): `assets/images/sandik_icon_fg.png` — saydam arkaplanlı, kenarlardan %33 boşluk bırakılmış (Android masking için). 1024x1024 PNG.
- **Adaptive icon background**: tek renk (`#0A1E15` — Sandik.background) yeterli.
- **Monochrome icon** (Android 13+ themed icons): siyah-beyaz silüet, 1024x1024.
- **Feature graphic** (Play Store): 1024x500 PNG/JPG. Logo + tagline.
- **Screenshot setleri** (en az 2, max 8):
  - Telefon: 1080x1920 minimum (örn. portföy listesi, varlık ekleme, performans grafiği, ortaklık, settings).
  - 7" tablet: opsiyonel ama önerilir.

**Maliyet seçenekleri:**
- Kendin yap: Figma ücretsiz, Canva $0-12/ay.
- Freelancer: fiverr.com ~$50-200, upwork.com daha pahalı ama kaliteli.
- Bir tasarımcı arkadaş varsa o ☺

---

## 2. 📜 HUKUKİ TODO'LAR (yayın bloker)

`legal/` klasöründeki 9 belgenin içinde `[ŞİRKET ADI]`, `[ADRES]` gibi placeholder'lar var. Hepsini gerçek değerle değiştirmen gerek.

### 2.1 Tüzel Kişilik Kararı (KRİTİK)

**Üç senaryo var, hangisi sende?**

#### Senaryo A — Bireysel girişimci (şirket yok)
- Veri sorumlusu: **Sen, ad-soyad** ile.
- Adres olarak ev adresi vermek istemiyorsan: sanal ofis hizmeti (~₺500/ay) veya muhasebecinin adresi.
- **VERBİS:** Bireysel veri işleyici muafiyet eşikleri var (yıllık ciro <100M TL VE çalışan <50 olanlar muaf olabilir). kvkk.gov.tr/Icerik/2030 → Verbis Hakkında. Muaf olsan bile KVKK Madde 10 aydınlatma yükümlülüğü devam eder.
- **Vergi:** Yıllık geliri ₺580.000 üstüne çıkarsa (2025 sınırı, yıllık güncelleniyor) basit usul vergi mükellefi ol.
- **Risk:** Şirketleşmeden uygulamadan gelir elde edersen vergi denetimi açar.

#### Senaryo B — Limited Şirket / Anonim Şirket
- Kuruluş maliyeti: ~₺15-30k (noter, sicil, muhasebeci, ilk ay).
- Aylık sabit gider: muhasebeci ₺2.5-5k.
- **Avantaj:** Vergi planlaması, sorumluluk şirkette, profesyonel görünüm.
- **VERBİS:** Çoğunlukla zorunlu.

#### Senaryo C — Şahıs şirketi (basit)
- Kuruluş ~₺3-5k. Vergiler şahıs üzerinden.
- Limited'in light versiyonu. App'ten ciddi gelir beklemiyorsan başlangıç için OK.

**Benim önerim:** App'i önce yayınla, kullanıcı bul, sonra para kazanmaya başlarken Senaryo C'ye geç. **Yayın için bireysel girişimci olarak başlayabilirsin** — sadece tüm hukuki belgelerde "Şirket" yerine "Veri Sorumlusu" sıfatıyla kendi adın ve sanal ofis adresinle imzala.

⚠️ **Karar al:** A, B veya C? Avukat veya muhasebeciyle 1 saatlik konsültasyon (~₺500-1000) çok mantıklı.

### 2.2 Placeholder'ları Doldur

Aşağıdaki tabloyu doldur, sonra tüm `legal/*.md` dosyalarında bulup değiştir.

| Placeholder | Senin değer |
|---|---|
| `[ŞİRKET ADI]` | (örn. "Yasin Çıralı" veya "Sandık Yazılım Ltd. Şti.") |
| `[AÇIK ADRES]` | (sanal ofis veya gerçek adres) |
| `[VERGİ NO]` | (varsa) |
| `[VERBİS NO]` | (varsa; muafsanız "Muaf — Madde 16") |
| `[KEP ADRESİ]` | (Limited/AŞ ise zorunlu; bireysel iseniz opsiyonel) |
| `[İLETİŞİM E-POSTA]` | (örn. destek@sandik.app) |
| `[TELEFON]` | (opsiyonel; girersen iş telefonu) |
| `[WEB SİTESİ]` | (örn. https://sandik.app) |
| `[YETKİLİ MAHKEME]` | (yerleşim yerin; örn. "İstanbul Anadolu") |
| `[DPO İSİM/E-POSTA]` | (Data Protection Officer — şirketsen ve verişlemen büyükse zorunlu, bireysel için yok) |
| `[EU REPRESENTATIVE]` | (AB pazarına ciddi servis veriyorsan zorunlu — başlangıçta atla) |

**Pratik komut** (placeholder'ı bul):
```bash
grep -rn "\[" legal/ | grep -v "^Binary" | grep -E "\[[A-Z]"
```

### 2.3 Hukuki Onay

Hazırladığım belgeler **kapsamlı şablon**. Ama **bir avukatla** mutlaka iki şeyi onaylat:

1. **Yatırım disclaimer'ı** — SPK avukatına: "Çoklu kullanıcı ortaklık özelliği 'kollektif portföy yönetimi' olarak yorumlanabilir mi?" sorusunu sor. Risk varsa "ortaklık" özelliğini "salt görüntüleme" olarak kısıtla.
2. **KVKK uygulanabilirliği** — KVKK avukatına: tüzel kişilik kararına göre VERBİS zorunlu mu, açık rıza metni yeterli mi.

**Avukat ücreti:** ~₺2-5k tek seferlik review (network'üne sor, KVKK + bilişim hukuku odaklı biri).

---

## 3. 🌐 WEB SAYFASI (Play Store BLOKER)

Google Play, hesap silme için **halka açık bir web URL** istiyor. Ek olarak privacy policy URL'i de zorunlu. Tek bir basit site yetiyor.

### 3.1 En Hızlı Yol: GitHub Pages (ÜCRETSİZ)

1. GitHub'da `sandik-website` adında yeni repo aç (public).
2. Şu dosyaları root'a koy:
   - `index.html` — landing page (logo, "App Store'dan indir" linki, hukuki link'leri)
   - `privacy.html` — `legal/tr/PRIVACY_POLICY.md` Markdown → HTML çeviri
   - `privacy-en.html` — `legal/en/PRIVACY_POLICY.md`
   - `terms.html` — Türkçe Terms
   - `terms-en.html`
   - `kvkk.html` — KVKK Aydınlatma Metni
   - `acik-riza.html` — Açık Rıza Metni
   - `data-deletion.html` — `legal/DATA_DELETION_REQUEST_FORM.md` içindeki HTML form
3. Settings → Pages → Source: `main` branch, `/` (root) → Save.
4. Domain bağla: Settings → Pages → Custom domain → `sandik.app` (DNS A record gerekir).

**Markdown → HTML için:** pandoc, marked-cli, veya en kolayı: https://stackedit.io üzerinde her dosyayı yapıştır + sağ taraftan "Export as HTML" indir.

### 3.2 Daha Profesyonel: Vercel / Netlify (ÜCRETSİZ)

- Next.js veya Astro ile statik site. Hızlı, SEO uyumlu.
- 2-3 saatlik iş.

### 3.3 Minimum Gereksinim

Aşağıdaki URL'ler **çalışır durumda** olmalı (Play Store reviewer click eder):

- `https://sandik.app/privacy` (TR + EN dil seçici)
- `https://sandik.app/terms`
- `https://sandik.app/legal/kvkk`
- `https://sandik.app/data-deletion` (form ile)
- `https://sandik.app/legal/acik-riza`

Tüm bu URL'ler kodda referans veriliyor (`lib/screens/settings_screen.dart` ve `register_screen.dart`).

### 3.4 Data Deletion Form Backend

`data-deletion.html` formunda kullanıcı talep gönderecek. İki seçenek:

**Basit:** Formspree (ücretsiz tier 50 istek/ay) — formu Formspree endpoint'ine post et, email olarak sana gelir.

**Gelişmiş:** Supabase Edge Function ile bir "deletion-request" tablosuna yaz, sana her istek için email bildirimi (kullanıcı uygulama içinden silmek yerine bu yolu seçerse).

---

## 3.5 🛡️ MobSF — Yayın öncesi APK güvenlik taraması (önerilir)

Mağazaya göndermeden önce derlenmiş APK/IPA'yı MobSF ile bir kez tara:
binary'ye sır sızmış mı, manifest/imza sertleştirmesi doğru mu.

- **CI'da otomatik:** `v*` tag push'unda `.github/workflows/mobsf-scan.yml`
  çalışır ve `mobsf-report.json` artefaktını üretir. İstersen Actions
  sekmesinden elle de tetikleyebilirsin (`workflow_dispatch`).
- **İsteğe bağlı secret:** `MOBSF_API_KEY` (yoksa CI-yerel sabit kullanılır).
- **Yerelde çalıştırma ve raporu okuma:** [`docs/security/mobsf.md`](docs/security/mobsf.md).

⚠️ MobSF **Dart iş mantığını okuyamaz** — yalnızca kabuğu (manifest, native
lib, gömülü string) denetler. Kaynak-seviyesi güvenlik incelemesi ayrıdır
(bkz. `SECURITY_AUDIT_2026_08.md`). İkisi birbirini tamamlar.

---

## 4. 🔐 RELEASE KEYSTORE OLUŞTUR (Play upload BLOKER)

Bu **çok kritik** — keystore'u kaybedersen Play Store'a güncelleme yükleyemez, uygulamayı baştan yeni paket adıyla yayınlamak zorunda kalırsın. **Yedekle.**

### 4.1 Keystore Üret

Bilgisayarında JDK kuruluysa (Android Studio kurduğun için var):

```bash
cd c:/projects/PortfoyTakip/android
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Sorulacaklar:
- **Keystore password:** Güçlü bir şifre seç (16+ karakter). NEVER UNUTMA.
- **Key password:** Aynı şifre olabilir (basitlik için).
- **First/last name:** Ad Soyadın.
- **Organizational unit:** boş geç.
- **Organization:** "sandık" veya şirket adın.
- **City:** İstanbul (veya bulunduğun yer).
- **State:** Türkiye.
- **Country code:** TR.
- "Is this correct?" → yes.

Sonuç: `android/upload-keystore.jks` dosyası oluşur.

### 4.2 key.properties Dosyası

`android/key.properties` (gitignore'da, commit edilmez):

```properties
storePassword=YUKARIDAKI_KEYSTORE_SIFRESI
keyPassword=YUKARIDAKI_KEY_SIFRESI
keyAlias=upload
storeFile=../upload-keystore.jks
```

Şablon var: `android/key.properties.example` — kopyala ve değerleri gir.

### 4.3 YEDEK AL — 3 ayrı yere

Bunlar kaybolursa uygulama "ölür". 3 ayrı yere yedek tut:

1. **Şifreli USB / harici disk** (offline yedek)
2. **Bulut storage** (Google Drive / iCloud / 1Password) — şifreli klasör içinde
3. **Fiziksel kâğıda yaz** (keystore + key alias + şifreler) ve cüzdana/kasaya koy

Yedek dosyalar:
- `upload-keystore.jks`
- `key.properties`
- Bu şifrelerin yazılı olduğu güvenli not

### 4.4 Test Et

```bash
cd c:/projects/PortfoyTakip
flutter build appbundle --release
```

Başarılıysa: `build/app/outputs/bundle/release/app-release.aab` dosyası üretildi → Play Store'a yüklenebilir.

Hata alırsan key.properties yolu yanlış olabilir; `storeFile=../upload-keystore.jks` `app/build.gradle.kts`'in olduğu dizinden bir üst dizine bakıyor demek (yani `android/upload-keystore.jks`).

---

## 5. ☁️ SUPABASE DEPLOY (hesap silme BLOKER)

Hesap silme akışı için backend tarafında 3 şey yapman gerek.

### 5.1 Supabase CLI Kur

```bash
# Windows (Scoop)
scoop install supabase

# veya manuel: https://supabase.com/docs/guides/cli/getting-started
```

### 5.2 Projeye Bağlan

```bash
cd c:/projects/PortfoyTakip
supabase login        # tarayıcı açar, login
supabase link --project-ref <SENIN_PROJECT_REF>
```

`<SENIN_PROJECT_REF>` = Supabase dashboard URL'inden `https://supabase.com/dashboard/project/XXXX` → XXXX kısmı.

### 5.3 Migration'ı Uygula

```bash
supabase db push
```

Bu komut `supabase/migrations/0007_account_deletion_log.sql` dosyasını gerçek DB'ye uygular. Tablo oluşur.

**Eğer "no schema migration" hatası alırsan:** Önce `supabase db pull` ile mevcut şemayı sync et, sonra push et. Veya Supabase Dashboard → SQL Editor'e gir, dosyanın içeriğini yapıştır, Run.

### 5.4 Edge Function Secret Set Et

```bash
# Hash salt — production'da random 64-character olmalı
supabase secrets set DELETION_HASH_SALT="$(openssl rand -hex 32)"
```

openssl yoksa: PowerShell'de `[guid]::NewGuid().ToString() + [guid]::NewGuid().ToString()` ile 64-char random üret.

### 5.5 Edge Function Deploy

```bash
supabase functions deploy delete-account
```

Output: `Function delete-account deployed successfully`.

### 5.6 Test Et

1. Test hesabı oluştur (uygulamadan).
2. Settings → Hesabımı Sil → şifre gir → onayla.
3. Supabase Dashboard → Authentication → Users: kullanıcı silinmiş olmalı.
4. Supabase Dashboard → Table Editor → `account_deletion_log`: 1 satır eklenmiş olmalı (anonim hash + email_domain).
5. Aynı e-posta ile tekrar register dene: "yeni hesap" gibi davranmalı, eski veri gelmemeli.

⚠️ **Eğer hata alırsan:** Edge Function loglarına bak: Supabase Dashboard → Edge Functions → delete-account → Logs.

---

## 6. 📱 GOOGLE PLAY CONSOLE

### 6.1 Hesap Aç

- **URL:** https://play.google.com/console
- **Maliyet:** $25 tek seferlik (lifetime).
- **Gerekli:** Google hesabı, kredi kartı, kimlik (TC kimlik için pasaport scan'i isteyebilir).
- **Süreç:** Genelde 1-2 gün içinde onaylanır.

### 6.2 Uygulama Oluştur

Play Console → Create app:
- **App name:** `Sandık: Portföy Takibi` (`store_listing/tr-TR/title.txt` ile birebir)
- **Default language:** Türkçe
- **App or game:** App
- **Free or paid:** Free
- **Declarations:** Uyguluyor mu uymuyor mu? Hepsi onayla.

### 6.3 Listing Doldur

Şu sekmeleri tamamla:
- **Main store listing:**
  - Short description (80 char): "Hisse, fon, döviz ve altın portföyünüzü kolayca takip edin."
  - Full description (4000 char): Özellikler, hedef kitle, gizlilik vurgusu (KVKK uyumlu). Sana taslak yazayım dersen söyle.
  - Icon: 512x512 PNG (mevcut launcher'ın yüksek çözünürlüklü versiyonu)
  - Feature graphic: 1024x500
  - Screenshots: minimum 2, maksimum 8 (telefon 16:9 oranlı)
- **Store settings:**
  - App category: Finance
  - Tags: portfolio, finance, tracker
  - Contact details: support email + privacy policy URL + website
- **Privacy policy:** `https://sandik.app/privacy` (sayfa hazır olmalı)
- **App content:**
  - Privacy policy URL ✓
  - Ads: No
  - Content rating: IARC questionnaire (~15 soru, ~10 dk). Finance, no violence, no gambling → muhtemelen Everyone / Mature 17+
  - Target audience: 18+ (yatırım uygulaması)
  - News app: No
  - Data safety: KVKK formundan veri envanteri kopyala
  - Government apps: No
  - Financial features: ✓ Manage personal finance / Track investments
- **Account deletion:**
  - In-app deletion: ✓ Available
  - Web URL: `https://sandik.app/data-deletion`

### 6.4 Internal Testing Track

İlk yayında **production'a değil internal test'e** yükle.

1. **Testing → Internal testing → Create new release**
2. Upload `app-release.aab`
3. Release notes (TR + EN): "İlk sürüm"
4. **Testers:** Email listesi oluştur (kendin, eşin, arkadaşların — max 100 kişi).
5. **Save → Review release → Start rollout to internal testing**
6. 2-4 saat sonra tester'lar Play Store'da app'i görebilir (özel link ile).

### 6.5 Production'a Geç

Internal testing 1-2 hafta sorunsuz çalıştıktan sonra:
- Crash rate < %1
- Negatif feedback yok
- ANR (App Not Responding) rate < %0.5

→ **Closed testing → Open testing → Production** kademeli geçiş.

İlk Production yükleme **2-7 gün** review alır (Türk app'lerinde genellikle 1-3 gün).

---

## 7. 🧪 MANUEL TEST PLANI

Yayından önce mutlaka şu akışları **gerçek emülatörde** test et:

### 7.1 Kritik Akışlar
- [ ] Yeni hesap aç (Register) — 3 onay kutusu zorunlu çalışıyor mu?
- [ ] Login → ana ekran → varlık ekle → fiyat çek → performans grafiği
- [ ] Logout → Login → aynı veri geliyor mu
- [ ] Ortak davet üret → ikinci hesapla kabul et → her iki tarafta görünüyor mu
- [ ] Push bildirim geliyor mu (gerçek cihazda — emülatörde FCM token alır ama bildirim deliveri için Firebase config doğru olmalı)
- [ ] **Hesap silme:** test hesabı → Settings → Hesabımı Sil → şifre → 30 sn içinde tamamlandı mı? Supabase'de gerçekten silindi mi?

### 7.2 Hata Senaryoları
- [ ] İnternet kapalıyken Login → "İnternet bağlantını kontrol et" mesajı çıkıyor mu (raw SocketException değil)
- [ ] Yanlış şifre ile login → "E-posta veya şifre hatalı"
- [ ] Yanlış şifre ile hesap sil → "Şifre hatalı"
- [ ] Zayıf internette refreshPrices → 15 sn sonra timeout, donmuyor
- [ ] Boş portföy → boş state ekranı, crash yok
- [ ] Yeni kayıt olunca onay kutusunu işaretlemeden submit → 3 farklı kırmızı uyarı çıkıyor mu

### 7.3 UI Testleri
- [ ] Splash → loading → ana ekran geçişleri akıcı mı
- [ ] Pie chart'a tıkla → kategori filtresi çalışıyor mu
- [ ] Dark theme her ekranda tutarlı mı
- [ ] Tüm modal/dialog'lar geri tuşuyla kapanıyor mu

### 7.4 Release Build Testi

Debug build her zaman çalışır, asıl test **release** build:

```bash
flutter build apk --release
# APK'yı cihaza yükle
adb install build/app/outputs/flutter-apk/app-release.apk
```

ProGuard/R8 sonrası kırılan bir şey varsa burada görünür (Reflection kullanan paketler vs.). Hata olursa `proguard-rules.pro`'ya keep rule ekleriz.

---

## 📋 ÖZET — Şu sıra ile ilerle

**Bu hafta:**
1. Domain al + email kur (1.1, 1.2) → ~1 saat
2. Tüzel kişilik kararı + avukatla 1 saat konuş (2.1, 2.3) → 1-2 gün
3. Hukuki placeholder'ları doldur (2.2) → 2 saat
4. Release keystore üret + yedekle (4.1-4.3) → 1 saat

**Önümüzdeki hafta:**
5. Web sitesi setup (3) → 1 gün
6. Supabase deploy (5) → 1 saat
7. Play Console hesap + listing (6.1-6.3) → 1 gün
8. Manuel test (7) → 4 saat

**3. hafta:**
9. Internal testing → tester feedback'i topla
10. Crashlytics ekleyelim mi karar ver (önerim: evet)
11. Production rollout

---

## ❓ ŞU AN BANA SORMAN GEREKENLER

Bir karara varman gerekirse aşağıdakileri net söyle, ona göre kod ve dokümanları güncelleyeyim:

1. **Domain:** `sandik.app` mı, başka bir şey mi? (URL'leri kodda + 9 hukuki belgede tek seferde değiştiririm)
2. **İletişim e-posta:** Hangi adres? (Belgelerde 3-4 yerde geçiyor)
3. **Tüzel kişilik:** Bireysel mi, şirket mi? (KVKK Aydınlatma Metni'nin tonu değişir)
4. **Faz 1'den kalan UI işleri:** Şu an sıradakiler — hangisinden devam edelim:
   - **Adaptive icon** (~3 saat) — Android 8+ launcher'da daha güzel görünür
   - **Onboarding** (yeni kullanıcıya 3-step tutorial) (~2 gün)
   - **"Verilerimi İndir" JSON export** (GDPR portability hakkı, ~1 gün)
   - **Firebase Crashlytics** entegrasyonu (~4 saat)
   - **Settings'e tema toggle / bildirim toggle** (~3 saat)

Şimdi söyleyebileceğin en yararlı şey: **1, 2, 3 numaralı kararlar.** Onlar olunca placeholder'ları silip tek bir commit ile her şeyi gerçek değerlerle güncellerim.
