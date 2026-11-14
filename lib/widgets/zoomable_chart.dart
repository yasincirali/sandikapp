import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/sandik.dart';
import '../l10n/l10n.dart';

/// Birden fazla grafik (ana + volume subchart) aynı X viewport'unu paylaşsın
/// diye kullanılan ChangeNotifier. Ana grafikte pinch/pan olur, viewport
/// güncellenir, alt grafik de dinleyip aynı X aralığını çizer.
class ChartViewport extends ChangeNotifier {
  ChartViewport({required this.fullMinX, required this.fullMaxX})
      : _minX = fullMinX,
        _maxX = fullMaxX;

  double fullMinX;
  double fullMaxX;
  double _minX;
  double _maxX;

  /// Ana grafikte pinch/pan/zaman sürüklemesi sürüyor mu. Aynı viewport'u
  /// dinleyen yan grafikler (hacim paneli) jest sırasında morf etmemeli:
  /// her karede 180 ms'lik yeni bir lerp başlatıp parmağın ve ana grafiğin
  /// GERİSİNDE kalıyordu (animasyon denetimi 2026-10-01). [ZoomableChart]
  /// yazar; dinleyici bildirimi atmaz (zaten her jest karesi `set` ile
  /// bildirir).
  bool jestSuruyor = false;

  double get minX => _minX;
  double get maxX => _maxX;
  bool get isZoomed =>
      (_minX - fullMinX).abs() > 0.001 || (_maxX - fullMaxX).abs() > 0.001;

  void set(double minX, double maxX) {
    if (_minX == minX && _maxX == maxX) return;
    _minX = minX;
    _maxX = maxX;
    notifyListeners();
  }

  void updateFullRange(double newMin, double newMax) {
    if (!updateFullRangeSessiz(newMin, newMax)) return;
    notifyListeners();
  }

  /// [updateFullRange]'in bildirim ATMAYAN hali — değişiklik olduysa `true`.
  ///
  /// BUILD İÇİNDEN çağıran yol içindir: `notifyListeners()` dinleyicide
  /// `setState` tetikliyor ve Flutter build sırasında bunu yasaklıyor
  /// ("setState() called during build" — emülatör logu 2026-09-23, lot
  /// silerken). Çağıran aralığı senkron yazar, [bildir]'i build sonrasına
  /// erteler (bkz. `_PerformansSeriler._ensureViewport`).
  bool updateFullRangeSessiz(double newMin, double newMax) {
    if (fullMinX == newMin && fullMaxX == newMax) return false;
    final p = korunanPencere(
      minX: _minX,
      maxX: _maxX,
      eskiMin: fullMinX,
      eskiMax: fullMaxX,
      yeniMin: newMin,
      yeniMax: newMax,
    );
    fullMinX = newMin;
    fullMaxX = newMax;
    _minX = p.$1;
    _maxX = p.$2;
    return true;
  }

  /// Tam aralık değişince görünür pencerenin yeni yeri.
  ///
  /// Eskiden her aralık değişimi pencereyi tam aralığa sıfırlıyordu. Aralık
  /// ise gün içinde durmadan uzuyor (yeni gün içi nokta, dakika dönümünde
  /// `DateTime.now()`), yani kullanıcı yakınlaştırdığı anda — bazen parmak
  /// ekrandayken — geri atılıyordu (animasyon denetimi 2026-10-01).
  ///
  /// - Yakınlaştırılmamışsa: yeni tam aralık (eski davranış).
  /// - Pencere sağ kenara dayalıysa (en güncel veriye bakıyor): genişlik
  ///   korunur, sağ kenarla birlikte kayar — canlı veriyi izlemeye devam eder.
  /// - Değilse: aynı yerde kalır; yeni aralığa sığmazsa içeri itilir.
  /// - Pencere yeni aralıktan genişse: tam aralık.
  static (double, double) korunanPencere({
    required double minX,
    required double maxX,
    required double eskiMin,
    required double eskiMax,
    required double yeniMin,
    required double yeniMax,
  }) {
    const eps = 0.001;
    final yakin = (minX - eskiMin).abs() > eps || (maxX - eskiMax).abs() > eps;
    final genislik = maxX - minX;
    if (!yakin || genislik <= 0 || genislik >= yeniMax - yeniMin) {
      return (yeniMin, yeniMax);
    }
    var lo = minX;
    var hi = maxX;
    if ((maxX - eskiMax).abs() <= eps) {
      hi = yeniMax;
      lo = hi - genislik;
    }
    if (lo < yeniMin) {
      lo = yeniMin;
      hi = lo + genislik;
    }
    if (hi > yeniMax) {
      hi = yeniMax;
      lo = hi - genislik;
    }
    return (lo, hi);
  }

  /// Ertelenmiş bildirimi at — [updateFullRangeSessiz] ile birlikte kullanılır.
  void bildir() => notifyListeners();

  /// Tam aralığı yazar VE pencereyi ona sıfırlar, bildirim atmadan (build
  /// içinden; bkz. [ZoomableChart.sifirlamaAnahtari]). Değiştiyse `true`.
  bool sifirlaSessiz(double newMin, double newMax) {
    if (fullMinX == newMin &&
        fullMaxX == newMax &&
        _minX == newMin &&
        _maxX == newMax) {
      return false;
    }
    fullMinX = newMin;
    fullMaxX = newMax;
    _minX = newMin;
    _maxX = newMax;
    return true;
  }

  void reset() {
    set(fullMinX, fullMaxX);
  }
}

/// fl_chart [LineChart] üzerine pinch (iki parmak) zoom, pan ve isteğe bağlı
/// crosshair (uzun basınca dikey rehber çizgi + fiyat/tarih pill'i) ekler.
///
/// Yaklaşım: LineChart'ın **üzerinde** her zaman aktif bir GestureDetector
/// katmanı var. `HitTestBehavior.translucent` ile aynı jesti alta da (LineChart
/// tooltip'ine) geçirir. Scale recognizer 2+ parmakta arena'yı kazanır ve
/// zoom uygulanır; tek parmak dokunma tooltip'e gider.
///
/// Crosshair, [crosshairLabelBuilder] verildiğinde aktif olur. Long-press
/// başlatır, pan devam ettirir, pointer kalkınca kaybolur.
class ZoomableChart extends StatefulWidget {
  final double fullMinX;
  final double fullMaxX;

  /// Ekran okuyucu özeti. Grafik dokunmatik bir yüzey; içindeki çizgiler
  /// TalkBack/VoiceOver için anlamsız. Çağıran "portföy değeri, 30 gün, %x"
  /// gibi bir cümle verir; vermezse jenerik etiket okunur (çevrilmiş;
  /// eskiden sabit Türkçe "Fiyat grafiği" idi — HIG denetimi 2026-10-10).
  final String? semanticLabel;

  /// Görünen pencerenin ekran okuyucu değeri ("görünen aralıkta yüzde 4,2
  /// arttı; en düşük …"). Pencere bu widget'ın kendi koordinatında verilir;
  /// seans sıkıştırması olan çağıran gerçek X'e kendisi çevirir. Metni
  /// çağıran kurar (`grafikOzetMetni`) çünkü Y'nin birimi (₺, yüzde, log)
  /// ve bakiye gizliliği yalnız orada bilinir. `null` → yalnız etiket.
  final String? Function(double minX, double maxX)? semanticValueBuilder;
  final LineChartData Function(double minX, double maxX) builder;
  final double height;

  /// Viewport her değiştiğinde çağrılır (pan/pinch/reset). ZoomDataController
  /// bunu dinleyip uygun çözünürlükte yeni veri yükleyebilir.
  final void Function(double minX, double maxX)? onViewportChanged;

  /// Crosshair aktif için gerekli. `x` chart data cinsinden (builder'a giden
  /// aynı X uzayı), dönüş pill'de gösterilecek 2 satır: `(title, subtitle)`.
  /// Örn: (`'₺1.234'`, `'14 Mar 15:30'`). `null` dönerse pill gösterilmez ama
  /// dikey çizgi hâlâ çizilir.
  final (String, String)? Function(double x)? crosshairLabelBuilder;

  /// Opsiyonel — verilirse pill'de fiyat/tarih altında ek detay satırları
  /// gösterilir (getiri, alım/satım vs.). Her satır: (metin, renk).
  final List<(String, Color)> Function(double x)? crosshairDetailsBuilder;

  /// Opsiyonel: crosshair X'ini en yakın data noktasına snap eder. Verilirse
  /// hem dikey çizgi hem pill label snap edilmiş X'te gösterilir — böylece
  /// fl_chart'ın built-in tooltip'i ile crosshair birebir aynı noktaya
  /// oturur, kullanıcı "çizgi ile veri tutmuyor" hissi almaz.
  final double Function(double x)? crosshairSnapX;

  /// Verilirse widget kendi viewport state'ini tutmaz — controller üstünden
  /// paylaşılır. Volume subchart gibi 2. panelin aynı X aralığına oturması
  /// için kullanılır.
  final ChartViewport? viewportController;

  /// Grafik altındaki X-axis label alanında horizontal drag = zaman ölçeği
  /// sıkıştır/genişlet. Sağ kenar pivot — son nokta sabit kalır.
  final bool enableTimeScaleDrag;

  /// Bottom axis alanı yüksekliği (px). enableTimeScaleDrag için sadece
  /// bu alan drag'i yakalar; üstteki chart alanı pinch/tap için serbest.
  final double bottomAxisHeight;

  /// Sağdaki Y-ekseni rezerv alanı (px). Chart plot area sağdan bu kadar
  /// içeride biter — crosshair/touch bu alana **girmez**. fl_chart'ın
  /// `rightTitles.reservedSize` değeriyle aynı olmalı.
  final double plotPaddingRight;

  /// Soldaki Y-ekseni rezerv alanı (px). fl_chart `leftTitles.reservedSize`
  /// ile aynı olmalı. Sağ Y kullanılıyorsa 0.
  final double plotPaddingLeft;

  /// Veri (periyot/filtre) değişiminde grafiğin eski şekilden yenisine
  /// morf süresi. Jest sırasında yok sayılır — bkz. build().
  final Duration swapDuration;

  /// Morf eğrisi. `ease-out` hızlı başlar: değişim hemen algılanır.
  final Curve swapCurve;

  /// Verilirse imlecin etiketi ([crosshairLabelBuilder] çıktısı) buraya da
  /// yazılır; imleç kalkınca `null`. Sayfa başlığındaki büyük fiyatın
  /// parmağı izlemesi için (göz alıcılık B, bayrak çağıranda).
  final ValueNotifier<(String, String)?>? imlecEtiketi;

  /// [imlecEtiketi]'ne yazılacak etiket; yoksa [crosshairLabelBuilder].
  ///
  /// Neden ayrı: grafiğin kendi etiketi sabit iki haneli olabilir, sayfa
  /// başlığındaki büyük fiyat ise varlığın kendi hane sayısıyla yazılır
  /// (fonda ₺0,123456). Başlık parmakla değişirken biçimi zıplamamalı.
  final (String, String)? Function(double x)? imlecEtiketiBuilder;

  /// İmleç bu X'lerden birine oturunca hafif titreşim (ör. dönemin zirvesi
  /// ve dibi). Boş → yalnız imlecin belirdiği anki titreşim (eski davranış).
  ///
  /// Neden: nokta başına titreşim yorucu (bkz. `_updateCrosshair`), hiç
  /// titreşim yoksa parmak "en yüksek burada" anını kaçırıyor. Yalnız
  /// anlamlı noktalarda — Robinhood/Apple Stocks yaklaşımı.
  final Set<double> titresimNoktalari;

