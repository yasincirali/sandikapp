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

### Kilometre taşları

| # | Ne | Kim | Süre | Geçiş şartı (go / no-go) |
|---|---|---|---|---|
| **K0** | Frankfurt hazır, cron kapalı | — | ✅ 2026-09-27 | — |
| **K1** | Köprü sürümü kodu: çift sunucu seçimi + zorunlu güncelleme kapısı + Android build numarası + rıza metni (+ haftalık şerit hatası, TECHNICAL_DEBT) | CLAUDE | 2–3 gün | Tam test paketi yeşil; emülatörde RC override ile **Tokyo → Frankfurt → Tokyo** gidiş-dönüş: her yönde temiz giriş ekranı, eski kullanıcının önbelleği sızmıyor |
| **K2** | 1.1.7 yayını: App Store + Play (kapalı test güncellemesi, sonra üretim). RC `sunucu=tokyo` | SEN (+CLAUDE CI) | onay 1–3 gün + yayılma ~7 gün | Analytics'te 1.1.7 payı ≥ %90 **veya** 7 gün; çökmesiz oturum ≥ %99 |
| **K3** | Prova: veri kopyası → Frankfurt; RC koşulu (kullanıcı özelliği / uygulama örneği) ile **yalnız senin cihazın** `frankfurt`; kendi hesabınla gerçek uygulamada gez | SEN + CLAUDE | 1 gün | Rakamlar Tokyo ile birebir (toplam, 1A köprüsü, dağılım); giriş, varlık ekle/sil, alarm, push (`push_test_trigger`) çalışıyor. Sonra Frankfurt boşaltılır |
| **K4** | Geçiş gecesi (runbook aşağıda) | SEN + CLAUDE | ~1 saat, hafta sonu 02:00–04:00 | Duman testi yeşil; 24 saat içinde geri dönüş penceresi |
| **K5** | Temizlik: GitHub secret'ları → Frankfurt, varsayılan `frankfurt` derlenir, hukuki metinler, Tokyo duraklat → 14 gün → sil | SEN + CLAUDE | 2 hafta | — |

Toplam ≈ 2 hafta; **geçiş gecesinin kritik yolunda mağaza yok.** Android
kapalı testin 14 günüyle örtüşür — testçiler köprü sürümünü güncelleme olarak alır.

### K4 — geçiş gecesi runbook'u

1. **[SEN] Tokyo cron'larını durdur** (Tokyo SQL Editor):
   `select cron.alter_job(job_id := jobid, active := false) from cron.job;`
2. **[SEN] Tokyo'yu yazmaya kapat** — köprü öncesi sürümler ve RC'yi henüz
   çekmemiş istemciler Tokyo'ya veri yazmasın (yazılan kaybolur):
   `revoke insert, update, delete on all tables in schema public from anon, authenticated;`
   (+ yazan `security definer` RPC'lerin `execute` yetkisi — liste K3'te çıkarılır).
   Uygulama yazma hatasını `friendlyError` ile gösterir; okuma çalışır.
3. **[SEN/CLAUDE] Son veri kopyası** (Faz 3.1 komutları) + tablo tablo sayım
   karşılaştırması. Önce Frankfurt boşaltılır (Faz 3 notu).
4. **[SEN] Frankfurt cron'larını aç:**
   `select cron.alter_job(job_id := jobid, active := true) from cron.job;`
5. **[SEN] Remote Config:** `sunucu = frankfurt` **ve** `min_build_* = 1.1.7 build`
   → yayınla. Köprü sürümü bir sonraki açılışta Frankfurt'a geçer; eskiler
   "Güncelle" ekranında kalır.
6. **[CLAUDE] Duman testi:** Frankfurt `net._http_response` 200'ler,
   `cron.job_run_details` succeeded, Crashlytics'te yeni hata dalgası yok,
   Analytics'te oturumlar Frankfurt'tan akıyor.
7. **[SEN] Sabah:** Tokyo'yu **duraklat** (Pause) — hâlâ Tokyo'ya takılı
   istemci kalmadığının kesin güvencesi.

**Geri dönüş (ilk 24 saat):** RC `sunucu = tokyo`, Tokyo'da yetkileri geri ver
(`grant …`) ve cron'ları aç, Frankfurt cron'larını kapat. Arada Frankfurt'a
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

1. **[SEN/CLAUDE] Veri kopyası** — Supabase'in "migrating within Supabase" yolu,
   **yalnızca veri** (şema Faz 2'de migration'larla kuruldu):
   ```bash
   supabase db dump --db-url "$ESKI_DB_URL" --data-only --use-copy -f tmp/tasima/data.sql
   psql "$YENI_DB_URL" -v ON_ERROR_STOP=1 \
     -c "set session_replication_role = replica" -f tmp/tasima/data.sql
   ```
   - `auth.users` + `auth.identities` şifre özetleriyle gelir → **yeniden kayıt yok**.
   - Oturumlar gelmez (JWT secret projeye özgü) → **herkes bir kez yeniden giriş yapar**.
   - Dump'tan çıkarılacaklar: `cron.*`, `vault.*`, `supabase_migrations.*`,
     `net.*` (yeni projede zaten var/projeye özgü). Provada dump içeriğini kontrol et.
   - `tmp/` gitignore'da; dump kişisel veri içerir → prova bitince **sil**.
   - ⚠️ **Önce yeni projenin `public` tablolarını boşalt.** Faz 2 denemeleri
     veri yazdı (`tufe` 24 satır, kripto kataloğu 348); `--data-only` yükleme
     aynı birincil anahtarlarda çakışır ve `ON_ERROR_STOP` ile yarıda kalır.
     `truncate … restart identity cascade` — liste provada dump'tan çıkarılır.
2. **[CLAUDE] Sayım karşılaştırması** — her tablo için eski/yeni `count(*)`.
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
- [ ] **[SEN]** Eski projeyi 14 gün **duraklat** (Pause), sonra son yedeği alıp **sil**.

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
