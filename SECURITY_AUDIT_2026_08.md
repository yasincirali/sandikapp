# Güvenlik İncelemesi — 11 Ağustos 2026

Kapsam: SQL injection, rate limiting ve genel güvenlik yüzeyi.
İnceleme alanı: `lib/` (Flutter istemci), `supabase/migrations/`,
`supabase/functions/` (Edge Functions), platform yapılandırması.

Bu inceleme `SECURITY_AND_UX_AUDIT.md` (A1–A7, B5, C1–C3, D1–D2)
bulgularının **üzerine** yapıldı; o turdaki düzeltmeler yerinde ve
etkili durumda.

---

## Yönetici özeti

Uygulamanın güvenlik temeli sağlam. Klasik SQL injection **yok** ve
yapısal olarak da mümkün değil (aşağıda gerekçe). Asıl bulgu rate
limiting'de: koruma güvenlik sınırının yanlış tarafındaydı.

| # | Bulgu | Önem | Durum |
|---|-------|------|-------|
| S1 | Davet kodu rate limit'i yalnızca istemcide | **Kritik** | Düzeltildi |
| S2 | `p_top_n` sınırsız → k-anonymity bypass | **Yüksek** | Düzeltildi |
| S3 | Edge Function'larda PostgREST `.or()` filtre enjeksiyonu | Orta (kırılganlık) | Düzeltildi |
| S4 | RPC'lerde `p_period_days` doğrulanmıyor | Orta | Düzeltildi |
| S5 | Snapshot tablolarında girdi doğrulaması yok | Orta | Düzeltildi |
| S6 | Snapshot INSERT sınırsız → depolama/DoS | Düşük | Düzeltildi |

---

## SQL Injection: bulunmadı (yapısal gerekçe)

Bu, "arattım, bir şey çıkmadı" değil — mimari olarak yüzey yok:

1. **İstemcide ham SQL yok.** Flutter tarafı yerelde `sqflite`,
   uzakta PostgREST kullanıyor. Tüm sorgular parametrik query
   builder üzerinden (`.eq()`, `.in()`, `.select()`).
2. **Dinamik SQL yok.** Tüm migration'larda `EXECUTE`, `format()`,
   `quote_ident()` ile string birleştirilerek kurulan tek bir sorgu
   yok. Grep ile doğrulandı — yalnızca `GRANT EXECUTE ON FUNCTION`
   eşleşmeleri var (bunlar DDL, dinamik SQL değil).
3. **RPC parametreleri tiplendirilmiş.** Tüm RPC'ler `INTEGER`
   alıyor; plpgsql içinde değişken olarak kullanılıyor, sorgu
   metnine gömülmüyor. `INTEGER` bir parametreye string enjekte
   edilemez.
4. **SECURITY DEFINER fonksiyonlarının hepsinde `SET search_path`
   açık.** `pg_temp` üzerinden fonksiyon gölgeleme (privilege
   escalation) kapalı.

**En yakın akraba bulgu S3'tür**: SQL değil ama benzer sınıftan bir
enjeksiyon — PostgREST filtre ifadesine değer gömme.

---

## S1 — Rate limit yalnızca istemcideydi (Kritik)

**Nerede:** `lib/services/auth_service.dart` `_checkRateLimit`

**Sorun:** Davet kodu deneme limiti (10 dakikada 5) tamamen
`SharedPreferences` içinde tutuluyordu. Bu bir güvenlik sınırı değil:

- Uygulama verisini temizlemek sayacı sıfırlıyordu,
- Saldırgan uygulamayı hiç çalıştırmadan Edge Function'a doğrudan
  `curl` ile istek atabiliyordu — sayaç o kod yolundan hiç geçmiyor,
- Sunucu tarafında **hiçbir** deneme sınırı yoktu.

**Etki:** Davet kodu 32^10 ≈ 1.1e15 kombinasyon ile tek başına güçlü.
Ancak aktif kod havuzu küçük (kodlar 24 saat geçerli, aynı anda az
sayıda açık davet var) ve sınırsız deneme hakkı varken saldırgan
**tek tek kod tahmin etmek yerine havuzu tarayabilir**. Başarılı
tahmin, saldırganı kurbanın ortağı yapar → portföy ROI'si ve varlık
dağılımı görünür hale gelir.

