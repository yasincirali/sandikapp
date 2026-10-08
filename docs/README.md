# sandık — GitHub Pages Site

Bu klasör https://yasincirali.github.io/sandikapp/ adresinde yayınlanan sandık landing + legal sayfalarını içerir.

## Yayınlama (bir kere)

1. GitHub repo: `sandikapp` (yoksa oluştur ve bu repo'yu push et — ya da mevcut `PortfoyTakip` repo'yu `sandikapp` olarak rename et; ancak URL'ler `/sandikapp/` prefix ile yazıldığı için repo adı **`sandikapp`** olmalı)
2. Repo Settings → Pages
3. Source: **Deploy from a branch**
4. Branch: `main` / `/docs` folder → Save
5. 1-2 dakika içinde https://yasincirali.github.io/sandikapp/ yayınlanır

## Yasal metinler: web ve uygulama tek kaynak

Kullanıcı kararı (2026-10-04): *"Webdekiyle de her zaman eşleyelim."*
`legal/tr/*.md` (çevirisi `legal/en/*.md`) hem bu sitedeki yasal sayfaların
hem de uygulamanın gösterip onaylattığı belgelerin (Kullanım Koşulları,
Gizlilik Politikası, KVKK Aydınlatma Metni, Açık Rıza Metni) **tek
kaynağıdır**. HTML'e de, uygulamaya da elle metin yazılmaz.

Metin değişince sıra:

1. `legal/tr/<BELGE>.md`'yi düzenle; künyede **"Sürüm"** satırını artır,
   "Yürürlük tarihi" / "Son güncelleme" o gün. Çevirisi varsa
   `legal/en/<BELGE>.md`'yi de çevir: "Version" ve "Source: TR x" yeni TR
   sürümünü yazsın.
2. `python docs/_build_legal.py` — sayfa listesindeki her md'yi ortak
   layout'a sarar, `docs/` altına yazar **ve** uygulamanın sabitini
   (`lib/config/yasal_belge_kaynaklari.g.dart`) üretir. `docs/index.html`'e
   dokunmaz (elle bakılır).
3. `flutter test --run-skipped --tags arac tool/yasal_metin_uret_test.dart`
   → `build/yasal_metin_ekleri.sql`'i YENİ bir migration'a koy (iki sunucu).
4. Kapının "Neler değişti" notu: `yasalKapiDegisiklikNotu` (iki .arb +
   `flutter gen-l10n`).
5. `flutter test test/yasal_web_esleme_test.dart test/yasal_metin_kilidi_test.dart`.

Ülke yer tutucuları (`{SUPABASE_ULKE}`, `{SUPABASE_ULKEDE}`): web'de
`_build_legal.py` → `YER_TUTUCULAR` ile (iki sunucunun durumu), uygulamada
bağlı sunucunun ülkesiyle dolar. Veritabanındaki metin ve hash şablon
hâlidir.

Kilit (`test/yasal_web_esleme_test.dart`, CI'da koşar): her HTML başlığına
kaynak md'nin sha256'sı (`sandik-kaynak-sha256`) ve sayfa gövdesinin sha256'sı
(`sandik-govde-sha256`) gömülür. md değişip betik koşulmazsa ya da HTML elle
düzenlenirse test kırılır; uygulama belgelerinde kaynak hash'i
veritabanındaki `govde_hash` ile aynıdır. Ayrıntı:
`lib/services/yasal_metin_katalogu.dart` → "Metin değişince ne yapılır".

Yalnız web'deki diğer md'leri (`COKEZ_VE_DEPOLAMA.md`,
`DATA_DELETION_REQUEST_FORM.md`, `GDPR_NOTICE.md`) değiştirdiysen 1–2 yeter.

## Yapı

```
docs/
├── index.html               → https://yasincirali.github.io/sandikapp/
├── indir/index.html         → /indir/ — indirme kapısı (paylaşım/davet bağlantıları; ?kod=, utm_*)
├── favicon.svg
├── privacy/index.html       → /privacy
├── privacy-en/index.html    → /privacy-en
├── terms/index.html         → /terms
├── terms-en/index.html      → /terms-en
├── legal/kvkk/index.html    → /legal/kvkk
├── legal/gdpr/index.html    → /legal/gdpr
├── legal/acik-riza/index.html → /legal/acik-riza
├── legal/depolama/index.html  → /legal/depolama
├── data-deletion/index.html → /data-deletion   (Play Console zorunlu)
├── data-request/index.html  → /data-request    (GDPR)
├── data/halka_arz.json     → /data/halka_arz.json — halka arz takvimi (uygulama okur)
├── _build_legal.py          → build script
├── faz10-draw-tools-plan.md → dev notu, Pages'te de render edilir ama önemsiz
└── README.md                → bu dosya
```

## Halka arz takvimi verisi (`data/halka_arz.json`)

Uygulamanın "Halka arzlar" ekranı bu dosyayı okur (`HalkaArzService`); ağ yoksa
uygulamaya gömülü kopyaya (`assets/data/halka_arz.json`) düşer.

**Otomatik (2026-10-01'den beri):** `.github/workflows/halka-arz.yml` her gün
09:30 TR'de `tool/halka_arz_guncelle.py`'yi koşar; aşağıdaki 1–3. adımları yapar
(yeni arz, boş alanı dolan kayıt, işlem görmeye başlayan kodun sembol listesine
eklenmesi), 4. adımdaki testi koşar ve değişiklik varsa PR açar — birleştirmek
yeterli. Dolu bir alanın üstüne yazmaz; elle düzeltme kalıcıdır. Elle yol yalnızca
kaynakta olmayan bir düzeltme için:

1. Kaydı ekle/düzelt — her alan kaynaktan (SPK bülteni, KAP, izahname, aracı kurum
   ya da halkarz.com şirket sayfası). Bilinmeyen alan `null`; tahmin yazma. `kaynak`
   zorunlu, `kod` `.IS` eki OLMADAN. Kök ve kayıttaki `guncelleme` = derleme günü.
2. Aynı içeriği `assets/data/halka_arz.json`'a kopyala (iki dosya birebir aynı olmalı).
3. İşlem görmeye başlayan yeni kodu `lib/models/asset_categories.dart` →
   `bist100StocksMap`'e ekle ("Katıldım" kaydı şirket adını oradan alır).
4. `flutter test test/halka_arz_veri_test.dart` — şema, tarih sırası, fiyat > 0 ya
   da null, iki kopyanın eşitliği ve sembol listesi burada kilitli.
5. `main`'e girince Pages yayınlar; uygulama en geç 1 saatte (bellek önbelleği)
   yeni listeyi görür. Uygulama sürümü gerekmez.

## Play Console form değerleri

Yayın sonrası Play Console → App content → Data Safety'e giren URL'ler:
- **Privacy policy URL:** https://yasincirali.github.io/sandikapp/privacy
- **Data deletion URL:** https://yasincirali.github.io/sandikapp/data-deletion

Form referansı: [store_listing/DATA_SAFETY_FORM.md](../store_listing/DATA_SAFETY_FORM.md)
