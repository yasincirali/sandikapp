# sandık tasarım dili ve bileşen standartları

Sürüm 1 · 2026-10-08 · PR #111

> yasin, 2026-10-08: "Tutarlı, smooth animasyonları olan rigid bir app
> istiyoruz; güvenilir ve tutarlı, aynı zamanda göze de hoş gelmeli."

Bu belge **kuraldır**. Yeni ekran ya da bileşen yazılırken önce buraya bakılır.
Her "TEK yol" kuralının bir kilit testi vardır (en altta). Kural değişirse
belge, kod ve test aynı değişiklikte güncellenir. Kodun içindeki yorumlar
gerekçeyi taşır; burada yalnızca karar ve nereye bakılacağı yazar.

---

## 1. İlkeler

1. **Bir iş, bir yol.** Aynı iş (düğme, alt sayfa, onay, yükleniyor, hata)
   uygulamanın her yerinde aynı bileşenle yapılır. Kullanıcı bir kez öğrenir.
2. **Hareket bilgi taşır, süs değildir.** Animasyon "ne değişti, nereden
   nereye gitti" sorusunu yanıtlar. Hızlı başlar, yumuşak oturur. Doğrusal
   hareket ve ease-in yoktur.
3. **Kesinlik.** İstek atan her dokunuş tek uçuştur: kilitlenir, gösterge
   döner, ikinci dokunuş yutulur. Ekran zıplamaz, boy değişmez.
