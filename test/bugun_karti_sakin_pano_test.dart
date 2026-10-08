import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/widgets/bugun_karti.dart';
import 'package:portfoy_takip/widgets/sigan_metin.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Bugün kartı — katmanlar gerçek ağaçta kurulur ve dar ekranda taşmaz.
///
/// 2026-10-01'de "Sakin pano" (D) olarak yazıldı; 2026-10-04'ten beri kart
/// "H · enflasyon kıyası öne" düzeninde (bayrak `bugun_karti_kiyas`,
/// 2026-10-05'te kalktı). D'ye özgü katman testleri (takvim yaprağı, bilgi
/// kutusu, haftalık yön kelimesi, enflasyon kutusu) D ile silindi; H'nin
/// ayrıntıları `bugun_karti_kiyas_test`'te.
///
/// Emülatör Flutter'ı render edemiyor (CLAUDE.md); yerleşim hatası ancak
/// burada görünür: `IntrinsicHeight` içindeki `Spacer`, iki sütunlu ızgara,
/// 320pt'te başlık satırı. Veri kaynakları testte ağa çıkamaz, bu yüzden
/// kart "gün içi veri geliyor" + artıdaki varlık + hedef hâliyle çizilir;
/// enflasyon çubuğu kaynak sözleşmesiyle denetlenir.

Asset _asset(String ticker, double qty, double alis, double simdi) => Asset(
      id: 'u-$ticker',
      userId: 'u',
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: alis,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: simdi,
      addedDate: DateTime(2026, 3, 14),
    );

final _defter = [
  _asset('THYAO', 100, 300, 312.40),
  _asset('ASELS', 10, 1100, 1000),
];

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _defter, usdTry: 42, eurTry: 46, gbpTry: 54);
}

