# sandık tasarım dili ve bileşen standartları

Sürüm 1.1 · 2026-10-10 (§7 Apple HIG kontrol listesi) · ilk sürüm 2026-10-08, PR #111

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
| Özel içerikli diyalog | `showSandikGecisli` (aynı geçiş) + `SandikDiyalogKabugu` (onay diyaloğuyla aynı kart, klavye payı); ham `AlertDialog`/`Dialog` yazılmaz |
| Aç/kapa bölüm | `SandikAcilir` + `SandikAcilirOk` |
| Satır kalkışı | `KapananSatir` |
| Değer değişim vurgusu | Tek büyük sayı (Ana toplam): `DegisimVurgusu` (metin rengi). Liste satırı tutarı/fiyatı: `DegisimParlamasi` (zemin tonu + tek seferlik ▲/▼; hareketi azalt → yalnız ok). Yakma kuralı ikisinde ortak: `degisimYonu` |
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
| İşi bitince sayfayı kapatan kaydet/onay düğmesi ("oldu" anı) | `SandikAsyncButton(basari: SandikBasariSinyali())` — çağıran başarı yolunda kapatmadan önce `await basari.goster()`: gösterge ✓'ye döner, başarı titreşimi, ✓ `modal` kadar görünür, sonra kapanış |
| İstek atan ikon / satır | `SandikAsyncTap` |
| İstek atmayan ana eylem | `FilledButton` (tema: amber, köşe 14, ~48 pt) |
| İkincil | `OutlinedButton` |
| Metin bağlantısı | `TextButton` |
| Basılabilir yüzey (kart, satır, çip) | `SandikTappable` (solma isteyen yüzey `soluk: true`; eski `SandikBasma` buna katıldı, `sandik_basma_ratchet_test`) |
| Çıkış | `SandikLogoutButton`, **yalnız Profil üst çubuğunda** |

**Tek yükleniyor davranışı:** iş sürerken düğme pasif, etiketin yerinde
küçük `CustomLoadingIndicator`, ikinci dokunuş sessizce yutulur, boy
değişmez. Ekran kendi `_busy` bayrağını ve kendi döneni yazmaz. İş düğmeden
geçmeden de başlayabiliyorsa (klavyede "Bitti", OTP 6. hane) ekran bayrağını
`mesgul:` ile düğmeye verir. Onaydan sonra istek atan akışta
`showSandikConfirm(islem: …)`: gösterge onay düğmesinde döner, hata olursa
diyalog açık kalır. Titreşim bileşenin varsayılanıdır (`medium`); çağıran
ezmez.

**Başarı durumu (Ar-Ge 11 Kas 19:04 #3).** Sayfayı kapatan akışta
(Varlık ekle Kaydet, Hızlı Al/Sat, alarm kur/düzenle, hedef kaydet)
düğme başarıda göstergeden ✓'ye döner (`SandikIkonGecisi.gecis`: `state`
sönüm + 0.9→1 ölçek), `SandikHaptic.basari` titreşir, ✓ `SandikMotion.modal`
kadar görünür ve sayfa ancak sonra kapanır. ✓ evresinde düğme kilitli
(çift dokunma yok); hata yolunda ✓ yok. Hareketi azaltta ✓ geçişsiz belirir,
görünme süresi kalır (bekleme hareket değil, okuma payı). Ekran okuyucu bir
kez "Kaydedildi" duyar. Başarıyı yalnız çağıran bildiği için bayrak değil
sinyal: ekran hatayı kendisi yakalayıp normal döndüğünde ✓ çıkmasın.
Varsayılan kapalı; sayfası açık kalan düğmede kullanılmaz (sonuç zaten
ekranda). Kilit `sandik_async_basari_test`, vitrin `hig_ortak_bilesen_test`.

Bilinçli istisnalar: iyimser güncellemeler (anahtar, oy, kaydırarak silme;
sonuç anında görünür, hata olursa geri alınır), hesap silme tam ekran
perdesi, CSV "Okunuyor…" aşaması, toplu eklemede "n/N kaydediliyor".

