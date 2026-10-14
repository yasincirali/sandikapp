import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/portfoy_yorumu_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/portfoy_yorumu_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/portfoy_yorumu_karti.dart';
import 'helpers/yazi_olcegi.dart';

/// Özet'teki AI yorumu kartı (0145): üç durum × dar/geniş ekran × büyük yazı.
///
/// Kilitlenen: "Yatırım tavsiyesi değildir" uyarısı HER durumda görünür
/// (kilitli dahil); kayıtlı yorum varken model düğmesi yoktur; taşma yok.
PortfoyYorumPaketi _paket(String iz) => PortfoyYorumPaketi(
      tur: YorumTuru.haftalik,
      baslangic: DateTime(2026, 10, 5),
      bitis: DateTime(2026, 10, 11),
      parmakIzi: iz,
      olcumler: const [
        YorumOlcumu('getiri', 'Dönem getirisi', '+%4,2'),
        YorumOlcumu('en_buyuk_pay',
            'Dönem sonunda en büyük pay: Türk Hava Yolları Anonim Ortaklığı', '%46,0'),
      ],
    );

PortfoyYorumu _yorum() => PortfoyYorumu(
      tur: YorumTuru.haftalik,
      baslangic: DateTime(2026, 10, 5),
      bitis: DateTime(2026, 10, 11),
      parmakIzi: 'v1:a',
      baslik: 'Portföyün geçen hafta +%4,2 değer kazandı.',
      maddeler: const [
        (
          metin: 'Portföyünün %46,0\'sı tek varlıkta, Türk Hava Yolları\'nda duruyor.',
          kanit: ['en_buyuk_pay', 'getiri'],
        ),
      ],
      olcumler: _paket('v1:a').olcumler,
      olusturuldu: DateTime(2026, 10, 12, 9),
    );