  /// Değişince yakınlaştırma SIFIRLANIR (tam aralık). Çağıran dönemi ve
  /// mum sıklığını verir.
  ///
  /// Neden (yasin, 2026-10-11 TestFlight): *"zoom yapıldığında zaman
  /// aralığı değişince chartta kalıyor o zoom, zaman değişikliğinde
  /// defaultunda açılmalı."* Tam aralık değişince pencere korunuyordu
  /// ([ChartViewport.korunanPencere]): bu, dakika dönümünde uzayan gün içi
  /// aralık için doğru (parmak ekrandayken geri atılmasın), dönem
  /// değişiminde yanlış — 1Y'de yakınlaştırılmış pencere 1H'ye taşınıyordu.
  /// İkisini ayırt edecek tek bilgi çağıranda: dönem değişti mi.
  /// `null` → eski davranış (yalnız aralık değişimi, pencere korunur).
  final Object? sifirlamaAnahtari;

  /// X ekseninin mutlak kökeni (x ile aynı birimde; Performans'ta dönem
  /// başı, Unix gününden). İki dönemin kökeni de verilmişse ve biri
  /// ötekinin penceresini kapsıyorsa dönem geçişi KAMERA olur: çizgi biçim
  /// değiştirmez, pencere yakınlaşır/uzaklaşır (yasin 2026-11-14, "C").
  /// `null` → nokta morfu (Bugün'ün dakika ekseni gibi farklı birimler).
  final double? kameraKokeni;

  const ZoomableChart({
    super.key,
    required this.fullMinX,
    required this.fullMaxX,
    required this.builder,
    this.height = 360,
    this.onViewportChanged,
    this.crosshairLabelBuilder,
    this.crosshairDetailsBuilder,
    this.crosshairSnapX,
    this.viewportController,
    this.enableTimeScaleDrag = true,
    this.bottomAxisHeight = 32,
    this.plotPaddingRight = 0,
    this.plotPaddingLeft = 0,
    this.semanticLabel,
    this.semanticValueBuilder,
    this.swapDuration = SandikMotion.state,
    this.swapCurve = SandikMotion.enter,
    this.imlecEtiketi,
    this.imlecEtiketiBuilder,
    this.titresimNoktalari = const {},
    this.sifirlamaAnahtari,
    this.kameraKokeni,
  });

  @override
  State<ZoomableChart> createState() => _ZoomableChartState();
}