**Düzeltme:**
- `migrations/0028_server_side_rate_limit.sql` — sayaç veritabanına
  taşındı (`rate_limit_attempts`). Tablo RLS + FORCE RLS ile korunuyor
  ve **hiç policy tanımlı değil**, dolayısıyla `anon`/`authenticated`
  hiçbir satıra erişemez; yalnızca service-role okur/yazar.
- `check_and_record_rate_limit` kontrolü ve kaydı **tek çağrıda**
  yapıyor (TOCTOU yarışı kapalı).
- Limit aşıldığında **yeni kayıt eklenmiyor** — aksi halde saldırgan
  denemeye devam ederek pencereyi süresiz uzatabilir, meşru kullanıcı
  kalıcı kilitlenirdi.
- `redeem-invite-code` bu kontrolü **kod aramasından önce** çağırıyor.
- Sayaç erişilemezse **fail-closed** (503) — brute-force'a açık
  kalmaktansa akış durur.
- İstemci sayacı silinmedi ama rolü yorumda netleştirildi: yalnızca
  UX (gereksiz ağ isteğini önler), güvenlik sınırı değil.

---

## S2 — k-anonymity bypass (Yüksek)

**Nerede:** `get_top_gainers_allocation` (migration 0014)

**Sorun:** k=20 kontrolü "havuzda en az 20 kişi var mı?" sorusunu
yanıtlıyordu ama **kaç satır döndüğünü** sınırlamıyordu. `p_top_n`
doğrudan `LIMIT`'e gidiyordu:

- `p_top_n = 1` → tek bir kullanıcının ROI'si + tam varlık dağılımı
  izole edilir. k-anonymity'nin engellemek istediği şey tam olarak
  budur; "20 kişi var" demek, o 20 kişiden birini tek başına
  göstermeyi meşrulaştırmaz.
- `p_top_n = 100000` → "top-N" agregatı fiilen tüm havuzun dökümüne
  dönüşür. `user_id` dönmese bile `(roi_pct, allocation)` çiftleri
  zaman içinde izlenerek kullanıcılar ayrıştırılabilir.

**Düzeltme:** `p_top_n` sunucuda `[3, 10]` aralığına clamp edildi.
İstemcinin geçtiği değere güvenilmiyor.

---

## S3 — PostgREST filtre enjeksiyonu (Orta — kırılganlık)

**Nerede:** `redeem-invite-code/index.ts`, `accept-invite/index.ts`

**Sorun:** Partnership kontrolü `.or()` içine şablon dizesiyle değer
gömüyordu:

```ts
.or(`and(user_id_1.eq.${user.id},user_id_2.eq.${invite.from_user_id}),...`)
```

`.or()` argümanı PostgREST tarafından bir **filtre ifadesi** olarak
ayrıştırılır. SQL değil, ama yine de bir dil: virgül/parantez içeren
bir değer ifadeyi yeniden yazabilir.

**Gerçekçi değerlendirme:** Bugün sömürülebilir **değil** — her iki
değer de Supabase Auth'tan gelen doğrulanmış UUID'ler. Bu bir açık
değil, kırılgan bir kalıp: değerlerin kaynağı değiştiği ilk gün
sessizce açığa dönüşür ve o an fark edilmez.

**Düzeltme:** Enjeksiyonun yapısal olarak mümkün olmadığı parametrik
forma geçildi — `.in()` ile iki taraf verilip eşleşme kodda süzülüyor.

---

## S4/S5/S6 — Girdi doğrulama ve kaynak sınırları

**S4:** RPC'ler `p_period_days` değerini doğrulamıyordu. Tabloda
`CHECK (period_days IN (7,30,365))` olduğu için bugün sahte periyot
yazılamıyor; yine de derinlemesine savunma olarak RPC'lere de
whitelist eklendi (ileride yeni bir periyot eklenirse havuzun
istemeden bölünüp k eşiğinin altına düşmesini engeller).

