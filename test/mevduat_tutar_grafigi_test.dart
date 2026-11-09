import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/sozlesme.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/sozlesme_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/mevduat_hesabi.dart';
import 'package:portfoy_takip/services/sozlesme_deposu.dart';

import 'helpers/kaynak.dart';

/// Mevduat varlık ekranı grafiği TOPLAM TL tutarı çizer (yasin, 2026-10-26):
/// *"vadeli mevduatlara özel grafikte benim vadeli mevduata ait tüm mal
/// varlığımın tutarını izleyebilmeliyim."* Hesap `MevduatHesabi.tutarSerisi`
/// (saf); ekran yalnız mevduatta, karşılaştırma kapalıyken çağırır. Diğer
/// türlerin grafiği birim fiyat kalır.

int _ms(DateTime t) => t.millisecondsSinceEpoch;

Asset _lot(double q, DateTime t,
        {AssetKind kind = AssetKind.buy,
        double fiyat = 1,
        DateTime? silindi}) =>
    Asset(
      id: 'lot-${t.millisecondsSinceEpoch}-$q',
      userId: 'u1',
      name: 'Enpara · Vadeli',
      ticker: 'MEVDUAT:x',
      type: AssetType.mevduat,
      quantity: q,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: t,
      kind: kind,
      deletedAt: silindi,
    );