class _ZoomableChartState extends State<ZoomableChart>
    with TickerProviderStateMixin {
  // Controller yoksa iç state — verildiyse controller kaynak.
  double _localMinX = 0;
  double _localMaxX = 0;

  double get _minX =>
      widget.viewportController?.minX ?? _localMinX;
  double get _maxX =>
      widget.viewportController?.maxX ?? _localMaxX;

  double _startMinX = 0;
  double _startMaxX = 0;
  double _startFocalRel = 0.5;
  // Jest başındaki odak noktası (piksel). Kaydırma BAŞLANGIÇTAN toplam
  // yer değiştirmeyle hesaplanır — bkz. `_onScaleUpdate`.
  double _startFocalPx = 0;
  double _chartWidth = 1.0;

  // Crosshair state — null = kapalı. `_crosshairPx` widget'ın soldan
  // piksel offset'i; `_crosshairX` chart data cinsinden değer.
  double? _crosshairPx;
  double? _crosshairX;

  // Kullanıcı şu an pinch/pan/time-scale drag yapıyor mu? Doğruysa
  // LineChart'ın implicit animasyonu kapatılır: viewport her karede
  // değişirken lerp etmek parmağın arkasında kalan "lastikli" bir his
  // yaratıyor. Jest bitince tekrar açılır ki periyot/filtre değişimleri
  // yumuşak morf'lansın.
  bool _interacting = false;

  // ── Veri önbelleği (animasyon denetimi, 2026-09-30) ──────────────────────
  //
  // Artı imleciyle gezinirken (scrub) her kare `setState` çalışıyor ve
  // `widget.builder(minX, maxX)` tüm `LineChartData`'yı — noktalar, eksen
  // etiketleri, çizgi stilleri — baştan üretiyordu; oysa değişen yalnız
  // imleç. Görünür aralık ve kurucu aynıysa önceki veri döner. Kurucu üst
  // widget her kurulduğunda yeni bir kapanıştır → üst yeniden kurulunca
  // (veri/dönem değişimi) önbellek kendiliğinden düşer; yalnız bu State'in
  // kendi setState'lerinde (imleç) isabet eder.
  LineChartData? _veri;
  double? _veriMin;
  double? _veriMax;
  Object? _veriKurucu;

  LineChartData _grafikVerisi() {
    final kurucu = widget.builder;
    if (_veri == null ||
        _veriMin != _minX ||
        _veriMax != _maxX ||
        !identical(_veriKurucu, kurucu)) {
      _veri = kurucu(_minX, _maxX);
      _veriMin = _minX;
      _veriMax = _maxX;
      _veriKurucu = kurucu;
    }
    return _veri!;
  }

  // ── Görünür değişim denetimi (animasyon denetimi 2026-10-01, ölçüm) ──────
  //
  // fl_chart yeni veriyi eskisiyle `==` ile karşılaştırıp farklıysa morf
  // başlatır. Ama `LineChartData` eksen etiketi ve dokunma geri çağrısı
  // gibi KAPANIŞLAR taşır ve sahipler (Performans, varlık detayı, fiyat
  // grafiği, karşılaştırma) her kurulumda yenisini verir — veri hiç
  // değişmese de eşit sayılmaz. Ölçüldü: fiyatı DEĞİŞMEYEN her 30 sn
  // tikinde Performans grafiği 12 kare (180 ms) boşuna yeniden boyuyordu.
  // Burada yalnız ÇİZİLEN şey karşılaştırılır (eksen aralığı + çizgi
  // noktaları/rengi/kalınlığı); aynıysa morf süresi sıfırdır. Sahiplere
  // dokunmadan dört grafik birden düzelir.
  LineChartData? _oncekiCizilen;

  /// Son karşılaştırmada çubuk sayısı değişti mi (bkz. [_gorunurDegisti]).
  bool _yapiDegisti = false;

  ///
  /// Karşılaştırma PİKSEL ALTI toleranslıdır: zaman ekseni "şu an"a bağlı
  /// grafiklerde her tikte son nokta ve eksen sonu biraz kayar (ölçüldü:
  /// 103 günlük pencerede 0,003 gün ≈ 0,01 px). Göz görmez; morf ise
  /// 180 ms boyar. Eşik eksen aralığının binde biri (~0,35 px).
  bool _gorunurDegisti(LineChartData yeni) {
    final r = _karsilastir(_oncekiCizilen, yeni);
    _oncekiCizilen = yeni;
    _yapiDegisti = r.yapi;
    return r.degisti;
  }

  /// [_gorunurDegisti]'nin yan etkisiz çekirdeği: köprü sürerken hedefin
  /// hâlâ aynı olup olmadığı da bununla sorulur.
  static ({bool degisti, bool yapi}) _karsilastir(
      LineChartData? eski, LineChartData yeni) {
    if (eski == null) return (degisti: true, yapi: false);
    if (identical(eski, yeni)) return (degisti: false, yapi: false);
    // Çubuk SAYISI değişti (gösterge, mum ya da karşılaştırma eklendi/
    // çıktı): morf YOK. fl_chart çubukları SIRA NUMARASIYLA eşler; başa
    // eklenen EMA, eski fiyat çizgisinin noktalarından kendi noktalarına
    // morf ediyor, fiyat çizgisi de bir sonraki çubuğa kayıyordu — ekranda
    // "grafik bozulup tekrar çiziliyor" (yasin 2026-10-11 TestFlight:
    // "sadece gösterge değiştiyse grafik sabit kalıp EMA eklenip
    // çıkarılmalı"). Katman anında belirir/kaybolur, fiyat çizgisi kımıldamaz.
    if (eski.lineBarsData.length != yeni.lineBarsData.length) {
      return (degisti: true, yapi: true);
    }
    final tx = (yeni.maxX - yeni.minX).abs() / 1000;
    final ty = (yeni.maxY - yeni.minY).abs() / 1000;
    bool yakin(double? a, double? b, double t) =>
        a == b || (a != null && b != null && (a - b).abs() <= t);
    if (!yakin(eski.minX, yeni.minX, tx) ||
        !yakin(eski.maxX, yeni.maxX, tx) ||
        !yakin(eski.minY, yeni.minY, ty) ||
        !yakin(eski.maxY, yeni.maxY, ty) ||
        eski.lineBarsData.length != yeni.lineBarsData.length) {
      return (degisti: true, yapi: false);
    }
    for (var i = 0; i < yeni.lineBarsData.length; i++) {
      final a = eski.lineBarsData[i];
      final b = yeni.lineBarsData[i];
      if (a.color != b.color ||
          a.gradient != b.gradient ||
          a.barWidth != b.barWidth ||
          a.show != b.show ||
          !listEquals(a.dashArray, b.dashArray) ||
          a.spots.length != b.spots.length) {
        return (degisti: true, yapi: false);
      }
      for (var j = 0; j < a.spots.length; j++) {
        final p = a.spots[j];
        final q = b.spots[j];
        if (p.isNull() != q.isNull()) return (degisti: true, yapi: false);
        if (p.isNull()) continue;
        if (!yakin(p.x, q.x, tx) || !yakin(p.y, q.y, ty)) return (degisti: true, yapi: false);
      }
    }
    return (degisti: false, yapi: false);
  }

  // ── Dönem geçişi: yerinde morf (yasin 2026-11-11 TestFlight) ──────────
  //
  // "Tüm grafik sayfalarında zaman aralığı değişince grafik hopluyor, ekran
  // baştan çiziliyor gibi." İki ayrı kusur vardı:
  //
  //  1. Nokta sayısı farklı iki seri (1 ay ≈ 32, 1 yıl ≈ 52, Bugün ≈ 160
  //     nokta): fl_chart noktaları SIRA NUMARASIYLA eşler; eskide karşılığı
  //     olmayan noktalar ilk karede SON yerinde belirir, ilk N nokta başka
  //     günlerin yerinden kayar. Çizginin bir kısmı akarken kuyruğu sıçrar.
  //     Çözüm köprü: iki seri de ortak (büyük olan) nokta sayısına
  //     SIKLAŞTIRILIR — ara noktalar mevcut iki köşe arasına eklenir, çizgi
  //     piksel piksel aynı kalır. Önce eski çizgi sıklaşmış hâliyle sıfır
  //     sürede verilir (görünür değişiklik yok), sonra yeni çizginin
  //     sıklaşmış hâline `swapDuration` ile akılır, akış bitince gerçek
  //     seri sıfır sürede yerine konur (yine görünür değişiklik yok;
  //     dokunma balonu gerçek noktaları okur).
  //  2. Çubuk SAYISI değişen dönem geçişi (genç lot: 1 hf'de yalnız aktif
  //     çizgi, 1 yıl'da alış öncesi gri parça + aktif): morf burada yanlış
  //     çubukları eşler, gösterge kuralı ([_karsilastir]) anında değiştirir.
  //     Gösterge aç/kapa için doğru olan bu, dönem değişiminde "hop" oldu.
  //     Dönem değişiminde ([sifirlamaAnahtari] ya da viewport controller
  //     değişti) eski çizim aynı kutuda üstte söner ([SandikMotion.state]);
  //     yeni çizim altında tam hâliyle durur. Ağaç biçimi sabit: sönen
  //     katman her zaman ağaçta (boşken `SizedBox.shrink`), LineChart'ın
  //     State'i kımıldamaz.
  //
  // Hareketi azalt açıkken ikisi de kurulmaz: yeni çizim tek karede gelir.

  /// Son dönem değişiminden beri görünür bir değişiklik çizildi mi. Dönem
  /// sekmesi önbellekten değil ağdan geliyorsa anahtar ÖNCE, veri SONRA
  /// değişir; sönme veri geldiği karede oynamalı.
  bool _donemDegisti = false;

  /// Sönen eski çizim (çubuk sayısı değişen dönem geçişi) ve kimliği.
  LineChartData? _solan;
  int _solmaNo = 0;

  /// Eski ve yeni seriyi ortak nokta sayısına sıklaştırır. Köprü
  /// kurulamıyorsa (boşluklu seri, noktası gösterilen çubuk, tek nokta)
  /// null: eski davranış (doğrudan morf) sürer.
  static ({LineChartData eski, LineChartData yeni})? _kopruKur(
      LineChartData eski, LineChartData yeni) {
    var fark = false;
    final eskiCubuklar = <LineChartBarData>[];
    final yeniCubuklar = <LineChartBarData>[];
    for (var i = 0; i < yeni.lineBarsData.length; i++) {
      final a = eski.lineBarsData[i];
      final b = yeni.lineBarsData[i];
      final m = a.spots.length;
      final n = b.spots.length;
      if (m == n) {
        eskiCubuklar.add(a);
        yeniCubuklar.add(b);
        continue;
      }
      // Ara nokta noktası gösterilen çubukta yeni bir nokta olarak
      // görünürdü; boşluk (`nullSpot`) içeren seride "iki köşe arası"
      // tanımsız. İkisinde de köprü yok.
      if (m < 2 ||
          n < 2 ||
          a.dotData.show ||
          b.dotData.show ||
          a.spots.any((p) => p.isNull()) ||
          b.spots.any((p) => p.isNull())) {
        return null;
      }
      fark = true;
      final k = m > n ? m : n;
      eskiCubuklar.add(a.copyWith(spots: _siklastir(a.spots, k)));
      yeniCubuklar.add(b.copyWith(spots: _siklastir(b.spots, k)));
    }
    if (!fark) return null;
    return (
      eski: eski.copyWith(lineBarsData: eskiCubuklar),
      yeni: yeni.copyWith(lineBarsData: yeniCubuklar),
    );
  }

  /// [s]'yi [k] noktaya çıkarır: her köşe yerinde kalır, eklenenler iki
  /// komşu köşenin arasına eşit aralıkla düşer (çizgi aynı görünür).
  /// Ekler parçalara eşit dağılır; morfta eski i. nokta yeni i. noktaya,
  /// yani serinin aynı ORANINA gider — çizgi soldan sağa bütün olarak akar.
  static List<FlSpot> _siklastir(List<FlSpot> s, int k) {
    final m = s.length;
    if (m >= k) return s;
    final ek = k - m;
    final parca = m - 1;
    final sonuc = <FlSpot>[];
    for (var j = 0; j < parca; j++) {
      final a = s[j];
      final b = s[j + 1];
      sonuc.add(a);
      final adet = ek ~/ parca + (j < ek % parca ? 1 : 0);
      for (var q = 1; q <= adet; q++) {
        final t = q / (adet + 1);
        sonuc.add(FlSpot(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t));
      }
    }
    sonuc.add(s.last);
    return sonuc;
  }

  // ── Geçiş motoru: tek saat, yay, kamera (yasin 2026-11-14) ────────────
  //
  // yasin (TestFlight): "zaman seçimleri arasında geçişte dikey uzunluk
  // değişiyor ve y etiketlerinin yerleri değişiyor"; artifact'te seçtiği
  // çözüm "C · kamera + yay", şartı "kararlı, sıçramasız, akıcı".
  //
  // Önceki düzen fl_chart'ın kendi lerp'ine dayanıyordu. O lerp minY/maxY
  // ile birlikte ETİKET ve IZGARA ADIMINI da ara değerlerden geçirir
  // (25 bin → 31.700 → 50 bin): etiketler her karede başka sayıya düşer,
  // genişlikleri değişip küçülür, sınıra denk gelen bir anda kaybolur.
  // Şimdi:
  //  • LineChart'a hep SIFIR süreyle hazır kare verilir; kareyi bu saat
  //    üretir. Çizgi, ölçek, ızgara ve etiket aynı saatten okur, ayrışmaz.
  //  • Saat süre değil yay sürer ([_yay]: tepki ~0,42 sn, sönüm 0,9 —
  //    gözle görülür sekme yok). Yarıda yeni dönem seçilirse hız korunur,
  //    hareket bulunduğu yerden döner; süreli eğri sıfır hızdan başlayıp
  //    duraklıyordu.
  //  • Kamera ([ZoomableChart.kameraKokeni]): iki dönem aynı zaman ekseninde
  //    yazılabiliyorsa çizgi biçim değiştirmez, pencere yakınlaşır ya da
  //    uzaklaşır. Pencereyi kapsayan seri ALTTA çizilir; öteki dönemin
  //    (sıklığı farklı) serisi ÜSTTE solar/belirir ve Y bandı ikisinin
  //    ağırlığıyla karışır — ilk kare önceki çizimin, son kare yeni çizimin
  //    pikseli pikseline aynısıdır. Her ara kare gerçek veridir.
  //  • Kamera kurulamıyorsa (Bugün ↔ dönem, kökensiz grafik) nokta morfu:
  //    köprü ([_kopruKur]) iki seriyi ortak nokta sayısına sıklaştırır.
  //  • Y etiketi ve yatay ızgara bu sınıfta çizilir ([_takimlar]): her
  //    etiket kendi DEĞERİNE bağlıdır, ölçekle o değerin yeni yerine kayar;
  //    adım değişince eski takım söner, yenisi belirir, ara değer yazılmaz.
  //
  // Hareketi azalt açıkken hiçbiri kurulmaz: yeni çizim tek karede gelir.

  static final SpringDescription _yay =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 224, ratio: 0.9);

  AnimationController? _gecisSaati;

  /// Süren geçiş: [_Morf] ya da [_Kamera]; durgunken null.
  Object? _gecis;
  int _gecisNo = 0;

  /// Son çizilen karenin kaynağı. Kamera "nereden" sorusunu buradan
  /// yanıtlar: hangi kurucu, hangi köken, hangi pencere (o kurucunun
  /// koordinatında). Morf karesinde kurucu yok (kamera kurulmaz).
  LineChartData Function(double, double)? _sonKurucu;
  double? _sonKoken;
  double _sonMin = 0;
  double _sonMax = 0;

  void _gecisBaslat(Object g) {
    final c = _gecisSaati ??= AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (mounted && !_kurulumda && _gecis != null) setState(() {});
      });
    final hiz = _gecis != null && c.isAnimating ? c.velocity * 0.6 : 0.0;
    _gecis = g;
    final no = ++_gecisNo;
    final k = _kurulumda;
    _kurulumda = true;
    c.value = 0;
    c
        .animateWith(SpringSimulation(_yay, 0, 1, hiz,
            tolerance: const Tolerance(distance: 0.002, velocity: 0.02)))
        .then((_) {
      if (!mounted || no != _gecisNo) return;
      setState(_gecisiBirak);
    });
    _kurulumda = k;
  }

  void _gecisiBirak() {
    _gecis = null;
    _gecisNo++;
    _gecisSaati?.stop();
  }

  _Kare _durgun(LineChartData veri) {
    _sonKurucu = widget.builder;
    _sonKoken = widget.kameraKokeni;
    _sonMin = veri.minX;
    _sonMax = veri.maxX;
    return _Kare(veri, veri);
  }

  _Kare _gecisKaresi(Object g, double p) {
    if (g is _Kamera) return _kameraKaresi(g, p);
    final m = g as _Morf;
    _sonKurucu = null;
    return _Kare(_morfKaresi(m.eski, m.yeni, p.clamp(0.0, 1.02)), m.hedef);
  }

  /// fl_chart'ın `LineChartData.lerp`'i yerine: sınırlar, çubuklar ve ek
  /// çizgiler ara değerden geçer, geri kalanı hedefin. O lerp null → değer
  /// adımında (otomatik → açık aralık) ilk karede 0 üretip assert'e
  /// düşüyordu; adımı bir taraf null ise ötekinden alırız. Adım ara değerden
  /// geçmeli: hedefin adımı eskinin aralığına uygulanırsa (dakika ↔ gün)
  /// eksen milyonlarca tik dener.
  static LineChartData _morfKaresi(LineChartData e, LineChartData y, double t) {
    double l(double a, double b) => a + (b - a) * t;
    double? li(double? a, double? b) =>
        a == null || b == null ? (b ?? a) : l(a, b);
    AxisTitles ax(AxisTitles a, AxisTitles b) => b.copyWith(
        sideTitles: b.sideTitles.copyWith(
            interval: li(a.sideTitles.interval, b.sideTitles.interval)));
    final et = e.titlesData;
    final yt = y.titlesData;
    return y.copyWith(
      minX: l(e.minX, y.minX),
      maxX: l(e.maxX, y.maxX),
      minY: l(e.minY, y.minY),
      maxY: l(e.maxY, y.maxY),
      lineBarsData: [
        for (var i = 0; i < y.lineBarsData.length; i++)
          i < e.lineBarsData.length
              ? LineChartBarData.lerp(e.lineBarsData[i], y.lineBarsData[i], t)
              : y.lineBarsData[i],
      ],
      extraLinesData: ExtraLinesData.lerp(e.extraLinesData, y.extraLinesData, t),
      titlesData: yt.copyWith(
        leftTitles: ax(et.leftTitles, yt.leftTitles),
        topTitles: ax(et.topTitles, yt.topTitles),
        rightTitles: ax(et.rightTitles, yt.rightTitles),
        bottomTitles: ax(et.bottomTitles, yt.bottomTitles),
      ),
      gridData: y.gridData.copyWith(
        horizontalInterval:
            li(e.gridData.horizontalInterval, y.gridData.horizontalInterval),
        verticalInterval:
            li(e.gridData.verticalInterval, y.gridData.verticalInterval),
      ),
    );
  }

  /// Eski pencere yenisinin içindeyse (ya da tersi) kamera; yoksa null.
  _Kamera? _kameraKur(LineChartData veri) {
    final yeniKoken = widget.kameraKokeni;
    final eskiKoken = _sonKoken;
    final eskiKurucu = _sonKurucu;
    if (yeniKoken == null || eskiKoken == null || eskiKurucu == null) {
      return null;
    }
    if (identical(eskiKurucu, widget.builder)) return null;
    // eski x + d = yeni x
    final d = eskiKoken - yeniKoken;
    final bMin = _sonMin + d;
    final bMax = _sonMax + d;
    final sMin = veri.minX;
    final sMax = veri.maxX;
    if (bMax - bMin <= 0 || sMax - sMin <= 0) return null;
    final eps = (sMax - sMin).abs() * 0.002 + 1e-9;
    final disari = sMin <= bMin + eps && sMax >= bMax - eps;
    final iceri = bMin <= sMin + eps && bMax >= sMax - eps;
    if (disari == iceri) return null;
    return disari
        // Uzaklaşma: yeni seri eski pencereyi kapsar → altta yeni, eski
        // (daha sık) seri üstte söner.
        ? _Kamera(
            hedef: veri,
            alt: widget.builder,
            altKayma: 0,
            altKoken: yeniKoken,
            ust: eskiKurucu,
            ustKayma: d,
            ustGiris: false,
            basMin: bMin,
            basMax: bMax,
            sonMin: sMin,
            sonMax: sMax)
        // Yakınlaşma: eski seri yeni pencereyi kapsar → altta eski, yeni
        // seri sonda belirir.
        : _Kamera(
            hedef: veri,
            alt: eskiKurucu,
            altKayma: d,
            altKoken: eskiKoken,
            ust: widget.builder,
            ustKayma: 0,
            ustGiris: true,
            basMin: bMin,
            basMax: bMax,
            sonMin: sMin,
            sonMax: sMax);
  }

  _Kare _kameraKaresi(_Kamera k, double p) {
    final q = p.clamp(0.0, 1.0);
    // Sağ uç doğrusal, genişlik logaritmik: 1 ay → 5 yıl yakınlaşması göze
    // sabit hızda görünür (doğrusal genişlikte ilk karelerde fırlardı).
    final sag = k.basMax + (k.sonMax - k.basMax) * q;
    final bu = k.basMax - k.basMin;
    final su = k.sonMax - k.sonMin;
    final uz = math.exp(math.log(bu) + (math.log(su) - math.log(bu)) * q);
    final sol = sag - uz;
    final a = k.alt(sol - k.altKayma, sag - k.altKayma);
    final u = k.ust(sol - k.ustKayma, sag - k.ustKayma);
    final w = Curves.easeInOut.transform(k.ustGiris
        ? ((q - 0.55) / 0.45).clamp(0.0, 1.0)
        : (1 - q / 0.45).clamp(0.0, 1.0));
    double karis(double x, double y) => x + (y - x) * w;

    final alt = _cizgiOpakligi(a, 1 - w * w)
        .copyWith(minY: karis(a.minY, u.minY), maxY: karis(a.maxY, u.maxY));
    _sonKurucu = k.alt;
    _sonKoken = k.altKoken;
    _sonMin = sol - k.altKayma;
    _sonMax = sag - k.altKayma;
    final eksen = w > 0.5 ? u : a;
    if (w <= 0.001) return _Kare(alt, eksen);
    return _Kare(alt, eksen, ust: _yalnizCizgi(u, alt), ustOpak: w);
  }

  /// Üst katman yalnız çizgiyi taşır: eksen yazısı, ızgara, ek çizgi ve
  /// dokunma alttaki grafiğindir. Etiket rezervleri aynı kalır ki çizim
  /// alanı birebir örtüşsün; Y bandı alttakinin.
  static LineChartData _yalnizCizgi(LineChartData d, LineChartData ref) =>
      d.copyWith(
        minY: ref.minY,
        maxY: ref.maxY,
        gridData: const FlGridData(show: false),
        titlesData: _bosEtiketler(ref.titlesData),
        extraLinesData: const ExtraLinesData(),
        rangeAnnotations: const RangeAnnotations(),
        lineTouchData: const LineTouchData(enabled: false),
        borderData: ref.borderData,
      );

  static AxisTitles _bosEksen(AxisTitles a) => a.copyWith(
        axisNameWidget: a.axisNameWidget == null ? null : const SizedBox.shrink(),
        sideTitles: a.sideTitles
            .copyWith(getTitlesWidget: (_, __) => const SizedBox.shrink()),
      );

  static FlTitlesData _bosEtiketler(FlTitlesData t) => t.copyWith(
        leftTitles: _bosEksen(t.leftTitles),
        topTitles: _bosEksen(t.topTitles),
        rightTitles: _bosEksen(t.rightTitles),
        bottomTitles: _bosEksen(t.bottomTitles),
      );

  static LineChartData _cizgiOpakligi(LineChartData d, double a) {
    if (a >= 0.999) return d;
    Color? c(Color? x) => x?.withValues(alpha: x.a * a);
    Gradient? g(Gradient? x) => x is LinearGradient
        ? LinearGradient(
            begin: x.begin,
            end: x.end,
            stops: x.stops,
            tileMode: x.tileMode,
            transform: x.transform,
            colors: [for (final k in x.colors) k.withValues(alpha: k.a * a)])
        : x;
    BarAreaData alan(BarAreaData b) => BarAreaData(
          show: b.show,
          color: c(b.color),
          gradient: g(b.gradient),
          spotsLine: b.spotsLine,
          cutOffY: b.cutOffY,
          applyCutOffY: b.applyCutOffY,
        );
    return d.copyWith(lineBarsData: [
      for (final b in d.lineBarsData)
        b.copyWith(
          color: c(b.color),
          gradient: g(b.gradient),
          belowBarData: alan(b.belowBarData),
          aboveBarData: alan(b.aboveBarData),
        ),
    ]);
  }

  /// Bu karede ne çizilecek. [veri] builder'ın verdiği seridir; geçiş
  /// kararı burada, build'in geri kalanı yalnız sonucu çizer.
  _Kare _cizimSec(BuildContext context, LineChartData veri) {
    _sakinKare = false;
    final hareketVar = !MediaQuery.disableAnimationsOf(context) &&
        widget.swapDuration > Duration.zero;
    final g = _gecis;
    if (g != null) {
      final hedef = g is _Kamera ? g.hedef : (g as _Morf).hedef;
      final p = _gecisSaati?.value ?? 1;
      if (!_interacting && hareketVar && !_karsilastir(hedef, veri).degisti) {
        _oncekiCizilen = veri;
        return _gecisKaresi(g, p);
      }
      // Hedef değişti (yeni tik, başka dönem) ya da jest başladı: o an
      // çizilen kare yeni karşılaştırmanın başlangıcıdır.
      _oncekiCizilen = _gecisKaresi(g, p).cizim;
      if (_interacting || !hareketVar) _gecisiBirak();
    }
    final onceki = _oncekiCizilen;
    final degisti = _gorunurDegisti(veri);
    final donem = _donemDegisti && degisti;
    if (degisti) _donemDegisti = false;
    if (!degisti || _interacting || !hareketVar || onceki == null) {
      if (_gecis != null) _gecisiBirak();
      _sakinKare = !degisti && !_interacting && hareketVar && onceki != null;
      return _durgun(veri);
    }
    if (donem) {
      final k = _kameraKur(veri);
      if (k != null) {
        _gecisBaslat(k);
        return _kameraKaresi(k, 0);
      }
    }
    if (_yapiDegisti) {
      // Gösterge aç/kapa: anında (bkz. [_karsilastir]). Dönem değişimi:
      // eski çizim üstte söner.
      if (donem) {
        _solan = onceki;
        _solmaNo++;
      }
      if (_gecis != null) _gecisiBirak();
      return _durgun(veri);
    }
    final kopru = _kopruKur(onceki, veri);
    final m = _Morf(veri, kopru?.eski ?? onceki, kopru?.yeni ?? veri);
    _gecisBaslat(m);
    return _gecisKaresi(m, 0);
  }

  // ── Değerine bağlı Y etiketleri ve yatay ızgara (2026-11-14) ──────────
  //
  // fl_chart sağ etiketleri ve yatay ızgarayı her karede adımın ara
  // değeriyle yeniden dizer. Burada her ADIM bir takımdır; takımın
  // etiketleri değerlerine bağlıdır ve ölçekle birlikte kayar. Adım
  // değişince eski takım [SandikMotion.surface] içinde söner, yenisi
  // belirir; iki takımda ortak değer hiç sönmez. Etiketin kendisi yine
  // sahibin `getTitlesWidget`'ından gelir (biçim ve stil sahibinde kalır),
  // yeri fl_chart'ın koyduğu yerdir: sağ rezervin solu, değerin hizası.

  List<_TikTakimi> _takimlar = [];
  AnimationController? _takimSaati;

  double _opak(_TikTakimi k) {
    final c = _takimSaati;
    if (c == null || !c.isAnimating) return k.hedef;
    return k.bas + (k.hedef - k.bas) * SandikMotion.enter.transform(c.value);
  }

  void _takimGuncelle(double adim, SideTitles etiket,
      FlLine Function(double)? izgara, bool hareket) {
    final son = _takimlar.isEmpty ? null : _takimlar.last;
    if (son != null && (son.adim - adim).abs() <= adim * 1e-9) {
      son.etiket = etiket;
      son.izgara = izgara;
      return;
    }
    if (!hareket || son == null) {
      _takimSaati?.stop();
      _takimlar = [_TikTakimi(adim, etiket, izgara, 1, 1)];
      return;
    }
    for (final k in _takimlar) {
      k.bas = _opak(k);
      k.hedef = 0;
    }
    _takimlar
      ..removeWhere((k) => k.bas <= 0.01)
      ..add(_TikTakimi(adim, etiket, izgara, 0, 1));
    final c = _takimSaati ??= AnimationController(vsync: this)
      ..addListener(() {
        if (mounted && !_kurulumda) setState(() {});
      })
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed && mounted) {
          setState(() => _takimlar.removeWhere((k) => k.hedef == 0));
        }
      });
    c.duration = SandikMotion.surface;
    final k = _kurulumda;
    _kurulumda = true;
    c.forward(from: 0);
    _kurulumda = k;
  }

  static double _yan(FlTitlesData t, AxisTitles a) => !t.show
      ? 0
      : (a.sideTitles.showTitles ? a.sideTitles.reservedSize : 0) +
          (a.axisNameWidget != null ? a.axisNameSize : 0);

  /// Sağ etiketleri bu sınıf mı çiziyor (rezervli sağ eksen, adım belli).
  static bool _yEkseniBizde(LineChartData d) =>
      d.titlesData.show &&
      d.titlesData.rightTitles.sideTitles.showTitles &&
      d.titlesData.rightTitles.sideTitles.interval != null &&
      d.minY < d.maxY;

  static bool _izgaraBizde(LineChartData d) {
    final g = d.gridData;
    final adim = d.titlesData.rightTitles.sideTitles.interval;
    return g.show &&
        g.drawHorizontalLine &&
        (g.horizontalInterval == null || g.horizontalInterval == adim);
  }

  /// fl_chart'a giden kare: sağ etiket yazısı ve (bizdeyse) yatay ızgara
  /// boşaltılır; rezerv aynı kalır, çizim alanı kımıldamaz.
  static LineChartData _eksensiz(LineChartData d, bool izgara) => d.copyWith(
        titlesData: d.titlesData.copyWith(
            rightTitles: _bosEksen(d.titlesData.rightTitles)),
        gridData: izgara ? d.gridData.copyWith(drawHorizontalLine: false) : null,
      );

  /// Görünür tikler: değer, opaklık (takım × kenar × sıklık), takım.
  static List<({double deger, double opak, _TikTakimi takim})> gorunurTikler(
    List<_TikTakimi> takimlar,
    double Function(_TikTakimi) opak, {
    required double minY,
    required double maxY,
    required double eksenPx,
  }) {
    final aralik = maxY - minY;
    if (aralik <= 0 || eksenPx <= 0) return const [];
    final tikler = <String, ({double deger, double opak, _TikTakimi takim})>{};
    for (final k in takimlar) {
      final o = opak(k);
      if (o <= 0.01 || k.adim <= 0) continue;
      // Adım ekranda 24 px'ten sıksa (ölçek açılırken sıkışan eski takım)
      // erken söner: etiketler üst üste binmez.
      final bosluk = eksenPx * k.adim / aralik;
      final sik = ((bosluk - 10) / 14).clamp(0.0, 1.0);
      if (sik <= 0) continue;
      final ilk = (minY / k.adim).ceil();
      final son = (maxY / k.adim).floor();
      if (son - ilk > 64) continue;
      for (var i = ilk; i <= son; i++) {
        final v = i * k.adim;
        final eps = k.adim * 1e-9;
        // fl_chart'taki sahipler uç değeri gizler (`val == meta.min/max`).
        if ((v - minY).abs() <= eps || (v - maxY).abs() <= eps) continue;
        // İki takımda aynı değer tek tiktir (ortak etiket sönmez).
        final anahtar = v.toStringAsPrecision(10);
        final top = o * sik;
        final eski = tikler[anahtar];
        if (eski == null || top >= eski.opak) {
          tikler[anahtar] = (deger: v, opak: math.max(top, eski?.opak ?? 0), takim: k);
        }
      }
    }
    return tikler.values.toList();
  }

  /// Izgara ve etiket katmanları; `null` → sağ ekseni fl_chart çiziyor.
  ({Widget izgara, Widget etiketler})? _yEkseniKatmanlari(
      LineChartData cizim, double genislik) {
    if (_takimlar.isEmpty || !_yEkseniBizde(cizim)) return null;
    final t = cizim.titlesData;
    final kenar = cizim.borderData.isVisible()
        ? cizim.borderData.border.dimensions.resolve(TextDirection.ltr)
        : EdgeInsets.zero;
    final ust = _yan(t, t.topTitles) + kenar.top;
    final alt = _yan(t, t.bottomTitles) + kenar.bottom;
    final sagRezerv = _yan(t, t.rightTitles);
    final sol = _yan(t, t.leftTitles) + kenar.left;
    final sag = genislik - sagRezerv - kenar.right;
    final eksenPx = widget.height - ust - alt;
    final minY = cizim.minY;
    final maxY = cizim.maxY;
    final tikler = gorunurTikler(_takimlar, _opak,
        minY: minY, maxY: maxY, eksenPx: eksenPx);
    double konum(double v) => (1 - (v - minY) / (maxY - minY)) * eksenPx;
    final cizgiler = <(double, double, FlLine)>[];
    final etiketler = <Widget>[];
    for (final tk in tikler) {
      final loc = konum(tk.deger);
      // Kenarda yumuşak çıkış: merkez çizim alanının 8 px dışına
      // giderken söner (fl_chart sınırı geçen etiketi tek karede atıyordu).
      final disari = loc < 0 ? -loc : (loc > eksenPx ? loc - eksenPx : 0.0);
      final o = tk.opak * (1 - disari / 8).clamp(0.0, 1.0);
      if (o <= 0.01) continue;
      final izgara = tk.takim.izgara;
      if (izgara != null && loc >= 0 && loc <= eksenPx) {
        cizgiler.add((ust + loc, o, izgara(tk.deger)));
      }
      final st = tk.takim.etiket;
      etiketler.add(Positioned(
        key: ValueKey(tk.deger.toStringAsPrecision(10)),
        left: genislik - sagRezerv,
        width: sagRezerv,
        top: ust + loc - 20,
        height: 40,
        child: Opacity(
          opacity: o,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: sagRezerv,
              child: st.getTitlesWidget(
                tk.deger,
                TitleMeta(
                  min: minY,
                  max: maxY,
                  parentAxisSize: eksenPx,
                  axisPosition: loc,
                  appliedInterval: tk.takim.adim,
                  sideTitles: st,
                  formattedValue: tk.deger.toString(),
                  axisSide: AxisSide.right,
                ),
              ),
            ),
          ),
        ),
      ));
    }
    return (
      izgara: CustomPaint(painter: _IzgaraBoyasi(cizgiler, sol, sag)),
      etiketler: Stack(clipBehavior: Clip.hardEdge, children: etiketler),
    );
  }

  // ── Kayan yatay çizgiler (alarm seviyesi, 2026-11-11) ──────────────────
  //
  // Alarm kurulunca/düzenlenince çizgisi yeni seviyede anında beliriyordu:
  // `_karsilastir` ek çizgilere bakmaz (bakması da yetmezdi — fl_chart
  // listeleri sıra numarasıyla eşler, çizgi sayısı değişince lerp etmez).
  // [KayanYatayCizgi] anahtar taşır; aynı anahtar yeni y ile gelince çizgi
  // DEĞER uzayında eskisinden kayar, piksel dönüşümü fl_chart'ta kalır.
  //
  // Kayma YALNIZ "sakin" karede başlar: grafiğin geri kalanı (eksen,
  // noktalar, çubuk sayısı) değişmemiş, jest yok, hareketi azalt kapalı,
  // grafik daha önce çizilmiş. Dönem değişimi, yakınlaştırma, LOG/
  // Karşılaştır geçişi noktaları değiştirir → çizgi anında yeni ölçekte
  // yerini alır (dönem morfu/köprüsü onu ölçekle birlikte taşır); aralığa
  // giren/çıkan alarm çizgisi de bu yüzden kaymaz, yalnız seviyesi
  // değişen kayar. Sakin karede kaybolan anahtar silinmiştir: söner.

  /// Bu karede grafiğin geri kalanı değişmedi mi (bkz. [_cizimSec]).
  bool _sakinKare = false;

  /// Build sürerken denetleyici bildirimi setState istemesin.
  bool _kurulumda = false;

  AnimationController? _kayma;
  final Map<Object, double> _kaymaBas = {};
  final Map<Object, double> _kaymaHedef = {};
  final Map<Object, HorizontalLine> _sonenler = {};

  double _kaymaT() => SandikMotion.move.transform(_kayma?.value ?? 1);

  double _gorunenY(Object k) {
    final hedef = _kaymaHedef[k]!;
    final bas = _kaymaBas[k];
    if (bas == null || !(_kayma?.isAnimating ?? false)) return hedef;
    return bas + (hedef - bas) * _kaymaT();
  }

  static HorizontalLine _cizgiKopyasi(HorizontalLine c,
          {required double y, double opaklik = 1}) =>
      HorizontalLine(
        y: y,
        label: c.label,
        color: c.color?.withValues(alpha: (c.color!.a * opaklik)),
        gradient: c.gradient,
        strokeWidth: c.strokeWidth,
        dashArray: c.dashArray,
        image: c.image,
        sizedPicture: c.sizedPicture,
        strokeCap: c.strokeCap,
      );

  LineChartData _kayanCizgiler(BuildContext context, LineChartData d) {
    final cizgiler = d.extraLinesData.horizontalLines;
    final kayanlar = <Object, KayanYatayCizgi>{
      for (final c in cizgiler)
        if (c is KayanYatayCizgi) c.anahtar: c,
    };
    if (kayanlar.isEmpty && _kaymaHedef.isEmpty && _sonenler.isEmpty) {
      return d;
    }

    var degisim = false;
    for (final e in kayanlar.entries) {
      if (_kaymaHedef[e.key] != e.value.y) degisim = true;
    }
    for (final k in _kaymaHedef.keys) {
      if (!kayanlar.containsKey(k)) degisim = true;
    }

    if (degisim) {
      final sure = SandikMotion.stateOf(context);
      final kaydir = _sakinKare && sure > Duration.zero;
      if (!kaydir) {
        _kayma?.stop();
        _kaymaBas.clear();
        _sonenler.clear();
      } else {
        // Yeni başlangıç: her çizginin ŞU AN göründüğü yer (süren kayma
        // yarıda kesilirse oradan devam eder, geri sıçramaz).
        final bas = <Object, double>{};
        for (final e in kayanlar.entries) {
          bas[e.key] = _kaymaHedef.containsKey(e.key)
              ? _gorunenY(e.key)
              : (e.value.dogumY ?? e.value.y);
        }
        for (final k in _kaymaHedef.keys) {
          if (!kayanlar.containsKey(k) && _sonCizgi.containsKey(k)) {
            _sonenler[k] = _cizgiKopyasi(_sonCizgi[k]!, y: _gorunenY(k));
          }
        }
        _kaymaBas
          ..clear()
          ..addAll(bas);
        final c = _kayma ??= AnimationController(vsync: this)
          ..addListener(() {
            if (mounted && !_kurulumda) setState(() {});
          })
          ..addStatusListener((st) {
            if (st == AnimationStatus.completed && mounted) {
              setState(() {
                _kaymaBas.clear();
                _sonenler.clear();
              });
            }
          });
        c.duration = sure;
        c.forward(from: 0);
      }
      _kaymaHedef
        ..clear()
        ..addAll({for (final e in kayanlar.entries) e.key: e.value.y});
      _sonCizgi
        ..clear()
        ..addAll(kayanlar);
    }

    final suruyor = _kayma?.isAnimating ?? false;
    if (!suruyor) return d;
    final t = _kaymaT();
    return d.copyWith(
      extraLinesData: ExtraLinesData(
          verticalLines: d.extraLinesData.verticalLines,
          extraLinesOnTop: d.extraLinesData.extraLinesOnTop,
          horizontalLines: [
            for (final c in cizgiler)
              if (c is KayanYatayCizgi)
                _cizgiKopyasi(c, y: _gorunenY(c.anahtar))
              else
                c,
            for (final c in _sonenler.values)
              _cizgiKopyasi(c, y: c.y, opaklik: 1 - t),
          ]),
    );
  }

  /// Son hedef çizgiler (sönen çizginin rengi/deseni buradan).
  final Map<Object, KayanYatayCizgi> _sonCizgi = {};

  void _setInteracting(bool v) {
    if (_interacting == v) return;
    // Jest sırasında setState zaten viewport değişimiyle tetikleniyor;
    // burada yalnızca bayrağı güncelliyoruz (build bir sonraki karede
    // doğru süreyi okur).
    _interacting = v;
    widget.viewportController?.jestSuruyor = v;
  }

  @override
  void initState() {
    super.initState();
    _localMinX = widget.fullMinX;
    _localMaxX = widget.fullMaxX;
    widget.viewportController?.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant ZoomableChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewportController != widget.viewportController) {
      oldWidget.viewportController?.removeListener(_onControllerChanged);
      widget.viewportController?.addListener(_onControllerChanged);
    }
    if (oldWidget.sifirlamaAnahtari != widget.sifirlamaAnahtari ||
        oldWidget.viewportController != widget.viewportController) {
      // Dönem/filtre değişimi: bir sonraki görünür değişiklik "dönem
      // geçişi"dir (bkz. [_cizimSec]). Performans dönem değişiminde yeni
      // viewport controller kurar, varlık ekranları anahtarı değiştirir.
      _donemDegisti = true;
    }
    if (oldWidget.sifirlamaAnahtari != widget.sifirlamaAnahtari) {
      // Dönem/sıklık değişti: yakınlaştırma taşınmaz (bkz.
      // [ZoomableChart.sifirlamaAnahtari]). Build sırasında: setState yok,
      // yerel pencere doğrudan yazılır; controller'ın bildirimi build
      // sonrasına ertelenir (`updateFullRangeSessiz` ile aynı gerekçe).
      _localMinX = widget.fullMinX;
      _localMaxX = widget.fullMaxX;
      final c = widget.viewportController;
      if (c != null && c.sifirlaSessiz(widget.fullMinX, widget.fullMaxX)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => c.bildir());
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onViewportChanged?.call(widget.fullMinX, widget.fullMaxX);
        }
      });
      return;
    }
    if (oldWidget.fullMinX != widget.fullMinX ||
        oldWidget.fullMaxX != widget.fullMaxX) {
      // Yakınlaştırma korunur (bkz. [ChartViewport.korunanPencere]): varlık
      // detayında `maxX` dakika dönümünde değişiyor ve eskiden yerel zoom'u
      // her dakika sıfırlıyordu.
      final p = ChartViewport.korunanPencere(
        minX: _localMinX,
        maxX: _localMaxX,
        eskiMin: oldWidget.fullMinX,
        eskiMax: oldWidget.fullMaxX,
        yeniMin: widget.fullMinX,
        yeniMax: widget.fullMaxX,
      );
      _localMinX = p.$1;
      _localMaxX = p.$2;
      // Controller varsa full range'i de güncelle
      widget.viewportController
          ?.updateFullRange(widget.fullMinX, widget.fullMaxX);
    }
  }

  @override
  void dispose() {
    _gecisSaati?.dispose();
    _takimSaati?.dispose();
    _kayma?.dispose();
    widget.viewportController?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _setViewport(double newMin, double newMax) {
    final c = widget.viewportController;
    if (c != null) {
      c.set(newMin, newMax);
    } else {
      setState(() {
        _localMinX = newMin;
        _localMaxX = newMax;
      });
    }
  }

  bool get _isZoomed =>
      (_minX - widget.fullMinX).abs() > 0.001 ||
      (_maxX - widget.fullMaxX).abs() > 0.001;

  bool get _crosshairEnabled => widget.crosshairLabelBuilder != null;

  void _reset() {
    _setViewport(widget.fullMinX, widget.fullMaxX);
    widget.onViewportChanged?.call(widget.fullMinX, widget.fullMaxX);
  }

  /// Son tek dokunuşun zamanı ve yeri — çift dokunuşu elle saymak için.
  static final Stopwatch _saat = Stopwatch()..start();
  Duration? _sonDokunusZamani;
  Offset? _sonDokunusYeri;
  double? _ciftDokunusPx;

  void _dokunusBitti(TapUpDetails d) {
    final simdi = _saat.elapsed;
    final onceki = _sonDokunusZamani;
    final oncekiYer = _sonDokunusYeri;
    if (onceki != null &&
        oncekiYer != null &&
        simdi - onceki <= kDoubleTapTimeout &&
        (d.localPosition - oncekiYer).distance <= kDoubleTapSlop) {
      _sonDokunusZamani = null;
      _sonDokunusYeri = null;
      _ciftDokunusPx = d.localPosition.dx;
      _ciftDokunus();
      return;
    }
    _sonDokunusZamani = simdi;
    _sonDokunusYeri = d.localPosition;
  }

  /// Çift dokunuş: yakın değilse dokunulan yere 2,5× yakınlaşır,
  /// yakınsa tam aralığa döner.
  ///
  /// yasin 2026-10-12 (TestFlight): "zoom featurelarını da iyileştirebiliriz,
  /// net ve doğru şekilde izlenebilmeli." Yakınlaşmanın tek yolu iki parmak,
  /// dönmenin tek yolu köşedeki küçük "Sıfırla" idi. Çift dokunuş iOS'un
  /// sistem kalıbı (Fotoğraflar, Haritalar) ve tek elle yapılır; tek
  /// dokunuşun bu grafiklerde işi yok (yerleşik dokunuşlar kapalı, imleç
  /// uzun basışta), yani bekletilen bir şey olmaz. Geçiş grafiğin kendi
  /// morfuyla akar (hareketi azalt'ta anlık, bkz. build).
  void _ciftDokunus() {
    final fullWidth = widget.fullMaxX - widget.fullMinX;
    if (fullWidth <= 0) return;
    SandikHaptic.selection.perform();
    if (_isZoomed) {
      _reset();
      return;
    }
    final px = _ciftDokunusPx;
    final rel = px == null
        ? 1.0
        : ((px - _plotLeft) / _plotWidth).clamp(0.0, 1.0);
    final odak = _minX + (_maxX - _minX) * rel;
    final genislik = fullWidth / 2.5;
    var lo = odak - genislik * rel;
    var hi = lo + genislik;
    if (lo < widget.fullMinX) {
      lo = widget.fullMinX;
      hi = lo + genislik;
    }
    if (hi > widget.fullMaxX) {
      hi = widget.fullMaxX;
      lo = hi - genislik;
    }
    _setViewport(lo, hi);
    widget.onViewportChanged?.call(lo, hi);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _setInteracting(true);
    _startMinX = _minX;
    _startMaxX = _maxX;
    // Focal point plot area sınırlarına clamp — Y ekseni bandına gelirse
    // %100 olarak alma.
    final localInPlot =
        (details.localFocalPoint.dx - _plotLeft).clamp(0.0, _plotWidth);
    _startFocalRel = (localInPlot / _plotWidth).clamp(0.0, 1.0);
    _startFocalPx = details.localFocalPoint.dx;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Sadece iki+ parmak (gerçek pinch) veya zoom'luyken tek parmak pan.
    if (details.pointerCount < 2 && !_isZoomed) return;

    final width = _startMaxX - _startMinX;
    if (width <= 0) return;

    // Pinch her açıda tetiklenmeli — yatay, dikey ya da çapraz. `details.scale`
    // geometric mean, dikey pinch'te ~1.0 kalıp chart'ı zoom etmiyor. Yatay ve
    // dikey ölçekten "1'den daha uzak olanı" seç → dikey pinch de X zoom yapar.
    final hs = details.horizontalScale;
    final vs = details.verticalScale;
    final effectiveScale = ((hs - 1).abs() >= (vs - 1).abs()) ? hs : vs;
    double newWidth = width / effectiveScale;
    final fullWidth = widget.fullMaxX - widget.fullMinX;
    final minWidth = fullWidth * 0.02;
    if (newWidth < minWidth) newWidth = minWidth;
    if (newWidth > fullWidth) newWidth = fullWidth;

    final focalX = _startMinX + width * _startFocalRel;
    double newMin = focalX - newWidth * _startFocalRel;
    double newMax = newMin + newWidth;

    // Kaydırma jest BAŞINDAN bu yana toplam yer değiştirme. Pencere her
    // karede başlangıç penceresinden (`_startMinX`) yeniden kurulduğu için
    // `focalPointDelta` (yalnız SON karenin farkı) kullanılamaz: grafik her
    // karede başlangıca bir kare kadar kayıp geri dönüyor, parmağı takip
    // etmiyordu (animasyon denetimi 2026-10-01). Toplam farkla, başta
    // parmağın altındaki veri noktası parmağın altında kalır.
    final panPx = details.localFocalPoint.dx - _startFocalPx;
    final panData = -panPx / _plotWidth * newWidth;
    newMin += panData;
    newMax += panData;

    if (newMin < widget.fullMinX) {
      final overflow = widget.fullMinX - newMin;
      newMin += overflow;
      newMax += overflow;
    }
    if (newMax > widget.fullMaxX) {
      final overflow = newMax - widget.fullMaxX;
      newMin -= overflow;
      newMax -= overflow;
    }

    _setViewport(newMin, newMax);
    widget.onViewportChanged?.call(newMin, newMax);
  }

  /// Chart plot area'nın genişliği = toplam - sağ Y rezervi - sol Y rezervi.
  /// Kullanıcı touch'ı bu alana konumlanır; Y ekseni bandına düşen dokunuşlar
  /// clamp'lenir. TradingView'de dikey crosshair Y-ekseni bantına asla girmez.
  double get _plotWidth {
    final w = _chartWidth - widget.plotPaddingRight - widget.plotPaddingLeft;
    return w <= 0 ? 1.0 : w;
  }

  double get _plotLeft => widget.plotPaddingLeft;
  double get _plotRight => _chartWidth - widget.plotPaddingRight;

  void _updateCrosshair(double localDx) {
    // Touch X'i plot area sınırlarına clamp — Y ekseni bandında dokunulsa
    // bile crosshair plot içinde kalır.
    final clamped = localDx.clamp(_plotLeft, _plotRight);
    final relInPlot = (clamped - _plotLeft) / _plotWidth;
    var xData = _minX + (_maxX - _minX) * relInPlot;
    var px = clamped;
    // En yakın data noktasına snap: hem çizgi hem label aynı X'te olsun.
    if (widget.crosshairSnapX != null) {
      final snappedX = widget.crosshairSnapX!(xData);
      xData = snappedX;
      final span = _maxX - _minX;
      if (span > 0) {
        px = (_plotLeft +
                (snappedX - _minX) / span * _plotWidth)
            .clamp(_plotLeft, _plotRight);
      }
    }
    // Aynı veri noktasına oturduysa yeniden kurma: parmak her pikselde olay
    // üretiyor ama imleç yalnız nokta değişince hareket ediyor — boşuna
    // etiket/detay kurucuları koşuyordu (animasyon denetimi 2026-10-01).
    if (px == _crosshairPx && xData == _crosshairX) return;
    // İmleç belirdiği an hafif dokunsal onay: uzun basış tuttu, artık
    // parmak grafiği okuyor. Nokta başına DEĞİL — yoğun seride (1Y ≈ 250
    // nokta) sürekli titreşim yorucu olur.
    if (_crosshairPx == null ||
        (xData != _crosshairX && widget.titresimNoktalari.contains(xData))) {
      SandikHaptic.selection.perform();
    }
    setState(() {
      _crosshairPx = px;
      _crosshairX = xData;
    });
    final dinleyen = widget.imlecEtiketi;
    if (dinleyen != null) {
      dinleyen.value =
          (widget.imlecEtiketiBuilder ?? widget.crosshairLabelBuilder)
              ?.call(xData);
    }
  }

  // ── Ekran okuyucuyla gün gün gezinme (erişilebilirlik, 2026-11-11) ──────
  //
  // Grafik VoiceOver/TalkBack'e yalnız özet veriyordu ("görünen aralıkta
  // yüzde 4 arttı"); görmeyen kullanıcı tek bir günün fiyatını
  // okuyamıyordu. Grafik artık ayarlanabilir öğe: yukarı/aşağı kaydırma
  // imleci görünen penceredeki bir sonraki/önceki noktaya taşır, değer o
  // noktanın imleç etiketiyle okunur ("12 Ağu 2026, ₺41,20"). Biçim
  // [crosshairLabelBuilder]'ın kendisi — parmakla gezinen kullanıcının
  // balonda gördüğü metin; birim/gizlilik kararı yine çağıranda kalır.
  //
  // Neden ortak bileşende: dört grafik yüzeyi (Performans, varlık detayı,
  // fiyat grafiği, karşılaştırma) aynı davranışı ister
  // (`chart_interaction_parity_test`); her ekran kendi gezinmesini kursaydı
  // ayrışırdı. Görsel imleç de aynı noktaya oturur (az gören kullanıcı
  // ekranda da izler); imleç seçilmemişken değer özet kalır.

  /// Ekran okuyucu imlecinin X'i; `null` → özet okunur. Dokunma imleci
  /// kalkınca ([_clearCrosshair]) o da bırakılır.
  double? _okuyucuX;

  /// Görünen penceredeki ilk çizginin nokta X'leri, sıralı. Ekran okuyucu
  /// adımları buradan; pencere/veri değişmedikçe yeniden kurulmaz.
  List<double> _okuyucuNoktalari() {
    final veri = _grafikVerisi();
    if (identical(veri, _noktaVerisi)) return _noktalar;
    _noktaVerisi = veri;
    final xs = <double>{};
    for (final bar in veri.lineBarsData) {
      if (bar.spots.isEmpty) continue;
      for (final p in bar.spots) {
        if (p.isNull() || p.x < _minX || p.x > _maxX) continue;
        xs.add(p.x);
      }
      break;
    }
    return _noktalar = xs.toList()..sort();
  }

  Object? _noktaVerisi;
  List<double> _noktalar = const [];

  /// Noktanın sesli metni: imleç etiketinin tarih + değer satırı.
  String? _noktaMetni(double x) {
    final e = widget.crosshairLabelBuilder?.call(x);
    if (e == null) return null;
    return e.$2.isEmpty ? e.$1 : '${e.$2}, ${e.$1}';
  }

  /// [yon] +1 sonraki, -1 önceki noktanın sırası; imleç yokken ileri ilk,
  /// geri son noktadan başlar. Uçta `null` (eylem sunulmaz).
  int? _okuyucuKomsu(List<double> xs, int yon) {
    if (xs.isEmpty) return null;
    final x = _okuyucuX;
    if (x == null) return yon > 0 ? 0 : xs.length - 1;
    // Pencere kaydıysa imleç en yakın sıraya oturur.
    var i = 0;
    var enIyi = double.infinity;
    for (var k = 0; k < xs.length; k++) {
      final d = (xs[k] - x).abs();
      if (d < enIyi) {
        enIyi = d;
        i = k;
      }
    }
    final j = i + yon;
    return j < 0 || j >= xs.length ? null : j;
  }

  void _okuyucuyaGit(double x) {
    final span = _maxX - _minX;
    final px = span > 0
        ? (_plotLeft + (x - _minX) / span * _plotWidth)
            .clamp(_plotLeft, _plotRight)
        : _plotLeft;
    setState(() {
      _okuyucuX = x;
      _crosshairX = x;
      _crosshairPx = px;
    });
    final dinleyen = widget.imlecEtiketi;
    if (dinleyen != null) {
      dinleyen.value =
          (widget.imlecEtiketiBuilder ?? widget.crosshairLabelBuilder)
              ?.call(x);
    }
  }

  void _clearCrosshair() {
    _okuyucuX = null;
    widget.imlecEtiketi?.value = null;
    if (_crosshairPx == null) return;
    setState(() {
      _crosshairPx = null;
      _crosshairX = null;
    });
  }

  // ── Time scale drag ────────────────────────────────────────────────────
  // Bottom axis alanında horizontal drag: sağa = daralt (zoom in), sola =
  // genişlet (zoom out). Sağ kenar pivot — son nokta sabit kalır.
  double _timeDragStartWidth = 0;

  void _onTimeDragStart(DragStartDetails _) {
    _setInteracting(true);
    _timeDragStartWidth = _maxX - _minX;
  }

  void _onTimeDragEnd(DragEndDetails _) {
    if (!mounted) return;
    setState(() => _setInteracting(false));
  }

  void _onTimeDragUpdate(DragUpdateDetails d) {
    if (_chartWidth <= 0 || _timeDragStartWidth <= 0) return;
    // Delta piksel → viewport genişlik oranı. Sağa 100px drag genişliğin
    // yaklaşık %25'i kadar daraltsın (~4x sensitivity).
    final delta = d.primaryDelta ?? 0;
    if (delta == 0) return;
    final factor = 1 - (delta / _plotWidth) * 2.5;
    double newWidth = (_maxX - _minX) * factor;
    final fullWidth = widget.fullMaxX - widget.fullMinX;
    final minWidth = fullWidth * 0.02;
    if (newWidth < minWidth) newWidth = minWidth;
    if (newWidth > fullWidth) newWidth = fullWidth;
    // Sağ kenar sabit: newMax = eski maxX, newMin = newMax - newWidth
    double newMin = _maxX - newWidth;
    double newMax = _maxX;
    if (newMin < widget.fullMinX) {
      newMin = widget.fullMinX;
      newMax = newMin + newWidth;
      if (newMax > widget.fullMaxX) newMax = widget.fullMaxX;
    }
    _setViewport(newMin, newMax);
    widget.onViewportChanged?.call(newMin, newMax);
  }

  @override
  Widget build(BuildContext context) {
    // Etiket kurucusu yoksa okunacak nokta metni de yok: eylem sunulmaz.
    final xs = widget.crosshairLabelBuilder == null
        ? const <double>[]
        : _okuyucuNoktalari();
    final okuyucuX = _okuyucuX;
    final deger = okuyucuX != null
        ? _noktaMetni(okuyucuX)
        : widget.semanticValueBuilder?.call(_minX, _maxX);
    // Ayarlanabilir öğe hem şimdiki hem komşu değeri okutmak ZORUNDA
    // (çerçeve, değeri boş eylemli düğümü reddeder). Özeti olmayan grafik
    // (yalnız etiket) ya da metni kurulamayan nokta → eylem sunulmaz.
    final degerVar = deger != null && deger.isNotEmpty;
    String? komsuMetni(int? i) {
      if (!degerVar || i == null) return null;
      final m = _noktaMetni(xs[i]);
      return m == null || m.isEmpty ? null : m;
    }

    final ileriI = _okuyucuKomsu(xs, 1);
    final geriI = _okuyucuKomsu(xs, -1);
    final ileri = komsuMetni(ileriI);
    final geri = komsuMetni(geriI);
    return Semantics(
      label: widget.semanticLabel ?? context.l10n.chartPriceSemantics,
      value: deger,
      increasedValue: ileri,
      decreasedValue: geri,
      onIncrease: ileri == null ? null : () => _okuyucuyaGit(xs[ileriI!]),
      onDecrease: geri == null ? null : () => _okuyucuyaGit(xs[geriI!]),
      image: true,
      child: LayoutBuilder(builder: (context, constraints) {
      _chartWidth = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;
      final ham = _cizimSec(context, _grafikVerisi());
      _kurulumda = true;
      var cizim = _kayanCizgiler(context, ham.cizim);
      _kurulumda = false;
      // Sağ eksen bizdeyse fl_chart'a yazısız ve (uygunsa) ızgarasız kare
      // gider; takım adımı eksen kaynağından (geçişin hedefi), konum çizilen
      // kareden okunur.
      ({Widget izgara, Widget etiketler})? yEkseni;
      if (_yEkseniBizde(ham.eksen) && _yEkseniBizde(cizim)) {
        final izgaraBizde = _izgaraBizde(ham.eksen);
        final st = ham.eksen.titlesData.rightTitles.sideTitles;
        _takimGuncelle(
            st.interval!,
            st,
            izgaraBizde ? ham.eksen.gridData.getDrawingHorizontalLine : null,
            !MediaQuery.disableAnimationsOf(context));
        yEkseni = _yEkseniKatmanlari(cizim, _chartWidth);
        if (yEkseni != null) {
          cizim = _eksensiz(cizim, izgaraBizde && _izgaraBizde(cizim));
        }
      } else {
        _takimlar = [];
      }
      final ust = ham.ust;
      final solan = _solan;
      return SizedBox(
        height: widget.height,
        child: Stack(
          // **Çizim kendi kutusunun DIŞINA taşamaz.**
          //
          // `Clip.none` gerekçesizdi ve pinch sırasında görünür bir hataya
          // yol açıyordu: `LineChart` bir ImplicitlyAnimatedWidget, jest
          // boyunca eski `LineChartData` ile yenisi arasında lerp'liyor ve
          // ara karelerde min/max sınırları anlık olarak hedefin dışına
          // çıkabiliyor. Clip yokken o karelerdeki çizgi kartın dışına,
          // başlığın ve dönem seçicinin üstüne basıyordu (kullanıcı
          // ekran görüntüsü, GÜNLÜK sekmesi).
          //
          // Stack'in Flutter varsayılanı zaten `Clip.hardEdge`; burada
          // taşmadan yararlanan bir çocuk YOK — crosshair çizgisi, pill ve
          // Sıfırla çipi hepsi kutunun içinde konumlanıyor.
          clipBehavior: Clip.hardEdge,
          children: [
            // Değerine bağlı yatay ızgara: çizginin ALTINDA (açık temada
            // ızgara beyazdır, üstte olsa çizgiyi keserdi). Katman HEP ağaçta.
            Positioned.fill(
              child: IgnorePointer(
                child: yEkseni?.izgara ?? const SizedBox.shrink(),
              ),
            ),
            // Alt: LineChart (tooltip'i için touch handler kendi içinde çalışır)
            //
            // `LineChart` bir ImplicitlyAnimatedWidget: yeni LineChartData
            // gelince eskisinden yenisine kendi lerp'ler. Periyot/filtre
            // değişiminde grafiğin "0'dan yeniden çizilmesi" yerine akıcı
            // şekilde şekil değiştirmesini sağlayan mekanizma budur —
            // ANCAK widget ağaçta kalmalı, aksi halde State ve tween sıfırlanır.
            //
            // Süre iki moda ayrılır:
            //  • Jest sırasında (pinch/pan) animasyon KAPALI (Duration.zero).
            //    Aksi halde her kare bir önceki hedefe doğru lerp'lerken yeni
            //    hedef gelir; parmak takip etmesi gecikmeli/lastikli hissedilir.
            //  • Veri/periyot değişiminde `swapDuration` ile yumuşak morf.
            // RepaintBoundary: imleç ve balon her karede değişirken çizgi
            // grafiği kendi katmanında kalır, yeniden boyanmaz.
            Positioned.fill(
              child: _IlkCizim(
                child: RepaintBoundary(
                child: LineChart(
                  cizim,
                  // Süre HEP sıfır: ara kareyi geçiş motoru üretir (bkz.
                  // `_cizimSec`). fl_chart'ın kendi lerp'i etiket adımını
                  // ara değerlerden geçirip etiketleri zıplatıyordu.
                  duration: Duration.zero,
                ),
              ),
              ),
            ),

            // Kamera geçişinde öteki dönemin serisi (yalnız çizgi) burada
            // solar/belirir. Katman HEP ağaçta, boşken yer tutmaz.
            Positioned.fill(
              child: IgnorePointer(
                child: ust == null
                    ? const SizedBox.shrink()
                    : Opacity(
                        opacity: ham.ustOpak.clamp(0.0, 1.0),
                        child: LineChart(ust, duration: Duration.zero),
                      ),
              ),
            ),

            // Değerine bağlı Y etiketleri (bkz. `_yEkseniKatmanlari`).
            Positioned.fill(
              child: IgnorePointer(
                child: yEkseni?.etiketler ?? const SizedBox.shrink(),
              ),
            ),

            // Çubuk sayısı değişen dönem geçişinde eski çizim burada söner
            // (bkz. `_cizimSec`). Katman HEP ağaçta: boşken yer tutmayan
            // kutu, Stack'in çocuk sırası hiç değişmez.
            Positioned.fill(
              child: IgnorePointer(
                child: solan == null
                    ? const SizedBox.shrink()
                    : TweenAnimationBuilder<double>(
                        key: ValueKey(_solmaNo),
                        tween: Tween<double>(begin: 1, end: 0),
                        duration: SandikMotion.stateOf(context),
                        curve: SandikMotion.exit,
                        onEnd: () {
                          if (mounted) setState(() => _solan = null);
                        },
                        builder: (context, t, c) =>
                            Opacity(opacity: t, child: c),
                        child: LineChart(solan, duration: Duration.zero),
                      ),
              ),
            ),

            // Crosshair overlay
            if (_crosshairEnabled && _crosshairPx != null)
              _CrosshairOverlay(
                px: _crosshairPx!,
                pill: widget.crosshairLabelBuilder!(_crosshairX!),
                details: widget.crosshairDetailsBuilder
                    ?.call(_crosshairX!),
                reserveTopRight: _isZoomed,
              ),

            // Üst: her zaman aktif gesture layer.
            // trackpad + touch scale recognizer'ı arena'da 2+ parmakla kazanır.
            // Trackpad'de (masaüstü) da scale çalışsın diye supportedDevices.
            Positioned.fill(
              child: RawGestureDetector(
                behavior: HitTestBehavior.translucent,
                gestures: <Type, GestureRecognizerFactory>{
                  ScaleGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          ScaleGestureRecognizer>(
                    () => ScaleGestureRecognizer(
                      supportedDevices: const {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.mouse,
                      },
                    ),
                    (instance) {
                      instance
                        ..onStart = _onScaleStart
                        ..onUpdate = _onScaleUpdate
                        // Jest bitti → implicit animasyon tekrar açılsın.
                        // setState şart: son kare doğru süreyle çizilmeli.
                        ..onEnd = (_) {
                          if (!mounted) return;
                          setState(() => _setInteracting(false));
                        };
                    },
                  ),
                  // Çift dokunuş elle sayılır (iki tek dokunuş, aralık
                  // [kDoubleTapTimeout] ve yakınlık [kDoubleTapSlop]):
                  // `DoubleTapGestureRecognizer` her dokunuşta bekleme
                  // zamanlayıcısı kurar ve tek parmak kaydırmanın sonunda
                  // bile asılı kalıyordu. Tek dokunuşun bu grafiklerde başka
                  // işi yok, beklenecek bir şey de yok.
                  TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                      TapGestureRecognizer>(
                    TapGestureRecognizer.new,
                    (instance) => instance.onTapUp = _dokunusBitti,
                  ),
                  if (_crosshairEnabled)
                    LongPressGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                            LongPressGestureRecognizer>(
                      () => LongPressGestureRecognizer(
                        duration: const Duration(milliseconds: 220),
                      ),
                      (instance) {
                        instance.onLongPressStart =
                            (d) => _updateCrosshair(d.localPosition.dx);
                        instance.onLongPressMoveUpdate =
                            (d) => _updateCrosshair(d.localPosition.dx);
                        instance.onLongPressEnd = (_) => _clearCrosshair();
                        instance.onLongPressCancel = _clearCrosshair;
                      },
                    ),
                },
              ),
            ),

            // Time scale drag zone — bottom axis label alanı üstünde.
            // Sadece bu ince şerit horizontal drag'i yakalar; üstteki pinch
            // ve tap zonları etkilenmez.
            if (widget.enableTimeScaleDrag)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: widget.bottomAxisHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: _onTimeDragStart,
                  onHorizontalDragUpdate: _onTimeDragUpdate,
                  onHorizontalDragEnd: _onTimeDragEnd,
                  onHorizontalDragCancel: () => _onTimeDragEnd(DragEndDetails()),
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: SizedBox.expand(),
                  ),
                ),
              ),

            // Reset chip'i sadece zoom'luyken üstte.
            //
            // Dokunma alanı 44 pt (HIG, 2026-10-12): görünen kapsül küçük
            // kalır, çevresindeki saydam pay dokunuşu alır. Eskiden kapsülün
            // kendisi (~26 pt) tek hedefti. Metin çevrilmiş, yazı tokenından.
            if (_isZoomed)
              Positioned(
                top: 0,
                right: 0,
                child: Semantics(
                  button: true,
                  label: context.l10n.filterReset,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _reset,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                          minWidth: SandikTouch.min,
                          minHeight: SandikTouch.min),
                      child: Padding(
                        padding: const EdgeInsets.all(SandikSpace.sm),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: context.c.golge.withValues(alpha: 0.45),
                            borderRadius:
                                BorderRadius.circular(SandikRadius.lg),
                            border: Border.all(color: context.c.text36),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.zoom_out_map_rounded,
                                  size: 14, color: context.c.text58),
                              const SizedBox(width: 4),
                              Text(context.l10n.filterReset,
                                  style: context.t.labelSmall
                                      ?.copyWith(color: context.c.text58)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }),
    );
  }
}

/// Dikey dashed çizgi (dokunulan X'te) + üstte sabit pozisyonda fiyat/tarih
/// pill'i. Pill sabit tutulur ki grafik içindeki ŞİMDİ/BAŞLANGIÇ etiketleriyle
/// çakışmasın — kullanıcı çizgiyle X'i, pill'le değeri ayrı ayrı okur.
class _CrosshairOverlay extends StatelessWidget {
  final double px;
  final (String, String)? pill;
  final List<(String, Color)>? details;
  /// Sıfırla chip'i sağ üstteyse pill onun soluna kayar.
  final bool reserveTopRight;

  const _CrosshairOverlay({
    required this.px,
    required this.pill,
    this.details,
    this.reserveTopRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(builder: (context, c) {
          return Stack(
            // Crosshair katmanı da kırpılır — dikey çizgi ve pill kutunun
            // içinde konumlanıyor, taşmaya ihtiyaç duyan çocuk yok. Üstteki
            // Stack ile aynı gerekçe.
            clipBehavior: Clip.hardEdge,
            children: [
              // Dikey dashed çizgi — dokunulan X'te
              Positioned(
                left: px - 0.5,
                top: 0,
                bottom: 0,
                child: CustomPaint(
                  size: const Size(1, double.infinity),
                  painter: _DashedLinePainter(
                    color: context.c.text58,
                  ),
                ),
              ),
              // Pill — sabit sağ üst (Sıfırla varsa onun soluna kaç)
              if (pill != null)
                Positioned(
                  top: 6,
                  right: reserveTopRight ? 96 : 8,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 120),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    // Hap zemini TEMAYA bağlıdır (açık tema denetimi
                    // 2026-10-08). Eskiden iki modda da sabit koyu
                    // (`0xFF0A1E15`) idi — "açık zeminde de çizgilerin
                    // arasında okunsun" diye. Ama alttaki `details`
                    // satırlarının renkleri çağırandan TEMAYA göre gelir
                    // (`context.c.gain/loss/text58`); açık temada bunlar
                    // koyu tonlardır ve koyu hap üstünde okunmuyordu
                    // (ör. açık `loss` ~2,3:1). Açık temada hap beyaz yüzey +
                    // kart gölgesi; koyu temada eskisiyle aynı yarı saydam
                    // koyu zemin (`background` %88 — eski sabit buydu).
                    decoration: BoxDecoration(
                      color: context.isLight
                          ? context.c.surface2
                          : context.c.background.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(SandikRadius.md),
                      border: Border.all(
                          color: context.isLight
                              ? context.c.hairline
                              : Colors.white.withValues(alpha: 0.14)),
                      boxShadow: context.isLight ? context.c.cardShadow : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          pill!.$1,
                          // Eşit genişlikli rakam: imleç gezerken fiyat
                          // değiştikçe hap genişliği ve sol kenarı
                          // titremesin (animasyon denetimi 2026-10-01).
                          style: TextStyle(
                            color: context.c.text90,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pill!.$2,
                          style: TextStyle(
                            color: context.c.text58,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (details != null && details!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            height: 1,
                            width: 40,
                            // Açık temada `overlay` opak beyazdır — beyaz
                            // hap üstünde çizgi kaybolurdu.
                            color: context.isLight
                                ? context.c.hairline
                                : context.c.overlay,
                          ),
                          const SizedBox(height: 4),
                          for (final line in details!)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 1),
                              child: Text(
                                line.$1,
                                // Seri rengi (karşılaştırmada amber/
                                // turkuaz…) koyu zemin için seçildi; hap
                                // zemininde metin olarak okunur tona
                                // kaydırılır. Eşiği geçen renk aynen kalır.
                                style: TextStyle(
                                  color: line.$2.okunurUstunde(
                                      context.isLight
                                          ? context.c.surface2
                                          : context.c.background),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashHeight = 4.0;
    const dashSpace = 4.0;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(0, y + dashHeight), paint);
      y += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}

/// Grafik ekrana İLK geldiğinde soldan sağa çizilerek açılır (2026-10-14): iskelet sönerken çizgi tek karede tam hâliyle
/// beliriyordu. Ana sayfa Bugün eğrisiyle aynı dil ([SandikMotion.flow] +
/// [SandikMotion.glide]). `TweenAnimationBuilder` yalnız ilk kurulumda
/// oynar; dönem/filtre değişimi LineChart'ın kendi morfuyla akar, jest
/// sırasında kutu dışına taşan bir şey yok.
/// Hareketi azalt açıkken çocuk doğrudan döner.
///
/// Yalnız ilk kurulumda oynadığı için grafiği taşıyan ekranlar dönem
/// değişiminde `ZoomableChart`'ı SÖKMEMELİ: sökülürse bu açılış her dönem
/// dokunuşunda yeniden oynar ("ekran baştan çiziliyor", yasin 2026-11-11;
/// kilit `grafik_aralik_gecisi_test`).
class _IlkCizim extends StatelessWidget {
  const _IlkCizim({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sure = SandikMotion.flowOf(context);
    if (sure == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: sure,
      curve: SandikMotion.glide,
      child: child,
      // Ağaç biçimi sabit kalır: ClipRect'i söküp takmak LineChart'ın
      // State'ini sıfırlardı. Oyun bitince kırpma kutunun kendisidir —
      // çizim zaten kutusunda kalır (`grafik_tasma_ve_yogunluk_test`).
      builder: (context, t, c) =>
          ClipRect(clipper: _SoldanKirpici(t), child: c),
    );
  }
}

class _SoldanKirpici extends CustomClipper<Rect> {
  const _SoldanKirpici(this.oran);

  final double oran;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * oran, size.height);

  @override
  bool shouldReclip(_SoldanKirpici eski) => eski.oran != oran;
}

/// Anahtarlı yatay çizgi: aynı [anahtar] yeni `y` ile gelince
/// [ZoomableChart] çizgiyi değer uzayında eskisinden kaydırır (bkz.
/// `_kayanCizgiler`). Alarm seviyesi için (2026-11-11).
// Üst sınıfın `image`/`sizedPicture` alanları fl_chart'ta final değil;
// bu sınıf yeni değişken alan eklemiyor.
// ignore: must_be_immutable
class KayanYatayCizgi extends HorizontalLine {
  KayanYatayCizgi({
    required this.anahtar,
    required super.y,
    this.dogumY,
    super.color,
    super.strokeWidth,
    super.dashArray,
  });

  /// Kimlik (alarm kimliği): seviye değişse de aynı çizgi.
  final Object anahtar;

  /// İlk kez göründüğünde (yeni kurulan alarm) buradan kayar — son fiyat.
  /// `null` → yerinde belirir.
  final double? dogumY;
}

/// Bir karede çizilecekler: alt grafik, eksen kaynağı (etiket adımı ve
/// biçimi bundan okunur: geçişte hedef), kamera geçişinde üst katman.
class _Kare {
  _Kare(this.cizim, this.eksen, {this.ust, this.ustOpak = 0});
  final LineChartData cizim;
  final LineChartData eksen;
  final LineChartData? ust;
  final double ustOpak;
}

/// Nokta morfu: [eski]'den [yeni]'ye (köprülü, eşit nokta sayısı); bitince
/// [hedef] (gerçek seri) çizilir.
class _Morf {
  _Morf(this.hedef, this.eski, this.yeni);
  final LineChartData hedef;
  final LineChartData eski;
  final LineChartData yeni;
}

/// Kamera geçişi. Pencere uçları YENİ dönemin koordinatında; kurucuya
/// verilirken kendi kaymasıyla çevrilir (kurucu x = ortak x − kayma).
class _Kamera {
  _Kamera({
    required this.hedef,
    required this.alt,
    required this.altKayma,
    required this.altKoken,
    required this.ust,
    required this.ustKayma,
    required this.ustGiris,
    required this.basMin,
    required this.basMax,
    required this.sonMin,
    required this.sonMax,
  });
  final LineChartData hedef;

  /// Geçiş boyunca pencereyi kapsayan seri (uzaklaşmada yeni, yakınlaşmada
  /// eski dönem).
  final LineChartData Function(double, double) alt;
  final double altKayma;
  final double altKoken;

  /// Öteki dönem: uzaklaşmada başta söner, yakınlaşmada sonda belirir.
  final LineChartData Function(double, double) ust;
  final double ustKayma;
  final bool ustGiris;
  final double basMin;
  final double basMax;
  final double sonMin;
  final double sonMax;
}

/// Bir etiket adımının takımı ve opaklık geçişi.
class _TikTakimi {
  _TikTakimi(this.adim, this.etiket, this.izgara, this.bas, this.hedef);
  final double adim;
  SideTitles etiket;
  FlLine Function(double)? izgara;
  double bas;
  double hedef;
}

class _IzgaraBoyasi extends CustomPainter {
  _IzgaraBoyasi(this.cizgiler, this.sol, this.sag);

  /// (piksel y, opaklık, çizgi stili)
  final List<(double, double, FlLine)> cizgiler;
  final double sol;
  final double sag;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (y, o, c) in cizgiler) {
      final renk = c.color;
      if (c.strokeWidth <= 0 || renk == null) continue;
      final boya = Paint()
        ..color = renk.withValues(alpha: renk.a * o)
        ..strokeWidth = c.strokeWidth
        ..style = PaintingStyle.stroke;
      final desen = c.dashArray;
      if (desen == null || desen.length < 2) {
        canvas.drawLine(Offset(sol, y), Offset(sag, y), boya);
        continue;
      }
      var x = sol;
      var i = 0;
      while (x < sag && i < 4096) {
        final uz = math.max(1.0, desen[i % desen.length].toDouble());
        if (i.isEven) {
          canvas.drawLine(Offset(x, y), Offset(math.min(x + uz, sag), y), boya);
        }
        x += uz;
        i++;
      }
    }
  }

  @override
  bool shouldRepaint(_IzgaraBoyasi eski) =>
      eski.sol != sol || eski.sag != sag || !listEquals(eski.cizgiler, cizgiler);
}
