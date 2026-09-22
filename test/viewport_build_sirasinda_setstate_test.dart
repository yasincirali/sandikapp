import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';

/// Emülatör logu (2026-09-23, kullanıcı "20 çeyrek sildim"):
///
/// ```
/// setState() or markNeedsBuild() called during build.
/// #3 _ZoomableChartState._onControllerChanged (zoomable_chart.dart:206)
/// #5 ChartViewport.updateFullRange (zoomable_chart.dart:37)
/// #6 _PerformansSeriler._ensureViewport (seriler.dart:317)
/// ```
///
/// ## Zincir
/// `_ensureViewport` BUILD İÇİNDEN çağrılıyor
/// (`grafik_kabi._buildChartContainer`). `updateFullRange` senkron
/// `notifyListeners()` atıyor; `_ZoomableChartState` dinleyicisinde
/// `setState` çağırıyor. Flutter build sırasında bunu yasaklıyor: kare
/// atlanıyor, Crashlytics'e non-fatal düşüyor ve grafik bir kare ESKİ
/// aralıkla çiziliyor.
///
/// Lot eklemek/silmek X aralığını değiştirdiği için tam o anda tetikleniyor
/// — yani kullanıcının test ettiği her işlemde.
///
/// ## Düzeltme
/// Aralık senkron yazılır (`updateFullRangeSessiz`), DİNLEYİCİ uyarısı
/// build sonrasına ertelenir (`bildir`).
void main() {
  group('updateFullRangeSessiz', () {
    test('aralığı yazar ama bildirim ATMAZ', () {
      final v = ChartViewport(fullMinX: 0, fullMaxX: 10);
      var bildirim = 0;
      v.addListener(() => bildirim++);

      final degisti = v.updateFullRangeSessiz(5, 20);

      expect(degisti, isTrue);
      expect(v.fullMinX, 5, reason: 'aralık AYNI karede yazılmalı');
      expect(v.fullMaxX, 20);
      expect(v.minX, 5, reason: 'görünür aralık da güncellenmeli');
      expect(v.maxX, 20);
      expect(bildirim, 0,
          reason: 'build sırasında bildirim = setState during build');
    });

    test('değişiklik yoksa false döner (boşuna kare yok)', () {
      final v = ChartViewport(fullMinX: 0, fullMaxX: 10);
      expect(v.updateFullRangeSessiz(0, 10), isFalse);
    });

    test('bildir() ertelenmiş uyarıyı atar', () {
      final v = ChartViewport(fullMinX: 0, fullMaxX: 10);
      var bildirim = 0;
      v.addListener(() => bildirim++);

      v.updateFullRangeSessiz(5, 20);
      expect(bildirim, 0);
      v.bildir();
      expect(bildirim, 1, reason: 'dinleyici geç kalmamalı, sadece ertelenmeli');
    });
  });

  group('updateFullRange (build DIŞI yol) bozulmadı', () {
    test('hem yazar hem bildirir', () {
      final v = ChartViewport(fullMinX: 0, fullMaxX: 10);
      var bildirim = 0;
      v.addListener(() => bildirim++);

      v.updateFullRange(5, 20);

      expect(v.fullMinX, 5);
      expect(v.fullMaxX, 20);
      expect(bildirim, 1);
    });

    test('değişiklik yoksa bildirim ATMAZ', () {
      final v = ChartViewport(fullMinX: 0, fullMaxX: 10);
      var bildirim = 0;
      v.addListener(() => bildirim++);
      v.updateFullRange(0, 10);
      expect(bildirim, 0);
    });
  });

  /// ⚠İŞE YARAMAZLIĞI ÖLÇÜLDÜ — bu test hatayı YAKALAYAMIYOR.
  ///
  /// Düzeltme geri alınıp eski senkron yol (`updateFullRange`) konduğunda
  /// bu test YİNE GEÇTİ. Sebep: `pumpWidget` ile kurulan ağaçta bu widget
  /// KÖK'e yakın; Flutter "dirty descendant her zaman ziyaret edilir"
  /// istisnasını uygulayıp hatayı fırlatmıyor. Gerçekte zincir derin
  /// (`kartlar` → `grafik_kabi` → `seriler`) ve ORADA fırlıyor.
  ///
  /// Yani aşağıdaki test bir GÜVENCE DEĞİL, yalnızca deseni belgeliyor.
  /// Gerçek koruma yukarıdaki birim testlerde: `updateFullRangeSessiz`
  /// bildirim atmazsa build sırasında setState de olamaz.
  ///
  /// Bu projede "kaynak doğru görünüyor ama davranış yanlış" sınıfı
  /// hatalar yaşandı; tersi de geçerli: yeşil bir test doğrulandığı
  /// anlamına gelmez. Kaldırılmadı çünkü deseni okunur kılıyor — ama
  /// ona GÜVENİLMEMELİ.
  testWidgets('BUILD İÇİNDEN aralık güncellemek hata ÜRETMEZ (zayıf test)',
      (tester) async {
    // `_ensureViewport`'un yaptığının birebir simülasyonu: build sırasında
    // aralık değişiyor ve bir dinleyici `setState` çağırıyor.
    final viewport = ChartViewport(fullMinX: 0, fullMaxX: 10);
    addTearDown(viewport.dispose);
    var hedefMax = 10.0;

    await tester.pumpWidget(MaterialApp(
      home: _BuildSirasindaGuncelleyen(
        viewport: viewport,
        hedefMax: () => hedefMax,
      ),
    ));
    expect(tester.takeException(), isNull);

    // Lot silindi → aralık değişti → yeniden build.
    //
    // Düz değişkeni değiştirmek build TETİKLEMEZ; gerçekte yeni aralık
    // yeni bir widget ağacıyla gelir (`pumpWidget` tekrar çağrılır).
    hedefMax = 25.0;
    await tester.pumpWidget(MaterialApp(
      home: _BuildSirasindaGuncelleyen(
        viewport: viewport,
        hedefMax: () => hedefMax,
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'eskiden "setState() called during build" fırlatıyordu');
    expect(viewport.fullMaxX, 25.0,
        reason: 'aralık yine de AYNI karede güncellenmeli — '
            'grafik bir kare eski aralıkla çizilmemeli');
  });
}

/// Build sırasında viewport güncelleyen kap — `_ensureViewport` deseni.
class _BuildSirasindaGuncelleyen extends StatefulWidget {
  const _BuildSirasindaGuncelleyen({
    required this.viewport,
    required this.hedefMax,
  });

  final ChartViewport viewport;
  final double Function() hedefMax;

  @override
  State<_BuildSirasindaGuncelleyen> createState() =>
      _BuildSirasindaGuncelleyenState();
}

class _BuildSirasindaGuncelleyenState
    extends State<_BuildSirasindaGuncelleyen> {
  @override
  void initState() {
    super.initState();
    // `_ZoomableChartState._onControllerChanged` ile aynı: bildirimde setState.
    widget.viewport.addListener(_degisti);
  }

  @override
  void dispose() {
    widget.viewport.removeListener(_degisti);
    super.dispose();
  }

  void _degisti() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // BUILD İÇİNDE güncelleme — `_ensureViewport`'un yaptığı.
    final hedef = widget.hedefMax();
    if (widget.viewport.fullMaxX != hedef) {
      widget.viewport.updateFullRangeSessiz(widget.viewport.fullMinX, hedef);
      final v = widget.viewport;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) v.bildir();
      });
    }
    return Text('${widget.viewport.fullMaxX}');
  }
}
