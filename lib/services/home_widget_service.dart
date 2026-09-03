import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/portfolio_provider.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'daily_summary.dart';

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

  /// Uygulamanın SEÇİLİ teması açık mı? Native taraf paleti buna göre seçer.
  ///
  /// Android widget'ı bugüne kadar `res/values` ↔ `values-night` ile
  /// **sistemin** karanlık modunu izliyordu; uygulamanın tercihini değil.
  /// Kullanıcı uygulamayı "Açık" yapıp cihazı koyu bıraktığında widget koyu
  /// kalıyordu — kullanıcı bulgusu buydu. Bu bayrak tercihi çözülmüş hâliyle
  /// taşır ("Sistem" seçiliyse cihazın görünümüne çözülür).
  static const _kIsLightTheme = 'sandik_is_light_theme';

  /// Uygulamanın çözülmüş tema tercihi.
  ///
  /// `LiveActivityService.themeIsLight` ile aynı desen ve aynı gerekçe:
  /// servis singleton olduğu için provider'ı kendisi okuyamaz, tercih
  /// dışarıdan itilir. Varsayılan `false` (koyu) — tercih henüz itilmemişken
  /// bugünkü davranış korunur.
  bool themeIsLight = false;

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

      // Tema, bakiye gizli olsun olmasın YAZILIR: gizli durumda da widget
      // çiziliyor ve o da uygulamanın temasını izlemeli.
      await HomeWidget.saveWidgetData<bool>(_kIsLightTheme, themeIsLight);

      if (hideBalance) {
        // Kullanıcı bakiyeyi uygulama içinde gizlemişse ana ekranda
        // göstermek o tercihi delerdi — omzunun üstünden bakan biri için
        // widget uygulamadan daha kolay görünür.
        await _writeHidden();
      } else {
        final tryFmt = NumberFormat.currency(
            locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

        // Özet ORTAK katmandan gelir — kilit ekranıyla (Live Activity)
        // birebir aynı hesap. İki yüzey ayrı ayrı hesaplarken üç yerde
        // ayrışmıştı: burada ömürlük getiri "günlük" diye gösteriliyor,
        // satış lot'ları toplama geri ekleniyor ve grafik sıfır slotlarla
        // düzleştiriliyordu.
        final summary = DailySummary.from(
          state: state,
          series: intraday ?? const {},
          now: DateTime.now(),
        );

        // Yön GÜNLÜK değişimden okunur, ömürlük getiriden değil.
        // Ölçüm yoksa ya da sıfırsa nötr kabul edilir.
        final isPos = (summary.changeTRY ?? 0) >= 0;

        await HomeWidget.saveWidgetData<String>(
            _kTotal, tryFmt.format(summary.totalTRY));
        await HomeWidget.saveWidgetData<String>(
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
        await HomeWidget.saveWidgetData<bool>(_kIsPositive, isPos);
        // Nötr durum: ölçüm yok ya da ölçüm sıfır. İkisinde de kâr/zarar
        // rengi basılmamalı.
        await HomeWidget.saveWidgetData<bool>(
            _kIsFlat, !summary.hasChange || summary.isFlat);
        // Yüzde rozeti — tutardan ayrı alan (kilit ekranıyla aynı düzen).
        await HomeWidget.saveWidgetData<String>(
          _kChangePct,
          !summary.hasChange || summary.isFlat
              ? ''
              : '${isPos ? '+' : '-'}'
                  '${fmtPct(summary.changePct!.abs(), digits: 2)} Günlük',
        );
        await HomeWidget.saveWidgetData<bool>(_kHasData, true);
        // Tarih — kilit ekranıyla AYNI biçim. Widget günlerce ekranda
        // durur; rakamın hangi güne ait olduğu okunabilmeli.
        await HomeWidget.saveWidgetData<String>(
            _kDate, DateFormat('d MMMM EEEE', 'tr_TR').format(DateTime.now()));
        // Piyasa durumu — banner "Piyasa kapalı" derse kullanıcı rakamın
        // neden değişmediğini bilir. Kilit ekranıyla AYNI kural.
        await HomeWidget.saveWidgetData<bool>(
            _kMarketOpen, DailySummary.isMarketOpen(DateTime.now()));
        await HomeWidget.saveWidgetData<String>(
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
          isMarketOpen: DailySummary.isMarketOpen(DateTime.now()),
        );
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
      await HomeWidget.saveWidgetData<int>(_kSparkPoints, values.length);
      return;
    }

    final path = await _renderSparkline(
      values,
      isPos: isPos,
      isFlat: isFlat,
      isMarketOpen: isMarketOpen,
    );
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
    await HomeWidget.saveWidgetData<bool>(_kIsFlat, true);
    await HomeWidget.saveWidgetData<String>(_kChangePct, '');
    await HomeWidget.saveWidgetData<bool>(_kHasData, true);
    await HomeWidget.saveWidgetData<String>(
        _kDate, DateFormat('d MMMM EEEE', 'tr_TR').format(DateTime.now()));
    await HomeWidget.saveWidgetData<bool>(
        _kMarketOpen, DailySummary.isMarketOpen(DateTime.now()));
    await HomeWidget.saveWidgetData<String>(
        _kUpdatedAt, DateFormat('HH:mm', 'tr_TR').format(DateTime.now()));
  }

  /// Tema tercihini yazar ve widget'ı hemen yeniler.
  ///
  /// Ayarlardan tema değiştirildiğinde çağrılır. Portföy verisi burada
  /// yeniden yazılmaz — yalnızca palet bayrağı değişir; onsuz widget bir
  /// sonraki portföy tazelemesine kadar eski temada kalır ve kullanıcı
  /// ayarı değiştirip ana ekrana çıktığında hiçbir şey değişmemiş görür.
  ///
  /// Sparkline PNG'si de yeniden çizilmez: bir sonraki [update] doğru
  /// paletle çizecek. Grafik tonları iki zeminde de okunur, aradaki kısa
  /// süre görsel bir tutarsızlık yaratmaz.
  Future<void> applyTheme(bool isLight) async {
    themeIsLight = isLight;
    try {
      await _ensureInit();
      await HomeWidget.saveWidgetData<bool>(_kIsLightTheme, isLight);
      await _requestUpdate();
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

      await HomeWidget.saveWidgetData<String>(_kTotal, '');
      await HomeWidget.saveWidgetData<String>(_kChange, '');
      await HomeWidget.saveWidgetData<bool>(_kHasData, false);
      await HomeWidget.saveWidgetData<bool>(_kIsFlat, true);
      await HomeWidget.saveWidgetData<String>(_kChangePct, '');
      await HomeWidget.saveWidgetData<String>(_kDate, '');
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
