# sandık — CPU/GPU ve Uygulama Boyutu Raporu (1 Ekim 2026)

Ölçüm: çalışma ağacı `d6aa360` + o anki commit'lenmemiş değişiklikler, Flutter 3.44.8,
uygulama 1.1.6+7. Paylaşılan sürüm: Claude Docs (aynı içerik, grafikli).

## Özet

Cihazda tek gerçek sorun Ana ekranın boşta hiç durmaması; boyutta ise işlevi bozmadan
alınacak kazanç 1 MB'nin altında kaldığı için büyük bir düşürme hedefi koymaya gerek yok.

- **CPU:** Ana ekran boşta 58 fps çiziyor, emülatörde bir çekirdeğin %64'ü (profile build).
  Kaynak kayan piyasa şeridi (`KayanBant`, `lib/widgets/piyasa_seridi.dart`); sistem
  "hareketi azalt" açıkken aynı ekran %1,5 ve 0 kare. Portföy/Performans boşta sıfır,
  arka plan zamanlayıcıları temiz, etkileşim maliyetleri normal.
- **GPU:** Jank yok (2.566 karede 0 janky, %0,7 kaçan). Raster yükü boşta %33 ve tamamı
  şeride ait; ağır katmanlar (blur) 30 Eylül animasyon denetiminde zaten kaldırılmış.
- **Boyut:** Android indirme tahmini 17,7 MB (27 Eylül CI çıktısı: 13,0), arm64 APK
  34,1 MB. Artışın 3,0 MB'si ekstre motorunun PDFium'u, 1,5 MB'si yeni Dart kodu.
  Boyutun %88'i üç yerel kitaplık; ikisi dokunulamaz, üçüncüsü (PDFium) işlev taşıyor.
- **Sıra:** şeridi dokunuş yokken durdur → Profil yoklamasının `setState` kapsamını
  daralt → ProGuard keep kurallarını cihaz testiyle daralt (0,4–0,8 MB). PDFium kalır.

## Yöntem ve ortam

| Konu | Nasıl ölçüldü | Sınır |
|---|---|---|
| CPU | pixel7_2 emülatörü (x86_64, 4 vCPU, 3 GB, targetSdk 36), **profile** build; `/proc/<pid>/task/*/stat` utime+stime farkı ile iş parçacığı bazında (ui / raster / io) örnekleme: boşta, sekme gezerken, grafik sürüklerken, liste kaydırırken | Emülatör x86; oranlar anlamlı, mutlak yüzdeler telefondan yüksek |
| GPU | Emülatörde GPU host'a geçer, yüzde okunmaz. Vekil: raster iş parçacığı süresi + `dumpsys SurfaceFlinger --timestats` kare/jank sayımı + kod taraması | Gerçek GPU yüzdesi yalnızca cihazda (Android GPU Inspector / Xcode GPU) |
| Boyut (Android) | arm64 release APK içeriği, `flutter build apk --release --target-platform android-arm64 --analyze-size`, `apkanalyzer apk download-size`, `apkanalyzer dex packages` | `--obfuscate` kapalı ölçüldü; CI çıktısı ~%3 daha küçük |
| Boyut (iOS) | Windows'ta derlenemez | Kesin sayı App Store Connect → Build → App Size |

Debug build aynı akışta örneklendi; sıralama aynı, mutlak değerler %30–45 yüksek
(Ana boşta %63, sekme gezme %83, liste %83).

## CPU kullanımı (profile build, tek çekirdek = %100)

| Durum | ui | raster | toplam | kare/sn |
|---|---|---|---|---|
| Ana — boşta | 23,8 | 32,8 | **64,1** | **58** |
| Ana — boşta, hareketi azalt açık | 1,0 | 0,3 | 1,5 | 0 |
| Profil — boşta | 8,4 | 1,5 | 15,6 | 2 |
| Portföy — boşta | 0,2 | 0,0 | 0,4 | 0 |
| Performans — boşta | 0,0 | 0,0 | 0,1 | 0 |
| Sekme gezme (4 sekme ×2) | 26,1 | 15,8 | 56,2 | — |
| Portföy listesi kaydırma | 30,5 | 21,8 | 57,2 | — |
| Performans grafik sürükleme | 44,8 | 2,7 | 46,8 | — |

