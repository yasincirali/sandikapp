// "Bunu mu demek istedin?" (müşteri işi 10 Kas). Kilitlenen: (1) bir harf
// uzaklık (atlanan, fazla, değişen ya da yer değiştiren harf) kodda ya da
// ad sözcüğünün başında; (2) 3 harften kısa sorguda öneri yok; (3) en çok
// 3, sıra uzaklık sonra kod; (4) genel aramada boş sonucun altında çip,
// dokununca sorgu öneriyle değişir.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/bist_hisseleri.dart';
import 'package:portfoy_takip/models/secici_arama.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/add_watchlist_screen.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<String> _bist(String q) => [
      for (final e in yakinOneriler(bist100StocksMap.entries, q,
          kod: (e) => e.key.replaceAll('.IS', ''), ad: (e) => e.value))
        e.key.replaceAll('.IS', ''),
    ];

const _fonlar = {
  'AFT': 'Ak Portföy Yeni Teknolojiler Yabancı Hisse Senedi Fonu',
  'AFA': 'Ak Portföy Amerika Yabancı Hisse Senedi Fonu',
  'IPB': 'İstanbul Portföy Birinci Değişken Fon',
  'TTE':
      'İş Portföy BIST Teknoloji Ağırlık Sınırlamalı Endeks Hisse Senedi Fonu',
};

List<String> _fon(String q) => [
      for (final e in yakinOneriler(_fonlar.entries, q,
          kod: (e) => e.key, ad: (e) => e.value))
        e.key,
    ];

class _Portfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async =>
      const PortfolioState(assets: <Asset>[]);
}

class _Takip extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => const [];
}

class _Oturumsuz extends AuthNotifier {
  @override
  Future<AppUser?> build() async => null;
}

void main() {
  group('yakinOneriler', () {
    test('gerçek kodlar katalogda', () {
      expect(bist100StocksMap, contains('THYAO.IS'));
      expect(bist100StocksMap, contains('ASELS.IS'));
    });

    test('atlanan harf: THYO → THYAO', () {
      expect(_bist('THYO'), contains('THYAO'));
      expect(_bist('thyo'), contains('THYAO'), reason: 'büyük/küçük harf');
    });

    test('yer değiştiren harf: ASLES → ASELS (Damerau)', () {
      expect(_bist('ASLES'), contains('ASELS'));
    });

    test('ASLSN iki harf uzakta (eksik E, fazla N): ASELS önerilmez', () {
      expect(_bist('ASLSN'), isNot(contains('ASELS')));
    });

    test('ad sözcüğünün başı: "aselsn" Aselsan\'ı bulur', () {
      expect(_bist('aselsn'), contains('ASELS'));
    });

    test('fazla harf: AFTT → AFT', () {
      expect(_fon('AFTT'), ['AFT']);
    });

    test('2 harfte öneri yok', () {
      expect(_bist('TH'), isEmpty);
      expect(_fon('AF'), isEmpty);
    });

    test('en çok 3, sıra uzaklık sonra kod, her seferinde aynı', () {
      final a = _bist('AKBN');
      expect(a.length, lessThanOrEqualTo(3));
      expect(a, _bist('AKBN'));
      final hepsi = yakinOneriler(['ABC', 'ABD', 'ABE', 'ABF', 'XBC'], 'ABX',
          kod: (s) => s, ad: (s) => s);
      expect(hepsi, ['ABC', 'ABD', 'ABE']);
    });

    test('tam eşleşme uzaklığı sıfır: önde', () {
      expect(yakinOneriler(['ABDE', 'ABC'], 'abc', kod: (s) => s, ad: (s) => s),
          ['ABC', 'ABDE']);
    });
  });

  group('genel arama', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SymbolSearchService.clearCacheForTest();
    });

    testWidgets('boş sonuçta çip; dokununca sorgu öneriye döner', (t) async {
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_Oturumsuz.new),
          portfolioProvider.overrideWith(_Portfoy.new),
          watchlistProvider.overrideWith(_Takip.new),
        ],
        child: const MaterialApp(home: AddWatchlistScreen()),
      ));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      Future<void> bekle() async {
        for (var i = 0; i < 20; i++) {
          await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)));
          await t.pump(const Duration(seconds: 1));
        }
      }

      await t.enterText(find.byType(EditableText), 'THYO');
      await bekle();
      expect(find.text('Bunu mu demek istedin?'), findsOneWidget);
      final cip = find.byKey(const ValueKey('arama_onerisi_THYAO'));
      expect(cip, findsOneWidget);
      expect(t.getSize(cip).height, greaterThanOrEqualTo(44));

      await t.tap(cip);
      await bekle();
      expect(find.text('Bunu mu demek istedin?'), findsNothing);
      expect(find.text('Türk Hava Yolları'), findsWidgets);
    });
  });
}
