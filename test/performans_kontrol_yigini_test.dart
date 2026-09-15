import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';
import 'package:portfoy_takip/widgets/kapsam_kisi_secici.dart';

/// Performans ekranı kontrol yığını — gerçek cihaz bildirimleri (2026-09-15).
///
/// Emülatör Flutter'ı render edemediği için bu ekrandaki iki hata UI
/// ağacından okunan ölçümlerle "geçti" sanıldı ve gerçek cihaz görüntüsünde
/// çıktı. Bu testler dış davranışı ölçer, iç yapıyı değil:
///   1. "GÜNLÜK" segmenti dar telefonda kırpılmaz (RenderParagraph'ın
///      gerçek genişliği metnin istediği genişlikten küçük olamaz).
///   2. Kişi seçimi ortak varken kontrol yığınının ilk satırında: Birlikte
///      ve Ben tek dokunuş, tek ortak doğrudan, çok ortak açılır liste;
///      ortak yokken satır hiç çizilmez.
///   3. Kapsam çipi artık kişiyi yazmaz (kişi başlığa taşındı).

const _uid = 'user-1';

Asset _asset({required String ticker, required String name}) => Asset(
      id: '$ticker-1',
      userId: _uid,
      name: name,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: 100,
      purchasePrice: 250.75,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 312.40,
      addedDate: DateTime(2026, 3, 14),
    );

AppUser _ortak() => AppUser(
      id: 'p-1',
      email: 'mehmet@example.com',
      displayName: 'Mehmet Yılmaz',
      createdAt: DateTime(2026, 1, 1),
    );

AppUser _ortak2() => AppUser(
      id: 'p-2',
      email: 'ayse@example.com',
      displayName: 'Ayşe Kaya',
      createdAt: DateTime(2026, 1, 1),
    );

/// Seçili durum `Semantics.selected`'dan okunur — semantik ağacı bayrak
/// API'si sürümler arasında değişiyor (flags → flagsCollection).
bool _secili(String ad) => find
    .byWidgetPredicate((w) =>
        w is Semantics &&
        w.properties.label == 'Kimin portföyü: $ad' &&
        w.properties.selected == true)
    .evaluate()
    .isNotEmpty;

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Yasin Test',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [_asset(ticker: 'THYAO.IS', name: 'Türk Hava Yolları')],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

