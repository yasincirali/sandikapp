# Supabase taşıması: Tokyo → Frankfurt

**Karar:** 2026-09-27, kullanıcı. **Neden:** Türkiye'den Tokyo'ya her istek
~250–300 ms, Frankfurt'a ~40–60 ms; uygulama açılışta ardışık sorgular yapıyor.
Supabase bölge değiştirmiyor → yeni proje + tam taşıma.

| | Eski | Yeni |
|---|---|---|
| Ref | `ybdbzouzhzwthjgwlbmk` | `ynwymnpdiwudrlxfrmuo` |
| Bölge | `ap-northeast-1` (Tokyo) | `eu-central-1` (Frankfurt) |
| Ad | yasincirali's Project | sandikapp-eu |
| Postgres | 17.6.1.105 | 17.6.1.166 |

Adımlar **[SEN]** (panel/secret — auto mode secret yazmayı ve canlı DB'ye
bağlanmayı engelliyor) ve **[CLAUDE]** diye işaretli. **Sıra önemli**; her
fazın sonunda "geri dönüş" satırı var.

---

## AÇILIŞ YOL HARİTASI (2026-09-27) — Frankfurt nasıl devreye girer

**Bugünkü durum:** Frankfurt hazır ama **kapalı**: şema, secret, 15 fonksiyon,
Auth + Türkçe şablon + Gmail SMTP uçtan uca denendi; 26 cron `active=false`;
kullanıcı verisi YOK. Uygulama sunucu adresini **derlemede** alıyor
(`--dart-define SUPABASE_URL/ANON_KEY` ← GitHub secret) — telefonlardaki her
sürüm Tokyo'ya bağlı ve güncellenene kadar öyle kalır.

### Karar: iki sürüm değil, tek "köprü sürümü" + Remote Config anahtarı