**S5:** `user_roi_snapshots.roi_pct` doğrudan istemciden geliyordu ve
RLS yalnızca `user_id = auth.uid()` kontrolü yapıyordu — **değeri**
denetleyen hiçbir şey yoktu. Kötü niyetli bir istemci `roi_pct`'yi
şişirip leaderboard'un tepesine yerleşebilir, `top_gainers`
agregatını zehirleyebilirdi. CHECK constraint eklendi
(ROI ∈ [-100, 100000], `type_count` ≤ 50, `allocation_pct` bir JSON
nesnesi ve ≤ 50 anahtar).

**S6:** Snapshot INSERT'i sınırsızdı; bir kullanıcı milyonlarca satır
yazarak depolamayı şişirebilir ve `DISTINCT ON` sorgularını
yavaşlatabilirdi. Kullanıcı+periyot başına dakikada 1 snapshot
trigger'ı eklendi.

---

## İncelenip temiz bulunanlar

- **RLS kapsamı:** Tüm tablolarda RLS açık — kapsam dışı tablo yok.
- **Edge Function yetkilendirme:** Hepsi JWT doğruluyor; `accept`
  yalnızca davet sahibine, `reject` sahip veya hedefe açık.
  `send-partner-invite-push` çağıranın gerçekten davet hedefi
  olduğunu kontrol ediyor. IDOR bulunmadı.
- **Hesap silme:** JWT'ye ek olarak **taze parola** doğrulaması
  istiyor — çalıntı cihaz/aktif oturum senaryosu kapalı.
- **Sır yönetimi:** `service_role` anahtarı istemci kodunda yok.
  Supabase URL/anon key `String.fromEnvironment` ile derleme
  zamanında geliyor. `GoogleService-Info.plist` içindeki API anahtarı
  Firebase istemci tanımlayıcısıdır — sır değil, ifşası beklenen bir
  değerdir.
- **Davet kodu entropisi:** `Random.secure()` + 32 karakterlik
  alfabe, 10 karakter. Kriptografik olarak yeterli.
- **Davet payload'ı:** A7 düzeltmesinden sonra PII taşımıyor.

---

## Doğrulama durumu