4. **Uydurma yok.** Bilinmeyen sayı gösterilmez. Eski veri eskiliğini
   söyler (ör. kilit widget'ı "13:05 itibarıyla").
5. **Herkes için.** 44 pt dokunma hedefi, açık/koyu temada okunur kontrast,
   "Hareketi azalt" açıkken hareket yok, yazı ×2'de taşma yok.
6. **Sakin yüzey, amber vurgu.** Zemin nötr. Amber yalnız ana eylem, seçim
   ve markadır. Kazanç/kayıp renkleri yalnız para yönü içindir.

## 2. Tokenlar (`lib/theme/sandik.dart`)

| Ne | Kullan | Yasak |
|---|---|---|
| Renk | `context.c.*` (`SandikPalette`, açık + koyu) | `Colors.*`, `Color(0x…)` |
| Yazı | `context.t.*` (DM Sans; sayılar `sandikNumber`) | `fontSize:`, ham `TextStyle(` |
| Boşluk | `SandikSpace` (2 pt adımlı), ekran kenarı `SandikSpace.screenH` | ölçek dışı sayı |
| Köşe | `SandikRadius.sm` 8 / `md` 14 / `lg` 20, sheet `sheetTop` | 12, 24, 28 gibi ara değer |
| Dokunma | `SandikTouch.min` 44 | `minimumSize: Size.zero`, 32 pt kutu |
| Hareket | `SandikMotion` (aşağıda) | `Duration(milliseconds:)`, `Curves.*` |
| Titreşim | `SandikHaptic` | doğrudan `HapticFeedback` |

**Köşe kuralı:** kart, düğme, giriş alanı ve diyalog düğmesi `md` (14).
Çip ve rozet `sm` (8). Sheet, büyük kart ve diyalog kabuğu `lg` (20).

**Renk kuralı:** metin `text90` (başlık) / `text58` (ikincil) / `text36`
(üçüncül) / `text20` (pasif). Amber dolgu üstünde metin `onAmber`. Metin
olarak amber `amberText` (açık temada okunur ton), dolgu olarak `amberFill`.

## 3. Hareket dili (`SandikMotion`)

Süre ve eğri **birlikte** seçilir:

| İş | Süre | Eğri |
|---|---|---|
| Basma geri bildirimi | `press` 110 | `enter` |
| Durum değişimi (çip, sekme, seçim, soluklaşma) | `state` 180 | `enter` / yer değiştiriyorsa `move` |
| Yüzey girişi (sheet, diyalog, açılır bölüm) | `surface` 240 | sheet `cekmece`, diğerleri `enter` |
| Tam ekran modal | `modal` 320 | `cekmece` |
| Gözün izlemesi istenen akış (çubuk, sayaç, imleç) | `flow` 560 | `glide` |
| Çıkış / ters yuva (`reverseCurve`, `switchOutCurve`) | girişten kısa | `exit` |
| Jest sonrası (bırakılan kart, tutamaç) | yay | `yayOtur` / `yayGeri` |

- Süre her zaman `SandikMotion.stateOf(context)` gibi **reduce-motion
  farkındalıklı** yardımcıdan gelir. "Hareketi azalt" açıkken süre sıfırdır.
  Tek istisna diyalog ve tam ekran modal: kayma/ölçek kalkar, kısa solma
  kalır (yön kaybı olmasın diye).
- `spring` ve `elastik` yalnız tek bir küçük göstergede kullanılır. Listede,
  metinde ve yüzeyde kullanılmaz.
- Ara süre yazılmaz (140/150/160 → `state`).

**Hareket bileşenleri:**

| İş | Bileşen |
|---|---|
| Sayfa geçişi | `pushGuarded(context, adaptiveRoute(...))` |
| Alt sayfa | `showSandikSheet` |
| Onay / bilgi / hata diyaloğu | `showSandikConfirm`, `showSandikDialog`, `showAppError/Success/Info` |
| Özel içerikli diyalog | `showSandikGecisli` (aynı geçiş) |
| Aç/kapa bölüm | `SandikAcilir` + `SandikAcilirOk` |
| Satır kalkışı | `KapananSatir` |
| Değer değişim vurgusu | `DegisimVurgusu` |
| Büyük fiyat/tutar metni (hane döner, ₺ ve kuruş geri çekilir) | `ParaMetni` (bayrak `goz_alici`; Ana toplam kartında kullanılmaz) |
| Grafik imleci → büyük fiyat | `ZoomableChart.imlecEtiketi` + `VarlikFiyatBlogu.imlec` (bayrak `goz_alici`; imleçte hane dönmez) |
| Grafikte anlamlı nokta titreşimi | `ZoomableChart.titresimNoktalari` (zirve/dip); nokta başına titreşim yok |
| Satır → ekran başlık uçuşu | `VarlikBaslikHero` (bayrak `varlik_hero_gecisi`) |
| Kaydırmalı kart geçişi | `KaydirmaliGecis` |

## 4. Bileşen standartları (bir iş = bir bileşen)

### Düğmeler
| İş | Bileşen |
|---|---|
| **İstek atan** her düğme | `SandikAsyncButton` (`tur`: `dolu` / `cerceve` / `metin`; diyalog ve kart içi `.kompakt`) |
| İstek atan ikon / satır | `SandikAsyncTap` |
| İstek atmayan ana eylem | `FilledButton` (tema: amber, köşe 14, ~48 pt) |
| İkincil | `OutlinedButton` |
| Metin bağlantısı | `TextButton` |
| Basılabilir yüzey (kart, satır, çip) | `SandikTappable` |
| Çıkış | `SandikLogoutButton`, **yalnız Profil üst çubuğunda** |

**Tek yükleniyor davranışı:** iş sürerken düğme pasif, etiketin yerinde
küçük `CustomLoadingIndicator`, ikinci dokunuş sessizce yutulur, boy
değişmez. Ekran kendi `_busy` bayrağını ve kendi döneni yazmaz. İş düğmeden
geçmeden de başlayabiliyorsa (klavyede "Bitti", OTP 6. hane) ekran bayrağını
`mesgul:` ile düğmeye verir. Onaydan sonra istek atan akışta
`showSandikConfirm(islem: …)`: gösterge onay düğmesinde döner, hata olursa
diyalog açık kalır. Titreşim bileşenin varsayılanıdır (`medium`); çağıran
ezmez.

Bilinçli istisnalar: iyimser güncellemeler (anahtar, oy, kaydırarak silme;
sonuç anında görünür, hata olursa geri alınır), hesap silme tam ekran
perdesi, CSV "Okunuyor…" aşaması, toplu eklemede "n/N kaydediliyor".

### Yüzeyler
| İş | Bileşen |
|---|---|
| Kart | `SandikCard` (`elevated`, `bordered`, `shadowed`) |
| Bölüm başlığı | `SandikSectionHeader` |
| Üst çubuk | `SandikAppBar` |
| 2–4 seçenekli seçici | `SandikSegment` |
| Açma/kapama | `Switch.adaptive` (açık track `amberText`) |
| Sheet tutamacı | `SandikTutamac` |
| Tarih seçici | `pickSandikDate` |
| Giriş alanı | `context.inputDecoration(...)`; dolgu temadan, ekranda `fillColor` yok |

### Durumlar
| Durum | Bileşen |
|---|---|
| İçerik yükleniyor | iskelet (`SandikSkeleton*`, `VarlikIskeleti`); spinner yalnız küçük seçici listede |
| Hata (ekran/kart) | `SandikErrorView` (yeniden dene düğmeli) |
| Boş ("henüz bir şey yok") | `SandikBosDurum` (kapalı sandık + metin) ya da kendi düzeni olan ekranda yalnız ikon yerine `SandikBosIkonu` (bayrak `goz_alici`; kapalıyken eski ikon). Hata boş gibi gösterilmez. |
| Sandık çizimi | `SandikCizimi` (paywall, boş durum, kilometre taşı); zemin `amber`/`yuzey` |
| Hata (eylem sonrası) | `showAppError` |
| Kısa bilgi / geri al | `sandikSnack` |
| Kullanıcıya metin | `friendlyError(e)`; ham `$e` yok |

### Metin ve sayı
Tutar `fmtTRY`, yüzde `fmtPct`, girdi `parseTrNumber`. Hitap "sen".
Çevrilmiş ekranda metin `context.l10n`. Türkçe ek sayıya göre çekilir
(`trSayiAyrilmaEki`: %30'undan, %20'sinden).

### İkonlar
Hisse/fon/kripto satırının başında sembol rozeti (`varlikMonogrami`, bayrak
`goz_alici`); sembolü anlamsız türler (altın, mevduat…) tür ikonunda kalır.
Liste satırının başındaki tür noktası `VarlikRozeti`'dir (takip listesi,
arama): bayrak açıkken aynı rozet, kapalıyken 8pt nokta. Yeni varlık listesi
kendi noktasını çizmez. Varlık sayfası başlığına rozet konmaz (sembol zaten
büyük yazılı).
Material `*_rounded` ailesi. Aynı glif iki ailede yazılmaz. Gezinti oku
`chevron_right_rounded`, rengi `text36`.

