import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/l10n.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/watchlist_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Takip listesi satırı — ekran okuyucu ve gösterim (2026-09-29 emülatör
/// testi #17).
///
/// Bulgu: satırlar TalkBack'te "clickable=false" (bütün satır
/// `ExcludeSemantics` altındaydı; dokunma eylemi ve + düğmesi de silinmişti),
/// grafik açıklamasında "ALTIN_GRAM"/"XU100" gibi ham iç semboller, BIST 100
/// endeksinde ₺ simgesi. Hizalama testi (`watchlist_ekle_hizasi_test`) aynı
/// satırın görsel sözleşmesini ayrıca korur.
class _SabitListe extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => [
        _kalem('1', 'SISE.IS', 'Şişe Cam', 38.46, -2.93),
        _kalem('2', 'XU100.IS', 'BIST 100 Endeksi', 12290.58, 1.2),
      ];
}

WatchlistItem _kalem(
        String id, String ticker, String ad, double? fiyat, double? pct,
        {AssetType tur = AssetType.hisse, String? alt}) =>
    WatchlistItem(
      id: id,
      userId: 'u1',
      ticker: ticker,
      name: ad,
      type: tur,
      subCategory: alt,
      currency: 'TRY',
      addedAt: DateTime(2026, 9, 1),
      currentPrice: fiyat,
      periodChangePct: pct,
    );

Future<void> _pump(WidgetTester tester, {Locale? dil}) async {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      watchlistProvider.overrideWith(_SabitListe.new),
      watchlistChartProvider.overrideWith((ref) async => const {}),
      activePartnersProvider.overrideWithValue(const []),
      watchlistLimitProvider.overrideWithValue(1 << 30),
    ],
    child: MaterialApp(
      locale: dil,
      localizationsDelegates:
          dil == null ? null : AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: const Scaffold(body: WatchlistBody()),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('satır tek bir ETKİN düğme; + düğmesi ayrı ve etiketli',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    final satir = find.bySemanticsLabel(RegExp(r'^Şişe Cam, '));
    expect(satir, findsOneWidget);
    expect(
      tester.getSemantics(satir),
      isSemantics(
        isButton: true,
        hasTapAction: true,
        customActions: [const CustomSemanticsAction(label: 'Takipten çıkar')],
      ),
      reason: 'Satır TalkBack\'te etkinleştirilebilmeli (clickable=true) '
          've kaydırarak silme özel eylem olarak da sunulmalı.',
    );
    final etiket = tester.getSemantics(satir).label;
    expect(etiket, contains('düşüş %2,93'));
    expect(etiket, contains('takip ediliyor'));
    expect(etiket, isNot(contains('portföyüme ekle')),
        reason: '+ düğmesi satır cümlesine karışmamalı, kendi düğümü olmalı.');

    final ekle = find.bySemanticsLabel('SISE portföyüme ekle');
    expect(ekle, findsOneWidget);
    expect(tester.getSemantics(ekle),
        isSemantics(isButton: true, hasTapAction: true));
    semantics.dispose();
  });

  testWidgets('BIST 100 puan olarak yazılır — ₺ ve kuruş yok', (tester) async {
    await _pump(tester);
    expect(find.text('12.291'), findsOneWidget);
    expect(find.textContaining('₺12.'), findsNothing);
    // Kısa ad endeksin görünen adı; ham "XU100" yazılmaz, ad iki kez de değil.
    expect(find.text('XU100'), findsNothing);
    expect(find.text('BIST 100 Endeksi'), findsOneWidget);
  });

  testWidgets('İngilizce modda satır cümlesi İngilizce', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, dil: const Locale('en'));
    final satir = find.bySemanticsLabel(RegExp(r'^Şişe Cam, '));
    final etiket = tester.getSemantics(satir).label;
    expect(etiket, contains('down %2,93'));
    expect(etiket, contains('on your watchlist'));
    expect(etiket, isNot(contains('düşüş')));
    expect(etiket, isNot(contains('takip ediliyor')));
    semantics.dispose();
  });

  group('kısa ad — satır ve grafik açıklaması aynı kuralı izler', () {
    test('iç semboller görünen ada çevrilir', () {
      final altin = _kalem('a', 'ALTIN_GRAM', 'Gram Altın', 1, 0,
          tur: AssetType.altin, alt: 'Gram Altın');
      final gremse = _kalem('b', 'ALTIN_GREMSE', 'Gremse Altın', 1, 0,
          tur: AssetType.altin);
      final endeks = _kalem('c', 'XU100.IS', 'BIST 100 Endeksi', 1, 0);
      final emtia =
          _kalem('d', 'CL=F', 'Ham Petrol', 1, 0, tur: AssetType.emtia);
      expect(altin.chartLabel, 'Gram Altın');
      expect(gremse.chartLabel, 'Gremse Altın');
      expect(endeks.chartLabel, 'BIST 100 Endeksi');
      expect(emtia.chartLabel, 'Ham Petrol');
    });

    test('tanınan kısaltmalar korunur', () {
      expect(_kalem('a', 'SISE.IS', 'Şişe Cam', 1, 0).chartLabel, 'SISE');
      expect(
          _kalem('b', 'TEFAS:AFO', 'Ata Fon', 1, 0, tur: AssetType.fon)
              .chartLabel,
          'AFO');
      expect(
          _kalem('c', 'USDTRY=X', 'Dolar', 1, 0, tur: AssetType.doviz)
              .chartLabel,
          'USD');
    });

    test('satır etiketi ile grafik etiketi aynı kaynaktan', () {
      final k = _kalem('a', 'ALTIN_GRAM', 'Gram Altın', 1, 0,
          tur: AssetType.altin);
      expect(k.chartLabel, k.kisaEtiket);
    });
  });

  group('takipFiyatMetni', () {
    test('endeks puan: simge ve kuruş yok', () {
      expect(takipFiyatMetni(_kalem('x', 'XU100.IS', 'BIST 100', 12290.58, 0)),
          '12.291');
      expect(bistEndeksiMi('XU030.IS'), isTrue);
      expect(bistEndeksiMi('XU100'), isTrue);
      expect(bistEndeksiMi('SISE.IS'), isFalse);
      expect(bistEndeksiMi('TEFAS:XUA'), isFalse);
    });

    test('hisse ₺ ve iki ondalık; fiyat yoksa tire', () {
      expect(takipFiyatMetni(_kalem('x', 'SISE.IS', 'Şişe', 38.46, 0)),
          '₺38,46');
      expect(takipFiyatMetni(_kalem('x', 'SISE.IS', 'Şişe', null, 0)), '—');
    });
  });
}
