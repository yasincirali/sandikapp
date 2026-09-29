import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/islem_notu.dart';

/// Portföy kartının açılır panelindeki "NOTLAR" (kullanıcı isteği
/// 2026-09-29: "not bilgisi Portföy sayfasında da yer almalı; kart
/// açıldığında orada olmalı").
///
/// Harness `asset_card_overflow_test` ile aynı: gerçek `PortfolioScreen`,
/// provider'lar override. Varlıklar `isManualPrice` — panel sparkline'ı
/// ağa çıkmasın.
const _uid = 'user-1';

Asset _lot(
  String id, {
  String notes = '',
  AssetKind kind = AssetKind.buy,
  DateTime? tarih,
  String ticker = 'THYAO.IS',
}) =>
    Asset(
      id: id,
      userId: _uid,
      name: 'Türk Hava Yolları',
      ticker: ticker,
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 250,
      currency: 'TRY',
      notes: notes,
      isManualPrice: true,
      currentPrice: 300,
      addedDate: tarih ?? DateTime(2026, 3, 14),
      kind: kind,
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this._assets);
  final List<Asset> _assets;

  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _assets, usdTry: 42, eurTry: 46, gbpTry: 54);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

Future<void> _pumpVeAc(WidgetTester tester, List<Asset> assets,
    {double width = 375}) async {
  tester.view.physicalSize = Size(width * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(() => _FakePortfolio(assets)),
      partnersProvider.overrideWith(_FakePartners.new),
    ],
    child: MaterialApp(theme: ThemeData.dark(), home: const PortfolioScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded).first);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('notluIslemler', () {
    test('en yeni önce; satıştaki eski kopya elenir', () {
      final lotlar = [
        _lot('a1', notes: 'maaştan', tarih: DateTime(2026, 1, 5)),
        _lot('a2', notes: 'ikramiye', tarih: DateTime(2026, 6, 5)),
        _lot('s1',
            kind: AssetKind.sell, notes: 'maaştan', tarih: DateTime(2026, 7, 1)),
        _lot('a3', tarih: DateTime(2026, 8, 1)),
      ];
      expect(notluIslemler(lotlar).map((n) => n.not), ['ikramiye', 'maaştan']);
    });
  });

  group('Portföy kartı paneli', () {
    testWidgets('açılınca notlar görünür, kapalıyken görünmez',
        (tester) async {
      await _pumpVeAc(tester, [
        _lot('a1', notes: 'Maaştan aldım', tarih: DateTime(2026, 1, 5)),
        _lot('a2', notes: 'Düşüşte ekledim', tarih: DateTime(2026, 6, 5)),
      ]);
      expect(find.text('NOTLAR'), findsOneWidget);
      expect(find.text('Maaştan aldım'), findsOneWidget);
      expect(find.text('Düşüşte ekledim'), findsOneWidget);
      // En yeni önce.
      expect(
        tester.getTopLeft(find.text('Düşüşte ekledim')).dy,
        lessThan(tester.getTopLeft(find.text('Maaştan aldım')).dy),
      );
      expect(tester.takeException(), isNull);

      // Kapatınca kaybolur.
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Maaştan aldım'), findsNothing);
    });

    testWidgets('notu olmayan pozisyonda bölüm hiç yok', (tester) async {
      await _pumpVeAc(tester, [_lot('a1')]);
      expect(find.text('NOTLAR'), findsNothing);
    });

    testWidgets('3\'ten fazla not: en yeni 3 + "not daha"', (tester) async {
      await _pumpVeAc(tester, [
        for (var i = 1; i <= 5; i++)
          _lot('a$i', notes: 'not $i', tarih: DateTime(2026, i, 1)),
      ]);
      expect(find.text('not 5'), findsOneWidget);
      expect(find.text('not 3'), findsOneWidget);
      expect(find.text('not 2'), findsNothing);
      expect(find.textContaining('+2 not daha'), findsOneWidget);
    });

    testWidgets('dar ekran + uzun not taşmaz', (tester) async {
      await _pumpVeAc(
        tester,
        [
          _lot('a1',
              notes: 'Uzun bir not: bu alışı maaş yattığı gün yaptım, '
                  'ortalama maliyeti düşürmek için; hedef fiyat 400, '
                  'zarar kes 220. Bir sonraki bilançoya kadar tutacağım.'),
        ],
        width: 320,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('NOTLAR'), findsOneWidget);
    });

    testWidgets('nota dokununca not sayfası açılır', (tester) async {
      await _pumpVeAc(tester, [_lot('a1', notes: 'Maaştan aldım')]);
      await tester.tap(find.text('Maaştan aldım'));
      await tester.pumpAndSettle();
      // Sayfada düzenlenebilir alan notla dolu.
      expect(find.widgetWithText(TextField, 'Maaştan aldım'), findsOneWidget);
    });
  });
}