| Ne | Nasıl | Sonuç |
|----|-------|-------|
| Dart derleme | `flutter analyze` | Temiz (5 önceden var olan deprecation info'su) |
| Test paketi | `flutter test` | 489/489 geçti |
| Edge Function tipleri | `deno check` | Her iki fonksiyon da temiz |
| SQL migration'ları | Uzak veritabanında koşuldu + davranış testi | Geçti (aşağıda) |

### Veritabanı doğrulaması (11 Ağustos 2026, uzak proje)

`0028` ve `0029` uygulandı ve **davranışsal olarak** test edildi —
nesnelerin var olması yeterli sayılmadı, gerçekten engelleyip
engellemedikleri sorgulandı.

| Test | Beklenen | Sonuç |
|------|----------|-------|
| Rate limit 1–3. deneme (limit=3) | `allowed=true` | ✅ |
| Rate limit 4. deneme | `allowed=false`, `retry_after=600` | ✅ |
| Limit aşıldığında yeni kayıt eklenmemesi | 3 kayıt kalmalı | ✅ 3 |
| `clear_rate_limit` | 0 kayıt | ✅ 0 |
| `roi_pct = 999999` INSERT | `check_violation` | ✅ reddedildi |
| `roi_pct = 12.5` INSERT | kabul | ✅ kabul |
| Aynı dakikada 2. snapshot | `snapshot_throttled` | ✅ engellendi |
| `allocation_pct = '[1,2,3]'` (dizi) | `check_violation` | ✅ reddedildi |
| `p_top_n` clamp: 1 / 100000 / NULL | 3 / 10 / 5 | ✅ |
| `p_period_days = 9999` | 0 satır | ✅ 0 |
| `authenticated` → rate limit RPC'leri | EXECUTE yok | ✅ false |
| `authenticated` / `anon` → `rate_limit_attempts` | SELECT yok | ✅ false |
| `rate_limit_attempts` RLS + FORCE | true/true, 0 policy | ✅ |
| `purge-rate-limit-attempts` cron | kurulu | ✅ |

Test satırları (`TEST-SUBJ-1`, `SEQ-TEST`, `SEQ2` ve geçici snapshot
kayıtları) temizlendi.

**Not — yöntem tuzağı:** İlk rate limit testi `generate_series` içinde
skaler alt-sorgu kullanıyordu; Postgres bunu her satır için yeniden
değerlendirmediği için 6 çağrının hepsi `true` göründü. Bu fonksiyonun
değil test sorgusunun hatasıydı; ayrı ifadelerle tekrarlandığında limit
doğru uygulandı. Rate limit testlerinde çağrıların **gerçekten ayrı
ayrı** yürüdüğü doğrulanmalı.

### Edge Function deploy (11 Ağustos 2026)

Doğru sırayla yapıldı — önce migration, sonra fonksiyonlar:

| Fonksiyon | Önce | Sonra | Durum |
|-----------|------|-------|-------|
| `redeem-invite-code` | v2 | **v3** | ACTIVE, `verify_jwt=true` |
| `accept-invite` | v3 | **v4** | ACTIVE, `verify_jwt=true` |

Deploy sonrası doğrulama:

| Test | Beklenen | Sonuç |
|------|----------|-------|
| Auth header yok | 401 | ✅ 401 |
| Geçersiz JWT | 401 | ✅ 401 (`UNAUTHORIZED_INVALID_JWT_FORMAT`) |
| `OPTIONS` (CORS preflight) | 200 | ✅ 200 |
| `service_role` → rate limit RPC'leri | EXECUTE var | ✅ true |
| `service_role` → `rate_limit_attempts` INSERT/DELETE | var | ✅ true |
| RPC imzaları ↔ fonksiyonun gönderdiği parametreler | eşleşme | ✅ birebir |

`service_role` izinleri doğrulandığı için **fail-closed (503) riski
yok** — fonksiyon RPC'ye erişebiliyor.

**S1 artık sunucuda etkin.**

---

## Deploy sonrası bulunan hata: kod girişi (S7 — güvenlik dışı)

**Belirti:** "Ortaklık kodu girdirmiyor, kodu format hatası gibi
gösteriyor."

**Bu deploy'dan kaynaklanmıyor.** Doğrulandı: doğrulama regex'ine
dokunulmadı, `profile_screen.dart` bu turda hiç değiştirilmemişti ve
`rate_limit_attempts` tablosu boştu (yani 429 değil, istemci tarafı
hatası). Önceden var olan bir UX kusuru.

**Kök neden:** Kod giriş alanında hiçbir `inputFormatters` yoktu.
Tireyi kullanıcının kendisinin yazması bekleniyordu; yazmadığında
istemcideki `^([A-Z2-9]{5}-[A-Z2-9]{5})$` kontrolü **doğru kodu**
reddedip "Geçersiz kod formatı" gösteriyordu. Boşluk, küçük harf ve
alfabe dışı karakterler de aynı sonucu veriyordu.

**Düzeltme:** `lib/utils/partner_code_formatter.dart` —
tire otomatik eklenir, küçük harf büyütülür, alfabe dışı karakterler
süzülür, 10 karakterle sınırlanır, imleç ortadan düzenlemede sona
atlamaz. `_submitCode` de aynı normalizasyondan geçiriliyor
(yapıştırma/otomatik doldurma gibi formatter'ı atlayan yollar için).

**Önemli ayrıntı:** Üretim alfabesi (`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`)
karışabilecek `0`, `1`, `I`, `O` karakterlerini **içermez** — yani
geçerli bir kod bunları asla taşımaz. Formatter bunları düşürür,
tahmini düzeltme (`0→O` gibi) yapmaz: alfabede iki karşılık da
bulunmadığından tahmin sessizce yanlış kod üretirdi.

Test: `test/partner_code_format_test.dart` (12 test).
Bu testler yazılırken formatter'da gerçek bir hata yakalandı —
`StringBuffer.length` karakter sayacı olarak kullanılınca 10. karakter
düşüyordu.

---

## S8 — Rate limit meşru kullanıcıyı kilitledi (sahada gözlendi)

**Belirti:** Gerçek kullanıcı davet kodu girerken 10 dakika bekletildi.

**Bu, korumanın çalıştığının kanıtı değil — bir tasarım kusuruydu.**
0028'deki `check_and_record_rate_limit` kontrol ile kaydı tek çağrıda
birleştiriyordu (TOCTOU için doğru) ama Edge Function bu çağrıyı
**daveti aramadan önce** yapıyordu. Sonuç: isteğin sonucu ne olursa
olsun sayaç artıyordu.

| Durum | Brute-force mı? | Eskiden sayılıyordu | Şimdi |
|-------|-----------------|---------------------|-------|
| Kod bulunamadı | **Evet** | ✓ | ✓ sayılır |
| Kendi kodunu girdi | Hayır | ✓ (hatalı) | ✗ |
| Zaten ortak | Hayır | ✓ (hatalı) | ✗ |
| Zaten talep edilmiş | Hayır | ✓ (hatalı) | ✗ |
| **Başarılı eşleşme** | Hayır | ✓ (hatalı) | ✗ |

Kullanıcının kilitlenmesini hızlandıran ikinci etken S7'ydi: kod giriş
alanında biçimlendirme olmadığı için "geçersiz format" hatasını aşmaya
çalışan kullanıcı sayacı boşa tüketiyordu.

**Düzeltme** (`0030_split_rate_limit_check.sql`): kontrol ve kayıt
ayrıştırıldı — `peek_rate_limit` yalnız okur, `record_rate_limit_attempt`
yalnız yazar. Edge Function önce peek eder, sayacı **yalnızca kod
bulunamadığında** artırır. Brute-force zaten tam olarak bu yoldan
ilerler; diğer dallarda saldırganın elinde geçerli bir kod vardır,
dolayısıyla saymanın koruyucu değeri yoktur.

**Kabul edilen ödünç:** Kontrol ile kayıt arasına bir sorgu girdiği
için eşzamanlı istekler limiti birkaç deneme aşabilir. Bu bilinçli:
rate limit'in amacı binlerce denemeyi kesmek, tam 5'te durmak değil.
Yanlış kilitlenen meşru kullanıcının maliyeti daha yüksek.

Doğrulama (uzak veritabanı):

| Test | Sonuç |
|------|-------|
| 10× `peek_rate_limit` → sayaç | ✅ 0 kayıt (artmıyor) |
| 5 gerçek deneme sonrası peek | ✅ engellendi |
| `clear_rate_limit` sonrası | ✅ açıldı |
| `service_role` EXECUTE (peek/record) | ✅ true |
| `authenticated` EXECUTE (peek) | ✅ false |

Deploy: `redeem-invite-code` **v4** ACTIVE.
Etkilenen kullanıcının sayacı elle temizlendi (`clear_rate_limit`).

### S8b — İstemci aynı iki kusuru tekrarlıyordu

Sunucu düzeltildikten sonra istemcide iki artık sorun kaldı:

**1. Sabit "10 dakika" mesajı.** Yerel sayaç (`_checkRateLimit`)
sunucuya hiç gitmeden kendi sabit metnini fırlatıyordu. Kullanıcı 9
dakika beklemiş olsa bile "10 dakika sonra tekrar deneyin" görüyor,
baştan beklemesi gerektiğini sanıyordu. Artık kalan süre **en eski
denemenin pencereden düşmesine kalan zamana** göre hesaplanıyor
("1 dakika", "45 saniye"). Sunucudan gelen `retry_after_seconds` ile
aynı biçimlendiriciyi paylaşıyor.

**2. Yerel sayaç da her hatayı sayıyordu.** S8'de sunucuda düzeltilen
ayrım istemcide yoktu: `_recordAttempt` her başarısızlıkta çağrılıyordu.
Yani sunucu saymasa bile istemci kullanıcıyı kilitleyebiliyordu.
Artık `_recordIfFailedGuess` yalnızca `invite_not_found_or_expired`
kodunu sayıyor — sunucudaki `recordFailedGuess` ile birebir aynı küme.

**3. Diyalog başlığı.** Bekleme durumu "Bir sorun oluştu" başlıklı
hata diyaloğunda çıkıyordu. Rate limit bir arıza değil; artık
"Biraz Bekle" başlıklı bilgi diyaloğunda ve kalan süre mesajın içinde.

Test: `test/rate_limit_message_test.dart` — kalan süre hesabı (en eski
denemeye göre, 9 dk beklendiyse 1 dk kalır) ve hangi hata kodlarının
sayıldığı.

### S8c — Kalan süre ekranda kalıcı olarak gösteriliyor

Kalan süre yalnızca engellendiği an diyalogda görünüyordu; kullanıcı
diyaloğu kapatınca ne kadar bekleyeceğini unutuyor ve tekrar deneyip
yeni bir ret alıyordu.

Eklenenler:
- `RateLimitedException` — mesajın yanında **kalan saniyeyi** de taşır.
  Yalnızca metin dönseydi ekran, süre dolduğunda kendini açamazdı.
  Hem yerel sayaç hem sunucudan gelen 429 bu türü fırlatır.
- Kod alanının altında **canlı geri sayım** ("Çok fazla deneme —
  4:05 sonra tekrar deneyebilirsin"), butonda da "Bekle — 4:05".
- Kilitliyken alan ve buton **devre dışı** — kullanıcı boşuna yazıp
  yeni bir ret almaz.
- Süre dolunca alan **kendiliğinden açılır**; ekrandan çıkıp girmek
  gerekmez.
- `partnerCodeLockRemainingSeconds` — ekran açılışında kilit önceki
  oturumdan kalmışsa geri sayım hemen kurulur.
- Timer `dispose`'da iptal edilir.

### S8d — Dialog geri sayımı canlı + iki UI hatası

**1. Dialog donuyordu.** `showSandikDialog` sabit `String message`
alıyordu; kullanıcı dialogu okurken süre eskiyor, "1:14 dakika" olduğu
yerde kalıyordu. Eklenen `liveMessage` callback'i saniyede bir
tazeleniyor ve `null` döndüğünde (süre bitti) dialog **kendini
kapatıyor**. `liveMessage` verilmeyen tüm mevcut çağrılar eskisi gibi
çalışır — davranış değişmedi.

**2. Saat ikonu tofu (boş kutu) çıkıyordu.** Kod alanının altındaki
geri sayımda `CupertinoIcons.clock` kullanmıştım; proje Material ikon
fontunu paketliyor, Cupertino fontu yok. `Icons.schedule_rounded`
ile değiştirildi (projenin başka yerlerinde kullanılan kalıp).

**3. Örnek kod geçersizdi.** Ekranda "örn: ABCDE-12345" yazıyordu ama
`1` üretim alfabesinde **yok** — bu kod hiç üretilemez. Kullanıcı
örneği deneyip "kod bulunamadı" alıyor ve boşuna rate limit sayacı
tüketiyordu. `KRHNJ-8P2SW` ile değiştirildi (alfabeden doğrulandı).

Test: `test/rate_limit_dialog_live_test.dart` — dialogun saniyede bir
tazelendiği, süre bitince kapandığı ve `liveMessage`'sız çağrıların
sabit kaldığı.

---

### Kalan: gerçek kullanıcı oturumuyla uçtan uca test

Yukarıdaki testler JWT doğrulamasında durduğu için rate limit koduna
ulaşmıyor; anon key CI secret'ında olduğundan bu makineden gerçek
oturum JWT'si üretilemedi. Uygulamadan yapılması gereken son kontrol:

1. Davet akışı uçtan uca çalışıyor mu (kod üret → gir → onayla)?
2. Arka arkaya 6 **hatalı** kod girildiğinde 6.'sı
   "Çok fazla başarısız deneme… X dakika sonra tekrar dene" mesajını
   veriyor mu? (Sunucudan 429 + `retry_after_seconds`.)
3. Başarılı bir eşleşmeden sonra sayaç sıfırlanıyor mu (arka arkaya
   iki ortaklık kurulabilmeli)?

Bu akış bozulursa geri dönüş: `supabase functions deploy` ile önceki
sürüm yeniden yayınlanır; migration'lar geri alınmaz (yalnızca
kısıt/limit ekliyorlar, veri şemasını bozmuyorlar).
