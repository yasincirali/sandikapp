import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/portfolio_provider.dart';
import '../utils/tr_format.dart';
import 'history_service.dart';

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
/// `SharedPreferences`, iOS'ta App Group). Bu yüzden buraya yalnızca ekranda
/// zaten görünen ÖZET yazılır — varlık listesi, ticker, adet, kullanıcı id'si
/// veya e-posta ASLA yazılmaz. Kullanıcı bakiyeyi gizlediyse
/// ([hideBalance]) tutar da yazılmaz.
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

  // Paylaşımlı depo anahtarları — native taraf bu adlarla okur.
  static const _kTotal = 'sandik_total';
  static const _kChange = 'sandik_change';
  static const _kIsPositive = 'sandik_is_positive';
  static const _kUpdatedAt = 'sandik_updated_at';
  static const _kHasData = 'sandik_has_data';
  static const _kSparkline = 'sandik_sparkline';
  static const _kSparkPoints = 'sandik_spark_points';

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

      if (hideBalance) {
        // Kullanıcı bakiyeyi uygulama içinde gizlemişse ana ekranda
        // göstermek o tercihi delerdi — omzunun üstünden bakan biri için
        // widget uygulamadan daha kolay görünür.
        await _writeHidden();
      } else {
        final tryFmt = NumberFormat.currency(
            locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
        final isPos = state.gainLoss >= 0;
        final pct = fmtPct(state.gainLossPercentage.abs(), digits: 2);

        await HomeWidget.saveWidgetData<String>(
            _kTotal, tryFmt.format(state.totalValue));
        await HomeWidget.saveWidgetData<String>(
          _kChange,
          '${isPos ? '+' : '-'}${tryFmt.format(state.gainLoss.abs())}  $pct',
        );
        await HomeWidget.saveWidgetData<bool>(_kIsPositive, isPos);
        await HomeWidget.saveWidgetData<bool>(_kHasData, true);
        await HomeWidget.saveWidgetData<String>(
            _kUpdatedAt, DateFormat('HH:mm', 'tr_TR').format(DateTime.now()));

        // Gün içi sparkline — grafik PNG olarak çizilip yola yazılır.
        // RemoteViews custom view çizemez, bu yüzden native taraf hazır
        // bir görsel alır.
        await _writeSparkline(intraday, isPos: isPos);
      }

      await _requestUpdate();
    } catch (e) {
      if (kDebugMode) debugPrint('HomeWidget update failed: $e');
    }
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
    final now = DateTime.now();
    final due = _lastChartAt == null ||
        now.difference(_lastChartAt!) >= _chartMinInterval;

    // Bakiye gizliyken grafik zaten çizilmeyecek; boşuna ağ turu atma.
    if (due && !hideBalance) {
      try {
        _lastChartAt = now;
        _lastSeries = await HistoryService.instance
            .getPortfolioHistoryHourly(state.activeAssets, 24);
      } catch (e) {
        if (kDebugMode) debugPrint('Widget chart fetch failed: $e');
      }
    }

    // Seri ÖNBELLEKTEN geçirilir, doğrudan yerel değişkenden değil.
    //
    // Düzeltilen hata: portföy açılışta arka arkaya birkaç kez yayınlanıyor.
    // İlk çağrı grafiği çekmeye başlıyor (~1.5 sn), o bitmeden gelen ikinci
    // çağrı `due=false` olduğu için grafiksiz yazıyordu ve prefs'te
    // `spark_points=0` kalıyordu — grafik hiç görünmüyordu. Son bilinen seri
    // saklanınca aradaki çağrılar da onu yazar.
    await update(state, hideBalance: hideBalance, intraday: _lastSeries);
  }

  /// Gün içi grafiğin en sık yenilenme aralığı.
  ///
  /// 15 dakika, veri çözünürlüğüyle (5 dk slot) uyumlu ve pil/kota
  /// açısından makul. Widget zaten "son bilinen değer" gösteriyor.
  static const _chartMinInterval = Duration(minutes: 15);
  DateTime? _lastChartAt;

  /// Son başarıyla çekilen gün içi seri.
  ///
  /// Aralık dolmadan gelen güncellemeler bunu yeniden kullanır; aksi halde
  /// grafiksiz yazan bir çağrı, grafiği olan yazının üstünü ezerdi.
  Map<int, double>? _lastSeries;

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
    Map<int, double>? intraday, {
    required bool isPos,
  }) async {
    final series = (intraday ?? const <int, double>{}).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // İki noktadan az veri çizgi oluşturmaz.
    if (series.length < 2) {
      await HomeWidget.saveWidgetData<int>(_kSparkPoints, series.length);
      return;
    }

    final values = series.map((e) => e.value).toList(growable: false);
    final path = await _renderSparkline(values, isPos: isPos);
    if (path != null) {
      await HomeWidget.saveWidgetData<String>(_kSparkline, path);
      await HomeWidget.saveWidgetData<int>(_kSparkPoints, values.length);
    }
  }

  /// Sparkline'ı çizip PNG olarak diske yazar; dosya yolunu döner.
  ///
  /// Çizim marka diline uyar: kazançta yeşil, kayıpta kırmızı çizgi; altında
  /// aynı renkten dikey gradient dolgu ve son noktada bir "canlı" işareti.
  /// Widget'ın kendisi opak bir kart olduğu için arka plan şeffaf bırakılır.
  Future<String?> _renderSparkline(
    List<double> values, {
    required bool isPos,
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

      final minV = values.reduce((a, b) => a < b ? a : b);
      final maxV = values.reduce((a, b) => a > b ? a : b);
      // Düz çizgi (min == max) sıfıra bölmeyi tetikler; ortada yatay çiz.
      final span = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);

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
      const plotW = w - padRight;
      double xAt(int i) => (i / (values.length - 1)) * plotW;
      double yAt(double v) => h - padY - ((v - minV) / span) * (h - padY * 2);

      final line = Path()..moveTo(xAt(0), yAt(values.first));
      for (var i = 1; i < values.length; i++) {
        line.lineTo(xAt(i), yAt(values[i]));
      }

      // Marka renkleri — dark palet tonları (widget zemini koyu/açık olabilir
      // ama bu tonlar iki zeminde de okunur; kontrast testinde doğrulandı).
      final color = isPos ? const Color(0xFF3DB77F) : const Color(0xFFFF6B52);

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

      // Faz: dakikaya bağlı, 0..1 arası. Her tazelemede halka farklı
      // büyüklükte olur; ardışık iki güncelleme aynı görünmez.
      final phase = (DateTime.now().minute % 6) / 6.0;
      final pulseR = haloR + phase * (pulseMaxR - haloR);
      final pulseAlpha = 0.26 * (1.0 - phase); // genişledikçe söner

      // Dış nabız halkası — genişleyip sönen dalga.
      canvas.drawCircle(
        center,
        pulseR,
        Paint()..color = color.withValues(alpha: pulseAlpha),
      );
      // Sabit iç hale — nokta zeminden ayrışsın.
      canvas.drawCircle(
        center,
        haloR,
        Paint()..color = color.withValues(alpha: 0.30),
      );
      // Beyaz yaka: koyu/açık iki zeminde de noktayı çizgiden ayırır.
      canvas.drawCircle(
        center,
        collarR,
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.92),
      );
      // Çekirdek — anlık değerin kendisi.
      canvas.drawCircle(center, coreR, Paint()..color = color);

      final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
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
    await HomeWidget.saveWidgetData<String>(_kTotal, '••••••');
    await HomeWidget.saveWidgetData<String>(_kChange, '');
    await HomeWidget.saveWidgetData<bool>(_kIsPositive, true);
    await HomeWidget.saveWidgetData<bool>(_kHasData, true);
    await HomeWidget.saveWidgetData<String>(
        _kUpdatedAt, DateFormat('HH:mm', 'tr_TR').format(DateTime.now()));
  }

  /// Oturum kapanışında çağrılır — çıkan kullanıcının bakiyesi ana ekranda
  /// asılı kalmamalı.
  Future<void> clear() async {
    try {
      await _ensureInit();
      // Önbellek de sıfırlanmalı: aksi halde bir sonraki kullanıcı önceki
      // hesabın gün içi grafiğini görürdü.
      _lastSeries = null;
      _lastChartAt = null;

      await HomeWidget.saveWidgetData<String>(_kTotal, '');
      await HomeWidget.saveWidgetData<String>(_kChange, '');
      await HomeWidget.saveWidgetData<bool>(_kHasData, false);
      await HomeWidget.saveWidgetData<String>(_kUpdatedAt, '');
      await HomeWidget.saveWidgetData<int>(_kSparkPoints, 0);
      await _requestUpdate();
    } catch (e) {
      if (kDebugMode) debugPrint('HomeWidget clear failed: $e');
    }
  }

  Future<void> _requestUpdate() => HomeWidget.updateWidget(
        name: _androidProvider,
        androidName: _androidProvider,
        iOSName: _iOSWidgetName,
      );
}
