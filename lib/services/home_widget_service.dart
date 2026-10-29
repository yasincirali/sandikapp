import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/portfolio_provider.dart';
import '../screens/main_navigation_screen.dart';
import '../screens/portfolio_performance_screen.dart';
import '../theme/sandik.dart';
import '../utils/piyasa_kapali_etiketi.dart';
import '../utils/tr_format.dart';
import 'daily_summary.dart';
import 'deep_link_router.dart';
import 'notification_service.dart';
import 'ozellik_olcumu.dart';
import 'remote_config_service.dart';
import 'retention_tracker.dart';
import 'surface_theme.dart';
import 'crash_reporter.dart';

/// Telefonun ANA EKRANINDAKİ widget'a veri besler (uygulama dışı yüzey).
///
/// Uygulama içi hiçbir şeyi çizmez — yalnızca native widget'ın okuyacağı
/// paylaşımlı depoya yazar ve "kendini yenile" sinyali gönderir.
///
/// ## Neden Live Activity değil
/// Live Activity (ActivityKit) Apple tarafından **başı ve sonu olan** olaylar
/// için tasarlandı: kargo, maç, yolculuk. Sistem 8 saat sonra oturumu
/// kendiliğinden sonlandırır ve sürekli açık duran bir portföy takibi App
/// Review'da reddedilebilir. Ana ekran widget'ında böyle bir kısıt yok ve
/// aynı bilgiyi iki platformda birden verir.
///
/// ## Gizlilik değişmezi
/// Widget verisi **cihaz genelinde** okunabilir bir depoya yazılır (Android'de
/// `SharedPreferences`, iOS'ta App Group). Bu yüzden portföy özetine
/// yalnızca ekranda zaten görünen ÖZET yazılır — varlık listesi, ticker,
/// adet, kullanıcı id'si veya e-posta ASLA yazılmaz. Kullanıcı bakiyeyi
/// gizlediyse ([hideBalance]) tutar da yazılmaz.
///
/// **Tek istisna, bilinçli (2026-10-24):** tek varlık widget'ının seçim
/// listesi ([varlikListesiniYaz], `sandik_varliklar`) varlık ADLARINI ve
/// piyasa fiyatlarını taşır — miktar, tutar, lot/kullanıcı kimliği ve
/// "portföyde mi takipte mi" bilgisi olmadan. Önce yalnız iOS'ta; Android
/// widget'ı gelince (2026-10-25) aynı anahtar, aynı sınırlarla Android'de de
/// yazılır. Gerekçe ve sınırlar `VarlikWidgetService`'te.
///
/// Oturum kapanınca [clear] çağrılmalı: aksi halde çıkış yapan kullanıcının
/// bakiyesi ana ekranda asılı kalır.
class HomeWidgetService {
  HomeWidgetService._();
  static final instance = HomeWidgetService._();

  /// iOS'ta widget ile uygulamanın ortak kabı. Xcode'da App Group olarak
  /// TANIMLANMALI, aksi halde iOS tarafı sessizce boş kalır (Android bundan
  /// etkilenmez).
  static const _appGroupId = 'group.com.sandik.app';

  /// Android widget sağlayıcısının sınıf adı — `AndroidManifest.xml` içindeki
  /// receiver ile birebir aynı olmalı.
  static const _androidProvider = 'SandikWidgetProvider';

  /// iOS widget'ının `kind` değeri (WidgetKit tarafında aynısı yazılır).
  static const _iOSWidgetName = 'SandikWidget';

  /// iOS kilit ekranı widget'ının `kind`'ı (karar 4.1, 2026-09-30).
  ///
  /// Ayrı tür: ana ekran widget'ının görünümüne ve arka planına dokunmadan
  /// kilit ekranı kartını (tek dikdörtgen) tanımlar. `home_widget`
  /// iOS'ta YALNIZ adı verilen türü yeniler (`reloadTimelines(ofKind:)`);
  /// bu yüzden [_requestUpdate] iOS'ta ikinci bir çağrı yapar.
  static const _iOSKilitWidgetName = 'SandikKilitWidget';

  /// iOS tek varlık widget'ının `kind`'ı (`SandikVarlikWidget.swift`).
  ///
  /// Ayrı tür, ayrı yenileme: portföy özeti yazıldığında bu tür yenilenmez
  /// (fiyatları ayrı turda, [varlikListesiniYaz] ile gelir); tema değişince
  /// [applyTheme] üçünü birden yeniler.
  static const iOSVarlikWidgetName = 'SandikVarlikWidget';

  /// iOS vitrin widget'ının `kind`'ı (`SandikVitrinWidget.swift`; orta boy,
  /// üç varlık, Ar-Ge 2026-10-29 §2). Tek varlık widget'ıyla AYNI paketi
  /// ([kVarliklar]) okur; ayrı tür olduğu için ayrı yenilenir — `home_widget`
  /// iOS'ta yalnız adı verilen türü yeniler. Android'de eşi yok (sonra).
  static const iOSVitrinWidgetName = 'SandikVitrinWidget';

  /// iOS mu? Vitrin türünün ek yenileme çağrısı yalnız iOS'ta (Android'de bu
  /// tür yok; adsız çağrı orada hata olurdu). Test dikişi.
  @visibleForTesting
  static bool Function() iOSMu = () => Platform.isIOS;

  /// Android tek varlık widget sağlayıcısının sınıf adı
  /// (`SandikVarlikWidgetProvider.kt`) — `AndroidManifest.xml`'deki receiver
  /// ile birebir aynı. iOS türü gibi ayrı yenilenir.
  static const androidVarlikWidgetName = 'SandikVarlikWidgetProvider';

  /// Tek varlık widget'ının seçim listesi + fiyatları — JSON (`v`, `saat`,
  /// `ogeler`; biçim `varlikWidgetPaketi`). YENİ anahtar: eski anahtarların
  /// hiçbiri ve biçimi değişmedi, eski build'in widget'ları bunu okumaz.
  static const kVarliklar = 'sandik_varliklar';

  /// Tek varlık widget'ının arka plan tazelemesi (`widget-fiyat`, yasin
  /// onayı 2026-10-26): AKTİF sunucunun public URL'si ve anon anahtarı.
  /// İkisi de uygulama paketinde zaten gömülü kamuya açık değerler; oturum
  /// jetonu YAZILMAZ. YENİ anahtarlar: eski hiçbir anahtar değişmedi.
  static const kWidgetApiUrl = 'sandik_widget_api_url';
  static const kWidgetApiAnahtar = 'sandik_widget_api_anahtar';

  /// Widget'ın sunucudan kendi çektiği son fiyatlar (yalnız native taraf
  /// YAZAR; JSON `{sembol: {fiyat, zaman, degisim?}}`). Dart yalnız oturum
  /// kapanınca boşaltır: seçili sembollerin adı sonraki oturuma kalmasın.
  static const kVarlikCanli = 'sandik_varlik_canli';