### Yüzeyler
| İş | Bileşen |
|---|---|
| Kart | `SandikCard` (`elevated`, `bordered`, `shadowed`) |
| Bölüm başlığı | `SandikSectionHeader` |
| Üst çubuk | `SandikAppBar` |
| Mod değiştiren 2–5 seçenekli seçici (ekranın ne gösterdiği değişir) | `SandikSegment` (ikonlu Ayarlar seçicileri dahil; Material `TabBar`/`ChoiceChip`/elle yazılmış amber hücre yok) |
| Listenin sırasını seçtiren düğme + alt sayfa (ekranın ne gösterdiği değişmez, yalnız sırası) | `SandikSiralamaDugmesi` — `.ikon` (üst çubuk 44 pt kutu, varsayılan dışı seçimde amber; Portföy) / `.etiketli` (ikon + seçili sıranın adı; takip listesi). Sayfayı kendisi açar; seçili satır amber + onay işareti; aynı satır değişiklik yapmaz; ekran kendi sıralama sayfasını yazmaz |
| Liste süzen çip ("Tümü" var) | `SandikFiltreCipi` — tam yuvarlak, 44 pt, seçiliyken amber dolgu + onay işareti |
| Çoklu aç/kapa çip | `GrafikCipi` (çerçeve + onay işareti) |
| Varlık türü süzgeci (sade çipler; elde olan önde, olmayan sonda pasif) | `TurFiltreCipleri` (Performans › Filtre; bayrak `goz_alici`) |
| Açma/kapama | `Switch.adaptive` (açık track `amberText`) |
| Alt sayfa kabuğu (zemin, tutamaç, başlık, klavye payı) | `showSandikSheet` — zemin varsayılanı `surface2`, tutamaç kabukta (varsayılan açık; şeffaf zeminde kapalı), `baslik:` + en fazla bir satır `altMetin:`. Ekran `backgroundColor:`, `SandikTutamac`, kendi başlık stilini yazmaz. Başlığı duruma göre değişen sayfa (alarmda seçilen varlık) `SandikSheetBasligi`'ni içeride kullanır. İçerik yatay payı `SandikSpace.screenH`; birincil düğme en altta, klavye payı kabukta (`isScrollControlled` sayfada). Bilinçli istisnalar: şeffaf zeminli kendi şeklini çizen sayfalar (sinyaller, sembol arama, yenilikler, kilometre taşı, değerlendirme, widget kurulumu, demo kaydı, mod bilgisi), tam sayfa varlık görünümü ve anket (`background`), paywall kutlaması, ekleme seçicileri (`surface1`: satırdaki logo kutusu `surface2`), paylaşım kartı önizlemesi |
| Sheet tutamacı | Kabuk çizer; `SandikTutamac` yalnız şeffaf zeminli sayfanın kendi şeklinin içinde |
| Tarih seçici | `pickSandikDate` |
| İşlem tarihi hızlı seçimi (Bugün · Dün · son iş günü · Başka tarih) | `TarihCipleri` — çipler `SandikFiltreCipi`, satır yatay kayar; son iş günü `BugunService.sonIslemGunu` (dünle aynıysa çıkmaz, takvim kapsamı dışında yok); "Başka tarih" `pickSandikDate` açar |
| Giriş alanı | `context.inputDecoration(...)`; dolgu temadan, ekranda `fillColor` yok |
| Sekme başlığı (içerik altından akar, kaydırınca kenar çizgisi + iOS'ta cam, başlık 0.88'e küçülür) | `SandikKaydirmaBasligi` (Portföy, Performans, Profil; bayrak `goz_alici`). Gövde payı `SandikKaydirmaBasligi.payIle` ile okunur — ekranın kendi `context`'i iskeletin üstündedir, pay 0 çıkar |
| Ana sayfa `SliverAppBar` zemini (aynı cam) | `SandikCamCubukZemini` |
| Cam yüzey (iOS blur; Android, yüksek kontrast ve iOS "Saydamlığı azalt" opak) | `SandikCamYuzey` — yalnız içeriğin altından aktığı çubukta ve yüzen hesap menüsünde |
| Hesap değiştirme (Profil kimlik kartında "ad ⌄", ok yalnız ≥2 hesapta) | `HesapBasligi` → `hesapMenusunuAc` (yüzen cam menü); kaldırma ve uzun basma `hesapSeciciniAc` alt sayfası |
| Varlık sayfası Al/Sat/Temettü | `PozisyonIslemCubugu(yuzen: SandikCam.acik)` — yüzen cam kapsül |
| Satıra uzun bas kısayolu (iOS sistem bağlam menüsü, Android alt sayfa) | `SandikBaglamMenusu` — aynı eylemler satırda/detayda da durur; yıkıcı eylem en sonda, kırmızı |

