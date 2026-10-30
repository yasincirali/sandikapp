import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/ohlc.dart';
import 'package:portfoy_takip/models/ozel_gosterge.dart';
import 'package:portfoy_takip/providers/ozel_gosterge_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/widgets/grafik_arac_cubugu.dart';
import 'package:portfoy_takip/widgets/katmanli_fiyat_grafigi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Üç ekran tutarlılığı (yasin 2026-10-10 gece): *"ana sayfa aramadan
/// gidilen varlık kartı, portföyden varlık performans ekranı ve
/// karşılaştırma ekranı: bu gösterge filtre, mum ve yenileme sıklığı
/// olmalı ve bu 3 ekran tutarlı olmalı."*
///
/// Kilitler:
///  · Üç yüzey aynı araç çubuğunu ([GrafikAracCubugu]) kurar; kendi çip
///    kopyası yazan yüzey bu testi kırar.
///  · Görünürlük kapısı aynı: paywall kapalı + admin değil → araç çubuğu
///    yok, varlık sayfasının grafiği birebir eskisi (canlıdaki kullanıcı).
///  · Paywall açık + ücretsiz → çubuk var, `ƒx` kilitli (Pine Premium),
///    mum/EMA kilitsiz.
class _Gostergeler extends OzelGostergelerNotifier {
  @override
  Future<List<OzelGosterge>> build() async => const [];
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  group('kaynak', () {
    test('üç yüzey ortak araç çubuğunu kurar', () {
      final detay = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
      expect(detay.contains('GrafikAracCubugu('), isTrue);
      expect(detay.contains('_OverlayChip('), isFalse,
          reason: 'çipler ortak bileşende (grafik_arac_cubugu.dart)');
      final sayfa = ekranKaynagiSync('lib/screens/varlik_sayfasi.dart');
      expect(sayfa.contains('KatmanliFiyatGrafigi('), isTrue);
      final katmanli =
          ekranKaynagiSync('lib/widgets/katmanli_fiyat_grafigi.dart');
      expect(katmanli.contains('GrafikAracCubugu('), isTrue);
      final kars = ekranKaynagiSync('lib/screens/comparison_screen.dart');
      expect(kars.contains('GrafikAracCubugu('), isTrue);
    });

    // yasin 2026-10-11: "mum grafik ve ema herkeste gösterilebilsin flag
    // arkasında olmasın". Mum/EMA kapısız; Premium görünürlüğü yalnız ƒx'te.
    test('mum/EMA kapısız, ƒx Premium görünürlüğünde', () {
      for (final yol in [
        'lib/screens/asset_detail/grafik_katmanlari.dart',
        'lib/widgets/katmanli_fiyat_grafigi.dart',
      ]) {
        expect(ekranKaynagiSync(yol).contains('premiumOzellikleriGorunurProvider'),
            isTrue,
            reason: '$yol: ƒx kapısı');
      }
      // Karşılaştır'da ƒx yok; Premium kapısı da kalmadı.
      expect(
          ekranKaynagiSync('lib/screens/comparison_screen.dart')
              .contains('premiumOzellikleriGorunurProvider'),
          isFalse);
    });

    test('mum isteği ve Pine çalıştırıcısı ortak', () {
      for (final yol in [
        'lib/widgets/katmanli_fiyat_grafigi.dart',
        'lib/screens/comparison_screen.dart',
      ]) {
        expect(ekranKaynagiSync(yol).contains('MumYukleyici('), isTrue,
            reason: yol);
      }
      expect(
          ekranKaynagiSync('lib/screens/asset_detail/ozel_gostergeler.dart')
              .contains('ozelGostergeleriCalistir('),
          isTrue);
    });
  });