void main() {
  group('MevduatHesabi.tutarSerisi', () {
    final g1 = DateTime(2026, 9, 1);
    final g2 = DateTime(2026, 9, 10);
    final g3 = DateTime(2026, 9, 20);
    final g4 = DateTime(2026, 10, 3);

    test('tek lot: her nokta pay × birim değer', () {
      final s = MevduatHesabi.tutarSerisi(
        birimSeri: {_ms(g1): 1.0, _ms(g2): 1.0, _ms(g3): 1.0},
        lotlar: [_lot(100000, g1)],
      );
      expect(s, {_ms(g1): 100000.0, _ms(g2): 100000.0, _ms(g3): 100000.0});
    });

    test('ilk lottan önceki nokta seriye girmez (uydurma yok)', () {
      final once = DateTime(2026, 8, 25);
      final s = MevduatHesabi.tutarSerisi(
        birimSeri: {_ms(once): 1.0, _ms(g2): 1.0},
        lotlar: [_lot(1000, g1)],
      );
      expect(s.keys, [_ms(g2)]);
    });

    test('sonradan para ekleme o tarihten itibaren tutarı artırır', () {
      final s = MevduatHesabi.tutarSerisi(
        birimSeri: {_ms(g1): 1.0, _ms(g2): 1.0, _ms(g3): 1.02},
        lotlar: [
          _lot(100000, g1),
          // 1,02'den 50.000 TL → 49.019,6 pay.
          _lot(50000 / 1.02, DateTime(2026, 9, 15), fiyat: 1.02),
        ],
      );
      expect(s[_ms(g1)], 100000);
      expect(s[_ms(g2)], 100000, reason: 'ekleme henüz yapılmadı');
      expect(s[_ms(g3)], closeTo(100000 * 1.02 + 50000, 1e-6));
    });

    test('vade günü net faiz eklenince basamak görünür', () {
      // 32 gün vadeli, %40 brüt, %15 stopaj → net %34.
      final d = MevduatDonemi(
        id: 'd1',
        sozlesmeId: 'x',
        baslangic: g1,
        vadeSonu: g1.add(const Duration(days: 32)),
        yillikFaiz: 40,
        stopaj: 15,
      );
      final vadeOncesi = g1.add(const Duration(days: 31));
      final vadeSonrasi = g1.add(const Duration(days: 33));
      final birim = {
        for (final t in [g1, vadeOncesi, vadeSonrasi])
          _ms(t): MevduatHesabi.birimDeger([d], t)!,
      };
      final s = MevduatHesabi.tutarSerisi(
          birimSeri: birim, lotlar: [_lot(100000, g1)]);
      expect(s[_ms(vadeOncesi)], closeTo(100000, 1e-6),
          reason: 'vade içinde değer düz');
      final faiz = 100000 * 0.40 * 0.85 * 32 / 365;
      expect(s[_ms(vadeSonrasi)]! - s[_ms(vadeOncesi)]!, closeTo(faiz, 0.01));
    });

    test('çekim düşer; tamamen çekilince nokta yok; silinen lot sayılmaz', () {
      final s = MevduatHesabi.tutarSerisi(
        birimSeri: {_ms(g1): 1.0, _ms(g2): 1.0, _ms(g3): 1.0, _ms(g4): 1.0},
        lotlar: [
          _lot(100000, g1),
          _lot(999999, g1, silindi: g2),
          _lot(40000, DateTime(2026, 9, 5), kind: AssetKind.sell),
          _lot(60000, DateTime(2026, 9, 15), kind: AssetKind.sell),
        ],
      );
      expect(s[_ms(g1)], 100000);
      expect(s[_ms(g2)], 60000);
      expect(s.containsKey(_ms(g3)), isFalse);
      expect(s.containsKey(_ms(g4)), isFalse);
    });

    test('lot yoksa boş seri', () {
      expect(
          MevduatHesabi.tutarSerisi(birimSeri: {_ms(g1): 1.0}, lotlar: []),
          isEmpty);
    });
  });

  group('ekran kaynağı', () {
    final kaynak =
        ekranKaynagiSync('lib/screens/asset_detail_screen.dart');

    test('dönüşüm yalnız mevduatta ve karşılaştırma kapalıyken', () {
      expect(
          RegExp(r'mevduatTutari\s*=\s*widget\.asset\.type == AssetType\.mevduat'
                  r'\s*&&\s*_compareAsset == null')
              .hasMatch(kaynak),
          isTrue);
      expect(
          RegExp(r'hamData != null && mevduatTutari\s*\?\s*_mevduatTutarSerisi')
              .hasMatch(kaynak),
          isTrue);
      // Diğer türler: sağ uç canlı BİRİM fiyat (birebir eskisi).
      expect(
          RegExp(r'currentUnitPriceOverride: mevduatTutari\s*\?\s*pnl\.currentValueTRY'
                  r'\s*:\s*currentUnitTRY')
              .hasMatch(kaynak),
          isTrue);
      // BES dönüşüme girmez.
      expect(kaynak.contains('AssetType.bes && _compareAsset'), isFalse);
    });

    test('imleç mevduatta da açık, değer başlıkla aynı biçimde', () {
      expect(
          RegExp(r'imlecAcik =\s*RemoteConfigService\.instance\.gozAlici && !compareOn;')
              .hasMatch(kaynak),
          isTrue);
      expect(kaynak.contains('? baz.fmt(fromY(snapped.y))'), isTrue);
    });
  });

  group('ekran', () {
    const sozlesmeId = '11111111-2222-3333-4444-555555555555';
    final sym = mevduatSembolu(sozlesmeId);
    final now = DateTime.now();
    final bas = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 400));

    Asset mevduatLotu() => Asset(
          id: 'm1',
          userId: 'ortak',
          name: 'Enpara · Vadeli',
          ticker: sym,
          type: AssetType.mevduat,
          quantity: 250000,
          purchasePrice: 1,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: 1.0,
          addedDate: bas,
          sozlesmeId: sozlesmeId,
        );

    setUpAll(() async {
      await initializeDateFormatting('tr_TR');
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
    });

    tearDown(() {
      SozlesmeDeposu.instance.temizle();
      HistoryService.clearCache();
    });

    testWidgets('mevduat grafiği TL tutar ölçeğinde (eksen ₺250K civarı)',
        (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      // Vadesiz %40: birim değer 1,0'dan büyür; tutar = 250.000 × birim.
      SozlesmeDeposu.instance.yaz([
        Sozlesme(
          id: sozlesmeId,
          userId: 'ortak',
          tur: SozlesmeTuru.mevduat,
          kurum: 'Enpara',
          baslangic: bas,
        ),
      ], [
        MevduatDonemi(
          id: 'd1',
          sozlesmeId: sozlesmeId,
          baslangic: bas,
          vadeSonu: null,
          yillikFaiz: 40,
          stopaj: 15,
        ),
      ]);
      final birimBugun = MevduatHesabi.birimDeger(
          SozlesmeDeposu.instance.donemler(sozlesmeId), now)!;
      final lot = mevduatLotu()..currentPrice = birimBugun;

      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          portfolioProvider.overrideWith(() => _FakePortfolio([lot])),
          // Gerçek sağlayıcı oturum yüklenirken depoyu temizler.
          sozlesmeProvider.overrideWith(_FakeSozlesme.new),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: AssetDetailScreen(asset: lot, showBackButton: true),
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      final metinler = [
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          t.data ?? t.textSpan?.toPlainText() ?? '',
      ];
      expect(find.textContaining('fiyat geçmişi şu an'), findsNothing);
      // Eksende "₺3xxK" gibi tutar etiketleri; birim (₺1,xx) etiketi yok.
      expect(metinler.any((m) => RegExp(r'^₺\d{3}(,\d+)?K$').hasMatch(m)),
          isTrue,
          reason: 'eksen TL tutar yazmalı: $metinler');
      expect(metinler.any((m) => RegExp(r'^₺1,\d+$').hasMatch(m)), isFalse,
          reason: 'birim değer ekseni kalmamalı: $metinler');
      await tester.pump(const Duration(seconds: 10));
    });
  });
}

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'user-1',
        email: 'test@example.com',
        displayName: 'Test',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this.lotlar);
  final List<Asset> lotlar;
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: lotlar,
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

class _FakeSozlesme extends SozlesmeNotifier {
  @override
  Future<SozlesmeState> build() async => const SozlesmeState();
}
