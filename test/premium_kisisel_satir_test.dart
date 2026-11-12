import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/aylik_rapor_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/temettu_tahmini_provider.dart';
import 'package:portfoy_takip/screens/aylik_rapor_screen.dart';
import 'package:portfoy_takip/screens/temettu_tahmini_screen.dart';
import 'package:portfoy_takip/services/aylik_rapor_ozeti.dart';
import 'package:portfoy_takip/services/temettu_gecmisi.dart';
import 'package:portfoy_takip/services/temettu_tahmini.dart';
import 'package:portfoy_takip/services/varlik_analizi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/aylik_rapor_bolumleri.dart';
import 'package:portfoy_takip/widgets/premium_kilit_karti.dart';

/// Kilitli Premium kartlarında kullanıcının kendi verisinden tek satır
/// (2026-11-12, Ar-Ge 12 Kas #3). Tutar yok, okunamayan veriyle cümle
/// kurulmaz, boşsa dürüst cümle (temettü) ya da satır yok (aylık rapor).
final _simdi = DateTime(2026, 11, 12);
final _tr = AppLocalizationsTr();
final _en = AppLocalizationsEn();

TemettuOlayi _olay(DateTime gun, [double pay = 1]) =>
    TemettuOlayi(hakTarihi: gun, tutarPay: pay);

Asset _lot(String id, AssetKind kind, DateTime tarih) => Asset(
      id: id,
      userId: 'u',
      name: 'THYAO.IS',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      kind: kind,
      sellPrice: kind == AssetKind.sell ? 120 : null,
      dividendAmount: kind == AssetKind.dividend ? 50 : 0,
      addedDate: tarih,
    );

AnalizOzeti _not(String ticker, DateTime donem) => AnalizOzeti(
    ticker: ticker, donem: donem, baslik: 'b', rozet: 'sakin', maddeSayisi: 3);

class _OturumYok extends AuthNotifier {
  @override
  Future<AppUser?> build() async => null;
}