- **Ana ekran boşta hiç durmuyor.** Ekran farkı (iki ekran görüntüsü, 0,4 sn arayla) yalnızca
  y 318–345 bandında değişiyor: piyasa şeridi. `KayanBant` her karede `Ticker` ile kayma
  hesaplayıp yeniden boyanıyor. Şerit `TickerMode` ve `MediaQuery.disableAnimationsOf`'u
  dinliyor (gizli sekmede ve hareket azaltmada duruyor) ama ön planda sonsuza dek akıyor.
- **Profil %15,6 / 2 fps** sürekli animasyon değil: 8 saniyelik pencereye `ForegroundPoller`'ın
  20 saniyelik bir turu denk geldi; `_load` sonrası `AnimatedSwitcher` geçişi 17 kare
  üretti. Tur başına ~1,2 sn CPU yüksek; yalnızca Profil açıkken ve ön planda.
- **Etkileşim normal.** Grafik sürükleme neredeyse tamamen ui iş parçacığında (fl_chart her
  parmak hareketinde yeniden kurulur); etkileşim süresince olduğu için pil etkisi sınırlı.
- **Arka plan temiz.** Fiyat nabzı (30 sn), ortaklık yoklaması (30 sn), `ForegroundPoller`
  arka planda duruyor; iskelet parıltısı / yükleme işareti / tur nabzı yalnızca kendi
  süresinde çalışıyor ve üçü de hareket azaltmayı dinliyor.

## GPU ve kare süreleri

SurfaceFlinger 75 saniyelik akışta 2.566 kare saydı, 18'i kaçtı (%0,7), uygulama
katmanında janky kare 0. Boşta raster %33: Impeller statik katmanları önbelleklemediği için
şerit yüzünden her karede bütün sahne GPU'ya yeniden gönderiliyor; pil maliyeti budur.

Kod taraması: `BackdropFilter` 1 (yalnızca tur kaplaması), `saveLayer` 2, animasyonsuz
`Opacity` 2, `ClipRRect` 15, `BoxShadow` 32, `RepaintBoundary` 20, `CustomPaint` 20.
Alt menü ve hero karttaki blur 30 Eylül denetiminde kaldırılmış. Android'de Impeller
varsayılan (manifestte geçersiz kılma yok), iOS'ta Metal.

## Uygulama boyutu

| Parça (arm64 release) | APK içinde | Play indirme tahmini |
|---|---|---|
| libapp.so (Dart AOT) | 13,3 MB | 5,3 MB |
| libflutter.so (motor) | 11,6 MB | 5,2 MB |
| libpdfium.so (ekstre PDF okuma, pdfrx native asset) | 6,4 MB | 3,0 MB |
| classes.dex | 2,7 MB | 2,6 MB |
| Diğer (kaynaklar, font, asset, meta) | 1,8 MB | 1,6 MB |
| **Toplam** | **35,8 MB** (dosya; analyze-size 34,1) | **17,7 MB** |

27 Eylül CI arm64 APK'sı: 26,0 MB / indirme 13,0 MB (PDFium yoktu, obfuscate açıktı).

Dart AOT 13 MB: Flutter 4 MB, uygulama kodu 3 MB, flutter_localizations 381 KB,
vector_graphics_compiler 163 KB, fl_chart 152 KB, intl 150 KB, riverpod 92 KB, xml 76 KB,
realtime_client 69 KB. DEX (4,7 MB açık): Google Play Services 1,65 MB (%35), Firebase
508 KB, io.flutter 475 KB, androidx 332 KB. Altı font ağırlığı da kullanımda (w800 86,
w900 7 yerde); Material ikon fontu %98 budanmış (29 KB). Görseller 30 KB.