İlk plan (aşağıda Faz 4'ün eski hâli) geçişi Frankfurt adresli İKİNCİ bir
mağaza sürümüne bağlıyordu: mağaza onayı geçiş gecesinin kritik yolundaydı,
kullanıcı iki kez güncelliyordu, geri dönüş yine mağaza istiyordu. Yerine:

**1.1.7 "köprü sürümü" İKİ yapılandırmayı da taşır** (Tokyo + Frankfurt URL ve
anon anahtarı; anon anahtarı zaten istemcide açık duran değerdir). Hangisine
bağlanacağını Remote Config `sunucu` anahtarı (`tokyo` | `frankfurt`) söyler.

| | İki sürüm (eski plan) | Köprü sürümü (seçilen) |
|---|---|---|
| Geçiş anı | Mağaza onayı + elle yayın | Remote Config'te tek anahtar |
| Kullanıcı güncellemesi | 2 | 1 |
| Geri dönüş | Yeni mağaza sürümü | Anahtarı geri çevir |
| Prova | Ayrı test build'i | RC koşuluyla YALNIZ senin cihazın |

**Köprü sürümünün kuralları (tasarım şartları — K1'de kodlanır):**
1. **Karar açılışta, Supabase başlamadan verilir.** Remote Config kısa zaman
   aşımlı (≈3 sn) çekilir; ağ yoksa son etkin değer kullanılır. Çalışırken
   değişiklik bir sonraki soğuk açılışta uygulanır (Supabase çalışırken
   yeniden başlatılmaz).
2. **Sunucu değişince yerel durum sıfırlanır:** oturum (JWT eski projenin —
   yeni projede geçersiz), kullanıcıya özel önbellekler
   (`kullaniciyaOzelTercihler`, `IntradaySeriesCache`, haftalık özet
   önbelleği) silinir → giriş ekranı. Kullanıcı bir kez yeniden giriş yapar
   (şifresi aynı; `auth.users` özetleriyle taşınır).
3. **Zorunlu güncelleme kapısı** (`min_build_android` / `min_build_ios`):
   köprü öncesi sürümler Tokyo'ya kilitli; geçişte onları "Güncelle"
   ekranında tutar.
4. **Rıza metni sunucuyu izler:** `frankfurt` iken "Almanya (AB)", `tokyo`
   iken gerçeği (Japonya) — bugünkü "ABD" iki durumda da yanlış
   (`register_screen.dart:402`, `legal_doc_screen.dart:152`).
5. **Varsayılan `tokyo`.** RC hiç okunamazsa (ilk kurulum, çevrimdışı) geçiş
   sonrasında yanlış sunucuya düşmemek için K4'te varsayılan da değişir:
   RC'nin *uygulama içi varsayılanı* köprü sürümünde `tokyo`, geçişten sonraki
   ilk normal sürümde `frankfurt` derlenir.

### K1 — yapılanlar (2026-09-27)

- `lib/services/sunucu_secimi.dart`: saf `sunucuSec` / `guncellemeGerekliMi` +
  servis. Karar açılışta RC'nin DİSKTEKİ değeriyle (ağ beklenmez); fetch ve
  **gerçek zamanlı dinleyici** (`onConfigUpdated`) farklı sunucu görürse
  `yenidenBaslatGerekli`. Yazım hatası / EU'suz derleme → birincil.
- `lib/widgets/sunucu_kapisi.dart`: "Güncelleme gerekli" (öncelikli) ve "Sandık
  yenilendi — kapatıp aç" tam ekranları; uygulamanın ÖNÜNE geçer.
- RC varsayılanları: `sunucu=tokyo`, `min_build_android=0`, `min_build_ios=0`.
- Oturum anahtarı zaten proje ref'inden türüyordu → Frankfurt'ta Tokyo oturumu
  okunmaz. Tercih/önbellekler UUID'ye bağlı → taşımada geçerli kalır.
- Rıza metni (kayıt kutusu + uygulama içi gizlilik/KVKK) verinin gerçek ülkesini
  söyler: Tokyo → Japonya, Frankfurt → Almanya (AB). Web'deki eşleri Faz 5.
- CI: `SUPABASE_URL_EU`/`SUPABASE_ANON_KEY_EU` define'ları (3 iş akışı);
  Android `--build-number=100+run` (versionCode artık artıyor).
- Doğrulama: 3080 test; 5554'te (Tokyo, gerçek hesap) bayraksız → Tokyo'da
  kaldı, oturum korundu, kapı yok.

**K1 uçtan uca bayrak denemesi (2026-09-27, emülatör 5554, gerçek hesap):**
Tokyo → `frankfurt`: gerçek zamanlı yol 2,5 dk'da ULAŞMADI; soğuk açılış
yolu kapıyı ~5 sn'de getirdi → yeniden açılış Frankfurt'ta giriş ekranı →
aynı şifreyle giriş, ortak seçici yok (Frankfurt). Frankfurt → `tokyo`:
gerçek zamanlı yol BU SEFER çalıştı (ön planda, yeniden başlatmasız);
dönüşte Tokyo oturumu korunmuştu, giriş istenmedi. Bulunan iki açık
düzeltildi: `refresh()` hiç çağrılmıyordu (ön plana dönüş + prod aralığı
1 sa → 15 dk, 2108c2c); Android "Uygulamayı kapat" `SystemNavigator.pop()`
Dart'ı canlı bırakıp aynı kapıyı geri getirdi → `exit(0)` (bd0330c).
Gerçek zamanlı yolun ilk denemede neden gelmediği bilinmiyor → K3'te
GERÇEK cihazda ölçülecek; geçiş ona dayanmıyor (soğuk açılış + 15 dk).
Firebase Console: `sunucu=tokyo`, `min_build_*=0` tanımlı ✅; GitHub
secret'ları `SUPABASE_URL_EU`/`SUPABASE_ANON_KEY_EU` ✅.

**K1'in kalanı [SEN] (eski not):** GitHub secret'ları `SUPABASE_URL_EU` +
`SUPABASE_ANON_KEY_EU`; Firebase Console'da `sunucu=tokyo`, `min_build_*=0`
ile anahtarları AÇIKÇA tanımla; uçtan uca bayrak denemesi (aşağıda K1 testi).

### Kilometre taşları

| # | Ne | Kim | Süre | Geçiş şartı (go / no-go) |
|---|---|---|---|---|
| **K0** | Frankfurt hazır, cron kapalı | — | ✅ 2026-09-27 | — |
| **K1** ✅ kod (2026-09-27) | Köprü sürümü kodu: çift sunucu seçimi + zorunlu güncelleme kapısı + Android build numarası + rıza metni (+ haftalık şerit hatası, TECHNICAL_DEBT) | CLAUDE | 2–3 gün | Tam test paketi yeşil; emülatörde RC override ile **Tokyo → Frankfurt → Tokyo** gidiş-dönüş: her yönde temiz giriş ekranı, eski kullanıcının önbelleği sızmıyor |
| **K2** | 1.1.7 yayını: App Store + Play (kapalı test güncellemesi, sonra üretim). RC `sunucu=tokyo` | SEN (+CLAUDE CI) | onay 1–3 gün + yayılma ~7 gün | Analytics'te 1.1.7 payı ≥ %90 **veya** 7 gün; çökmesiz oturum ≥ %99 |
| **K3** | Prova: veri kopyası → Frankfurt; RC koşulu (kullanıcı özelliği / uygulama örneği) ile **yalnız senin cihazın** `frankfurt`; kendi hesabınla gerçek uygulamada gez | SEN + CLAUDE | 1 gün | Rakamlar Tokyo ile birebir (toplam, 1A köprüsü, dağılım); giriş, varlık ekle/sil, alarm, push (`push_test_trigger`) çalışıyor. Sonra Frankfurt boşaltılır |
| **K4** | Geçiş gecesi (runbook aşağıda) | SEN + CLAUDE | ~1 saat, hafta sonu 02:00–04:00 | Duman testi yeşil; 24 saat içinde geri dönüş penceresi |
| **K5** | Temizlik: GitHub secret'ları → Frankfurt, varsayılan `frankfurt` derlenir, hukuki metinler (iki bölge), **Tokyo SİLİNMEZ → yedek** (aşağıda) | SEN + CLAUDE | 2 hafta | — |

Toplam ≈ 2 hafta; **geçiş gecesinin kritik yolunda mağaza yok.** Android
kapalı testin 14 günüyle örtüşür — testçiler köprü sürümünü güncelleme olarak alır.

### K4 — geçiş gecesi runbook'u

1. **[SEN] Tokyo cron'larını durdur** (Tokyo SQL Editor):
   `select cron.alter_job(job_id := jobid, active := false) from cron.job;`
2. **[SEN] Tokyo'yu istemcilere kapat** — köprü öncesi sürümler ve RC'yi henüz
   çekmemiş istemciler Tokyo'ya veri yazmasın (yazılan kaybolur):
   `python tool/tasima/veri_tasima.py tokyo-kapat --onay ybdbzouzhzwthjgwlbmk`
   Araç yetkiyi geri alır ve **gerçekten kapandığını doğrular**; `public` şeması
   PUBLIC rolüne açıksa (PostgreSQL varsayılanı — `kontrol` önceden söyler)
   işlemi geri alıp durur → o durumda **panel: Tokyo → Project Settings →
   Data API → Enable Data API KAPAT** (yetkilere dokunmaz, tüm REST/RPC'yi
   keser, Auth çalışır). İsteğe bağlı: Tokyo Auth → yeni kayıtları kapat
   (pencerede açılan hesap kaybolurdu).
3. **[SEN] Son veri kopyası** — `bosalt` → `tasi` → `sayim` (Faz 3.1).
   `tasi` kendi sonunda sayımı tutturamazsa COMMIT etmez.
4. **[SEN] Frankfurt cron'larını aç:**
   `select cron.alter_job(job_id := jobid, active := true) from cron.job;`
5. **[SEN] Remote Config:** `sunucu = frankfurt` **ve** `min_build_* = 1.1.7 build`
   → yayınla. Köprü sürümü bir sonraki açılışta Frankfurt'a geçer; eskiler
   "Güncelle" ekranında kalır.
6. **[CLAUDE] Duman testi:** Frankfurt `net._http_response` 200'ler,
   `cron.job_run_details` succeeded, Crashlytics'te yeni hata dalgası yok,
   Analytics'te oturumlar Frankfurt'tan akıyor.
7. **[SEN] Sabah:** Tokyo **silinmez, duraklatılmaz** — donmuş kalır (Data API
   kapalı, cron'lar kapalı) ve yedek rolüne geçer (bkz. "Tokyo yedek olarak").
   Eski sürümlere karşı güvence Data API'nin kapalı olması.

**Geri dönüş (ilk 24 saat):** RC `sunucu = tokyo`, Tokyo'yu istemcilere aç
(`veri_tasima.py tokyo-ac --onay ybdb…` ya da Data API'yi aç) ve cron'ları aç, Frankfurt cron'larını kapat. Arada Frankfurt'a
yazılan veri kaybolur — pencere kısa ve gece olduğu için.

---

## Faz 1 — Kod hazırlığı (eski proje etkilenmez)

- [x] **[CLAUDE] `0076_edge_function_url_vault.sql`** — 14 fonksiyondaki sabit
      Tokyo adresi → `public.edge_function_url(fn)` = Vault `project_url` +
      `/functions/v1/<fn>`. Eksikse çağrı anında patlar (fail-closed), migration
      anında WARNING (yerel yığın boş Vault'la koşuyor). Kapı:
      `supabase/tests/edge_function_url_test.ts`. **Henüz hiçbir projeye uygulanmadı.**
      ⚠️ **Eski projeye `db push` (supabase-deploy) koşulacaksa ÖNCE** eski
      projenin Vault'una `project_url` = `https://ybdbzouzhzwthjgwlbmk.supabase.co`
      yaz; yoksa 0076 uygulandığı anda eski projenin tüm cron'ları "project_url
      bulunamadi" ile durur.
- [ ] **[CLAUDE] Zorunlu güncelleme kapısı** — Remote Config `min_build_android`
      / `min_build_ios`; altındaki sürüm "Güncelle" ekranında kalır. **Uygulamada
      yok (doğrulandı).** Olmadan geçişten sonra eski sürümler Tokyo'ya yazmaya
      devam eder ve o veri kaybolur. Geçişten ÖNCEKİ bir sürümle mağazalarda olmalı.
- [ ] **[CLAUDE] Android build numarası** — `android-release.yml` versionCode
      artırmıyor (`GOOGLE_GIRIS_KURULUM.md` §8). Bu fazın her AAB'si için şart.

## Faz 2 — Yeni projeyi kur (kullanıcı yok, risk yok)

> **Durum 2026-09-27:** 2.1–2.6 ✅ — legacy JWT anahtarları etkin; Vault'ta 11
> secret (`tefas_nav` ve `weekly_summary` cron secret'ları sohbete sızdığı için
> YENİ projede yeniden üretildi — Tokyo'da eski değerler duruyor); 70 migration;
> 26 cron kapalı; 18 fonksiyon secret'ı (APNs/FCM eskiyle aynı özet, EVDS aynı
> anahtar, `DELETION_HASH_SALT` yeni); 15 fonksiyon dağıtıldı.
> Uçtan uca: `analyze-signals` 200 (verify_jwt=true), `kripto-katalog` 200
> (348), `fetch-inflation` 200 (24 ay, son 2026-08). Yardımcı betikler
> `tmp/tasima/` (gitignore): `cron_secrets.py`, `diger_secrets.py`,
> `auth_kopyala.py`.
>
> **2.7 ✅ (aynı gün):** 11 Auth ayarı + 28 Türkçe şablon Management API ile
> kopyalandı (`auth_kopyala.py`; kapsamlı token: Auth R/W + project admin R/W,
> "Auth Signing Keys" KAPALI). **Free planda varsayılan e-posta sağlayıcısıyla
> şablon değiştirilemiyor (HTTP 400)** → özel SMTP zorunlu oldu: **Gmail SMTP**
> (`sandikapp.destek@gmail.com`, uygulama şifresi, smtp.gmail.com:465).
> Şablon ŞART, süs değil: kayıt akışı `{{ .Token }}` (6 hane) bekliyor,
> varsayılan şablon bağlantı yollar → kimse kayıt olamazdı. İlk uygulama
> şifresi başka hesapta üretildiği için 535 verdi (`smtp_dene.py` ayırdı).
> Bilinçli kopyalanmayan: `rate_limit_email_sent` (eski = varsayılan
> sağlayıcının düşük sınırı), `audit_log_disable_postgres`.
> Uçtan uca: `sandikapp.destek+tasimatest@gmail.com` kaydı → HTTP 200,
> 6 haneli kodlu e-posta Birincil kutuya düştü.
> ⚠️ **Bu deneme kullanıcısı `auth.users`'ta duruyor — Faz 3 kopyasından
> önce silinecek** (boşaltma adımına dahil).

1. **[SEN] API anahtarları.** Panel → Project Settings → API Keys. 2026'da açılan
   projeler varsayılan olarak `sb_publishable_…` / `sb_secret_…` anahtarlarıyla
   geliyor. Bizim iki bağımlılığımız **JWT biçimi** istiyor:
   - uygulamanın `SUPABASE_ANON_KEY`'i (istemci),
   - Vault `cron_gateway_jwt` (0054: gateway `Authorization`'ı JWT olarak ayrıştırıyor).
   **"Legacy API keys"** sekmesinde `anon` ve `service_role` JWT'lerinin
   **etkin** olduğunu doğrula ve not al. Etkin değilse etkinleştir. (Yeni
   anahtarlara geçiş ayrı bir iş; taşımayla karıştırma.)
2. **[SEN] Vault — `db push`'tan ÖNCE.** SQL Editor (yeni proje):
   ```sql
   select vault.create_secret('https://ynwymnpdiwudrlxfrmuo.supabase.co', 'project_url');
   select vault.create_secret('<YENİ projenin service_role JWT''si>', 'cron_gateway_jwt');
   -- 9 cron secret'ı: ESKİ projedeki değerlerin AYNISI (fonksiyon env'leriyle eşleşmeli).
   -- Eski projede: select name, decrypted_secret from vault.decrypted_secrets where name like '%cron_secret%';
   select vault.create_secret('<değer>', 'analyze_signals_cron_secret');
   select vault.create_secret('<değer>', 'calendar_nudge_cron_secret');
   select vault.create_secret('<değer>', 'daily_brief_cron_secret');
   select vault.create_secret('<değer>', 'inflation_fetch_cron_secret');
   select vault.create_secret('<değer>', 'live_activity_cron_secret');
   select vault.create_secret('<değer>', 'price_alerts_cron_secret');
   select vault.create_secret('<değer>', 'weekly_summary_cron_secret');
   select vault.create_secret('<değer>', 'kripto_cron_secret');
   select vault.create_secret('<değer>', 'tefas_nav_cron_secret');
   ```
   **Neden önce:** 0054'ün doğrulama bloğu bu secret'ları arıyor; yoksa önce
   `local-stack-only` yer tutucularını tohumlar (yerel yığın için yazılmış yol).
   Canlıda yer tutucu kalırsa cron'lar 401 alır.
3. **[CLAUDE] Şemayı kur** — `supabase link --project-ref ynwymnpdiwudrlxfrmuo`
   + `supabase db push` (0000 → 0076). Çıktıda `0054 tamam` ve `0076 tamam`
   notice'leri görülmeli. Auto mode canlı DB'yi engellerse komutu [SEN] koşar.
4. **[CLAUDE→SEN] Cron'ları HEMEN durdur** (yeni proje, SQL Editor):
   ```sql
   select cron.alter_job(job_id := jobid, active := false) from cron.job;
   ```
   (`update cron.job` Supabase'de 42501 verir — tablo doğrudan yazılamaz,
   `cron.alter_job` şart; 2026-09-27'de görüldü.)
   **Neden:** Faz 3'te gerçek kullanıcı verisi kopyalanınca yeni projenin
   cron'ları da push göndermeye başlar — kullanıcılar her bildirimi İKİ KEZ alır.
   Geçiş anına kadar yalnızca eski projenin cron'ları çalışır.
5. **[SEN] Edge function secret'ları** — Panel → Edge Functions → Secrets
   (ya da `supabase secrets set --project-ref ynwy…`). Eski projeyle **aynı değerler**:
   `APNS_BUNDLE_ID`, `APNS_HOST`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY`,
   `APNS_TEAM_ID`, `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_JSON`, `EVDS_API_KEY`,
   `DELETION_HASH_SALT` (**aynı olmak zorunda** — silinmiş hesap özetleri bununla
   karşılaştırılıyor), ve 9 `*_CRON_SECRET` (Vault'takilerle aynı).
   `CRON_AUTH_ALLOW_UNSET` **girilmez** (fail-closed kuralı).
   `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` otomatik gelir.
6. **[CLAUDE] Fonksiyonları dağıt** — 15 fonksiyon, `supabase functions deploy
   --project-ref ynwy…`. `supabase/config.toml`'daki `verify_jwt` ayarları korunur.
7. **[SEN] Auth ayarları** — eski projedekilerin aynısı (panelden bak, kopyala):
   Site URL + Redirect URLs (`sandik://…` deep link), e-posta şablonları,
   **SMTP** (`docs/SUPABASE_SMTP_SETUP.md`), **Apple** sağlayıcısı (Services ID +
   anahtar), şifre politikası, rate limit'ler. **Google** sağlayıcısı: henüz
   kurulmadı → doğrudan YENİ projede kurulacak (`GOOGLE_GIRIS_KURULUM.md`).
8. **Storage:** kullanılmıyor (`lib`'de `storage.from` yok) — atla.

**Geri dönüş:** yeni projeyi sil/boşalt; eski proje hiç etkilenmedi.

## Faz 3 — Prova (gerçek veriyle, kullanıcıya görünmez)

1. **[SEN] Veri kopyası — `tool/tasima/veri_tasima.py`** (2026-09-27).
   `pg_dump`/`supabase db dump` değil: makinede PostgreSQL istemcisi yok,
   `db dump` Docker ister, pg_dump sunucu sürümüne eşlenmek zorunda. Araç
   tablo tablo `COPY` akıtır; yön kilidi (kaynak yalnız Tokyo, hedef yalnız
   Frankfurt — ref doğrulanır), tek anlık görüntü (REPEATABLE READ), tek
   işlem, `session_replication_role = replica` (profil tetikleyicisi çift
   satır üretmez), dizi değerleri, son sayım tutmazsa geri alma. Yerel
   Docker testi: `python tool/tasima/test/calistir.py` (36/36).
   ```bash
   python -m pip install "psycopg[binary]>=3.2"
   # Panel → Connect → Session pooler (IPv4). Şifreler ekrana basılmaz.
   export ESKI_DB_URL='postgresql://postgres.ybdbzouzhzwthjgwlbmk:<şifre>@aws-1-ap-northeast-1.pooler.supabase.com:5432/postgres'
   export YENI_DB_URL='postgresql://postgres.ynwymnpdiwudrlxfrmuo:<şifre>@aws-0-eu-central-1.pooler.supabase.com:5432/postgres'
   python tool/tasima/veri_tasima.py kontrol       # salt okuma — ENGEL 0 olmalı
   python tool/tasima/veri_tasima.py bosalt --onay ynwymnpdiwudrlxfrmuo
   python tool/tasima/veri_tasima.py tasi   --onay ynwymnpdiwudrlxfrmuo
   python tool/tasima/veri_tasima.py sayim         # EŞİT olmalı
   ```
   - `auth.users` + `auth.identities` şifre özetleriyle gelir → **yeniden kayıt yok**.
   - Oturumlar gelmez (JWT secret projeye özgü) → **herkes bir kez yeniden giriş yapar**.
   - Taşınmayanlar: `cron.*`, `vault.*`, `supabase_migrations.*`, `net.*`,
     auth oturum tabloları (Faz 2'de kuruldu / projeye özgü).
   - `bosalt` Faz 2 deneme verisini de siler (`tufe` 24, kripto 348,
     `sandikapp.destek+tasimatest@gmail.com` deneme kullanıcısı).
   - ⚠️ `kontrol`'ün canlıda cevaplayacağı üç açık soru (yerel testte
     sınanamadı, Supabase'e özgü): `session_replication_role` postgres
     rolüne açık mı; `auth.users`'a INSERT/DELETE yetkisi var mı; Tokyo'da
     `public` PUBLIC'e açık mı. **K3'ten önce `kontrol`'ü bir kez koş.**
   - ✅ **Cevaplandı (2026-09-27, canlı `kontrol`):** 36 tablo şema-uyumlu
     (kolon farkı yok); `session_replication_role = replica` postgres rolüne
     AÇIK; `auth.users` INSERT/DELETE var; **Tokyo `public` PUBLIC'e AÇIK →
     `tokyo-kapat` işe yaramaz, K4.2'de panelden Data API kapatılır.**
     Bağlantı: Tokyo pooler `aws-1-ap-northeast-1`, Frankfurt `aws-0-eu-central-1`;
     şifre `ESKI_DB_SIFRE`/`YENI_DB_SIFRE` ile ayrı verilir.
2. **[CLAUDE] Sayım** — `sayim` çıktısı + birkaç kullanıcı için ekrandaki
   toplamların Tokyo ile karşılaştırması.
3. **[SEN] Debug build ile deneme** — yeni URL/anahtarla (`--dart-define`) gerçek
   cihazda: giriş, portföy, grafik, varlık ekle/sil, alarm oluştur, hesap sil
   (test hesabıyla). Push'u elle tetikle (`push_test_trigger`) — cron'lar kapalı.
4. Prova verisini boşalt (Faz 4'te taze kopya alınacak).

**Geri dönüş:** yeni projeyi boşalt; eski proje hâlâ tek canlı.

## Faz 4 — Geçiş (bakım penceresi, ~1 saat, hafta sonu gecesi)

> ⚠️ **Yerini "AÇILIŞ YOL HARİTASI → K4" aldı** (köprü sürümü kararı,
> 2026-09-27). Aşağısı iki-sürüm planının kaydı olarak duruyor.

Ön koşul: Faz 1'in zorunlu güncelleme kapısını taşıyan sürüm mağazalarda ve
kullanıcıların çoğu onda. Yeni URL'li sürümler **inceleme onayı almış ama
elle yayın bekliyor** (App Store "Manually release", Play "yönetilen yayınlama").

1. **[SEN]** Eski projede cron'ları durdur: `select cron.alter_job(job_id := jobid, active := false) from cron.job;`
2. **[SEN]** Eski projeyi yazmaya kapat (eski istemciler yazmasın):
   Remote Config `min_build_*` = yeni sürüm → eski sürümler "Güncelle" ekranında kalır.
3. **[SEN/CLAUDE]** Taze veri kopyası (Faz 3.1) + sayım karşılaştırması.
4. **[SEN]** Yeni projede cron'ları aç: `select cron.alter_job(job_id := jobid, active := true) from cron.job;`
5. **[SEN]** Yeni sürümleri yayınla (App Store + Play).
6. **[CLAUDE]** Duman testi: `net._http_response`'ta 200'ler, `cron.job_run_details`
   "succeeded", Crashlytics'te yeni hata dalgası yok.

**Geri dönüş (ilk 24 saat):** `min_build_*`'ı geri al, eski projede cron'ları aç.
Arada yeni projeye yazılan veri kaybolur — bu yüzden pencere kısa ve gece.

## Faz 5 — Temizlik

- [ ] **[SEN]** GitHub secret'ları: `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
      `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD` → yeni proje.
      (`supabase-deploy.yml` bu ref'e dağıtır; değiştirilmezse eski projeye gider.)
- [ ] **[SEN/CLAUDE]** `SUPABASE_ACCESS_TOKEN` → **iki projeye yetkili** token
      (kullanıcı kararı 2026-09-30: bu paketle birlikte). Bugünkü token kısıtlı,
      yalnız Tokyo'yu görüyor: Frankfurt'ta Management API **403**. Sonuçları:
      günlük `sema-esitlik.yml` her gün KIRMIZI (fark yüzünden değil, Frankfurt
      okunamadığı için) ve `supabase-deploy.yml` Frankfurt adımında düşer. O güne
      kadar dağıtım + eşitlik kanıtı **yerel CLI** ile (`supabase link` →
      `db push` → `functions deploy --project-ref` → Tokyo'ya geri link →
      `python tool/sema_esitlik.py`). Seçenekler: (a) yerel CLI token'ını
      `gh secret set` ile yaz — tüm organizasyona yetkili, kişisel token;
      (b) panelde yalnız bu iki projeye kapsamlı yeni token aç — daha dar.
      Token değişince `sema-esitlik.yml`'yi elle bir kez koştur, yeşil görmeli.
- [ ] **[CLAUDE]** Hukuki metinler: gizlilik politikası (TR/EN), KVKK aydınlatma,
      **açık rıza metni**, `DATA_SAFETY_FORM.md` — "ABD" → **"Almanya (AB)"**.
      **Uygulama içi metinler de** (2026-09-27 emülatör turunda görüldü —
      kullanıcı RIZAYI bunlara veriyor): `register_screen.dart:402` açık rıza
      kutusu "Supabase (ABD)", `legal_doc_screen.dart:152` "ABD'de barındırıldığından".
      Rıza metni değişince `legal/` sürüm numarası artmalı ve mevcut kullanıcıdan
      yeniden onay istenip istenmeyeceği hukukçuya sorulmalı.
      Bugünkü metin zaten yanlış (gerçek: Japonya). Hukukçuya gösterilmeli:
      KVKK yurt dışı aktarım kuralları 1 Haziran 2024'te değişti (7499 s. Kanun).
- [ ] **[CLAUDE]** CLAUDE.md + hafıza: proje ref'i, bölge.
- [ ] **Tokyo SİLİNMEZ — yedek olarak kalır** (kullanıcı kararı 2026-09-27).
      Ayrıntı ve açık kararlar aşağıda.

### Tokyo yedek olarak (kullanıcı kararı 2026-09-27: "silme, yedek olarak kullanırız")

**Neden değerli:** Frankfurt Free planda — **otomatik günlük yedek yok**. Başka
kıtadaki ikinci proje bölgesel arızaya karşı da korur.

**Tek başına bırakılırsa yedek DEĞİL, anlık görüntü:** geçiş gecesinin hâli
donar; sonra Frankfurt'a yazılan hiçbir şey oraya gitmez.

| Açık karar | Seçenek | Not |
|---|---|---|
| Güncellik | `veri_tasima.py yedekle` — **Frankfurt → Tokyo**, ayrı yön kilidi ve `--onay`; haftalık/günlük | Geçişten ÖNCE Tokyo asla yazılmaz değişmezi korunur: komut yalnız geçiş sonrası (Tokyo donmuşken) çalışır |
| Zamanlama | Elle / GitHub Action (şifreler secret'ta) | Action için `SUPABASE_DB_PASSWORD` benzeri iki secret |
| Free plan duraklatması | 7 gün hareketsizlikte otomatik Pause; 90 gün geri açılmazsa panelden geri yüklenemez | Düzenli `yedekle` hareket sayılır → çözer |
| Güvenlik yüzeyi | Tokyo'daki APNs/FCM/EVDS fonksiyon secret'larını sil ya da boşalt | Cron kapalıyken kullanılmıyorlar |
| Hukuk | Veri İKİ bölgede (Almanya + Japonya) | Gizlilik politikası, KVKK aydınlatma, açık rıza iki ülkeyi de yazar |

Geri dönüş anlamı değişir: Tokyo güncel tutuldukça "Frankfurt'u kaybettik"
senaryosunda RC `sunucu = tokyo` + Tokyo'yu çöz ile dönülebilir.

---

### İki sunucu birebir (kullanıcı kuralı 2026-09-28)

*"Bu sessionda db tarafında yapılan değişiklikler birebir Frankfurt sunucusunda
da çalışmalı, o iki sunucu hep senkron birebir aynı gitmeli."*

- **Uygulama:** `supabase-deploy.yml` → hedef `ikisi` (varsayılan). Frankfurt
  önce (kanarya), kırılırsa Tokyo'ya gitmez; sonda `esitlik` işi.
- **Kanıt:** `tool/sema_esitlik.py` — `supabase/audit/sema_parmak_izi.sql`'i iki
  projede salt okunur koşar (tablo/kısıt/indeks/politika/fonksiyon/tetikleyici/
  GRANT/sütun GRANT/eklenti/event trigger/cron/Vault ADI/migration defteri).
  Satır sonu ve sütun sırası anlam taşımadığı için normalize edilir.
- **Günlük:** `sema-esitlik.yml` 07:30 TR — deploy dışı kaymayı (SQL Editor,
  panel ayarı) yakalar. ⚠️ Faz 5'teki token değişimine kadar Frankfurt'ta
  403 ile KIRMIZI döner; kırmızı "fark var" demek DEĞİLDİR — log'da
  `Management API HTTP 403` satırına bak. Kanıt o güne kadar yerelde
  (son ölçüm 2026-09-30, 0086/0087 sonrası: ŞEMA EŞİT).
- **İlk ölçüm (2026-09-28): 52 fark.** 30'u beklenen (Tokyo'da 0076 yok) ve
  satır sonu. Gerçek kayma 4 madde → `0078_sunucu_esitleme.sql`:
  1. `profiles_select_partner` Frankfurt'ta **hatalı** (`p.id` — ortak profili
     görünmüyordu); 0000'daki nitelenmemiş `id`.
  2. `user_push_tokens` Frankfurt'ta 0000 biçimi (id PK); Tokyo'da PK=token.
  3. `disclaimer_acceptances` tekil kısıt adı.
  4. Tokyo'da panelden açılmış `rls_auto_enable` + `ensure_rls` event trigger.
- **Doğrulama (uygulamadan önce):** iki projenin gerçek şema dökümü yerel
  Supabase Postgres'e kuruldu, bekleyen migration'lar üstüne uygulandı →
  parmak izi **0 fark**.

---

## Açık riskler

| Risk | Önlem |
|---|---|
| Yeni projede legacy JWT anahtarları kapalı | Faz 2.1 — önce doğrula; kapalıysa `cron_gateway_jwt` ve istemci anahtarı çalışmaz |
| Çift push (iki projenin cron'u aynı anda) | Faz 2.4 + Faz 4.1/4.4 sırası |
| Eski sürüm Tokyo'ya yazmaya devam eder | Faz 1 zorunlu güncelleme kapısı, geçişten önce yayında |
| Herkes bir kez çıkış yapmış olur | Kaçınılmaz (JWT secret projeye özgü); sürüm notunda söyle |
| `data-only` dump'ta `auth` şeması eksik gelir | Faz 3 provasında `auth.users` sayımıyla doğrula |
| `DELETION_HASH_SALT` farklı girilir | Faz 2.5 — aynı değer; silinmiş hesap eşleşmesi bozulur |