  // Paylaşımlı depo anahtarları — native taraf bu adlarla okur.
  static const _kTotal = 'sandik_total';
  static const _kChange = 'sandik_change';
  static const _kIsPositive = 'sandik_is_positive';
  static const _kUpdatedAt = 'sandik_updated_at';
  static const _kHasData = 'sandik_has_data';
  static const _kSparkline = 'sandik_sparkline';
  static const _kSparkPoints = 'sandik_spark_points';

  /// Sparkline'ın HAM (0…1 normalize) serisi — virgülle ayrık.
  ///
  /// Android PNG okur (`_kSparkline`), iOS ise SwiftUI ile kendi çizer.
  /// Sebep teknik: PNG `getApplicationSupportDirectory()` altına yazılıyor,
  /// bu da uygulamanın KENDİ kabı; widget uzantısı ayrı sandbox'ta ve o
  /// yolu okuyamaz. Paylaşımlı `UserDefaults` (app group) ise ikisine de
  /// açık, bu yüzden iOS'a görsel değil SAYI gönderilir.
  static const _kSparkSeries = 'sandik_spark_series';
  /// Değişim ölçüldü ama SIFIR mı? Native taraf rengi buna göre nötrler.
  ///
  /// `sandik_is_positive` tek başına yetmez: sıfır bir YÖN taşımaz ama
  /// bool iki değerden birini seçmek zorundadır ve hangisi seçilirse
  /// seçilsin (yeşil ya da kırmızı) olmayan bir hareketi varmış gibi
  /// gösterir. Kullanıcı "Değişim yok" yazısını KIRMIZI görüyordu.
  static const _kIsFlat = 'sandik_is_flat';
  /// Verinin ait olduğu gün — `d MMMM EEEE`. Kilit ekranıyla aynı biçim.
  static const _kDate = 'sandik_date';
  /// Yüzde rozeti metni — tutardan AYRI alan.
  ///
  /// Kilit ekranı ikisini ayrı öğe olarak gösteriyor (tutar büyük, yüzde
  /// altında rozet). Tek bir metinde birleştirmek widget'ı ondan
  /// ayrıştırıyordu.
  static const _kChangePct = 'sandik_change_pct';
  /// BIST işlem saatleri içinde miyiz? Canlılık noktasının rengini sürer.
  static const _kMarketOpen = 'sandik_market_open';

  /// Portföy yalnızca borsa ürünü mü (hisse/fon/BES)? "Piyasa kapalı"
  /// ibaresi ve gri nokta YALNIZCA o zaman (kullanıcı kararı 2026-10-01,
  /// bkz. `yalnizcaBorsa`). [_kMarketOpen] BIST seansını anlatmaya devam
  /// eder — iOS kilit widget'ının kapanış geri sayımı ona bakar (seans
  /// çubuğu 2026-10-01'de kaldırıldı).
  /// Native taraf anahtar yoksa `true` varsayar (eski davranış).
  static const _kYalnizBorsa = 'sandik_yalniz_borsa';

  /// Göz alıcılık (Remote Config `goz_alici`, 2026-10-09): widget'taki
  /// toplamda ₺ ve kuruş küçük — uygulamadaki büyük fiyatla aynı yazım.
  /// Native taraf anahtar yoksa `false` varsayar: eski sürümün yazdığı
  /// veride bugünkü görünüm.
  static const _kGozAlici = 'sandik_goz_alici';

  /// Uygulamanın SEÇİLİ teması açık mı? Native taraf paleti buna göre seçer.
  ///
  /// Android widget'ı bugüne kadar `res/values` ↔ `values-night` ile
  /// **sistemin** karanlık modunu izliyordu; uygulamanın tercihini değil.
  /// Kullanıcı uygulamayı "Açık" yapıp cihazı koyu bıraktığında widget koyu
  /// kalıyordu — kullanıcı bulgusu buydu. Bu bayrak tercihi çözülmüş hâliyle
  /// taşır ("Sistem" seçiliyse cihazın görünümüne çözülür).
  static const _kIsLightTheme = 'sandik_is_light_theme';

  // ── Kilit ekranı widget'ı (karar 4.1 / 4.3 / 4.4 / 4.5) ──────────────────

  /// Kilit ekranında TUTAR gösterilsin mi — Canlı Etkinlik'in "Kilit
  /// ekranında tutar göster" tercihinin AYNISI (karar 4.4: iki kilit ekranı
  /// yüzeyi tek ayar). Varsayılan kapalı: kilit ekranı telefon açılmadan
  /// görülür.
  static const _kLockAmounts = 'sandik_lock_amounts';

  /// Kısa, işaretli günlük yüzde: `+%0,42` / `−%0,06` / `%0,00`; ölçüm
  /// yoksa `—`. `_kChangePct`'teki " Günlük" soneki kilit ekranına sığmaz.
  /// Biçim `fmtPctIsaretli` — uygulamanın tek işaretli yüzde kaynağı.
  static const _kLockPct = 'sandik_lock_pct';

  /// Bakiye gizli mi (karar 4.5): kilit ekranı gizliyken yüzdeyi de
  /// göstermez. Ana ekran widget'ı bunu maskeli metinden anlıyor; kilit
  /// ekranı açık bir bayrakla karar verir.
  static const _kHidden = 'sandik_hidden';

  /// Kilit widget'ı rakamı Canlı Etkinlik'ten mi okusun (2026-10-03,
  /// yasin: "Canlı aktivite, dinamik ada, kilit ekranı widget, performans
  /// günlük aynı değeri göstermeli ve senkron olmalı").
  ///
  /// Uygulama kapalıyken widget'ı yalnız bu yazım besliyordu ve son
  /// rakamda donuyordu; Canlı Etkinlik ise sunucudan dakikada bir ileri
  /// taşınıyor (`push-live-activity`, `canli_etkinlik_dakikalik`). Açık
  /// bir etkinlik varken widget onun son içeriğini okur — iki kilit
  /// ekranı yüzeyi aynı push'tan beslenir. Aynı Remote Config bayrağına
  /// bağlı: kapalıyken widget bugünkü gibi yalnız bu yazımı okur.
  static const _kCanliEtkinligiIzle = 'sandik_lock_follow_la';

  /// [_kLockAmounts]'ın değeri — servis Riverpod okuyamaz; `main.dart`
  /// portföy dinleyicisi ve Ayarlar anahtarı buraya yazar (Canlı Etkinlik'teki
  /// `showAmountsOnLockScreen` ile aynı desen).
  bool lockScreenAmounts = false;

  /// [_kCanliEtkinligiIzle]'nin değeri — `main.dart` Remote Config'ten
  /// (`canli_etkinlik_dakikalik`) atar, Canlı Etkinlik'teki
  /// `dakikalikGuncelleme` ile aynı anda.
  bool canliEtkinligiIzle = false;

