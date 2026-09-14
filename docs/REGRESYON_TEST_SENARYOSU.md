# sandık — Elle Regresyon Test Senaryosu

**Oluşturma:** 2026-09-14 · **Kapsam:** her sürüm öncesi elle koşulacak testler

> **Bu dosya neyi kapsar:** yalnızca **otomatik testin ulaşamadığı** vakaları.
> 193 test dosyası (`test/`) widget ve mantık katmanını zaten kilitliyor;
> burada yazılanlar cihaz donanımı, sunucu sınırı ve mağaza şartlarıyla
> ilgili — yani CI'da koşamayanlar.
>
> **Neden elle:** Bu projenin emülatörleri Flutter'ı render edemiyor
> (CLAUDE.md "yerel makine notları"), bu yüzden görsel doğrulama gerçek
> cihazda yapılır. Push, biyometri, Live Activity ve derin bağlantı zaten
> emülatörde anlamlı sonuç vermez.
>
> Yayın öncesi ticari/hukuki kontroller ayrı dosyada:
> [`YAPMAN_GEREKENLER.md`](../YAPMAN_GEREKENLER.md) §7.

## Nasıl kullanılır

Her vaka **R-xx** kodludur. Sürüm öncesi ilgili blokları koş, sonucu yanına
yaz. Kırmızı bir vaka bulursan koda değil önce bu dosyaya bak: "beklenen"
sütunu kasıtlı davranışları da anlatıyor (çoğu "hata sandığın şey aslında
doğru davranış" vakası).

**Öncelik:** 🔴 yayın bloker · 🟠 sürüm öncesi zorunlu · 🟡 çeyreklik

---

## A. Sunucu / cron zinciri

SQL Editor'dan koşulur, cihaz gerekmez. Hepsinin ortak doğrulaması:

```sql
-- tetikleyiciyi çağır, 5-10 sn bekle, sonra:
select id, status_code, left(content, 200) as content, created
  from net._http_response
 where created > now() - interval '2 minutes'
 order by id desc;
```

`where created > now() - ...` filtresi kasıtlı: filtresiz sorguda eski bir
401 satırını bugünün sonucu sanmak bu projede bir kez yaşanmış teşhis
hatasıdır.

**Durum kodu sözlüğü — üç kod üç ayrı eksiği gösterir, karıştırma:**

| Kod | Anlamı | Düzeltmesi |
|---|---|---|
| `200` | ✅ geçti | — |
| `401 UNAUTHORIZED_INVALID_JWT_FORMAT` | Gateway reddetti; istek fonksiyona hiç ulaşmadı | `cron_gateway_jwt` Vault kaydını yaz (service_role JWT) |
| `401 Yetkisiz cron cagrisi` | Fonksiyona ULAŞTI, Vault ≠ function secret | İki değeri eşitle |
| `503 cron_secret_missing` | `supabase secrets set` yapılmamış | Function secret'ını yaz |

| # | Vaka | Adım | Beklenen | Öncelik |
|---|---|---|---|---|
| R-01 | Sabah brifingi yetkisi | `select public.trigger_daily_brief();` | `200`. `sent:0` + "Brifing icin hisse yok." piyasa kapalıyken **normaldir** — sınanan şey yetki kapısı | 🟠 |
| R-02 | Haftalık özet yetkisi | `select public.trigger_weekly_summary();` | `200`, `failures: []`. Sıfır sayaçlar normal (bkz. R-03) | 🟠 |
| R-03 | Haftalık özet eleme mantığı | R-02 çıktısındaki `skipped_*` alanlarını oku | `skipped_flow` > 0 ise **doğru**: hafta içinde alım/satım yapana yüzde göndermek yanlış rakam olurdu. Bug değil | 🟡 |
| R-04 | TÜFE çekimi | `select public.trigger_fetch_inflation();` | `200`, `written:24`. `reason:"no_new_data"` = o ayın verisi zaten var, normal | 🟠 |
| R-05 | TÜFE baz yılı koruması | `select count(*), min(period), max(period) from inflation_index;` | ≥13 satır (rozet 365 günlük pencere ister). `409 base_year_break` dönerse TÜİK baz yılını değiştirmiştir — **otomatik çözülmez**, karar senin | 🟡 |
| R-06 | Sinyal analizi | `select public.trigger_analyze_signals('hourly');` | `200`. ⚠️ **Parametre ZORUNLU** (`morning`/`afternoon`/`hourly`); argümansız çağrı `42883 does not exist` der — yetki sorunu değil, imza uyuşmazlığı | 🟠 |
| R-07 | Sinyal de-dup (0062) | R-06 çıktısında `positions` alanı | Piyasa saatinde >0. `skipped_by_frequency` yüksekse frekans kapısı (0024) elemiştir, bug değil | 🟠 |
| R-08 | Takvim kancası | `select public.trigger_calendar_nudge();` | `200`. `failures` içinde FCM `404 NotRegistered` çıkabilir — ölü token **kendiliğinden silinir** (`fcm.ts` `shouldDeleteToken`), sonraki turda çıkmaz | 🟠 |
| R-09 | Fiyat alarmları | `select public.trigger_check_price_alerts();` | `200`. "Fiyat alinamadi." piyasa kapalıyken normal | 🟠 |
| R-10 | Live Activity push'u | iPhone'da Live Activity başlat → `select public.trigger_live_activity_push();` | `200`, `sent` ≥1. ⚠️ Aktif oturum yoksa fonksiyon **HTTP turu bile atmaz**, yeni satır düşmez — eski kaydı okuyup "bozuk" sanma, `created` damgasına bak | 🟠 |
| R-11 | Sessiz saatler | Ayarlar → Bildirimler → sessiz saati şimdiyi kapsayacak yap → R-01 | `skipped_quiet_hours` > 0 | 🟡 |
| R-12 | Cron zamanlaması | `select jobname, schedule from cron.job order by jobname;` | `daily-brief='45 6 * * 2-5'`, `weekly-summary='45 6 * * 1'` — Pazartesi İKİSİ BİRDEN koşmamalı | 🟡 |
| R-13 | Fail-closed kapısı | (yalnız denetimde) Bir function secret'ını geçici sil → tetikle | `503 cron_secret_missing`. Secret yokken çağrı **geçmemeli** — geçiyorsa `CRON_AUTH_ALLOW_UNSET` üretime sızmıştır | 🟡 |

---

## B. Cihaz / donanım

Gerçek cihazda koşulur; emülatör bu vakalarda anlamlı sonuç vermez.

| # | Vaka | Adım | Beklenen | Öncelik |
|---|---|---|---|---|
| R-20 | Biyometrik kilit — açılış | Ayarlar → Hesap → Biyometrik kilit'i aç | Açarken bir kez doğrulama ister; cihaz desteklemiyorsa uyarır, sessizce açılmaz | 🟠 |
| R-21 | Biyometrik kilit — arka plan | Uygulamayı 30 sn+ arkaya al, dön | Kilit ekranı gelir. **30 sn'den kısa sürede gelmez** (bilinçli eşik) | 🟠 |
| R-22 | Biyometrik kilit — reddetme | Kilit ekranında biyometriyi iptal et | İçerik AÇILMAZ, uygulama çökmez; tekrar deneme sunulur | 🟠 |
| R-23 | Biyometrik kilit — PIN yedeği | Biyometriyi cihazda geçersiz kıl, PIN ile dene | PIN kabul edilir (`biometricOnly=false`) | 🟡 |
| R-24 | Oturum kasası geçişi | Yeni build'i **mevcut oturumun üstüne** kur, aç | Doğrudan ana ekran. **Yeniden giriş İSTENMEZ** — token SharedPreferences'tan Keychain/Keystore'a taşınır. Giriş isteniyorsa geçiş kırık | 🔴 |
| R-25 | Idle logout | Uygulamayı 10 dk+ arkada bırak, dön | Çıkış yapılmış olmalı (`backgroundedAtMs` ≥10 dk) | 🟡 |
| R-26 | Derin bağlantı | Notlar'a `sandik://asset/<gerçek id>` yaz, dokun | İlgili varlık ekranı açılır. Uygulama kapalıyken de çalışmalı | 🟠 |
| R-27 | Derin bağlantı — çift işleme | R-26'yı uygulama AÇIKKEN tekrarla | Ekran bir kez açılır; iki kez push'lanmaz (`DeepLinkService` yalnızca `asset` host'unu alır) | 🟡 |
| R-28 | Push → ekran | Sinyal push'una dokun | Doğru varlık ekranı açılır (derin bağlantıyla aynı yol) | 🟠 |
| R-29 | Live Activity teması | Temayı Açık/Koyu **sabitle** → uygulamayı kill et → 5-10 dk kilit ekranını izle | Palet DEĞİŞMEZ. ⚠️ "Tercih: Sistem" seçiliyse cihazla değişmesi **normaldir** | 🟠 |
| R-30 | Live Activity teşhisi | Profil → (admin) Push Teşhisi → §6 CANLI ETKİNLİK / TEMA | `Yerel karar` = `sütun (is_light_theme)`. "SÜTUN YOK" ise `0050` koşulmamış | 🟡 |
| R-31 | Ana ekran widget'ı | Widget'ı ekle, portföyü değiştir | Değer güncellenir. Emülatörde **görülebilir** (widget native, Flutter render'ına bağlı değil) | 🟡 |
| R-32 | Bildirim izni reddi | Kurulumda bildirim iznini reddet | Uygulama çalışmaya devam eder; bildirim ayarları "kapalı" gösterir, çökme yok | 🟡 |

---

## C. Hesap ve kimlik

| # | Vaka | Adım | Beklenen | Öncelik |
|---|---|---|---|---|
| R-40 | Hesap silme — tuz kapısı | Ayarlar → Hesap → Hesabı sil → ikinci onaya kadar git | Onay ekranı gelir. **503 / "şu an yapılamıyor" gelirse** `DELETION_HASH_SALT` set edilmemiştir — Play bloker'ı | 🔴 |
| R-41 | Hesap silme — tam akış | Test hesabıyla sonuna kadar götür | 30 sn içinde biter; Supabase'de kullanıcı ve verileri gerçekten silinmiş | 🔴 |
| R-42 | Hesap silme — yanlış şifre | Onayda yanlış şifre gir | "Şifre hatalı" — ham hata değil | 🟠 |
| R-42b | **Hesap silme — ekran kilidi** | İkinci onaydan (HESABI SİL) sonra istek uçarken ekrana dokun, geri tuşuna bas | Tam ekran örtü + "Hesabın siliniyor…"; **hiçbir şeye tıklanamaz**, geri oku GİZLİ, sistem geri hareketi çalışmaz. 🐞 2026-09-14'te bulundu ve düzeltildi (`AbsorbPointer` yalnızca `body`'yi sarıyordu; app bar ve PopScope açıktı) — `delete_account_lock_test.dart` kilitliyor | 🟠 |
| R-43 | Hesap silme — sosyal hesap | Apple/Google ile açılmış hesapta sil | Taze kimlik doğrulaması ister (`{provider,id_token,nonce}`); şifre sorulmaz | 🟠 |
| R-44 | Apple ile giriş | iOS'ta Apple düğmesi → giriş | İlk girişte ad gelir ve profile yazılır; **sonraki girişlerde ad gelmez** (Apple böyle çalışır, bug değil) | 🟠 |
| R-45 | Google ile giriş | Google düğmesi → giriş | Başarılı. ⚠️ Düğme **görünmüyorsa** `GOOGLE_WEB_CLIENT_ID` derlemeye verilmemiştir — bilinçli, kırılma değil | 🟠 |
| R-46 | Sosyal giriş — vazgeçme | Apple/Google ekranında iptal et | Hata gösterilmez, giriş ekranında kalınır | 🟡 |
| R-47 | Kayıt onay kutuları | 3 kutuyu işaretlemeden kaydol | Üç ayrı kırmızı uyarı; submit engellenir | 🟠 |
| R-48 | Kayıt — hesap sayımı | Var olan e-posta ile kaydol | Hesabın varlığını **ELE VERMEYEN** mesaj (M4 kararı) | 🟡 |
| R-49 | Ortaklık akışı | Davet üret → ikinci hesapla kabul et | İki tarafta da görünür; davet kodu tekrar kullanılamaz | 🟠 |

---

## D. Veri bütünlüğü

Otomatik testlerle de korunuyor; elle koşması sürüm öncesi duman testi.

| # | Vaka | Adım | Beklenen | Öncelik |
|---|---|---|---|---|
| R-60 | Kapanmış pozisyon | Bir varlığı tamamen sat | Portföy toplamından düşer; **Hareketler listesinde kalır** (geçmiş ham defterden okunur) | 🟠 |
| R-61 | Satılan varlığa sinyal | R-60 sonrası bir cron turu bekle | O varlık için push GELMEZ (`closed_or_deleted_lots` eler) | 🟠 |
| R-62 | Silme → geri al | Varlığı sil → snack'te "Geri al" | Lotlar geri gelir, silme log'u kalkar | 🟠 |
| R-63 | Ortak pozisyon | Ortaklı bir varlığa bak | Ortak lot'ları tek havuzda **toplanmaz**; kâr/zarar sahibine göre ayrı | 🟠 |
| R-64 | Kırılım toplamı | Özet toplamı ile kategori dökümünü karşılaştır | Σ parça == bütün. Fark varsa sentetik "Diğer" açılmalı, sessizce yutulmamalı | 🟠 |
| R-65 | Çevrimdışı açılış | Uçak modunda uygulamayı aç | Önbellekten açılır + "çevrimdışı" şeridi; hata ekranı değil | 🟠 |
| R-66 | Fiyat çekimi timeout | Zayıf bağlantıda fiyat yenile | 15 sn sonra timeout; arayüz donmaz | 🟡 |
| R-67 | Boş portföy | Sıfır varlıkla ana ekran | Boş durum kartı; şeritler ve başlıklar gizli, çökme yok | 🟠 |
| R-68 | CSV içe aktarma | Toplu Ekle → CSV yapıştır (TR sayı, `;` ayraç) | Önizleme doğru; hatalı satırlar nedeniyle birlikte listelenir | 🟡 |
| R-69 | Yüzdelik şerit k-anonimliği | Ana ekrandaki getiri sıralaması şeridi | Havuzda <8 kişi varsa "Yakında". **Doğru davranış** — KVKK k-anonimliği, migration eksikliği değil | 🟡 |
| R-70 | Ham hata sızıntısı | Ağı kapatıp birkaç akışı zorla | Hiçbir ekranda `Exception:` / stack trace görünmez; hepsi `friendlyError` | 🟠 |

---

## E. Sürüm / paketleme

| # | Vaka | Adım | Beklenen | Öncelik |
|---|---|---|---|---|
| R-80 | Release build | `flutter build apk --release` → cihaza kur | Açılır ve çalışır. ProGuard/R8 kırılmaları **yalnızca burada** görünür | 🔴 |
| R-81 | Keystore kapısı | `android/key.properties` yokken release build dene | **Build KIRILIR** (`GradleException`) — debug anahtarıyla sessiz imzalama yok. Kırılmıyorsa kapı çalışmıyor | 🟠 |
| R-82 | Derleme bayrağı | `SUPABASE_URL` dart-define'ı vermeden build | Kırılır; fallback literal YOK | 🟠 |
| R-83 | Font paketleme | TestFlight'ta kilit ekranı yazısı | DM Sans (uygulama içiyle aynı). SF Pro'ya düşmüşse `UIAppFonts` ya da hedef üyeliği bozuk | 🟡 |
| R-84 | Otomatik test paketi | `bash tool/deploy_emulators.sh` | analyze temiz + tüm testler geçer. Kırılırsa APK emülatöre gitmez | 🔴 |

---

## Sürüm öncesi minimum set

Zaman kısıtlıysa **yalnızca bunlar**: R-24, R-40, R-80, R-84 (dördü de 🔴)
artı o sürümde dokunulan alanın blokları.

## Koşum kaydı

| Tarih | Sürüm | Koşulan | Sonuç |
|---|---|---|---|
| 2026-09-14 | 1.1.4+7 | R-01, R-02, R-04, R-06, R-08, R-09, R-10, R-12 | ✅ hepsi `200`. R-08'de ölü FCM token'ı kendiliğinden silindi. R-07 sınanamadı (`positions:0` — gece, frekans kapısı 12 varlığı eledi) |
| 2026-09-14 | 1.1.4+7 | R-40, R-41, R-42b | R-40 ✅ / R-41 ✅ (kullanıcı gerçekten silindi) / **R-42b 🐞 KIRIK bulundu → düzeltildi** — silme uçarken ekran etkileşime açıktı |
| 2026-09-15 | 1.1.4+7 | R-42b (düzeltme sonrası) + cihaz turu | ✅ Kilit doğrulandı: örtü görünüyor, dokunuş yutuluyor, geri çıkış engelli. Elle regresyonun ilk turu bir gerçek bug yakaladı — senaryonun karşılığını verdi |

**Henüz hiç koşulmayanlar:** B bloğunun tamamı (cihaz), C bloğu, E bloğu.