void main() {
  group('temettuKancasi (saf)', () {
    test('son 12 ayda dağıtanlar alfabetik; eski ve sıfır olay sayılmaz', () {
      final k = temettuKancasi([
        ('TUPRS', [_olay(DateTime(2026, 5, 2))]),
        ('ASELS', [_olay(DateTime(2026, 7, 1))]),
        ('THYAO', [_olay(DateTime(2025, 6, 1))]), // pencere dışı
        ('KCHOL', [_olay(DateTime(2026, 3, 1), 0)]), // tutar yok
        ('SISE', const []),
      ], simdi: _simdi)!;
      expect(k.kodlar, ['ASELS', 'TUPRS']);
      expect(k.bos, isFalse);
    });

    test('tek okuma düşerse null: yarım sayıyla cümle kurulmaz', () {
      expect(
          temettuKancasi([
            ('ASELS', [_olay(DateTime(2026, 7, 1))]),
            ('TUPRS', null),
          ], simdi: _simdi),
          isNull);
    });

    test('BIST hissesi yok ya da hiçbiri dağıtmadı → boş (dürüst satır)', () {
      expect(temettuKancasi(const [], simdi: _simdi)!.bos, isTrue);
      expect(
          temettuKancasi([('SISE', const <TemettuOlayi>[])], simdi: _simdi)!
              .bos,
          isTrue);
    });
  });

  group('temettuKancaCumlesi', () {
    test('en çok üç kod, fazlası +N', () {
      expect(temettuKancaCumlesi(_tr, const TemettuKancasi(['A', 'B', 'C'])),
          'Portföyündeki 3 hisse son 12 ayda temettü dağıttı: A, B, C');
      expect(
          temettuKancaCumlesi(
              _tr, const TemettuKancasi(['A', 'B', 'C', 'D', 'E'])),
          'Portföyündeki 5 hisse son 12 ayda temettü dağıttı: A, B, C +2');
    });

    test('boş: dürüst cümle; İngilizce tekil', () {
      expect(temettuKancaCumlesi(_tr, const TemettuKancasi([])),
          'Portföyünde şu an temettü dağıtan BIST hissesi yok');
      expect(temettuKancaCumlesi(_en, const TemettuKancasi(['ASELS'])),
          contains('1 stock in your portfolio paid a dividend'));
    });

    test('cümlede tutar yok (kilitli içerik verilmez)', () {
      final c = temettuKancaCumlesi(_tr, const TemettuKancasi(['ASELS']));
      expect(c, isNot(contains('₺')));
    });
  });

  group('aylikRaporKancasi (saf)', () {
    final ekim = DateTime(2026, 10);
    test('ayın alım/satım/temettü sayısı ve o ayın notları', () {
      final k = aylikRaporKancasi(
        lotlar: [
          _lot('1', AssetKind.buy, DateTime(2026, 10, 3)),
          _lot('2', AssetKind.buy, DateTime(2026, 10, 20)),
          _lot('3', AssetKind.dividend, DateTime(2026, 10, 15)),
          _lot('4', AssetKind.buy, DateTime(2026, 9, 30)), // önceki ay
        ],
        donem: ekim,
        simdi: _simdi,
        notlar: [
          _not('THYAO.IS', ekim),
          _not('TEFAS:TTE', ekim),
          _not('ASELS.IS', DateTime(2026, 9)), // başka ay
        ],
      );
      expect(k.alimSayisi, 2);
      expect(k.satisSayisi, 0);
      expect(k.temettuSayisi, 1);
      expect(k.notSayisi, 2);
      expect(aylikKancaCumlesi(_tr, 'Ekim', k),
          'Ekim ayında 2 alımın ve 1 temettün var; 2 varlığının ay notu hazır.');
    });

    test('üç parça virgül + "ve"; yalnız not; yalnız hareket', () {
      expect(
          aylikKancaCumlesi(
              _tr,
              'Ekim',
              const AylikRaporKancasi(
                  alimSayisi: 4, satisSayisi: 2, temettuSayisi: 1)),
          'Ekim ayında 4 alımın, 2 satışın ve 1 temettün var.');
      expect(aylikKancaCumlesi(_tr, 'Ekim', const AylikRaporKancasi(notSayisi: 7)),
          'Ekim ayı için 7 varlığının notu hazır.');
      expect(
          aylikKancaCumlesi(
              _en, 'October', const AylikRaporKancasi(alimSayisi: 1)),
          'In October you have 1 buy.');
    });

    test('hiçbir şey yoksa satır yok', () {
      expect(aylikKancaCumlesi(_tr, 'Ekim', const AylikRaporKancasi()), isNull);
    });
  });

  group('PremiumKilitKarti kişisel satır', () {
    Future<void> kur(WidgetTester tester, String? kisisel,
        {double olcek = 1}) async {
      tester.view.physicalSize = const Size(320 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('tr', 'TR'),
          home: MediaQuery(
            data: MediaQueryData(
                size: const Size(320, 800),
                textScaler: TextScaler.linear(olcek)),
            child: Scaffold(
              body: PremiumKilitGovdesi(
                kart: PremiumKilitKarti(
                  ikon: Icons.event_repeat_rounded,
                  baslik: 'Temettü tahmini',
                  govde: 'Genel paragraf',
                  kilitMetni: "Temettü tahmini Premium'da",
                  kaynak: 'test',
                  kisisel: kisisel,
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    const satir =
        'Portföyündeki 5 hisse son 12 ayda temettü dağıttı: ASELS, EREGL, TUPRS +2';

    testWidgets('satır görünür ve ekran okuyucu okur', (tester) async {
      final h = tester.ensureSemantics();
      await kur(tester, satir);
      expect(find.text(satir), findsOneWidget);
      // Kart düğümleri birleştirebilir; satır etiketin içinde okunmalı.
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(satir))),
          findsWidgets);
      h.dispose();
    });

    testWidgets('veri yokken satır yok', (tester) async {
      await kur(tester, null);
      expect(find.textContaining('Portföyündeki'), findsNothing);
      expect(find.text("Temettü tahmini Premium'da"), findsOneWidget);
    });

    testWidgets('2× yazıda 320 pt\'de taşma yok', (tester) async {
      await kur(tester, satir, olcek: 2);
      expect(tester.takeException(), isNull);
      expect(find.text(satir), findsOneWidget);
    });
  });

  group('kilitli ekranlar', () {
    Future<void> kur(WidgetTester tester, Widget ekran,
        List<Override> ek) async {
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_OturumYok.new),
          premiumKilitliProvider.overrideWithValue(true),
          ...ek,
        ],
        child: MaterialApp(
          locale: const Locale('tr', 'TR'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
          home: ekran,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('temettü tahmini: kendi hisseleriyle satır', (tester) async {
      await kur(tester, const TemettuTahminiScreen(), [
        temettuKancasiProvider.overrideWith(
            (ref) async => const TemettuKancasi(['ASELS', 'EREGL', 'TUPRS'])),
      ]);
      expect(
          find.text(
              'Portföyündeki 3 hisse son 12 ayda temettü dağıttı: ASELS, EREGL, TUPRS'),
          findsOneWidget);
    });

    testWidgets('temettü tahmini: okunamadıysa satır yok', (tester) async {
      await kur(tester, const TemettuTahminiScreen(), [
        temettuKancasiProvider.overrideWith((ref) async => null),
      ]);
      expect(find.byType(PremiumKilitKarti), findsOneWidget);
      expect(find.textContaining('Portföyün'), findsNothing);
    });

    testWidgets('aylık rapor: ayın kendi sayılarıyla satır', (tester) async {
      await kur(tester, AylikRaporScreen(donem: DateTime(2026, 10)), [
        aylikRaporKancasiProvider.overrideWith((ref, d) async =>
            const AylikRaporKancasi(
                alimSayisi: 4, temettuSayisi: 1, notSayisi: 7)),
      ]);
      expect(
          find.text(
              'Ekim ayında 4 alımın ve 1 temettün var; 7 varlığının ay notu hazır.'),
          findsOneWidget);
    });

    testWidgets('aylık rapor: söylenecek şey yoksa satır yok', (tester) async {
      await kur(tester, AylikRaporScreen(donem: DateTime(2026, 10)), [
        aylikRaporKancasiProvider
            .overrideWith((ref, d) async => const AylikRaporKancasi()),
      ]);
      expect(find.byType(PremiumKilitKarti), findsOneWidget);
      expect(find.textContaining('Ekim ayında'), findsNothing);
    });
  });
}