  /// Uygulamanın çözülmüş tema tercihi — tek kaynaktan OKUNUR.
  ///
  /// `LiveActivityService.themeIsLight` ile aynı desen: karar
  /// [SurfaceTheme] içinde yaşar, diske yazılır ve yalnızca meşru
  /// tetikleyicilerle değişir. Eskiden dışarıdan itilen bir alandı;
  /// itişi kaçıran bir kod yolu (ya da henüz itilmemiş yeni bir süreç)
  /// widget'ı `false` = KOYU bırakıyordu.
  bool get themeIsLight => SurfaceTheme.instance.isLight;

  /// Sparkline PNG'sinin renkleri — uygulamanın seçili temasına göre.
  ///
  /// Bu grafik Dart tarafında rasterize ediliyor, yani XML kaynaklarından
  /// beslenmiyor. Eskiden sabit dark tonlardı ve açık temada widget'ın kendi
  /// renkleriyle ayrışıyordu: XML `widget_gain` `#0F7A4E` iken çizgi
  /// `#3DB77F` çiziliyordu.
  ///
  /// Değerler KOPYALANMAZ, doğrudan `SandikPalette`'ten okunur. Elle senkron
  /// tutulan ikinci bir kopya, tam da burada yaşanan ayrışmanın kaynağıydı —
  /// ve `design_token_leak_test` bu sınıf sızıntıyı zaten yasaklıyor.
  SandikPalette get _sparkPalette =>
      themeIsLight ? SandikPalette.light : SandikPalette.dark;

  /// Widget dokunuşunun taşıdığı URI.
  ///
  /// Kotlin tarafındaki `SandikWidgetProvider.WIDGET_CLICK_URI` ile BİREBİR
  /// aynı olmalı — atıf bu eşleşmeye dayanıyor. Değeri değiştirirken iki
  /// dosya birlikte güncellenmeli.
  static const widgetClickUri = 'sandik://widget/home?homeWidget=1';

  StreamSubscription<Uri?>? _clickSub;
  bool _clickAttributionStarted = false;

  /// Uygulama widget'a dokunularak mı açıldı?
  ///
  /// Soğuk açılışta BİR KEZ, açılış kaynağı kaydedilmeden önce sorulmalı:
  /// önce `cold` yazıp sonra `widget` eklemek aynı açılışı iki kez sayardı.
  Future<bool> launchedFromWidget() async {
    try {
      await _ensureInit();
      final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (uri == null) return false;
      await _dokunusuSay(uri);
      // Dokunuş performans ekranına (günlük grafik) götürür. İstek
      // `MainNavigationScreen` daha kurulmadan yazılabilir; ekran
      // `initState`'te mevcut değeri de okuduğu için kaybolmaz.
      _sekmeyeYonlendir(uri);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('launchedFromWidget failed: $e');
      return false;
    }
  }

  /// Uygulama AÇIKKEN widget'a dokunulmasını dinler.
  ///
  /// [launchedFromWidget] yalnızca soğuk açılışı kapsar; kullanıcı uygulamayı
  /// arka plana alıp widget'tan geri döndüğünde olay bu akıştan gelir.
  Future<void> startClickAttribution() async {
    if (_clickAttributionStarted) return;
    _clickAttributionStarted = true;
    try {
      await _ensureInit();
      _clickSub = HomeWidget.widgetClicked.listen((uri) {
        if (uri == null) return;
        CrashReporter.arkaPlan(_dokunusuSay(uri),
            reason: 'home_widget_service.recordWidgetTap');
        CrashReporter.arkaPlan(RetentionTracker.instance.recordLaunch(source: 'widget'), reason: 'home_widget_service.RetentionTracker.recordLaunch');
        // Uygulama AÇIKKEN gelen dokunuş: yeni ekran push EDİLMEZ, yalnızca
        // sekme değişir. Push etmek, kullanıcı zaten uygulamadayken üst üste
        // yığılan kopyalar üretirdi.
        _sekmeyeYonlendir(uri);
      });
    } catch (e) {
      // Widget atfı ikincil bir ölçüm — kurulamazsa uygulama etkilenmez.
      if (kDebugMode) debugPrint('startClickAttribution failed: $e');
    }
  }

  /// Dokunuşu ölçer: yüzey host'tan ([DeepLinkRouter.widgetYuzeyi]); tek
  /// varlık widget'ı ayrıca özellik kullanımı olarak sayılır (günde bir).
  Future<void> _dokunusuSay(Uri uri) async {
    final yuzey = DeepLinkRouter.widgetYuzeyi(uri);
    if (yuzey == 'varlik_widget') OzellikOlcumu.say(Ozellik.varlikWidget);
    await RetentionTracker.instance.recordWidgetTap(surface: yuzey);
  }

  /// Dokunuşu hedef sekmeye çevirir.
  ///
  /// Eşleme kararı [DeepLinkRouter]'da — bu metot yalnızca UYGULAR.
  /// Tanınmayan URI'de hiçbir şey yapılmaz: uygulama yine açılır, sekme
  /// değişmez.
  void _sekmeyeYonlendir(Uri uri) {
    // Varlık bağlantısı sekmeden önce: `sandik://asset/<id>` doğrudan
    // detay ekranını açar (push bildirimiyle aynı yol).
    final varlik = DeepLinkRouter.hedefVarlikId(uri);
    if (varlik != null) {
      NotificationService.instance.openAssetPerformance(varlik);
      return;
    }
    final hedef = DeepLinkRouter.hedefSekme(uri);
    if (hedef == null) return;
    // GÜNLÜK isteği sekme isteğinden ÖNCE yazılır.
    //
    // Sıra önemli: soğuk açılışta performans ekranı sekme isteği işlenirken
    // kuruluyor ve `initState` bekleyen günlük isteğini o anda okuyor. Sonra
    // yazsaydık ekran zaten kurulmuş, dinleyici de henüz bağlanmamış olurdu —
    // istek sessizce düşerdi.
    if (DeepLinkRouter.gunlukGorunumIster(uri)) {
      PortfolioPerformanceScreen.gunlukIstegi.value = true;
    }
    MainNavigationScreen.sekmeIstegi.value = hedef;
  }

