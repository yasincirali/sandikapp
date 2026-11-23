import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/kur_ayrismasi.dart';
import 'package:portfoy_takip/providers/aylik_getiri_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/services/aylik_getiri_tablosu.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/money_format.dart';
import 'package:portfoy_takip/widgets/aylik_getiri_karti.dart';
import 'package:portfoy_takip/widgets/basa_bas_satiri.dart';
import 'package:portfoy_takip/widgets/kur_ayrismasi_satiri.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart' show KilitSatiri;

import 'helpers/kaynak.dart';

/// UI/UX inceleme turu 16 (Ar-Ge 2026-11-23 12:03): Performans ve varlık
/// sayfasının "param gerçekte ne durumda" Premium satırları.
///
/// #1 alış kuru eksik metni gerçek davranışı söyler, #2 zarardaki
/// pozisyonda kur ayrışması "zarar" der, #3 kur + başa baş ikisi kilitliyse
/// tek kilit, #4 aylık getiri ilk yüklemede iskelet, #5 hata hâlinde
/// "Tekrar dene", #6 Özet sekmesinde ham boşluk yerine ölçek.

KurAyrismasi _ayrisma({required double fiyat, required double kur}) => (
      fiyatEtkisi: fiyat,
      kurEtkisi: kur,
      alisKuru: 30.0,
      guncelKur: 29.0,
      dovizKar: fiyat / 30,
      dovizDeger: 1200.0,
      sembol: r'$',
      kurFarki: -1.0,
      toplam: fiyat + kur,
      alisOrtalamasi: 100.0,
      guncelFiyat: 120.0,
      dovizDegisimYuzde: 20.0,
    );

final _kar = _ayrisma(fiyat: 6000, kur: -1200);
final _zarar = _ayrisma(fiyat: -6000, kur: 1200);

Widget _uygulama(Widget govde, {required bool kilitli, List<Override>? ek}) =>
    ProviderScope(
      overrides: [
        premiumOzellikleriGorunurProvider.overrideWithValue(true),
        premiumKilitliProvider.overrideWithValue(kilitli),
        ...?ek,
      ],
      child: MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: Scaffold(body: SingleChildScrollView(child: govde)),
      ),
    );