class _FakePartners extends PartnersNotifier {
  _FakePartners(this._liste);
  final List<PartnerAccount> _liste;
  @override
  Future<List<PartnerAccount>> build() async => _liste;
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

Future<void> _pump(
  WidgetTester tester, {
  required List<PartnerAccount> partners,
  double width = 375,
}) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(_FakePortfolio.new),
        partnersProvider.overrideWith(() => _FakePartners(partners)),
        allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
      ],
      child: const MaterialApp(home: PortfolioPerformanceScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Metin, kendi istediği genişlikten dar bir kutuya sıkıştırılmış mı?
/// `softWrap: false` ile taşma yerine KIRPMA olur; taşma testi yakalamaz.
void _kirpilmamis(WidgetTester tester, String metin) {
  final f = find.text(metin);
  expect(f, findsOneWidget, reason: '$metin ekranda yok');
  final rp = tester.renderObject<RenderParagraph>(f);
  final gereken = rp.getMaxIntrinsicWidth(double.infinity);
  expect(rp.size.width, greaterThanOrEqualTo(gereken - 0.5),
      reason: '"$metin" ${rp.size.width.toStringAsFixed(1)}px kutuya '
          'sıkışmış; metin ${gereken.toStringAsFixed(1)}px ister — kırpılır');
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  group('dönem seçici — GÜNLÜK kırpılmaz', () {
    for (final w in [320.0, 375.0, 430.0]) {
      testWidgets('${w.toInt()}pt: beş dönem de tam görünür', (tester) async {
        await _pump(tester, partners: const [], width: w);
        for (final d in ['GÜNLÜK', '1H', '1A', '6A', '1Y']) {
          _kirpilmamis(tester, d);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('tam ekran ipucu dönem düğmelerini KAPSAMAZ', (tester) async {
      // Kardeş semantik birleşmesi: yatay kaydırıcının kaydırma semantiği
      // ile tam ekran çipinin `Tooltip` etiketi çakışan eylem/bayrak
      // taşımadığı için tek düğümde birleşiyor ve dönem düğmeleri
      // "Grafiği tam ekran aç" kabının çocuğu oluyordu. Ekran okuyucu için
      // yanlış; `Semantics(container: true)` sınırı bunu engeller.
      // `addTearDown` ile dispose GEÇ kalır: flutter_test, handle'ları test
      // gövdesi biter bitmez (tearDown'lardan önce) denetler ve açık handle
      // testi düşürür. Bu yüzden gövdenin sonunda açıkça kapatılıyor.
      final semantics = tester.ensureSemantics();
      await _pump(tester, partners: const []);

      var node = tester.getSemantics(find.text('GÜNLÜK')).parent;
      while (node != null) {
        expect(node.tooltip, isNot('Grafiği tam ekran aç'),
            reason: 'dönem düğmeleri tam ekran ipucunun altında');
        node = node.parent;
      }
      semantics.dispose();
    });
  });

  group('kişi seçici — kontrol yığınının ilk satırı', () {
    testWidgets('ortak yokken çizilmez', (tester) async {
      await _pump(tester, partners: const []);
      expect(find.byType(KapsamKisiSecici), findsNothing);
    });

    testWidgets('tek ortak: üç segment, hepsi TEK dokunuş', (tester) async {
      // "Birlikte ve Ben hızlı tıklanabilir"; tek ortak da menüsüz.
      await _pump(tester, partners: [
        PartnerAccount(user: _ortak(), isActive: true),
      ]);

      expect(find.byType(KapsamKisiSecici), findsOneWidget);
      final ben = find.bySemanticsLabel('Kimin portföyü: Ben');
      final mehmet = find.bySemanticsLabel('Kimin portföyü: Mehmet');
      expect(ben, findsOneWidget);
      expect(find.bySemanticsLabel('Kimin portföyü: Birlikte'), findsOneWidget);
      expect(mehmet, findsOneWidget, reason: 'ilk ad; soyad yok');
      expect(_secili('Ben'), isTrue, reason: 'açılışta Ben seçili');

      await tester.tap(mehmet);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_secili('Mehmet'), isTrue, reason: 'tek dokunuşla seçilmeli');
      expect(_secili('Ben'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('çok ortak: üçüncü segment açılır liste', (tester) async {
      // "ortaklar kısmı da dropdown liste olabilir".
      await _pump(tester, partners: [
        PartnerAccount(user: _ortak(), isActive: true),
        PartnerAccount(user: _ortak2(), isActive: true),
      ]);

      final ortaklar = find.bySemanticsLabel('Kimin portföyü: Ortaklar');
      expect(ortaklar, findsOneWidget,
          reason: 'ortak seçili değilken segment "Ortaklar" yazar');
      expect(find.text('Mehmet'), findsNothing, reason: 'liste henüz kapalı');

      await tester.tap(ortaklar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Mehmet'), findsOneWidget);
      expect(find.text('Ayşe'), findsOneWidget);

      await tester.tap(find.text('Ayşe'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_secili('Ayşe'), isTrue,
          reason: 'seçilen ortağın adı segmente yazılır ve seçili olur');
      expect(tester.takeException(), isNull);
    });

    testWidgets('PASİF ortak sayılmaz', (tester) async {
      await _pump(tester, partners: [
        PartnerAccount(user: _ortak(), isActive: false),
      ]);
      expect(find.byType(KapsamKisiSecici), findsNothing,
          reason: 'aktif ortak yok → satır çizilmez');
    });
  });

  group('kapsam çipi — kategori yazar, kişi yazmaz', () {
    testWidgets('etiket kategori önekli (+ mod)', (tester) async {
      await _pump(tester, partners: [
        PartnerAccount(user: _ortak(), isActive: true),
      ]);
      // Çıplak "Tümü" neyin tümü olduğunu söylemiyordu; önek çipin bir
      // VARLIK KATEGORİSİ seçtiğini açık eder. Kim ayrı satırda.
      expect(find.bySemanticsLabel('Kapsam: Kategori: Tümü'), findsOneWidget,
          reason: '"Ben · Tümü" değil, "Tümü" de değil — kategori önekli');
    });
  });

  group('dönem seçici — tam genişlik, içerik oranında', () {
    testWidgets('kabuk satırı doldurur ve GÜNLÜK payı en büyük',
        (tester) async {
      // "time interval da ortalanmalı": kabuk üstteki satırlarla aynı
      // hizada bitmeli. Ama pay EŞİT olmamalı, yoksa GÜNLÜK kırpılır.
      await _pump(tester, partners: const [], width: 375);

      // Kabuk genişliği ilk ve son segmentin uçlarından ölçülür — araya
      // giren `Container`/`Padding` katmanlarını aramaktan bağımsız.
      final gunluk = tester.getRect(find.text('GÜNLÜK'));
      final birY = tester.getRect(find.text('1Y'));
      final birH = tester.getRect(find.text('1H'));
      final kabukGenislik = birY.right - gunluk.left;

      expect(kabukGenislik, greaterThan(280),
          reason: 'seçici 375pt satırda içeriğe büzülmüş: $kabukGenislik');
      expect(gunluk.width, greaterThan(birH.width),
          reason: 'GÜNLÜK payı 1H ile eşitlenmiş — kırpılma riski');
      expect(tester.takeException(), isNull);
    });
  });
}