iOS ölçülmedi. Aynı parçalar: App.framework, Flutter.framework, PDFium xcframework (pdfrx
iOS'ta da gömüyor), Firebase pod'ları, SandikWidget uzantısı.

## Boyut düşürme seçenekleri

| Seçenek | Kazanç (indirme) | Risk | Performans / işlev | Karar |
|---|---|---|---|---|
| ProGuard geniş keep'leri daraltmak (`io.flutter.**`, `com.google.firebase.**`, `com.google.android.gms.**` `{ *; }`); kütüphaneler consumer kurallarını AAR'da taşıyor | 0,4–0,8 MB | Orta (yansıma) | Olumsuz yok. Cihaz testi: Google/Apple girişi, push, Crashlytics, Remote Config, widget, bildirim kanalı | **Yap**, cihaz testiyle |
| Logo SVG → `CustomPainter`/PNG, flutter_svg çıkar | ~0,1 MB | Düşük | Yok | İsteğe bağlı |
| PDFium'u kaldırıp ekstreyi sunucuda ayırmak | 3,0 MB + iOS | Yüksek (gizlilik, ağsız çalışmaz) | İşlev + KVKK metni değişir | Yapma |
| iOS'ta `pdfrx_coregraphics` | iOS PDFium payı | Yüksek: deneysel, Flutter 3.47 ister (bizde 3.44.8), dikey/RTL metin boşlukları | Ekstre tanıma doğruluğu | Ertele; 3.47'de gerçek ekstrelerle kıyasla |
| PDFium'u deferred component'e taşımak | 3,0 MB ilk indirme | Yüksek: native asset deferred modüle taşınamıyor, Play Core bağımlılığı | Ekstre açılışında indirme | Yapma |
| `resConfigs("tr","en")` | APK ~0,3 MB; Play'de ~0 (dil bölmeleri var) | Düşük | Yok | Gerek yok |
| Font ağırlığı azaltma | ~25 KB/ağırlık | Marka | Görsel | Yapma |
| `--obfuscate --split-debug-info` | Zaten CI'da | — | — | Koru |
| flutter_localizations / intl budama | API yok | — | — | — |
| Flutter yükseltme | Belirsiz (±) | Orta | Geniş regresyon | Boyut için yapma |

## Öneriler ve sıra

1. **Piyasa şeridini boşta durdur** (`KayanBant`): dokunuş yokken iki tur (~35 sn) sonra
   `Ticker` dursun, şerit yerinde kalsın; dokunuş, kaydırma, yeni fiyat turu
   (`TazelikRitmi.nabiz`) ya da öne gelişle yeniden aksın. "30 fps'e düşür" alternatifi
   kaydırmayı titretir, tercih edilmez. Tur adımı şeridi anlatıyorsa metni güncelle;
   `piyasa_seridi_test`'e "boşta durur" vakası ekle.
2. **Profil yoklaması:** yanıt aynıysa `setState` çağırma ya da yalnızca değişen alanı kur.
3. **ProGuard daraltma** + yukarıdaki cihaz test listesi; her kalan satıra gerekçe yorumu.
4. **İzleme:** ölçüm betikleri `tool/` altına alınıp `deploy_emulators.sh` sonrasına
   "Ana boşta kare sayısı = 0" kapısı eklenebilir; bulgu widget testinde görünmez.

Sonraki sürümde App Store Connect iOS App Size raporunu bir kez oku.

## Yapılmaması gerekenler

- Şeridi kaldırma ya da kare hızını düşürme (tasarım kararı; sorun kimse bakmazken sürmesi).
- PDFium'u sunucuya taşıma (ekstre cihazdan çıkar); `pdfrx_coregraphics`'e şimdi geçme.
- `isMinifyEnabled` / `isShrinkResources` kapatma, `--obfuscate` kaldırma.
- `extractNativeLibs=true` / `useLegacyPackaging` (kurulum iki kat yer, yavaş açılış).
- ABI atma (Play AAB'den uygun olanı veriyor; eski cihazlar düşer).
- Font ağırlığı / ikon budama ayarıyla oynama; Firebase modülü çıkarma (<1 MB, canlı işlev).
- Boyut gerekçesiyle Flutter yükseltme.

## Ölçüm araçları

Betikler oturumun scratchpad'inde yazıldı (`cpu_olc.py`: fazlı ölçüm; `cpu_ekran.py`:
sekme başına boşta). Özü: `/proc/<pid>/task/*/stat` utime+stime farkı / `CLK_TCK` / süre;
`dumpsys SurfaceFlinger --timestats -enable -clear … -dump` ile uygulama katmanının
`totalFrames` / `jankyFrames`; `settings put global transition_animation_scale 0` Flutter'ın
`disableAnimations` bayrağını açar (kontrol deneyi); `adb emu screenrecord screenshot` +
PIL fark ile değişen bölge; `apkanalyzer apk download-size` Play indirme tahmini.

## Uygulananlar (2 Ekim 2026)

Kullanıcı kararı: akan her animasyon (kaydırma, grafik, slide/click/collapse)
60 fps kalır; kare hızı düşürülmedi. Diğer öneriler uygulandı:

| Öneri | Ne yapıldı | Doğrulama |
|---|---|---|
| Şerit boşta durur | `KayanBant`: 35 sn dokunuşsuz akıştan sonra hız üstel söner (τ 0,6 sn), ticker durur. Dokunuş (`Listener`, jest arenası beklenmez), öne geliş, Ana sekmesine dönüş yeniden akıtır; yeni fiyat turu uyandırmaz (nabız 30 sn < 35 sn, uyandırsaydı seans boyunca durmazdı). Tur adımı metni güncellendi. | Emülatör profile: Ana boşta 40 sn sonra **1 kare / 8 sn, %3,9 CPU** (önce 58 fps, %64); dokunuşta 5 sn'de 232 kare (46 fps) ile akış geri geldi. 6 yeni widget testi. |
| Profil yoklaması | `PendingInvitesNotifier.refresh`: yanıt öncekiyle aynıysa state yazılmaz (JSON kıyası). | `pending_invites_ayni_kayit_test` (4 test). Emülatör: Profil boşta %1,2, 0 kare. |
| ProGuard daraltma | `io.flutter.**`, `com.google.firebase.**`, `com.google.android.gms.**` `{ *; }` keep'leri kaldırıldı; kullanılmayan MPAndroidChart/kotlinx kuralları silindi; dexterous, Crashlytics, uygulama sınıfları kaldı. | DEX 4,55 → 3,17 MB (açık). arm64 APK 35,8 → 35,1 MB; **Play indirme 17,70 → 16,98 MB**. Emülatörde release (debug anahtarla imzalanmış) build: giriş korunarak açıldı, Firebase/Crashlytics init OK, sekmeler, Bildirimler ekranı ve widget yayını çökmedi, yansıma hatası yok. |
| İzleme | `tool/cpu_olc.py` (fazlı ölçüm), `tool/cpu_ekran.py` (sekme başına boşta; `--kapi` Ana'da 40 sn bekleyip 5 fps eşiği). `deploy_emulators.sh` sonuna bloklamayan ek adım (`BOSTA_KAPI=0` ile atlanır). | Kapı bu build'de yeşil. |

**Gerçek cihazda kalan doğrulama (ProGuard):** Google ile giriş, Apple ile giriş, push
bildirimi alma, Remote Config bayrağı, yerel bildirim gösterimi. Emülatörde
oturum açık olduğundan giriş akışları denenmedi.
