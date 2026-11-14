import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/config/pref_keys.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/comparison_screen.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/kiyas_seti.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Karşılaştır Premium turu (Ar-Ge 14 Kas 2026 22:03).
///
/// Seriler `ComparisonScreen.testSeriKaynagi` ile verilir: sayılar testin
/// kendi sabitleridir, ağ yok.

/// Dönem getirisi [pct] olan iki noktalı normalize seri.
NormalizedSeries _seri(double pct) =>
    normalizeSeries({1000: 100, 2000: 100 + pct})!;

Widget _ekran({required int sinir, Widget child = const ComparisonScreen()}) =>
    ProviderScope(
      overrides: [
        karsilastirmaSeriSiniriProvider.overrideWithValue(sinir),
      ],
      child: MaterialApp(home: child),
    );

/// Uzun ekran: çip satırı ListView'in tembel kurulumunda görünür kalsın.
void _uzunEkran(WidgetTester tester) {
  tester.view.physicalSize = const Size(430 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> _ekle(WidgetTester tester, SymbolHit hit) async {
  final state = tester.state(find.byType(ComparisonScreen));
  // ignore: avoid_dynamic_calls
  await (state as dynamic).addForTest(hit);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// `SandikTappable`'ın kendi `Semantics` etiketi (çocuk metinle birleşmeden).
Finder _etiket(String label) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == label);

const _thy = SymbolHit(ticker: 'THYAO.IS', name: 'THY', source: 'BIST');
const _asel = SymbolHit(ticker: 'ASELS.IS', name: 'Aselsan', source: 'BIST');

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  final getiri = <String, double>{};
  setUp(() {
    getiri
      ..clear()
      ..addAll({
        'THYAO.IS': 4,
        'ASELS.IS': -2,
        'XU100.IS': 3,
        'USDTRY=X': 1,
        'ALTIN_GRAM': 12.4,
      });
    ComparisonScreen.testSeriKaynagi = (t, _) async {
      final p = getiri[t];
      return p == null ? null : _seri(p);
    };
  });
  tearDown(() => ComparisonScreen.testSeriKaynagi = null);

  /// Satır başlıklarının ekrandaki sırası (sembol metni, dikey konuma göre).
  List<String> satirSirasi(WidgetTester tester, List<String> adaylar) {
    final bulunan = [
      for (final a in adaylar)
        if (find.text(a).evaluate().isNotEmpty) a,
    ];
    bulunan.sort((a, b) => tester
        .getTopLeft(find.text(a).first)
        .dy
        .compareTo(tester.getTopLeft(find.text(b).first).dy));
    return bulunan;
  }

  group('kıyas seti hatırlanır (fikir 2)', () {
    const kayitli = [
      SymbolHit(ticker: 'ASELS.IS', name: 'Aselsan', source: 'BIST'),
      SymbolHit(ticker: 'XU100.IS', name: 'BIST 100', source: 'Endeks'),
      SymbolHit(ticker: 'USDTRY=X', name: 'Dolar', source: 'Döviz'),
      SymbolHit(ticker: 'AKBNK.IS', name: 'Akbank', source: 'BIST'),
      SymbolHit(ticker: 'GARAN.IS', name: 'Garanti', source: 'BIST'),
    ];
    const satirlar = [
      'THYAO.IS', 'ASELS.IS', 'XU100.IS', 'USDTRY=X', 'AKBNK.IS', 'GARAN.IS',
    ];

    Future<void> kur(List<SymbolHit> set) async {
      SharedPreferences.setMockInitialValues({
        PrefKeys.karsilastirmaSeti: kiyasSetiKodla(set),
      });
      await initPreferencesCache();
    }

    testWidgets('Premium: set aynı sırayla geri gelir', (tester) async {
      _uzunEkran(tester);
      await kur(kayitli.take(3).toList());
      await tester.pumpWidget(_ekran(sinir: kKarsilastirmaEnFazla));
      await tester.pump();
      expect(satirSirasi(tester, satirlar),
          ['ASELS.IS', 'XU100.IS', 'USDTRY=X']);
    });

    testWidgets('varlık sayfasından: varlık başta, set arkasında, 5e kırpılır',
        (tester) async {
      _uzunEkran(tester);
      await kur(kayitli);
      final thy = Asset(
        id: 'a1',
        userId: 'u1',
        name: 'THY',
        ticker: 'THYAO.IS',
        type: AssetType.hisse,
        quantity: 1,
        purchasePrice: 100,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 110,
        addedDate: DateTime(2026, 1, 1),
      );
      getiri.clear(); // birim varlık yolu ağ ister; satır sırası yeter
      await tester.pumpWidget(_ekran(
          sinir: kKarsilastirmaEnFazla,
          child: ComparisonScreen(baslangicVarligi: thy)));
      await tester.pump();
      expect(satirSirasi(tester, satirlar),
          ['THYAO.IS', 'ASELS.IS', 'XU100.IS', 'USDTRY=X', 'AKBNK.IS']);
    });

    testWidgets('ücretsiz: set kurulmaz, kayıt silinmez', (tester) async {
      _uzunEkran(tester);
      await kur(kayitli.take(2).toList());
      await tester.pumpWidget(_ekran(sinir: 2));
      await tester.pump();
      expect(satirSirasi(tester, satirlar), isEmpty);
      await _ekle(tester, _thy);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(PrefKeys.karsilastirmaSeti),
          kiyasSetiKodla(kayitli.take(2)));
    });

    testWidgets('Premium: ekleme ve çıkarma sete yazılır', (tester) async {
      _uzunEkran(tester);
      await kur(kayitli.take(1).toList());
      await tester.pumpWidget(_ekran(sinir: kKarsilastirmaEnFazla));
      await tester.pump();
      await _ekle(tester, _thy);
      final prefs = await SharedPreferences.getInstance();
      expect(
          kiyasSetiCoz(prefs.getStringList(PrefKeys.karsilastirmaSeti),
                  ortakIdleri: const {})
              .map((h) => h.ticker),
          ['ASELS.IS', 'THYAO.IS']);
    });
  });

  group('kilitli çip (fikir 1)', () {
    testWidgets('ücretsiz sınırda dolu: kilit ikonu, normal ton, Premium etiketi',
        (tester) async {
      _uzunEkran(tester);
      await tester.pumpWidget(_ekran(sinir: 2));
      await tester.pump();
      await _ekle(tester, _thy);
      await _ekle(tester, _asel);

      expect(_etiket('Gram altın kıyasa ekle, Premium'), findsOneWidget);
      expect(_etiket('Gram altın kıyasa ekle'), findsNothing);
      // Çip satırındaki beş çipin hepsi kilitli; ekle düğmesininki ayrı.
      expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(6));

      final metin = tester.widget<Text>(find.text('Gram altın'));
      expect(metin.style?.color, SandikPalette.dark.text90,
          reason: 'kilitli çip soluk (text36) yazmamalı');
    });

    testWidgets('Premium sınırında dolu: devre dışı kalır, kilit yok',
        (tester) async {
      _uzunEkran(tester);
      await tester.pumpWidget(_ekran(sinir: kKarsilastirmaEnFazla));
      await tester.pump();
      for (final h in const [
        _thy,
        _asel,
        SymbolHit(ticker: 'XU100.IS', name: 'BIST 100', source: 'Endeks'),
        SymbolHit(ticker: 'USDTRY=X', name: 'Dolar', source: 'Döviz'),
        SymbolHit(ticker: 'AKBNK.IS', name: 'Akbank', source: 'BIST'),
      ]) {
        await _ekle(tester, h);
      }
      expect(_etiket('Gram altın kıyasa ekle, Premium'), findsNothing);
      final metin = tester.widget<Text>(find.text('Gram altın'));
      expect(metin.style?.color, SandikPalette.dark.text36);
    });
  });

  group('sıralama cümlesi (fikir 3)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
    });

    testWidgets('Premium, üç seri: cümle rozet sayılarıyla görünür',
        (tester) async {
      _uzunEkran(tester);
      await tester.pumpWidget(_ekran(sinir: kKarsilastirmaEnFazla));
      await tester.pump();
      await _ekle(tester, _thy);
      await _ekle(tester, _asel);
      expect(find.textContaining('Önde'), findsNothing,
          reason: 'iki seride cümle yok');
      await _ekle(tester, const SymbolHit(
          ticker: 'ALTIN_GRAM', name: 'Gram altın', source: 'Altın'));
      expect(
          find.text('Önde Gram altın: +%12,40. '
              'Sıra: Gram altın, THYAO.IS, ASELS.IS.'),
          findsOneWidget);
    });

    testWidgets('ücretsiz sınırda cümle yok', (tester) async {
      _uzunEkran(tester);
      await tester.pumpWidget(_ekran(sinir: 3));
      await tester.pump();
      await _ekle(tester, _thy);
      await _ekle(tester, _asel);
      await _ekle(tester, const SymbolHit(
          ticker: 'ALTIN_GRAM', name: 'Gram altın', source: 'Altın'));
      expect(find.textContaining('Önde'), findsNothing);
    });
  });

  group('kilitli çipin yarım sonucu (fikir 4)', () {
    var cekim = 0;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
      ComparisonScreen.kilitliOnizlemeyiSifirla();
      cekim = 0;
      final asil = ComparisonScreen.testSeriKaynagi!;
      ComparisonScreen.testSeriKaynagi = (t, d) {
        cekim++;
        return asil(t, d);
      };
    });

    Future<void> doluUcretsiz(WidgetTester tester) async {
      _uzunEkran(tester);
      await tester.pumpWidget(_ekran(sinir: 2));
      await tester.pump();
      await _ekle(tester, _thy);
      await _ekle(tester, _asel);
      cekim = 0;
    }

    const satir = 'Gram altın bu dönemde +%12,40. '
        "Çizgisini ve sıralamayı Premium'da görürsün.";

    testWidgets('ilk dokunuş: seri çekilir, çizilmez, tek satır çıkar',
        (tester) async {
      await doluUcretsiz(tester);
      await tester.tap(find.text('Gram altın'));
      await tester.pump();
      await tester.pump();
      expect(cekim, 1);
      expect(find.text(satir), findsOneWidget);
      // Çizilmedi: seçim listesinde satırı yok.
      expect(find.text('ALTIN_GRAM'), findsNothing);
      // Satır ≥44 pt dokunma hedefi.
      expect(tester.getSize(find.ancestor(
              of: find.text(satir), matching: find.byType(Container)).first)
          .height, greaterThanOrEqualTo(44));

      // Aynı oturumda ikinci kilitli dokunuş seri çekmez (paywall yolu).
      await tester.tap(find.text('Dolar'));
      await tester.pump();
      expect(cekim, 1);
      expect(find.textContaining('Dolar bu dönemde'), findsNothing);
    });

    testWidgets('veri yoksa satır çıkmaz (doğrudan paywall)', (tester) async {
      await doluUcretsiz(tester);
      await tester.tap(find.text('TÜFE'));
      await tester.pump();
      await tester.pump();
      expect(cekim, 1);
      expect(find.textContaining('bu dönemde'), findsNothing);
      // Hak harcandı: sonraki dokunuş da çekmez.
      await tester.tap(find.text('Gram altın'));
      await tester.pump();
      expect(cekim, 1);
    });
  });
}