  /// Testler için aboneliği bırakır.
  Future<void> stopClickAttribution() async {
    await _clickSub?.cancel();
    _clickSub = null;
    _clickAttributionStarted = false;
  }

  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await HomeWidget.setAppGroupId(_appGroupId);
    _initialized = true;
  }

  /// Portföy özetini widget'a yaz ve yenile.
  ///
  /// [intraday] verilirse gün içi sparkline da çizilir (bkz. [_renderSparkline]).
  /// Sessizce başarısız olur: ana ekran widget'ı ikincil bir yüzeydir,
  /// yazma hatası uygulamanın akışını bozmamalı.
  Future<void> update(
    PortfolioState state, {
    required bool hideBalance,
    Map<int, double>? intraday,
  }) {
    // Yazmalar SIRAYA alınır.
    //
    // Düzeltilen hata: açılışta portföy arka arkaya yayınlanıyor ve iki
    // `update` iç içe çalışıyordu. Biri grafikli (PNG yolunu yazan), diğeri
    // grafiksiz (`spark_points = 0` yazan) olduğu için prefs tutarsız
    // kalıyordu: yol dolu ama nokta sayısı sıfır → native taraf grafiği
    // gizliyordu. Zincirleme, her yazmanın bir öncekini tamamlanmış
    // görmesini garanti eder.
    _writeQueue = _writeQueue.then((_) => _update(
          state,
          hideBalance: hideBalance,
          intraday: intraday,
        ));
    return _writeQueue;
  }

  Future<void> _writeQueue = Future.value();

  Future<void> _update(
    PortfolioState state, {
    required bool hideBalance,
    Map<int, double>? intraday,
  }) async {
    try {
      await _ensureInit();
      _toplanan = <String, Object?>{};

      // Tema, bakiye gizli olsun olmasın YAZILIR: gizli durumda da widget
      // çiziliyor ve o da uygulamanın temasını izlemeli.
      await _yaz<bool>(_kIsLightTheme, themeIsLight);
      await _yaz<bool>(_kLockAmounts, lockScreenAmounts);
      await _yaz<bool>(
          _kCanliEtkinligiIzle, canliEtkinligiIzle);
      // Gizliyken de yazılır: gizli widget da "Piyasa kapalı" satırı çizer.
      final yalnizBorsa = yalnizcaBorsaVarliklardan(state.assets);
      await _yaz<bool>(_kYalnizBorsa, yalnizBorsa);
      await _yaz<bool>(
          _kGozAlici, RemoteConfigService.instance.gozAlici);

      if (hideBalance) {
        // Kullanıcı bakiyeyi uygulama içinde gizlemişse ana ekranda
        // göstermek o tercihi delerdi — omzunun üstünden bakan biri için
        // widget uygulamadan daha kolay görünür.
        await _writeHidden();
      } else {
        final tryFmt = tryFormatter(digits: 0);

        // Özet ORTAK katmandan gelir — kilit ekranıyla (Live Activity)
        // birebir aynı hesap. İki yüzey ayrı ayrı hesaplarken üç yerde
        // ayrışmıştı: burada ömürlük getiri "günlük" diye gösteriliyor,
        // satış lot'ları toplama geri ekleniyor ve grafik sıfır slotlarla
        // düzleştiriliyordu.
        final summary = DailySummary.from(
          state: state,
          series: intraday ?? const {},
          now: DateTime.now(),
          // Çizilen seans bugün olmayabilir (hafta sonu → Cuma). Uygulamanın
          // günlük grafiği de ekseni bu güne kurar.
          seansGunu: IntradaySeriesCache.instance.seansGunu,
        );

        // Yön GÜNLÜK değişimden okunur, ömürlük getiriden değil.
        // Ölçüm yoksa ya da sıfırsa nötr kabul edilir.
        final isPos = (summary.changeTRY ?? 0) >= 0;

        await _yaz<String>(
            _kTotal, tryFmt.format(summary.totalTRY));
        await _yaz<String>(
          _kChange,
          // Üç ayrı durum — kilit ekranıyla AYNI kural
          // (bkz. LiveActivityService._payload):
          //   ölçüm yok   → "—"      (uydurma sıfır yazılmaz)
          //   ölçüm sıfır → "₺0"     (işaretSİZ; sıfır bir yön taşımaz ve
          //                 kırmızı bir "-₺0" kayıp olarak okunur)
          //   ölçüm var   → işaretli tutar
          //
          // Yüzde artık BURAYA girmez: ayrı bir rozet alanına yazılır
          // (`_kChangePct`), kilit ekranındaki düzenle aynı.
          !summary.hasChange
              ? '—'
              : summary.isFlat
                  ? tryFmt.format(0)
                  : '${isPos ? '+' : '-'}'
                      '${tryFmt.format(summary.changeTRY!.abs())}',
        );
        await _yaz<bool>(_kIsPositive, isPos);
        // Nötr durum: ölçüm yok ya da ölçüm sıfır. İkisinde de kâr/zarar
        // rengi basılmamalı.
        await _yaz<bool>(
            _kIsFlat, !summary.hasChange || summary.isFlat);
        // Yüzde rozeti — tutardan ayrı alan (kilit ekranıyla aynı düzen).
        await _yaz<String>(
          _kChangePct,
          !summary.hasChange || summary.isFlat
              ? ''
              : '${isPos ? '+' : '-'}'
                  '${fmtPct(summary.changePct!.abs(), digits: 2)} Günlük',
        );
        await _yaz<bool>(_kHasData, true);
        await _yaz<bool>(_kHidden, false);
        await _yaz<String>(
            _kLockPct,
            summary.hasChange
                ? fmtPctIsaretli(summary.changePct!, digits: 2)
                : '—');
        // Tarih — kilit ekranıyla AYNI biçim. Widget günlerce ekranda
        // durur; rakamın hangi güne ait olduğu okunabilmeli.
        await _yaz<String>(
            _kDate, DateFormat('d MMMM EEEE', 'tr_TR').format(DateTime.now()));
        // Piyasa durumu — banner "Piyasa kapalı" derse kullanıcı rakamın
        // neden değişmediğini bilir. Kilit ekranıyla AYNI kural.
        await _yaz<bool>(
            _kMarketOpen, DailySummary.isMarketOpen(DateTime.now()));
        await _yaz<String>(
            _kUpdatedAt, DateFormat('HH:mm', 'tr_TR').format(DateTime.now()));

        // Gün içi sparkline — grafik PNG olarak çizilip yola yazılır.
        // RemoteViews custom view çizemez, bu yüzden native taraf hazır
        // bir görsel alır.
        //
        // Ham seri DEĞİL, özetin işlenmiş serisi çizilir: sıfır slotlar
        // atılmış ve son nokta canlı toplama sabitlenmiştir. Aksi halde
        // grafik düz çizgiye ezilir ve "nabız" noktası 15 dakika geride
        // kalırdı.
        await _writeSparkline(
          summary.sparkline,
          isPos: isPos,
          // Hareket yoksa çizgi de nötr çizilir: düz kırmızı bir çizgi
          // "bugün kaybettim" diye okunur.
          isFlat: !summary.hasChange || summary.isFlat,
          // Karışık portföyde nokta canlı kalır: borsa kapalı olsa da
          // altın/döviz/kripto rakamı hareket ettiriyor.
          isMarketOpen:
              DailySummary.isMarketOpen(DateTime.now()) || !yalnizBorsa,
        );
      }

      // Yalnız DEĞİŞEN anahtarlar yazılır; hiçbiri değişmediyse widget
      // yenilenmez (bkz. [_toplanan]).
      final toplanan = _toplanan!;
      _toplanan = null;
      final degisen = <String, Object?>{
        for (final e in toplanan.entries)
          if (!_sonYazilan.containsKey(e.key) ||
              _sonYazilan[e.key] != e.value)
            e.key: e.value,
      };
      if (degisen.isEmpty) return;
      for (final e in degisen.entries) {
        await HomeWidget.saveWidgetData(e.key, e.value);
        _sonYazilan[e.key] = e.value;
      }
      await _requestUpdate();
    } catch (e) {
      // Yarım kalan yazımdan sonra cihazdaki değerler bilinmiyor: bir
      // sonraki tur her anahtarı baştan yazsın.
      _toplanan = null;
      _sonYazilan.clear();
      if (kDebugMode) debugPrint('HomeWidget update failed: $e');
    }
  }

  /// Son çizilen sparkline PNG'sinin girdileri ve yolu.
  String? _sonPngAnahtari;
  String? _sonPngYolu;

  /// Sparkline PNG'si çizilsin mi — yalnız Android okur. Test dikişi.
  @visibleForTesting
  static bool Function() pngCizilsinMi = () => !Platform.isIOS;
  bool get _pngCiz => pngCizilsinMi();

  /// Bu turda yazılacak anahtarlar — [_update] süresince dolu.
  ///
  /// ## Neden (kaynak kullanımı denetimi, 2026-10-12)
  /// Portföy dinleyicisi her yayında (ön planda en az 30 sn'de bir) bu
  /// servisi çağırıyor. Rakam değişmese de her turda 20 kanal çağrısı,
  /// bir PNG çizimi ve iOS'ta iki zaman çizelgesi yenilemesi yapılıyordu
  /// (test ortamında tur başına 14–20 ms). Değerler artık önce burada
  /// toplanır, cihazdaki son değerle kıyaslanır ve yalnız farklı olanlar
  /// yazılır.
  ///
  /// **Tazelik kaybı yok:** güncelleme saati (`HH:mm`) ve tarih de
  /// kıyaslanan değerler arasında; rakam aynı kalsa bile dakika dönünce
  /// saat yazılır ve widget yenilenir. Ekranda görünen her alan eskisi
  /// kadar taze, yalnızca aynı değerin üstüne aynı değer yazılmıyor.
  Map<String, Object?>? _toplanan;

  /// Cihazın paylaşımlı deposuna bu süreçte en son yazılan değerler.
  /// Süreç yeniden başlayınca boştur: ilk tur her şeyi yazar.
  final Map<String, Object?> _sonYazilan = {};

  /// Testler için: her test yeni (boş) bir sahte depo kurar; kıyas belleği
  /// de sıfırlanmalı ki ilk yazım eksiksiz olsun (gerçekte depo yalnızca
  /// `clear()` ile boşalır, o da belleği sıfırlıyor).
  @visibleForTesting
  void kiyasBelleginiSifirla() {
    _sonYazilan.clear();
    _sonPngAnahtari = null;
    _sonPngYolu = null;
  }

  /// [_update] içindeki yazım: toplama açıksa biriktirir, değilse yazar.
  Future<void> _yaz<T>(String id, T? data) async {
    final t = _toplanan;
    if (t != null) {
      t[id] = data;
      return;
    }
    await HomeWidget.saveWidgetData<T>(id, data);
    _sonYazilan[id] = data;
  }

  /// Grafiği de tazeleyen sarmalayıcı — portföy dinleyicisinin çağırdığı yol.
  ///
  /// **Neden ayrı metot:** portföy state'i çok sık değişir (her fiyat tick'i,
  /// her ekleme). Gün içi seriyi her seferinde çekmek gereksiz ağ turu demek.
  /// Burada grafik en fazla [_chartMinInterval]'da bir yenilenir; tutar ve
  /// yüzde ise HER değişimde güncellenir (ucuz, yerel hesap).
  ///
  /// Grafik çekimi başarısız olursa özet yine yazılır — sayı grafikten
  /// önemlidir.
  Future<void> updateWithChart(
    PortfolioState state, {
    required bool hideBalance,
  }) async {
    // Seri ORTAK önbellekten gelir — Live Activity ile aynı kaynak.
    //
    // İki yüzey ayrı ayrı önbelleklerse aynı veri için iki ağ turu atılır
    // ve — daha kötüsü — farklı anlarda tazelenip aynı anda FARKLI rakam
    // gösterirler. Kullanıcı kilit ekranıyla ana ekranı yan yana gördüğünde
    // bu doğrudan "uygulama bozuk" demektir.
    //
    // Önbellek gün dönümünde koşulsuz düşer ve damgayı yalnızca başarılı
    // fetch'te atar; ikisi de burada elle tekrarlanmaz.
    //
    // Bakiye gizliyken grafik zaten çizilmeyecek; boşuna ağ turu atma.
    final series = hideBalance
        ? const <int, double>{}
        : await IntradaySeriesCache.instance.get(state);

    await update(state, hideBalance: hideBalance, intraday: series);
  }

  /// Gün içi seriyi sparkline PNG'sine çevirip yolunu paylaşımlı depoya yazar.
  ///
  /// **Neden PNG:** Android `RemoteViews` yalnızca sınırlı bir view kümesini
  /// destekler; custom `Canvas` çizimi yapılamaz. Grafiği burada rasterize
  /// edip `ImageView`'a dosya yolu vermek tek yol.
  ///
  /// **Neden `dart:ui` (widget ağacı değil):** `HomeWidget.renderFlutterWidget`
  /// bir `RepaintBoundary` kurup ağacı pump etmeyi gerektirir; bu çağrı
  /// arka planda / uygulama kapanırken güvenli değil. `PictureRecorder` saf
  /// çizimdir, ağaca dokunmaz.
  ///
  /// Nokta sayısı [_kSparkPoints] ile ayrıca yazılır: native taraf veri
  /// yetersizse grafiği gizleyip yerine boşluk bırakır (tek noktalı "çizgi"
  /// yanıltıcı olurdu).
  Future<void> _writeSparkline(
    List<double> values, {
    required bool isPos,
    bool isFlat = false,
    bool isMarketOpen = true,
  }) async {
    // İki noktadan az veri çizgi oluşturmaz.
    if (values.length < 2) {
      await _yaz<int>(_kSparkPoints, values.length);
      // Seri de temizlenir: kalsaydı iOS widget'ı bugün ölçüm yokken
      // DÜNÜN eğrisini çizmeye devam ederdi.
      await _yaz<String>(_kSparkSeries, '');
      return;
    }

    // PNG yalnız Android içindir: iOS widget'ı eğriyi aşağıdaki sayı
    // dizisinden kendisi çizer ve PNG'yi hiç okumaz (`SandikHomeWidget
    // .swift`, kendi kabından uygulamanın dosyasını göremez). iOS'ta her
    // turda 960×180 çizip kodlamak saf israftı (denetim 2026-10-12).
    //
    // Android'de de girdiler aynıysa yeniden çizilmez: çizim yalnızca
    // seriye, yöne ve temaya bağlı; aynı girdi aynı PNG'yi üretir.
    if (_pngCiz) {
      final anahtar = '${values.join(',')}|$isPos|$isFlat|$isMarketOpen|'
          '$themeIsLight';
      final onceki = _sonPngYolu;
      final String? path;
      if (anahtar == _sonPngAnahtari &&
          onceki != null &&
          File(onceki).existsSync()) {
        path = onceki;
      } else {
        path = await _renderSparkline(
          values,
          isPos: isPos,
          isFlat: isFlat,
          isMarketOpen: isMarketOpen,
        );
        _sonPngAnahtari = path == null ? null : anahtar;
        _sonPngYolu = path;
        // Dosya adı sabit: yol metni aynı kalsa da içerik değişti. Yol bu
        // turda yeniden yazılsın ki widget yenilensin.
        if (path != null) _sonYazilan.remove(_kSparkline);
      }
      if (path != null) {
        await _yaz<String>(_kSparkline, path);
        await _yaz<int>(_kSparkPoints, values.length);
      }
    } else {
      await _yaz<int>(_kSparkPoints, values.length);
    }

    // iOS için ham seri. Normalize ORTAK katmanda yapılır ki kilit ekranı
    // ile ana ekran widget'ı aynı portföy için aynı eğriyi çizsin.
    // Üç ondalık yeter: seri 0…1 aralığında ve çizim birkaç yüz piksel
    // genişliğinde — daha fazlası yalnızca anahtarı şişirir.
    final seri = DailySummary.normalizeForSparkline(values);
    await _yaz<String>(
      _kSparkSeries,
      seri.map((v) => v.toStringAsFixed(3)).join(','),
    );
  }

  /// Sparkline'ı çizip PNG olarak diske yazar; dosya yolunu döner.
  ///
  /// Çizim marka diline uyar: kazançta yeşil, kayıpta kırmızı çizgi; altında
  /// aynı renkten dikey gradient dolgu ve son noktada bir "canlı" işareti.
  /// Widget'ın kendisi opak bir kart olduğu için arka plan şeffaf bırakılır.
  Future<String?> _renderSparkline(
    List<double> values, {
    required bool isPos,
    bool isFlat = false,
    bool isMarketOpen = true,
  }) async {
    try {
      // Piksel ölçüsü: widget dar bir şerit; 3x yoğunlukta çizip
      // ImageView'a bırakıyoruz (ölçekleme yumuşasın).
      //
      // **Oran ImageView ile eşleşmeli.** ImageView `fitXY` ile ölçekliyor,
      // yani tuval oranı hedefe uymazsa görüntü YATAYDA EZİLİR. 480×200
      // (2.4:1) çizip ~340dp×64dp (~5.3:1) alana basınca nabız noktası
      // daireden ovale dönüyordu. Tuval hedefin oranında tutulur; nokta
      // yarıçapları da bu ölçeğe göre seçilmiştir.
      const w = 960.0;
      const h = 180.0;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));


      // Eksen sınırları OKUNABİLİR (yuvarlak) değerlere oturtulur.
      //
      // Hesap ortak katmanda — kilit ekranı da aynı fonksiyonu kullanır,
      // yoksa iki yüzey aynı portföy için farklı eksen gösterirdi.
      // Sınırlar veriyi her zaman kapsar ve asgari bant kuralı orada
      // uygulanır (bkz. `DailySummary.niceAxisBounds`).
      //
      // Düz seride de aynı fonksiyon çalışır: asgari bant devreye girer
      // ve iki etiket farklı rakam gösterir.
      final bounds = DailySummary.niceAxisBounds(values);
      final axisMin = bounds.min;
      final axisMax = bounds.max;

      final span = (axisMax - axisMin).abs() < 1e-9 ? 1.0 : axisMax - axisMin;
      final minV = axisMin;

      // Nabız göstergesinin yarıçapları (tuval ölçeğinde). Dolgu payları
      // bunlardan türetilir — sabitleri elle iki yerde tutmak, birini
      // değiştirince diğerinin unutulmasına yol açardı.
      const pulseMaxR = 26.0; // en geniş nabız halkası
      const haloR = 12.0; // sabit iç hale
      const collarR = 8.0; // beyaz yaka
      const coreR = 5.5; // çekirdek

      // Dikey pay: son nokta serinin en yükseği/en düşüğü olduğunda nabız
      // halkası üstten veya alttan kırpılıyordu.
      const padY = pulseMaxR;
      // SAĞ pay: `xAt` son değeri tam `w` veriyordu, halkanın yarısı tuval
      // dışında kalıyordu. Nabzın yarıçapı yetiyor ama gösterge kartın
      // kenarına yapışık duruyordu; 1.6x ile nefes payı bırakılır.
      const padRight = pulseMaxR * 1.6;
      // SOL pay: eksen etiketleri (tutar) buraya yazılır. Çizgi
      // etiketlerin üstünden geçmemeli, yoksa ikisi de okunmaz.
      const padLeft = 150.0;
      const plotW = w - padRight - padLeft;
      double xAt(int i) => padLeft + (i / (values.length - 1)) * plotW;
      double yAt(double v) => h - padY - ((v - minV) / span) * (h - padY * 2);

      // ── Eksen kılavuzları ────────────────────────────────────────────
      //
      // İki yatay çizgi: eksen üst ve alt sınırı. Sınırlar gerçek
      // min/max'ın biraz DIŞINDA olduğu için çizgi onlara değmez ve
      // kullanıcı hareketin hangi bantta gezindiğini görür.
      //
      // Grafik tutar ekseni OLMADAN "ne kadar oynadı" sorusunu
      // yanıtlamıyordu: aynı görünen iki çizgiden biri 5 kuruşluk,
      // diğeri 50.000 TL'lik hareket olabilir.
      final guidePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _sparkPalette.text36.withValues(alpha: 0.28);

      // Eksen etiketi de DM Sans — kartın geri kalanı (ve uygulamanın
      // tamamı) bu ailede. Sistem fontuna düşmek grafiği metinden
      // görsel olarak ayırıyordu.
      //
      // `tnum` (tabular figures) uygulamanın sayı stilleriyle aynı kural
      // (bkz. `sandik.dart` numSmall/numMedium): orantılı rakamlarda `1`
      // ile `8` farklı genişliktedir ve eksen her tazelemede yatayda
      // zıplar.
      const labelFamily = 'DM Sans';
      const tabular = [ui.FontFeature.tabularFigures()];

      final labelStyle = ui.TextStyle(
        color: _sparkPalette.text36.withValues(alpha: 0.85),
        fontSize: 22,
        fontWeight: FontWeight.w600,
        fontFamily: labelFamily,
        fontFeatures: tabular,
      );

      void drawGuide(double value) {
        final y = yAt(value);
        canvas.drawLine(Offset(padLeft, y), Offset(w - padRight, y), guidePaint);

        final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
          textAlign: TextAlign.right,
          fontSize: 22,
          fontFamily: labelFamily,
        ))
          ..pushStyle(labelStyle)
          ..addText(fmtTRYAxis(value, axisMax - axisMin));
        final para = builder.build()
          ..layout(const ui.ParagraphConstraints(width: padLeft - 14));
        // Etiket çizginin ortasına hizalanır.
        canvas.drawParagraph(para, Offset(0, y - para.height / 2));
      }

      drawGuide(axisMax);
      drawGuide(axisMin);

      final line = Path()..moveTo(xAt(0), yAt(values.first));
      for (var i = 1; i < values.length; i++) {
        line.lineTo(xAt(i), yAt(values[i]));
      }

      // Marka renkleri, SEÇİLİ temaya göre (bkz. `_sparkPalette`).
      // Hareket yoksa nötr gri — kâr/zarar rengi olmayan bir yönü ima
      // etmemeli. Kullanıcı düz bir çizgiyi kırmızı görünce "kaybettim"
      // diye okuyordu.
      final palet = _sparkPalette;
      // Nötr ton `text36`: Android tarafındaki `widget_text_muted` ile aynı
      // token — "hareket yok" iki yüzeyde de aynı renkte okunmalı.
      final color =
          isFlat ? palet.text36 : (isPos ? palet.gain : palet.loss);

      // Alan dolgusu: çizginin altını kapatan gradient.
      final fill = Path.from(line)
        ..lineTo(xAt(values.length - 1), h)
        ..lineTo(xAt(0), h)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, 0),
            const Offset(0, h),
            [
              color.withValues(alpha: 0.30),
              color.withValues(alpha: 0.0),
            ],
          ),
      );

      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          // Tuval 960 genişliğinde ve ~340dp'ye küçülüyor (~2.8x): çizgi
          // ekranda ~1.4dp'ye iner. 4 ince kalıyordu, 6 ile net duruyor.
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );

      // ── Anlık değer göstergesi ("canlı" nabzı) ───────────────────────
      //
      // Bakışı ANLIK değere çeker: sparkline'ın sonu = şu anki portföy.
      //
      // **Gerçek animasyon neden yok:** Android widget'ları `RemoteViews`
      // ile çizilir ve kendi başına kare üretemez; her kare için sistemden
      // güncelleme istemek gerekir ve `updatePeriodMillis` alt sınırı 30
      // dakikadır. Saniyede birkaç kez yenilemek pili tüketir ve sistem
      // zaten kısar. Bunun yerine nabız her GÜNCELLEMEDE farklı bir fazda
      // çizilir — widget tazelendikçe gösterge "nefes alır".
      final lastX = xAt(values.length - 1);
      final lastY = yAt(values.last);
      final center = Offset(lastX, lastY);

      // Hale yalnızca piyasa AÇIKKEN — kilit ekranıyla aynı kural
      // (bkz. SandikSparkline). Hale "veri akıyor" demektir ve gece bu
      // doğru değildir; kapalıyken yalnızca sade bir nokta kalır.
      //
      // Nabız halkası KALDIRILDI: kilit ekranında yok ve iki yüzey aynı
      // görünmeli. Ayrıca marka kuralı gereği bu yüzeylerde dikkat çekmeye
      // çalışan hareketli öğe bulunmaz.
      if (isMarketOpen) {
        canvas.drawCircle(
          center,
          haloR,
          Paint()..color = color.withValues(alpha: 0.26),
        );
      }
      // Beyaz yaka: koyu/açık iki zeminde de noktayı çizgiden ayırır.
      canvas.drawCircle(
        center,
        collarR,
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.92),
      );
      // Çekirdek — anlık değerin kendisi. Kilit ekranıyla aynı kural:
      // piyasa açıkken gain yeşili, kapalıyken gri.
      final dotColor =
          isMarketOpen ? _sparkPalette.gain : _sparkPalette.text36;
      canvas.drawCircle(center, coreR, Paint()..color = dotColor);

      // Resim ve kayıt hemen bırakılır: 960×180 RGBA ~675 KB yerel bellek,
      // çöp toplayıcıya bırakılınca her turda birikebiliyordu.
      final picture = recorder.endRecording();
      final image = await picture.toImage(w.toInt(), h.toInt());
      picture.dispose();
      final ByteData? bytes;
      try {
        bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        image.dispose();
      }
      if (bytes == null) return null;

      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/sandik_widget_spark.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      return file.path;
    } catch (e) {
      if (kDebugMode) debugPrint('Sparkline render failed: $e');
      return null;
    }
  }

  /// Bakiye gizliyken: tutar yazılmaz, widget "gizli" durumunu gösterir.
  Future<void> _writeHidden() async {
    // Seri temizlenir: kalsaydı tutar gizliyken bile eğri portföyün
    // gün içi hareketini ele verirdi.
    await _yaz<String>(_kSparkSeries, '');
    await _yaz<String>(_kTotal, '••••••');
    await _yaz<String>(_kChange, '');
    await _yaz<bool>(_kIsPositive, true);
    await _yaz<bool>(_kIsFlat, true);
    await _yaz<String>(_kChangePct, '');
    await _yaz<bool>(_kHasData, true);
    // Kilit ekranı: yüzde de gizli (karar 4.5) — değer yazılmaz, bayrak
    // gizli der.
    await _yaz<bool>(_kHidden, true);
    await _yaz<String>(_kLockPct, '');
    await _yaz<String>(
        _kDate, DateFormat('d MMMM EEEE', 'tr_TR').format(DateTime.now()));
    await _yaz<bool>(
        _kMarketOpen, DailySummary.isMarketOpen(DateTime.now()));
    await _yaz<String>(
        _kUpdatedAt, DateFormat('HH:mm', 'tr_TR').format(DateTime.now()));
  }

  /// Çözülmüş tema kararını widget'ın paylaşımlı deposuna yazar ve widget'ı
  /// hemen yeniler.
  ///
  /// Tema değiştiğinde çağrılır. Portföy verisi burada yeniden yazılmaz —
  /// yalnızca palet bayrağı değişir; onsuz widget bir sonraki portföy
  /// tazelemesine kadar eski temada kalır ve kullanıcı ayarı değiştirip ana
  /// ekrana çıktığında hiçbir şey değişmemiş görür.
  ///
  /// **Parametre ALMAZ:** değer [SurfaceTheme]'den okunur. Eskiden bool
  /// dışarıdan geliyordu ve çağıran taraflar kendi başına çözüyordu — iki
  /// çağrı yeri iki farklı an örnekleyince widget ile kilit ekranı
  /// ayrışıyordu.
  ///
  /// Sparkline PNG'si burada yeniden çizilmez: bir sonraki [update] doğru
  /// paletle çizecek. Grafik tonları iki zeminde de okunur, aradaki kısa
  /// süre görsel bir tutarsızlık yaratmaz.
  Future<void> applyTheme() async {
    try {
      await _ensureInit();
      await HomeWidget.saveWidgetData<bool>(_kIsLightTheme, themeIsLight);
      _sonYazilan[_kIsLightTheme] = themeIsLight;
      await _requestUpdate();
      // Tek varlık widget'ı da aynı tema bayrağını okur.
      await _varlikWidgetiniYenile();
    } catch (e) {
      if (kDebugMode) debugPrint('HomeWidget applyTheme failed: $e');
    }
  }

  /// Oturum kapanışında çağrılır — çıkan kullanıcının bakiyesi ana ekranda
  /// asılı kalmamalı.
  Future<void> clear() async {
    try {
      await _ensureInit();
      // Önbellek de sıfırlanmalı: aksi halde bir sonraki kullanıcı önceki
      // hesabın gün içi grafiğini görürdü. Önbellek ORTAK olduğu için
      // Live Activity tarafı da bu temizlikten yararlanır.
      IntradaySeriesCache.instance.clear();
      // Burada anahtarlar doğrudan siliniyor: kıyas belleği de sıfırlanır
      // ki sonraki oturumun ilk yazımı eksiksiz olsun.
      _sonYazilan.clear();
      _sonPngAnahtari = null;

      await HomeWidget.saveWidgetData<String>(_kTotal, '');
      await HomeWidget.saveWidgetData<String>(_kChange, '');
      await HomeWidget.saveWidgetData<bool>(_kHasData, false);
      await HomeWidget.saveWidgetData<bool>(_kIsFlat, true);
      await HomeWidget.saveWidgetData<String>(_kChangePct, '');
      await HomeWidget.saveWidgetData<String>(_kDate, '');
      await HomeWidget.saveWidgetData<String>(_kUpdatedAt, '');
      await HomeWidget.saveWidgetData<int>(_kSparkPoints, 0);
      // Tek varlık widget'ının seçim listesi de: çıkan kullanıcının takip
      // ve portföy adları sonraki oturuma kalmamalı. Boş metin = "liste
      // yok" (Swift tarafı boşu ve bozuk JSON'u aynı okur).
      await HomeWidget.saveWidgetData<String>(kVarliklar, '');
      await HomeWidget.saveWidgetData<String>(kVarlikCanli, '');
      await _requestUpdate();
      await _varlikWidgetiniYenile();
    } catch (e) {
      if (kDebugMode) debugPrint('HomeWidget clear failed: $e');
    }
  }

  /// Tek varlık widget'ının paketini yazar ve YALNIZ o türü yeniler.
  ///
  /// Paketi `VarlikWidgetService` kurar (seçim listesi + fiyat); bu metot
  /// yalnız sözleşmenin yazma ucudur. Aynı paket ikinci kez yazılmaz.
  Future<void> varlikListesiniYaz(String paket) async {
    try {
      await _ensureInit();
      if (_sonYazilan[kVarliklar] == paket) return;
      await HomeWidget.saveWidgetData<String>(kVarliklar, paket);
      _sonYazilan[kVarliklar] = paket;
      await HomeWidget.updateWidget(
        androidName: androidVarlikWidgetName,
        iOSName: iOSVarlikWidgetName,
      );
      // Vitrin aynı paketi okur (bkz. [iOSVitrinWidgetName]).
      if (iOSMu()) {
        await HomeWidget.updateWidget(iOSName: iOSVitrinWidgetName);
      }
    } catch (e) {
      _sonYazilan.remove(kVarliklar);
      if (kDebugMode) debugPrint('HomeWidget varlikListesiniYaz failed: $e');
    }
  }

  /// Widget'ın arka planda çağıracağı sunucuyu yazar (bkz. [kWidgetApiUrl]).
  /// Aynı değer ikinci kez yazılmaz; widget'ı yenilemez (sıradaki paket
  /// yazımı yeniler).
  Future<void> widgetSunucusunuYaz({
    required String url,
    required String anonKey,
  }) async {
    if (url.isEmpty || anonKey.isEmpty) return;
    try {
      await _ensureInit();
      if (_sonYazilan[kWidgetApiUrl] != url) {
        await HomeWidget.saveWidgetData<String>(kWidgetApiUrl, url);
        _sonYazilan[kWidgetApiUrl] = url;
      }
      if (_sonYazilan[kWidgetApiAnahtar] != anonKey) {
        await HomeWidget.saveWidgetData<String>(kWidgetApiAnahtar, anonKey);
        _sonYazilan[kWidgetApiAnahtar] = anonKey;
      }
    } catch (e) {
      _sonYazilan.remove(kWidgetApiUrl);
      _sonYazilan.remove(kWidgetApiAnahtar);
      if (kDebugMode) debugPrint('HomeWidget widgetSunucusunuYaz failed: $e');
    }
  }

  /// Tek varlık widget'ı ana ekranda kurulu mu (iOS `WidgetCenter`,
  /// Android `AppWidgetManager`)? Kurulu değilken `VarlikWidgetService`
  /// fiyat için ağa çıkmaz.
  ///
  /// Android sınıf adı `ComponentName.shortClassName` olarak gelir
  /// (`.SandikVarlikWidgetProvider`); son parça karşılaştırılır. Portföy
  /// widget'ı (`SandikWidgetProvider`) burada SAYILMAZ; vitrin widget'ı
  /// (aynı paketi okur, 2026-10-29) SAYILIR.
  Future<bool> varlikWidgetiKuruluMu() async {
    await _ensureInit();
    final kurulu = await HomeWidget.getInstalledWidgets();
    return kurulu.any((w) =>
        w.iOSKind == iOSVarlikWidgetName ||
        w.iOSKind == iOSVitrinWidgetName ||
        w.androidClassName?.split('.').last == androidVarlikWidgetName);
  }

  /// Tek varlık widget'ını yeniler (tema değişimi, oturum kapanışı).
  ///
  /// Yalnız iOS ve Android'de: masaüstü/test ortamında çağrı yapılmaz
  /// (önceden `Platform.isIOS` ile korunan çağrının iki platformlu hâli).
  Future<void> _varlikWidgetiniYenile() async {
    if (!(Platform.isIOS || Platform.isAndroid)) return;
    await HomeWidget.updateWidget(
      androidName: androidVarlikWidgetName,
      iOSName: iOSVarlikWidgetName,
    );
    if (iOSMu()) {
      await HomeWidget.updateWidget(iOSName: iOSVitrinWidgetName);
    }
  }

  Future<void> _requestUpdate() async {
    await HomeWidget.updateWidget(
      name: _androidProvider,
      androidName: _androidProvider,
      iOSName: _iOSWidgetName,
    );
    // Kilit ekranı türü ayrı yenilenir (bkz. [_iOSKilitWidgetName]);
    // Android'de bu tür yok — çağrı yalnız iOS'ta.
    if (Platform.isIOS) {
      await HomeWidget.updateWidget(iOSName: _iOSKilitWidgetName);
    }
  }
}
