import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/recap_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/period_summary_view.dart';

/// Özet sekmesinin GÖRSEL kapısı.
///
/// **Neden widget testi, neden emülatör değil:** pixel7_1/pixel7_2 AVD'leri
/// Flutter'ı render edemiyor — ekran görüntüsü tamamen siyah geliyor
/// (doğrulandı 2026-08-09). `tool/deploy_emulators.sh` "çalışıyor mu"
/// sorusunu yanıtlıyor, "doğru görünüyor mu" sorusunu yanıtlamıyor. O soru
/// yalnızca burada yanıtlanabilir.
///
/// Kovalanan dört şey:
///   1. Kazanç ve kayıp tonu AYRI AYRI — kayıpta kutlama dili sızmasın.
///   2. 320pt genişlikte taşma yok (en dar desteklenen ekran).
///   3. Açık ve koyu tema.
///   4. Köprü bloğunun renk kuralı: katkı MAVİ, yalnızca piyasa yeşil/kırmızı.

PeriodSummary _ozet({
  required SummaryPeriod period,
  double? bas = 168774,
  double? son = 185684,
  double? katki = 12000,
  double? piyasa = 4910,
  double? pct = 2.72,
  RecapAsset? enIyi,
  RecapAsset? enZayif,
  double? tufe,
  List<double> sparkline = const [],
  ({int artida, int toplam})? gunSayimi,
  Map<AssetType, double>? dagilimBasi,
  Map<AssetType, double>? dagilimSonu,
}) =>
    PeriodSummary(
      period: period,
      start: DateTime(2026, 8, 14),
      end: DateTime(2026, 9, 13),
      baslangicTRY: bas,
      sonTRY: son,
      katkiTRY: katki,
      piyasaTRY: piyasa,
      getiriPct: pct,
      enIyi: enIyi,
      enZayif: enZayif,
      tufeFarki: tufe,
      sparkline: sparkline,
      gunSayimi: gunSayimi,
      dagilimBasi: dagilimBasi,
      dagilimSonu: dagilimSonu,
    );

/// Ekranı verilen genişlik ve temada kurar.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // `context.c` paleti `ThemeExtension<SandikPalette>` üzerinden okur ve
  // `context.surfaceCard()` yönünü `Theme.brightness`'tan alır (light'ta
  // kenarlık + gölge, dark'ta overlay). İkisini de vermek zorunludur;
  // eksik bırakılırsa test dark varsayımına düşer ve light modu hiç
  // denenmemiş olur.
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        extensions: [
          brightness == Brightness.light
              ? SandikPalette.light
              : SandikPalette.dark,
        ],
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Kutlama / uyarı / eylem dili — hiçbir tonda görünmemeli.
const _yasakliKelimeler = [
  'Tebrikler',
  'tebrikler',
  'Harika',
  'harika',
  'Muhteşem',
  'Bravo',
  'Devam et',
  'düştü',
  'Dikkat',
  'Kaybettin',
  'Acele',
  'Kaçırma',
  '🎉',
  '🔥',
  '📈',
  '📉',
  '💰',
];

void _tonDenetimi(WidgetTester tester) {
  for (final k in _yasakliKelimeler) {
    expect(find.textContaining(k), findsNothing,
        reason: '"$k" — RETENTION_STRATEJISI §8/§9 ile çelişir');
  }
}