void main() {
  group('#1 alış kuru eksik metni', () {
    test('düzenleme yolu yerine otomatik yeniden deneme söylenir', () {
      expect(trMetni('fxSplitMissingRate'),
          'Alış günündeki kur henüz bulunamadı; her gün yeniden denenir');
    });
  });

  group('#2 zarardaki pozisyonda zarar dili', () {
    test('karar modelde: fiyat + kur etkisi < 0', () {
      expect(kurAyrismasiZararda(_kar), isFalse);
      expect(kurAyrismasiZararda(_zarar), isTrue);
      // Tam sıfır kâr dilinde kalır (eski davranış).
      expect(kurAyrismasiZararda(_ayrisma(fiyat: 500, kur: -500)), isFalse);
    });

    testWidgets('kilitli + zarar: "Zararının ..." kilidi', (tester) async {
      await tester.pumpWidget(_uygulama(
          KurAyrismasiSatiri(ayrisma: _zarar, baz: const BazPara.lira()),
          kilitli: true));
      expect(find.text("Zararının ne kadarı fiyattan, ne kadarı kurdan: "
          "Premium'da"), findsOneWidget);
      expect(find.textContaining('Kârının'), findsNothing);
    });

    testWidgets('kilitli + kâr: metin birebir eski', (tester) async {
      await tester.pumpWidget(_uygulama(
          KurAyrismasiSatiri(ayrisma: _kar, baz: const BazPara.lira()),
          kilitli: true));
      expect(find.text("Kârının ne kadarı fiyattan, ne kadarı kurdan: "
          "Premium'da"), findsOneWidget);
    });

    testWidgets('açık + zarar: ekran okuyucu, sayfa başlığı ve toplam',
        (tester) async {
      await tester.pumpWidget(_uygulama(
          KurAyrismasiSatiri(ayrisma: _zarar, baz: const BazPara.lira()),
          kilitli: false));
      expect(
          find.bySemanticsLabel(RegExp('^Zararının fiyattan gelen kısmı')),
          findsOneWidget);
      await tester.tap(find.byType(KurAyrismasiSatiri));
      await tester.pumpAndSettle();
      expect(find.text('Zarar nereden geldi'), findsOneWidget);
      expect(find.text('İkisinin toplamı: TL zarar'), findsOneWidget);
      expect(find.text('Kâr nereden geldi'), findsNothing);
    });

    testWidgets('açık + kâr: sayfa başlığı birebir eski', (tester) async {
      await tester.pumpWidget(_uygulama(
          KurAyrismasiSatiri(ayrisma: _kar, baz: const BazPara.lira()),
          kilitli: false));
      await tester.tap(find.byType(KurAyrismasiSatiri));
      await tester.pumpAndSettle();
      expect(find.text('Kâr nereden geldi'), findsOneWidget);
      expect(find.text('İkisinin toplamı: TL kâr'), findsOneWidget);
    });
  });

  group('#3 kur + başa baş kilidi tek satır', () {
    Iterable<KilitSatiri> kilitler(WidgetTester tester) =>
        tester.widgetList<KilitSatiri>(find.byType(KilitSatiri));

    testWidgets('ikisi kilitli: tek satır, kaynak varlik_basa_bas',
        (tester) async {
      await tester.pumpWidget(_uygulama(
          PozisyonEkSatirlari(
              baz: const BazPara.lira(),
              kurAyrismasi: _zarar,
              basaBasOrani: 19),
          kilitli: true));
      expect(kilitler(tester), hasLength(1));
      expect(kilitler(tester).single.kaynak, 'varlik_basa_bas');
      expect(
          find.text("Kurun payı ve başa baş için gereken yükseliş Premium'da"),
          findsOneWidget);
      expect(find.byType(KurAyrismasiSatiri), findsNothing);
      expect(find.byType(BasaBasSatiri), findsNothing);
      expect(tester.getSize(find.byType(KilitSatiri)).height,
          greaterThanOrEqualTo(SandikTouch.min));
    });

    testWidgets('yalnız kur kilitli (kârda): bugünkü satır', (tester) async {
      await tester.pumpWidget(_uygulama(
          PozisyonEkSatirlari(baz: const BazPara.lira(), kurAyrismasi: _kar),
          kilitli: true));
      expect(kilitler(tester).map((k) => k.kaynak), ['kur_ayrismasi']);
    });

    testWidgets('yalnız başa baş kilitli (TL varlık): bugünkü satır',
        (tester) async {
      await tester.pumpWidget(_uygulama(
          const PozisyonEkSatirlari(baz: BazPara.lira(), basaBasOrani: 19),
          kilitli: true));
      expect(kilitler(tester).map((k) => k.kaynak), ['varlik_basa_bas']);
      expect(find.byType(BasaBasSatiri), findsOneWidget);
    });

    testWidgets('açık: iki satır aynen, kilit yok', (tester) async {
      await tester.pumpWidget(_uygulama(
          PozisyonEkSatirlari(
              baz: const BazPara.lira(),
              kurAyrismasi: _zarar,
              basaBasOrani: 19),
          kilitli: false));
      expect(find.byType(KilitSatiri), findsNothing);
      expect(find.byType(KurAyrismasiSatiri), findsOneWidget);
      expect(find.byType(BasaBasSatiri), findsOneWidget);
    });
  });

  group('#5 aylık getiri hatası: tekrar dene', () {
    Asset alim(DateTime t) => Asset(
          id: 'a',
          userId: 'u',
          name: 'THYAO',
          ticker: 'THYAO',
          type: AssetType.hisse,
          quantity: 1,
          purchasePrice: 1,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: 1,
          addedDate: t,
          kind: AssetKind.buy,
        );

    testWidgets('düğme provider\'ı yeniden çalıştırır, tablo gelir',
        (tester) async {
      var cagri = 0;
      final tablo = AylikGetiriTablosu(
        aylar: {
          2025: [for (var m = 1; m <= 12; m++) m <= 11 ? 1.5 : null],
        },
        yilToplami: {2025: 4.2},
        ilkAy: DateTime(2025, 1),
        buAy: DateTime(2025, 11),
        olculenAySayisi: 11,
      );
      final lot = alim(DateTime(2025, 1, 1));
      await tester.pumpWidget(_uygulama(
        AylikGetiriKarti(
          istek: AylikGetiriIstegi(
              anahtar: 't', seriLotlari: [lot], hesapLotlari: [lot]),
          simdi: DateTime(2025, 11, 11),
        ),
        kilitli: false,
        ek: [
          aylikGetiriProvider.overrideWith((ref, _) async {
            cagri++;
            if (cagri == 1) throw StateError('ag koptu xyz');
            return tablo;
          }),
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.text('Tablo hesaplanamadı.'), findsOneWidget);
      expect(find.textContaining('xyz'), findsNothing);
      final dugme = find.text('Tekrar dene');
      expect(dugme, findsOneWidget);
      expect(tester.getSize(find.ancestor(
              of: dugme, matching: find.byType(TextButton))).height,
          greaterThanOrEqualTo(SandikTouch.min));
      await tester.tap(dugme);
      await tester.pumpAndSettle();
      expect(cagri, 2);
      expect(find.text('Tablo hesaplanamadı.'), findsNothing);
      expect(find.text('Oca'), findsOneWidget);
    });
  });

  group('kaynak', () {
    test('#4 iskelet yalnız ilk yüklemede, hata yeniden denerken değil', () {
      final src = ekranKaynagiSync('lib/widgets/aylik_getiri_karti.dart');
      expect(src, contains('SandikSkeleton()'));
      expect(src, contains('tablo == null && durum.isLoading'));
      expect(src,
          contains('tablo == null && durum.hasError && !durum.isLoading'));
      expect(src, contains('ref.invalidate(aylikGetiriProvider(istek))'));
    });

    test('#6 Performans Özet sekmesinde ham 12/16 boşluk yok', () {
      final src = ekranKaynagiSync(
          'lib/screens/portfolio_performance_screen.dart');
      // Dipnotun iki yanı (tek akış ve sekmeli Özet aynı ölçeği kullanır).
      expect(
          RegExp(r'SizedBox\(height: 1[26]\),\s*const DisclaimerWidget\(kisa: true\),'
                  r'\s*const SizedBox\(height: 1[26]\)')
              .hasMatch(src),
          isFalse);
      expect(
          RegExp(r'SizedBox\(height: SandikSpace\.smd\),\s*'
                  r'const DisclaimerWidget\(kisa: true\),\s*'
                  r'const SizedBox\(height: SandikSpace\.md\)')
              .allMatches(src)
              .length,
          greaterThanOrEqualTo(3));
    });
  });
}
