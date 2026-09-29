import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/temettu_gecmisi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/dividend_dialog.dart';
import 'package:portfoy_takip/widgets/temettu_gecmisi_karti.dart';

/// "Son 12 ay temettü" kartı ve ön dolu temettü diyaloğu (plan §F5).
///
/// Kart: bayrak kapalıyken / hisse değilken / olay yokken TEK PİKSEL yer
/// kaplamaz; dar ekranda (320pt) ve büyük metinde taşmaz. Diyalog: stopaj
/// bilinmiyorsa BRÜT + "net tutarı gir", biliniyorsa NET + "stopaj %x
/// varsayıldı"; tarih hak tarihi.

Asset _satir({
  required String id,
  String ticker = 'THYAO.IS',
  AssetType type = AssetType.hisse,
  double quantity = 100,
  AssetKind kind = AssetKind.buy,
  DateTime? tarih,
  double dividendAmount = 0,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Türk Hava Yolları Anonim Ortaklığı',
      ticker: ticker,
      type: type,
      quantity: quantity,
      purchasePrice: 250,
      currency: 'TRY',
      notes: '',
      currentPrice: 300,
      addedDate: tarih ?? _alimGunu.add(const Duration(hours: 9)),
      kind: kind,
      dividendAmount: dividendAmount,
    );

/// Tarihler BUGÜNE göre: kartın "kaydettiğin" toplamı son 365 günü sayar,
/// sabit tarihli test bir yıl sonra kendiliğinden kırılırdı.
final _bugun = trGunu(DateTime.now());
final _yakin = _bugun.subtract(const Duration(days: 100));
final _uzak = _bugun.subtract(const Duration(days: 200));
final _alimGunu = _bugun.subtract(const Duration(days: 300));
String _g(DateTime d, [String ayrac = '.']) =>
    '${d.day.toString().padLeft(2, '0')}$ayrac'
    '${d.month.toString().padLeft(2, '0')}$ayrac${d.year}';

final _olaylar = [
  TemettuOlayi(hakTarihi: _yakin, tutarPay: 3.442),
  TemettuOlayi(hakTarihi: _uzak, tutarPay: 1.25),
];

Future<void> _pump(
  WidgetTester tester,
  Widget body, {
  double width = 375,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(SandikSpace.smd),
            child: body,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('kart', () {
    final alim = _satir(id: 'a');

    testWidgets('bayrak KAPALIYKEN hiç görünmez ve ağa çıkmaz', (t) async {
      var cagri = 0;
      await _pump(
        t,
        TemettuGecmisiKarti(
          varlik: alim,
          defter: [alim],
          etkin: false,
          olayCekici: (_) async {
            cagri++;
            return _olaylar;
          },
        ),
      );
      expect(cagri, 0);
      expect(find.textContaining('TEMETT'), findsNothing);
      expect(find.byType(SandikCard), findsNothing);
    });

    testWidgets('BIST hissesi değilse (fon) hiç görünmez', (t) async {
      final fon = _satir(id: 'f', ticker: 'AFA', type: AssetType.fon);
      var cagri = 0;
      await _pump(
        t,
        TemettuGecmisiKarti(
          varlik: fon,
          defter: [fon],
          etkin: true,
          olayCekici: (_) async {
            cagri++;
            return _olaylar;
          },
        ),
      );
      expect(cagri, 0);
      expect(find.byType(SandikCard), findsNothing);
    });

    testWidgets('hak tarihinde lot yoksa kart yok', (t) async {
      final gec = _satir(id: 'g', tarih: _bugun);
      await _pump(
        t,
        TemettuGecmisiKarti(
          varlik: gec,
          defter: [gec],
          etkin: true,
          olayCekici: (_) async => _olaylar,
        ),
      );
      expect(find.byType(SandikCard), findsNothing);
    });

    testWidgets('kaydedilen ve kaydedilmeyen olay ayrışır', (t) async {
      final kayit = _satir(
        id: 'd',
        kind: AssetKind.dividend,
        quantity: 0,
        dividendAmount: 106.25,
        tarih: _uzak.add(const Duration(days: 1, hours: 9)),
      );
      await _pump(
        t,
        TemettuGecmisiKarti(
          varlik: alim,
          defter: [alim, kayit],
          etkin: true,
          olayCekici: (_) async => _olaylar,
        ),
      );
      expect(find.textContaining('TEMETT'), findsOneWidget);
      expect(find.text(_g(_yakin)), findsOneWidget);
      expect(find.text(_g(_uzak)), findsOneWidget);
      // Pay tutarı kırpılmaz: 3,442 (3,44 değil).
      expect(find.textContaining('100 lot × ₺3,442'), findsOneWidget);
      expect(find.textContaining('₺344,20 brüt'), findsOneWidget);
      expect(find.text('Kaydedildi'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Kaydet'), findsOneWidget);
      expect(find.textContaining('Kaydettiğin: ₺106,25'), findsOneWidget);
    });

    for (final (genislik, olcek) in [(320.0, 1.0), (320.0, 1.3)]) {
      testWidgets('${genislik.toInt()}pt × metin $olcek: taşma yok', (t) async {
        await _pump(
          t,
          TemettuGecmisiKarti(
            varlik: _satir(id: 'a', quantity: 123456.789),
            defter: [_satir(id: 'a', quantity: 123456.789)],
            etkin: true,
            olayCekici: (_) async => _olaylar,
          ),
          width: genislik,
          textScale: olcek,
        );
        expect(find.byType(SandikCard), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('"Kaydet" ön dolu diyaloğu açar (brüt, hak tarihi)', (t) async {
      await _pump(
        t,
        TemettuGecmisiKarti(
          varlik: alim,
          defter: [alim],
          etkin: true,
          olayCekici: (_) async => _olaylar.take(1).toList(),
        ),
      );
      await t.tap(find.widgetWithText(TextButton, 'Kaydet'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final alan = t.widget<TextField>(find.byType(TextField));
      // Remote Config testte varsayılan: stopaj -1 → bilinmiyor → BRÜT.
      expect(alan.controller!.text, '344,2');
      expect(find.textContaining('Ödeme tarihi: ${_g(_yakin, '/')}'),
          findsOneWidget);
    });
  });

  group('diyalog ön dolumu', () {
    final varlik = _satir(id: 'a');
    final oneri = TemettuOnerisi(
      ticker: 'THYAO.IS',
      hakTarihi: DateTime.utc(2025, 6, 16),
      tutarPay: 3.442,
      lot: 100,
    );

    Future<void> ac(WidgetTester t, {TemettuOnerisi? o, double? stopaj}) async {
      await _pump(
        t,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDividendDialog(
              context,
              asset: varlik,
              oneri: o,
              stopajKaynagi: () => stopaj,
            ),
            child: const Text('ac'),
          ),
        ),
      );
      await t.tap(find.text('ac'));
      await t.pumpAndSettle();
    }

    testWidgets('stopaj BİLİNMİYOR → brüt + "net tutarı gir"', (t) async {
      await ac(t, o: oneri);
      final alan = t.widget<TextField>(find.byType(TextField));
      expect(alan.controller!.text, '344,2');
      expect(find.textContaining('Stopaj oranı bilinmiyor'), findsOneWidget);
      expect(find.textContaining('varsayıldı'), findsNothing);
      expect(find.textContaining('THYAO · hak tarihi 16/06/2025'),
          findsOneWidget);
      expect(find.textContaining('100 lot × ₺3,442 = ₺344,20 brüt'),
          findsOneWidget);
      expect(find.textContaining('16/06/2025'), findsNWidgets(2));
    });

    testWidgets('stopaj %15 → net 292,57 + "stopaj %15 varsayıldı"', (t) async {
      await ac(t, o: oneri, stopaj: 0.15);
      final alan = t.widget<TextField>(find.byType(TextField));
      expect(alan.controller!.text, '292,57');
      expect(find.textContaining('Stopaj %15 varsayıldı'), findsOneWidget);
      expect(find.textContaining('bilinmiyor'), findsNothing);
    });

    testWidgets('önerisiz açılış eskisi gibi: boş alan, not yok', (t) async {
      await ac(t);
      final alan = t.widget<TextField>(find.byType(TextField));
      expect(alan.controller!.text, isEmpty);
      expect(find.textContaining('Stopaj'), findsNothing);
      expect(find.textContaining('hak tarihi'), findsNothing);
    });

    testWidgets('320pt + büyük metin: öneri satırlarıyla taşmaz', (t) async {
      t.view.physicalSize = const Size(320 * 3, 568 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);
      await ac(t, o: oneri, stopaj: 0.15);
      expect(t.takeException(), isNull);
    });
  });
}