Future<void> _pump(WidgetTester tester,
    {required PortfoyYorumDurumu? durum,
    bool kilitli = false,
    double en = 375,
    Widget kart = const PortfoyYorumuKarti(),
    PortfoyYorumu? varlikKaydi}) async {
  tester.view.physicalSize = Size(en * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3.0;
  yaziOlceginiUygula(tester);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      premiumKilitliProvider.overrideWithValue(kilitli),
      portfoyYorumRizaProvider.overrideWith((ref) async => true),
      portfoyYorumuProvider.overrideWith((ref, tur) async => durum),
      portfoySeciliYorumProvider.overrideWith((ref, p) async => durum),
      varlikYorumKaydiProvider.overrideWith((ref, a) async => varlikKaydi),
    ],
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(SandikSpace.md),
          child: kart,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  yaziOlcegiEkseni(() {
    for (final en in [320.0, 430.0]) {
      testWidgets('kayıt yok: tek düğme, uyarı görünür ($en)', (tester) async {
        await _pump(tester,
            durum: PortfoyYorumDurumu(paket: _paket('v1:a'), kayit: null), en: en);
        expect(tester.takeException(), isNull);
        expect(find.text('Bu dönemi yorumla'), findsOneWidget);
        expect(find.textContaining('Yatırım tavsiyesi değildir'), findsOneWidget);
      });

      testWidgets('kayıtlı yorum: düğme yok, kanıt çipi var ($en)', (tester) async {
        await _pump(tester,
            durum: PortfoyYorumDurumu(paket: _paket('v1:a'), kayit: _yorum()), en: en);
        expect(tester.takeException(), isNull);
        expect(find.text('Bu dönemi yorumla'), findsNothing);
        expect(find.textContaining('değişti'), findsNothing);
        expect(find.textContaining('+%4,2', findRichText: true), findsWidgets);
        expect(find.textContaining('Yatırım tavsiyesi değildir'), findsOneWidget);
      });

      testWidgets('portföy değişti: yeniden yorumla çıkar ($en)', (tester) async {
        await _pump(tester,
            durum: PortfoyYorumDurumu(paket: _paket('v1:b'), kayit: _yorum()), en: en);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('değişti'), findsOneWidget);
      });

      testWidgets('kilitli: istek düğmesi yok, uyarı yine var ($en)', (tester) async {
        await _pump(tester,
            durum: PortfoyYorumDurumu(paket: _paket('v1:a'), kayit: null),
            kilitli: true,
            en: en);
        expect(tester.takeException(), isNull);
        expect(find.text('Bu dönemi yorumla'), findsNothing);
        expect(find.textContaining('Yatırım tavsiyesi değildir'), findsOneWidget);
      });

      testWidgets('seçili dönem: ilk sekme, ekonomist açıklaması ($en)', (tester) async {
        await _pump(tester,
            durum: PortfoyYorumDurumu(paket: _paket('v1:a'), kayit: null),
            en: en,
            kart: const PortfoyYorumuKarti(secili: SummaryPeriod.ucAy));
        expect(tester.takeException(), isNull);
        expect(find.text('Seçili (3A)'), findsOneWidget);
        expect(find.text('Geçen hafta'), findsOneWidget);
        expect(find.textContaining('ekonomist'), findsOneWidget);
        expect(find.text('Bu dönemi yorumla'), findsOneWidget);
      });

      testWidgets('GÜNLÜK: yorum yazılmaz, nedeni söylenir ($en)', (tester) async {
        await _pump(tester,
            durum: PortfoyYorumDurumu(paket: _paket('v1:a'), kayit: null),
            en: en,
            kart: const PortfoyYorumuKarti(secili: SummaryPeriod.gunluk));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Gün içi dönem yorumlanmaz'), findsOneWidget);
        expect(find.text('Bu dönemi yorumla'), findsNothing);
      });

      Widget varlikKarti({bool hazir = true, double miktar = 10}) => VarlikYorumuKarti(
            period: SummaryPeriod.ucAy,
            positionKey: 'hisse|THYAO|TRY',
            miktar: miktar,
            veriHazir: hazir,
            paketKur: () async => null,
          );

      testWidgets('varlık: kayıt yok → tek düğme, uyarı ($en)', (tester) async {
        await _pump(tester, durum: null, en: en, kart: varlikKarti());
        expect(tester.takeException(), isNull);
        expect(find.text('Bu dönemi yorumla'), findsOneWidget);
        expect(find.textContaining('bu varlıkta'), findsOneWidget);
        expect(find.textContaining('Yatırım tavsiyesi değildir'), findsOneWidget);
      });

      testWidgets('varlık: seri gelmeden düğme yok ($en)', (tester) async {
        await _pump(tester, durum: null, en: en, kart: varlikKarti(hazir: false));
        expect(find.text('Bu dönemi yorumla'), findsNothing);
        expect(find.textContaining('yorum yazacak kadar veri yok'), findsOneWidget);
      });

      testWidgets('varlık: miktar değişti → yeniden yorumla ($en)', (tester) async {
        final y = _yorum();
        final kayit = PortfoyYorumu(
          tur: YorumTuru.secili,
          baslangic: y.baslangic,
          bitis: y.bitis,
          parmakIzi: varlikParmakIzi('hisse|THYAO|TRY', 10),
          baslik: y.baslik,
          maddeler: y.maddeler,
          olcumler: y.olcumler,
          olusturuldu: y.olusturuldu,
        );
        await _pump(tester,
            durum: null, en: en, kart: varlikKarti(), varlikKaydi: kayit);
        expect(tester.takeException(), isNull);
        expect(find.text(y.baslik), findsOneWidget);
        expect(find.text('Yeniden yorumla'), findsNothing);

        await _pump(tester,
            durum: null, en: en, kart: varlikKarti(miktar: 12), varlikKaydi: kayit);
        expect(find.text('Yeniden yorumla'), findsOneWidget);
      });
    }
  });
}