  group('varlık sayfası grafiği', () {
    Future<void> kur(WidgetTester t,
        {required bool gorunur, required bool kilitli}) async {
      final simdi = DateTime.now();
      final seri = <int, double>{
        for (var i = 60; i >= 0; i--)
          simdi.subtract(Duration(days: i)).millisecondsSinceEpoch:
              100 + i % 7 + (60 - i) * 0.5,
      };
      await t.pumpWidget(ProviderScope(
        overrides: [
          premiumOzellikleriGorunurProvider.overrideWithValue(gorunur),
          premiumKilitliProvider.overrideWithValue(kilitli),
          ozelGostergelerProvider.overrideWith(_Gostergeler.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KatmanliFiyatGrafigi(
                ticker: 'THYAO.IS',
                type: AssetType.hisse,
                currency: 'TRY',
                sembolEtiketi: 'THYAO',
                seri: seri,
                periodDays: 90,
                bicim: NumberFormat('#,##0.00', 'tr_TR'),
                semanticLabel: 'grafik',
              ),
            ),
          ),
        ),
      ));
      await t.pump(const Duration(milliseconds: 100));
      // Çipler "Göstergeler" düğmesinin ardında (UX raporu 30 Eki §2).
      await t.tap(find.byType(GostergelerDugmesi));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
    }

    testWidgets('paywall kapalı, admin değil: mum ve EMA var, ƒx yok',
        (t) async {
      await kur(t, gorunur: false, kilitli: false);
      expect(find.byType(GrafikAracCubugu), findsOneWidget);
      final etiketler = t
          .widgetList<GrafikCipi>(find.byType(GrafikCipi))
          .map((c) => c.label)
          .toList();
      expect(etiketler, containsAll(['MUM', 'LOG', 'MA20', 'EMA50', 'EMA200']));
      expect(etiketler.where((e) => e.startsWith('ƒx')), isEmpty);
    });

    testWidgets('paywall açık, ücretsiz: çubuk var, yalnız ƒx kilitli',
        (t) async {
      await kur(t, gorunur: true, kilitli: true);
      expect(find.byType(GrafikAracCubugu), findsOneWidget);
      final cipler =
          t.widgetList<GrafikCipi>(find.byType(GrafikCipi)).toList();
      expect(cipler.map((c) => c.label),
          containsAll(['MUM', 'LOG', 'ƒx', 'MA20', 'EMA50', 'EMA200']));
      for (final c in cipler) {
        expect(c.kilitli, c.label.startsWith('ƒx'), reason: c.label);
      }
    });
  });

  // yasin 2026-10-10 gece: "grafik çizdirme sıklığı bir dropdown ile
  // seçtirilebilir. defaultta da tradingviewdeki time-interval ve default
  // frequency ile açılsın ekranlarda".
  group('aralık menüsü', () {
    testWidgets('açılır menü: seçim yalnız seçildiği dönemde geçerli',
        (t) async {
      late WidgetRef r;
      await t.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(builder: (context, ref, _) {
              r = ref;
              const hafta = 7 * 1440.0;
              final secim = secilenMumAraligi(ref, hafta);
              return GrafikAracCubugu(
                katmanlar: true,
                ma20Acik: false,
                mumAcik: true,
                aralik: secim ?? MumAraligi.dk5,
                gecerliAraliklar: const [
                  MumAraligi.dk1,
                  MumAraligi.dk5,
                  MumAraligi.dk15,
                  MumAraligi.saat1,
                ],
                pencereDakika: hafta,
              );
            }),
          ),
        ),
      ));
      // Segment şeridi yok; tek çip "5 dk ⌄".
      expect(find.byType(MumAraligiMenusu), findsOneWidget);
      expect(find.text('5 dk'), findsOneWidget);
      expect(find.text('15 dk'), findsNothing);
      await t.tap(find.byType(MumAraligiMenusu));
      await t.pumpAndSettle();
      await t.tap(find.text('15 dakikalık').last);
      await t.pumpAndSettle();
      expect(find.text('15 dk'), findsOneWidget);
      // Başka dönemde seçim yok sayılır → varsayılan.
      expect(secilenMumAraligi(r, 30 * 1440.0), isNull);
      expect(secilenMumAraligi(r, 7 * 1440.0), MumAraligi.dk15);
    });

    testWidgets('dokunma alanı 44 pt', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: MumAraligiMenusu(
              aralik: MumAraligi.dk5,
              gecerli: const [MumAraligi.dk1, MumAraligi.dk5],
              onSec: (_) {},
            ),
          ),
        ),
      ));
      final boy = t.getSize(find.byType(MumAraligiMenusu));
      expect(boy.height, greaterThanOrEqualTo(44));
      expect(boy.width, greaterThanOrEqualTo(44));
    });
  });
}