/// `SiganMetin` kendi RenderBox'ıyla çizer; `find.text` onu görmez.
/// Seçilen (ekranda TAM yazılan) metne göre bulur.
Finder sigan(String metin) => find.byElementPredicate((e) {
      final r = e.renderObject;
      return r is SiganMetinRender && r.secilen == metin;
    });

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    BugunKarti.anliklariTemizle();
    HistoryService.clearCache();
    HistoryService.seriCekici = (s, r, i) async => const [];
  });
  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    BugunKarti.anliklariTemizle();
  });

  Future<void> kur(WidgetTester tester, {required double genislik}) async {
    tester.view.physicalSize = Size(genislik * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      portfolioProvider.overrideWith(_FakePortfolio.new),
    ]);
    addTearDown(container.dispose);
    final state = await container.read(portfolioProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(child: BugunKarti(state: state)),
        ),
      ),
    ));
    await tester.pump();
    // Reel/haftalık yükleyicileri ağa çıkamaz; kendi bütçeleriyle düşer.
    await tester.pump(const Duration(seconds: 12));
    await tester.pump();
  }

  for (final genislik in [390.0, 320.0]) {
    testWidgets('${genislik.toInt()}pt: katmanlar kurulur, taşma yok',
        (tester) async {
      await kur(tester, genislik: genislik);
      expect(tester.takeException(), isNull);
      // Başlık: "BUGÜN · <tarih>" (sığmazsa "BUGÜN"); ölçüm bloğu; hedef.
      expect(
          find.byWidgetPredicate(
              (w) => w is SiganMetin && w.adaylar.last == 'BUGÜN'),
          findsOneWidget);
      // Test yazı tipi (Ahem) gerçek yazıdan ~2 kat geniş: hangi yazımın
      // seçildiği ortama bağlı; kural "adaylardan biri TAM yazılır".
      expect(
          sigan('Günün hareketi · sadece fiyat etkisi')
                  .evaluate()
                  .isNotEmpty ||
              sigan('Günün hareketi · fiyat etkisi').evaluate().isNotEmpty ||
              sigan('Günün hareketi').evaluate().isNotEmpty,
          isTrue);
      expect(sigan('Hedef belirle'), findsOneWidget);
      // D'nin dönen bilgi kutuları H'de yok.
      expect(sigan('Artıdaki varlık'), findsNothing);
      expect(sigan('Son 7 gün'), findsNothing);
    });
  }

  testWidgets('hedef belirlenince eylem kutusu ilerlemeyi yazar',
      (tester) async {
    await kur(tester, genislik: 390);
    // ₺41.240 defter → ₺100.000 hedef: %41, kalan ₺58,8 bin.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(BugunKarti)));
    await container.read(kapsamHedefiProvider('').notifier).set(100000);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(sigan('Hedefe %41'), findsOneWidget);
    expect(sigan('Hedef belirle'), findsNothing);
  });

  group('satır içi kıvılcım — tutar öncelikli (3. tur, seçim G)', () {
    test('artan yer 56pt altındaysa kıvılcım çizilmez', () {
      expect(kivilcimGenisligi(0), isNull);
      expect(kivilcimGenisligi(55.9), isNull);
    });
    test('56..120 arası artan yer kadar, üstü 120', () {
      expect(kivilcimGenisligi(56), 56);
      expect(kivilcimGenisligi(90), 90);
      expect(kivilcimGenisligi(120), 120);
      expect(kivilcimGenisligi(400), 120);
    });
    test('kaynak: kıvılcım artan yerden ölçülür, tutar ölçülür, rozet sabit',
        () {
      final src = ekranKaynagiSync('lib/widgets/bugun_karti.dart');
      expect(
          src.contains('final artan = k.maxWidth - tutarW - rozetW'), isTrue);
      expect(src.contains('seriCiz ? kivilcimGenisligi(artan) : null'), isTrue);
      expect(src.contains('_YuzdeRozeti.azamiGenislik'), isTrue);
      // Eksen satırı (açılış / şimdi) kalktı — yer kazanımının yarısı oydu.
      expect(src.contains('todayAxisOpen'), isFalse);
    });
  });

  group('her metin tam okunur — SiganMetin (kullanıcı kuralı 2026-10-01)', () {
    // flutter_test yazı tipi Ahem: her karakter fontSize kadar geniş;
    // ölçüm deterministik.
    const stil = TextStyle(fontSize: 10);
    String? sec(List<String> adaylar, double genislik, {int maxLines = 1}) =>
        SiganMetin.sigan(adaylar,
            genislik: genislik,
            stil: stil,
            yon: TextDirection.ltr,
            olcek: TextScaler.noScaling,
            maxLines: maxLines);

    test('sığan ilk (en uzun) yazım seçilir', () {
      expect(sec(['uzun yazim', 'kisa'], 100), 'uzun yazim');
      expect(sec(['uzun yazim', 'kisa'], 60), 'kisa');
    });
    test('hiçbiri sığmazsa null — widget en kısayı satıra kırar', () {
      expect(sec(['uzun yazim', 'kisa'], 30), isNull);
    });
    test('iki satırda sığma kontrolü', () {
      expect(sec(['uzun yazim'], 60, maxLines: 2), 'uzun yazim');
    });
    testWidgets('dar yerde kısa yazım TAM yazılır, üç nokta yok',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 60,
            child: SiganMetin(['Haftalik ozet hazir', 'Ozet'], style: stil),
          ),
        ),
      ));
      expect(sigan('Ozet'), findsOneWidget);
      expect(sigan('Haftalik ozet hazir'), findsNothing);
    });
    test('kaynak: kartta çıplak ellipsis Text kalmadı', () {
      final src = ekranKaynagiSync('lib/widgets/bugun_karti.dart');
      // Tutar/değer FittedBox'ta (küçülür, kırpılmaz); gün adı ve ay
      // kısaltması sabit ve kısa. Diğer her metin SiganMetin'den geçer.
      expect(RegExp(r'overflow: TextOverflow\.ellipsis').allMatches(src).length,
          lessThanOrEqualTo(2),
          reason: 'Yeni metin ellipsis ile değil SiganMetin ile eklenir');
    });
  });

  group('kaynak sözleşmesi', () {
    final src = ekranKaynagiSync('lib/widgets/bugun_karti.dart');

    test('enflasyon kıyası geniş blokta (H düzeni)', () {
      expect(src.contains('_EnflasyonKiyasi('), isTrue);
      expect(src.contains('_EnflasyonCubugu('), isFalse,
          reason: 'D\'nin kutu içi çubuğu D ile kalktı');
    });

    test('gün içi eğri açılış seviyesini kesik çizgiyle gösterir', () {
      expect(src.contains('final tabanY = y(seri.first);'), isTrue,
          reason:
              'Açılış seviyesi serinin ilk noktası — DailySummary ile aynı');
    });
  });
}