**Seçici kuralı (2026-10-12).** "Birini seç" üç işe ayrılır ve her işin tek
görünümü vardır: mod değiştirmek kayan segment, süzmek süzme çipi, çoklu
aç/kapa grafik çipi. "Seçili" bilgisi etiketle aynı semantik düğümde okunur
(dışta ayrı `Semantics(selected:)` yok; etiket verilen çipte metin
`ExcludeSemantics`). Segmentlere cam konmaz: arkalarında akan içerik yok,
iOS'ta da segment camın üstünde opak durur. Kilit: `secici_kurali_test`.

**Cam kuralı (2026-10-12).** Cam bir *malzeme*dir, süs değil: yalnız arkasından
içerik akan çubukta (sekme başlığı, yüzen kapsül) ve içeriğin üstünde yüzen
hesap menüsünde (`hesapMenusunuAc`, Profil'de "ad ⌄"; yasin 2026-11-07: "Liquid
Glass yalnız hesap menüsünde") kullanılır. Menü iOS'ta buzlu cam; Android, yüksek
kontrast, "Saydamlığı azalt" ve "Hareketi azalt" açıkken katı `surface2`. Sayı, toplam kart,
sheet ve kart arkasına blur konmaz. Bulanıklık yalnız iOS'ta ve içerik başlığın
altına girdiğinde kurulur; Android, yüksek kontrast ve iOS "Saydamlığı azalt"ta opak ton geçişi. Efektler
kaydırma konumunu izler (zamanlayıcı yok), yerleşimi değiştirmez; "hareketi azalt"
başlık küçülmesini kapatır.

### Durumlar
| Durum | Bileşen |
|---|---|
| İçerik yükleniyor | iskelet (`SandikSkeleton*`, `VarlikIskeleti`); spinner yalnız küçük seçici listede |
| Hata (ekran/kart) | `SandikErrorView` (yeniden dene düğmeli) |
| Boş ("henüz bir şey yok") | `SandikBosDurum` (kapalı sandık + metin) ya da kendi düzeni olan ekranda yalnız ikon yerine `SandikBosIkonu` (bayrak `goz_alici`; kapalıyken eski ikon). Hata boş gibi gösterilmez. |
| Sandık çizimi | `SandikCizimi` (paywall, boş durum, kilometre taşı); zemin `amber`/`yuzey` |
| Kart kart anlatım (hikâye) | `HikayeAkisi` + `HikayeSayfasi` (aylık hikâye ve yıllık özet; sayfa başına tek büyük öğe). |
| Hata (eylem sonrası) | `showAppError` |
| Kısa bilgi / geri al | `sandikSnack` (başarı türü yalnız `onUndo:`/`action:` ile; §6/5) |
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
Material `*_rounded` ailesi. Aynı glif iki ailede yazılmaz. Aç/kapa ikonu
(yıldız, beğeni, göz, onay) `SandikIkonGecisi` ile yerinde değişir; tek
karede atlamaz (2026-10-20). Gezinti oku
`chevron_right_rounded`, rengi `text36`.

## 5. Kilit testleri

| Kural | Test |
|---|---|
| Ham renk, yazı, süre sayısı yalnız azalır | `design_token_leak_test`, `design_token_ratchet_test` |
| Boşluk ölçeği | `spacing_scale_test` |
| Eğrisiz animasyon yok, ters yuvada `exit` | `animasyon_denetimi_test`, `design_token_leak_test` |
| Hareketi azalt kapsamı | `reduce_motion_coverage_test` |
| 44 pt hedef | `touch_target_size_test` (kaynak), `hig_ortak_bilesen_test` (çizilmiş bileşen) |
| Ortak bileşenlerde etiket, kontrast, yazı ×2; etiketsiz `IconButton` yok | `hig_ortak_bilesen_test` |
| Çift dokunma koruması | `navigasyon_korumasi_test` |
| Tek yükleniyor davranışı | `yukleniyor_tek_davranis_test` |
| Düğme başarı durumu (✓, kilit, hareketi azalt) | `sandik_async_basari_test` |
| Başarı snack'ı yalnız geri al / eylem düğmesiyle | `snack_basari_kurali_test` |
| Tek sheet açıcı, platform diyaloğu yok, düğme köşesi, ölçek dışı süre yok | `tasarim_dili_test` |
| Sheet kabuğu: çağrı yerinde zemin ve elle tutamaç yalnız azalır, `showDragHandle` yok | `sheet_standardi_test` |
| Açık tema kontrastı | `acik_tema_*_kontrast_test` |
| Giriş alanı dolgusu | `input_fill_consistency_test` |
| Çevrilmiş ekranlarda ham metin yok | `l10n_coverage_test` |
| Çıkış yalnız Profil'de | `cikis_tek_yer_test` |

## 6. Sonraki adımlar (denetimde bulundu, henüz yapılmadı)

Öncelik sırasıyla. Her biri yapıldığında buradan silinir ve kilit testi
eklenir.

1. **Boş durum bileşeni.** `SandikBosDurum` / `SandikBosIkonu` geldi
   (2026-10-09, bayrak `goz_alici`); `analiz_notu`, `aylik_rapor`,
   `hafta_ozeti` hatada artık `SandikErrorView` gösteriyor; `kiyas_karti`
   hatada kart içi "Tekrar dene" (2026-10-09). Portföy listesi ve dönem
   özetinin "yetersiz geçmiş" kartı da bayrak açıkken `SandikBosDurum`
   çizer (Ar-Ge 5 Kas 22:40 #6). Kendi düzeninde kalanlar: izleme listesi
   (başlık + gövde + öneri çipleri, `SandikBosIkonu`), Zirve (havuz
   ilerleme kartı, boşluk değil bilgi), ana sayfa ilk varlık çağrısı.
   Kalan: bayrak herkese açılınca eski ikon dalları silinir.
2. ~~**Tek basma ilkeli.**~~ Yapıldı (Ar-Ge 5 Kas 21:10 #2 ve 22:40 #3):
   `InkWell` ve `SandikBasma` `SandikTappable`'a taşındı; solma
   `soluk: true`. Kilit `inkwell_ratchet_test`, `sandik_basma_ratchet_test`.
3. ~~**Sheet içeriği standardı.**~~ Kabuk yapıldı (Ar-Ge 5 Kas 22:40 #1,
   6 Kas 08:45 #2): `showSandikSheet` zemini (`surface2`), tutamacı,
   `baslik:`/`altMetin:`'i ve klavye payını tek yerden verir; 51 çağrının
   zemini, 32 elle tutamaç ve 5 Material tutamacı kabuğa taşındı. Kilit
   `sheet_standardi_test` (zemin 18, tutamaç 8; yalnız azalır). Kalan:
   başlığını içeride elle yazan sayfalar adım adım `baslik:`'a ya da
   `SandikSheetBasligi`'ne geçer (taşınanlar: raporlar, radar terimi,
   portföy seçimi kabukta; hedef, alarm, işlem notu, elle fiyat, kısmi
   aktarım içeride).
4. **Ortak çip.** Hızlı doldurma çipi alarmda ve hedefte artık
   `SandikFiltreCipi` (alarm: tek, yatay kayan satır; 6 Kas 08:45 #3).
   Kalan: diğer hızlı tutar çipleri. Hedef: `SandikCip`.
5. **Hata kanalı kuralı.** Aynı tür hata bazen diyalog, bazen snack. Kural
   önerisi: kullanıcının girdiği form başarısızsa diyalog, arka plan / tek
   satır eylem başarısızsa snack. Başarı mesajı: yalnız geri alınabilir
   eylemde snack, diğerlerinde sessiz. Sessizliğin "kaydetti mi?" kuşkusunu
   sayfayı kapatan düğmede ✓ durumu giderir (`SandikAsyncButton(basari:)`,
   Ar-Ge 11 Kas 19:04 #3; §4 Düğmeler). Başarı snack'ı yalnız `onUndo:` ya da
   eylem düğmesiyle (`action:`); sonucu ekranda görünen geri alınamaz eylem
   snack değil `SandikHaptic.basari` alır (Ar-Ge #6: alarm düzenleme,
   özel gösterge, vadesiz oran, kullanıcı adı, çizgi alarmı adı kalktı).
   Bilgi taşıyanlar ve henüz incelenmeyenler gerekçeli izin listesinde
   (`snack_basari_kurali_test`, yalnız azalır).
6. ~~**Kalan ham `AlertDialog`/`Dialog`**~~ Yapıldı (Ar-Ge 5 Kas 22:40 #7):
   Ayarlar şifre adımı `showSandikConfirm(detail:)`; yasal uyarı, temettü ve
   hızlı al/sat `SandikDiyalogKabugu`.
7. **Sayı değişimi hareketi.** Özet kartında renk vurgusu
   (`DegisimVurgusu`); Portföy kart tutarı ve Takip satırı fiyatı
   `DegisimParlamasi` (Ar-Ge 11 Kas 18:04 #2). Kalan: varlık sayfası
   büyük fiyatı, piyasa şeridi.
8. ~~**İskelet → içerik geçişi.**~~ Yapıldı: `SandikYuklemeGecisi` /
   `SandikIcerikGecisi` (~23 dosya); son büyük ada portföy yorumu kartıydı
   (2026-10-20). Yeni yüzey bunları kullanır.
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
12. ~~**Üst çubuk:**~~ Yapıldı (Ar-Ge 5 Kas 22:40 #7): kayıt ve şifre
    sıfırlama `CupertinoNavigationBar`'dan `SandikAppBar`'a geçti.
13. **Düğme yüksekliği:** istek atmayan ana düğmeler 36–56 pt arasında
    dağınık. Kural önerisi: tam genişlik ana eylem 52, sheet/kart içi 48.

## 7. Apple HIG kontrol listesi (her UI değişikliğinde)

> yasin, 2026-10-10: "komponentleri apple'ın hig prensiplerine göre gözden
> geçiriyor muyuz, bişey değiştirirken bunu standart olarak sorgulayalım."

Bir bileşen ya da ekran eklenir/değişirken aşağıdaki liste **tek tek**
sorulur; PR açıklamasına ve yasin'e gösterilen önce/sonra artifact'ine kısa
bir **"HIG kontrolü"** bölümü yazılır: neye bakıldı, ne uygun, neyden bilerek
sapıldı ve neden. Uymayan madde "sonra bakarız" diye geçilmez; ya düzeltilir
ya da sapma gerekçesiyle yazılır. Android'de Material karşılığı bozulmaz
(sütun 3).

| # | Soru | Bizde nasıl | Material karşılığı |
|---|---|---|---|
| 1 | **Dokunma alanı** en az 44×44 pt mi? Görsel küçükse şeffaf pay var mı? | `SandikTouch.min`; `SandikSegment` görsel kabuktan bağımsız 44 | Material düğmeleri 48 dp `padded` alır; ortak bileşenlerde tek eşik 44 (bilinçli) |
| 2 | **Dynamic Type**: yazı ×2'de taşma, kesilme, üst üste binme yok mu? Sabit `height:` metni sıkıştırıyor mu? | `context.t.*`; `TextScaler.noScaling` yasak; `text_scale_overflow_test` | Android "Yazı tipi boyutu" aynı yoldan gelir |
| 3 | **Kontrast**: metin açık ve koyu temada okunur mu (gövde 4.5:1, büyük 3:1)? `text36`/`text20` anlam taşıyan metinde mi? | `text90`/`text58` anlam, `text36` yardımcı, `text20` yalnız pasif; `light_mode_contrast_test` | aynı |
| 4 | **Renk körlüğü**: kazanç/kayıp yalnız renkle mi anlatılıyor? İşaret (+/−), ok ya da metin de var mı? | yön taşıyan yüzde `fmtPctIsaretli` (+%/−%), tutar U+2212 ile; işaret ya da ok renkle birlikte | aynı |
| 5 | **Güvenli alan**: alt düğme, sheet içeriği, tam ekran içerik çentiğe/ana çubuğa girmiyor mu? Klavye açılınca eylem görünür mü? | `SafeArea`, `showSandikSheet`, `MediaQuery.viewInsets` | sistem gezinme çubuğu aynı |
| 6 | **Standart gezinme**: geri kaydırma çalışıyor mu? `PopScope(canPop: false)` yalnız kaydedilmemiş veri/ödeme gibi gerçek risklerde mi? | `pushGuarded(adaptiveRoute)`; özel geri oku yok (`SandikAppBar`) | sistem geri tuşu/jesti aynı yolu izler |
| 7 | **Sheet ve modal**: kısa, bağlamdan kopmayan iş sheet'te mi? Tutamaç ve aşağı kaydırarak kapama var mı? Tam ekran modal yalnız odak isteyen akışta mı? | `showSandikSheet` (tutamaç kabukta); tam ekran `modal` hareketi | Material bottom sheet aynı |
| 8 | **Haptic**: titreşim anlamlı anda mı (seçim, başarı, hata, eşik)? Kaydırma/imleç her adımda titretmiyor mu? | yalnız `SandikHaptic`; grafikte yalnız zirve/dip | Android titreşimi aynı çağrıdan |
| 9 | **Erişilebilirlik etiketi**: yalnız ikonlu düğme/dokunulabilir öğe ne yaptığını söylüyor mu? Grafik/sayı kartı tek cümleyle okunuyor mu? Süs ikon `excludeSemantics` mi? | `IconButton.tooltip`, `SandikTappable.semanticLabel`, `SandikAsyncTap.semanticLabel`, `Semantics(label:)` | TalkBack aynı ağacı okur |
| 10 | **Hareketi azalt**: "Hareketi azalt" açıkken kayma/ölçek kalkıyor mu? | `SandikMotion.*Of(context)`; `reduce_motion_coverage_test` | "Animasyonları kaldır" aynı bayrak |
| 11 | **Sistem kalıbı**: iOS'ta beklenen kontrol mü (anahtar `Switch.adaptive`, tarih `pickSandikDate`, onay `showSandikConfirm`)? Kendi icadımız sistem davranışını bozuyor mu? | §4 tablosu | `.adaptive` Android'de Material çizer |

**Otomatik denetlenen:** 1 (kaynak + çizilmiş ortak bileşen), 2 (ortak
bileşen ve seçili ekranlar ×2), 3 (açık tema ve ortak bileşen kontrastı),
9 (ortak bileşenlerde etiket; etiketsiz `IconButton` yok),
10. Geri kalanı (4–8, 11) incelemeyle sorulur; o yüzden PR'daki "HIG
kontrolü" bölümü atlanmaz.

**Bilinçli sapmalar** (gerekçesiyle; değişirse burası güncellenir):
- Dokunma eşiği platformdan bağımsız 44 (Material 48 dp önerir). Segment ve
  liste satırları 44'te; Material düğmeleri temadan zaten 48 alır.
- Gezinme çubuğu (alt sekme) değişmez — yasin kuralı; HIG tab bar
  kalıbıyla zaten uyumlu.