## 5. Kilit testleri

| Kural | Test |
|---|---|
| Ham renk, yazı, süre sayısı yalnız azalır | `design_token_leak_test`, `design_token_ratchet_test` |
| Boşluk ölçeği | `spacing_scale_test` |
| Eğrisiz animasyon yok, ters yuvada `exit` | `animasyon_denetimi_test`, `design_token_leak_test` |
| Hareketi azalt kapsamı | `reduce_motion_coverage_test` |
| 44 pt hedef | `touch_target_size_test` |
| Çift dokunma koruması | `navigasyon_korumasi_test` |
| Tek yükleniyor davranışı | `yukleniyor_tek_davranis_test` |
| Tek sheet açıcı, platform diyaloğu yok, düğme köşesi, ölçek dışı süre yok | `tasarim_dili_test` |
| Açık tema kontrastı | `acik_tema_*_kontrast_test` |
| Giriş alanı dolgusu | `input_fill_consistency_test` |
| Çevrilmiş ekranlarda ham metin yok | `l10n_coverage_test` |
| Çıkış yalnız Profil'de | `cikis_tek_yer_test` |

## 6. Sonraki adımlar (denetimde bulundu, henüz yapılmadı)

Öncelik sırasıyla. Her biri yapıldığında buradan silinir ve kilit testi
eklenir.

1. **Boş durum bileşeni.** `SandikBosDurum` / `SandikBosIkonu` geldi
   (2026-10-09, bayrak `goz_alici`); `analiz_notu`, `aylik_rapor`,
   `hafta_ozeti` hatada artık `SandikErrorView` gösteriyor. Kalan:
   `kiyas_karti` hatada hâlâ "veri yok" yazıyor (kart içi küçük yeniden dene
   satırı için yeni metin anahtarı gerekir); bayrak herkese açılınca eski
   ikon dalları silinir.
2. **Tek basma ilkeli.** `SandikTappable` (54), `SandikBasma` (32) ve
   Material dalga (`InkWell`, 26) yan yana. Hedef: hepsi `SandikTappable`.
3. **Sheet içeriği standardı.** Hareket artık tek (`showSandikSheet`), ama
   zemin üç tonda (`surface1`/`surface2`/`background`), 15 sheet'te tutamaç
   yok, başlık iki farklı stilde. Hedef: `showSandikSheet`'e `baslik:` ve
   tutamaç gömülsün, zemin tek ton.
4. **Ortak çip.** Hızlı tutar çipi bile üç ayrı uygulamada. Hedef: `SandikCip`.
5. **Hata kanalı kuralı.** Aynı tür hata bazen diyalog, bazen snack. Kural
   önerisi: kullanıcının girdiği form başarısızsa diyalog, arka plan / tek
   satır eylem başarısızsa snack. Başarı mesajı: yalnız geri alınabilir
   eylemde snack, diğerlerinde sessiz.
6. **Kalan beş ham `AlertDialog`/`Dialog`** (ana ekran, Ayarlar ×2, temettü,
   hızlı düzeltme) marka diyalog kabuğuna taşınsın.
7. **Sayı değişimi hareketi.** Fiyat ve toplamlar anında değişiyor; yalnız
   özet kartında renk vurgusu var. Öneri: canlı fiyat değişiminde
   `DegisimVurgusu` her yerde.
8. **İskelet → içerik geçişi.** Her yerde sert kesme. Öneri: `state`
   süresinde çapraz solma (tek sarmalayıcı).
9. **Sekme içeriği değişimi.** Altı farklı davranış var (anında, solma,
   solma+kayma, liste solması, yay, TabBarView kayması). Tek kural: içerik
   değişimi `state` solma.
10. **"Hareketi azalt" kalan boşlukları:** normal sayfa geçişi (yalnız tam
    ekran modal korumalı), izleme listesinde kaydırarak silme (`Dismissible`
    süreleri), Portföy kaydırma paneli (`Slidable`), karşılaştırma sekmeleri
    (`TabBarView`), tarih seçici.
11. **İkon ailesi:** 72 `*_outlined` kullanımı (23'ü Ayarlar'da). Aynı
    glifin iki ailesi temizlendi (`lock_outline`, `chevron_right`); kalan
    `visibility_off`, `savings`, `notifications_active`, `add_alert` çiftleri.
12. **Üst çubuk:** kayıt ve şifre sıfırlama `CupertinoNavigationBar`
    kullanıyor (başlık 17/w600, geri ikonu farklı). `SandikAppBar`'a taşınsın.
13. **Düğme yüksekliği:** istek atmayan ana düğmeler 36–56 pt arasında
    dağınık. Kural önerisi: tam genişlik ana eylem 52, sheet/kart içi 48.