void main() {
  // Tarih aralığı `DateFormat(..., 'tr_TR')` ile biçimlenir; locale verisi
  // yüklenmeden DateFormat kurulamaz.
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('kazanç tonu', () {
    testWidgets('ana rakam ve yüzde rozeti çizilir', (t) async {
      await _pump(
          t, PeriodSummaryView(summary: _ozet(period: SummaryPeriod.birAy)));

      // Ana rakam SAF piyasa getirisi — ham 16.910 değil.
      expect(find.textContaining('4.910'), findsWidgets);
      expect(find.textContaining('16.910'), findsNothing,
          reason: 'ham birikim farkı ana rakam DEĞİL — katkı ayrılmış olmalı');
      expect(find.byIcon(Icons.arrow_upward_rounded), findsWidgets);
      _tonDenetimi(t);
    });

    testWidgets('köprü dört satırı da yazar', (t) async {
      await _pump(
          t, PeriodSummaryView(summary: _ozet(period: SummaryPeriod.birAy)));

      expect(find.text('Nereden geldi'), findsOneWidget);
      expect(find.text('Dönem başı'), findsOneWidget);
      expect(find.text('Katkın'), findsOneWidget);
      expect(find.text('Piyasa'), findsOneWidget);
      expect(find.text('Şimdi'), findsOneWidget);

      // Açıklama satırı: mavi çubuğun getiri OLMADIĞINI söylemek zorunda.
      expect(
        find.textContaining('senin paran'),
        findsOneWidget,
        reason: 'köprünün tek argümanı bu cümle — kaybolmamalı',
      );
    });
  });

  group('kayıp tonu', () {
    testWidgets('kutlama yok, uyarı yok, uzun pencere bağlamı var', (t) async {
      await _pump(
        t,
        PeriodSummaryView(
          summary: _ozet(
            period: SummaryPeriod.birAy,
            son: 160000,
            piyasa: -20774,
            pct: -11.5,
          ),
          uzunDonemPct: 31.8,
        ),
      );

      expect(find.byIcon(Icons.arrow_downward_rounded), findsWidgets);
      expect(
        find.text('Bu ay ekside. Daha uzun pencerede hâlâ +%31,8.'),
        findsOneWidget,
        reason: 'kayıpta ton: bağlam ver, kutlama ya da uyarı yok',
      );
      _tonDenetimi(t);
    });

    testWidgets('kayıpta ana rakam − işaretiyle ve loss renginde', (t) async {
      await _pump(
        t,
        PeriodSummaryView(
          summary: _ozet(
            period: SummaryPeriod.birHafta,
            piyasa: -5000,
            pct: -3.1,
          ),
        ),
      );
      expect(find.textContaining('−'), findsWidgets);
      _tonDenetimi(t);
    });

    testWidgets('değer artmış ama piyasa ekside — yine kayıp tonu', (t) async {
      // Katkının maskelediği senaryo: köprü bunu görünür kılmak için var.
      await _pump(
        t,
        PeriodSummaryView(
          summary: _ozet(
            period: SummaryPeriod.birAy,
            bas: 100000,
            son: 108000,
            katki: 12000,
            piyasa: -4000,
            pct: -3.57,
          ),
        ),
      );
      expect(find.byIcon(Icons.arrow_downward_rounded), findsWidgets);
      expect(find.textContaining('ekside'), findsOneWidget);
      _tonDenetimi(t);
    });
  });

  group('düz dönem', () {
    testWidgets('"Değişim yok" nötr hâli — yüzde rozeti çizilmez', (t) async {
      await _pump(
        t,
        PeriodSummaryView(
          summary: _ozet(
            period: SummaryPeriod.birAy,
            son: 168774,
            katki: 0,
            piyasa: 0,
            pct: 0,
          ),
        ),
      );
      expect(find.text('Değişim yok'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing,
          reason: 'sıfır bir YÖN taşımaz — ok gösterilmemeli');
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    });
  });

  group('320pt taşma yok', () {
    for (final period in SummaryPeriod.values) {
      testWidgets('${period.label} dar ekranda taşmıyor', (t) async {
        await _pump(
          t,
          PeriodSummaryView(
            summary: _ozet(
              period: period,
              // Milyonluk portföy: en uzun rakam hâli.
              bas: 2489186,
              son: 2685684,
              katki: 120000,
              piyasa: 76498,
              enIyi: const RecapAsset('Çok Uzun Varlık Adı AAA', 18.4),
              enZayif: const RecapAsset('Başka Uzun Varlık BBB', -7.2),
              tufe: 6.4,
              sparkline: const [100, 102, 101, 105, 103, 108],
              gunSayimi: (artida: 3, toplam: 5),
              dagilimBasi: const {
                AssetType.altin: 900000,
                AssetType.hisse: 800000,
                AssetType.doviz: 789186,
              },
              dagilimSonu: const {
                AssetType.altin: 1200000,
                AssetType.hisse: 700000,
                AssetType.doviz: 785684,
              },
            ),
            uzunDonemPct: 31.8,
            karakter: PortfolioCharacter.altinci,
            enSabirli: const RecapAsset('Gram Altın', 0),
            enSabirliGun: 412,
            percentile: 22,
            percentileKatilimci: 148,
            onShare: () {},
          ),
          width: 320,
        );
        expect(renderHatalari(), isEmpty);
      });
    }
  });

  group('tema', () {
    for (final b in Brightness.values) {
      testWidgets('${b.name} temada çizilir', (t) async {
        await _pump(
          t,
          PeriodSummaryView(
            summary: _ozet(
              period: SummaryPeriod.birYil,
              tufe: 6.4,
              enIyi: const RecapAsset('AAA', 18.4),
            ),
            karakter: PortfolioCharacter.dengeli,
            percentile: 40,
            onShare: () {},
          ),
          brightness: b,
        );
        expect(find.text('Nereden geldi'), findsOneWidget);
        expect(renderHatalari(), isEmpty);
      });
    }
  });

  group('5 segment dar ekranda', () {
    testWidgets('benchmark şeridinde yalnızca BİR çubuk vurgulu', (t) async {
      await _pump(
        t,
        PeriodSummaryView(
          summary: _ozet(period: SummaryPeriod.altiAy),
          percentile: 22,
          percentileKatilimci: 148,
        ),
        width: 320,
      );

      expect(find.text('Altı aylık karşılaştırma'), findsOneWidget);

      // Kural: bütün çubuklar sessiz text20; YALNIZCA kullanıcının çubuğu
      // amberFill. Beş kategorik renk sinyali öldürür.
      final ctx = elementOf(find.text('Altı aylık karşılaştırma'));
      final amber = ctx.c.amberFill;
      final vurgulu = t
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .where((w) => (w.decoration as BoxDecoration?)?.color == amber)
          .length;
      expect(vurgulu, 1,
          reason: 'tek vurgu olmalı — kırmızı/yeşil duvarı sinyali öldürür');
    });
  });

  group('veri yoksa', () {
    testWidgets('sayı UYDURULMAZ, boş durum çizilir', (t) async {
      await _pump(
        t,
        PeriodSummaryView(
          summary: _ozet(
            period: SummaryPeriod.altiAy,
            bas: null,
            son: null,
            katki: null,
            piyasa: null,
            pct: null,
          ),
        ),
      );
      expect(find.textContaining('yeterli geçmiş yok'), findsOneWidget);
      expect(find.text('Nereden geldi'), findsNothing,
          reason: 'eksik uçla köprü çizilemez — toplam=parçalar kırılırdı');
      expect(find.textContaining('₺0'), findsNothing,
          reason: 'sıfır bir ÖLÇÜMDÜR; ölçüm yokken basılmaz');
    });
  });
}

/// Render sırasında biriken istisnalar (taşma dahil).
List<Object> renderHatalari() {
  final out = <Object>[];
  var hata = TestWidgetsFlutterBinding.instance.takeException();
  while (hata != null) {
    out.add(hata as Object);
    hata = TestWidgetsFlutterBinding.instance.takeException();
  }
  return out;
}

BuildContext elementOf(Finder f) => f.evaluate().first;
