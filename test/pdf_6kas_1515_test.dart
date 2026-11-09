import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/pdf.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show premiumKilitliProvider;
import 'package:portfoy_takip/screens/yillik_rapor_screen.dart';
import 'package:portfoy_takip/services/disa_aktarim/pdf_marka.dart';
import 'package:portfoy_takip/services/disa_aktarim/pdf_yazici.dart';
import 'package:portfoy_takip/services/disa_aktarim/rapor_belgeleri.dart';
import 'package:portfoy_takip/services/disa_aktarim/rapor_belgesi.dart';
import 'package:portfoy_takip/services/portfoy_yorumu_service.dart';
import 'package:portfoy_takip/services/yorum_notu.dart';
import 'package:portfoy_takip/theme/sandik.dart';

import 'helpers/kaynak.dart';

/// Müşteri raporu 6 Kas 15:15 (Ar-Ge 14:45) YAP'larının kilidi:
/// PDF tür rengi türden gelir (sıradan değil), büyük harfli etiket ve
/// sıralı palet geri gelmez, üst bant 104 pt, yıllık raporda tek birincil
/// "Mali müşavirime gönder" + ≥44 pt metin düğmeleri, puan farkı tek satır.
Asset _lot(String id, AssetType tur, double fiyat,
        {AssetKind kind = AssetKind.buy, double? satis, DateTime? tarih}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Varlık $id',
      ticker: id.toUpperCase(),
      type: tur,
      quantity: 10,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      kind: kind,
      sellPrice: satis,
      addedDate: tarih ?? DateTime(2025, 6, 1),
    );

RaporGrafigi _dagilim(List<Asset> lotlar) => portfoyBelgesi(
      lotlar: lotlar,
      tlYap: (t, _) => t,
      kim: 'demo',
      olusturma: DateTime(2026, 11, 6),
    ).grafikler.firstWhere((g) => g.tur == RaporGrafikTuru.dagilim);

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _Portfoy extends PortfolioNotifier {
  _Portfoy(this.lotlar);
  final List<Asset> lotlar;
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: lotlar, usdTry: 42, eurTry: 46, gbpTry: 54);
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('tür rengi', () {
    test('aynı tür, sıra değişse de aynı renk', () {
      // Önce hisse büyük, sonra fon büyük: satır sırası tersine döner.
      final a = _dagilim([
        _lot('h', AssetType.hisse, 200),
        _lot('f', AssetType.fon, 100),
      ]);
      final b = _dagilim([
        _lot('h', AssetType.hisse, 100),
        _lot('f', AssetType.fon, 200),
      ]);
      expect(a.kalemler.first.$1, AssetType.hisse.label);
      expect(b.kalemler.first.$1, AssetType.fon.label);
      for (final t in [AssetType.hisse, AssetType.fon]) {
        final ra = PdfMarka.turRengi(a.turler[t.label]);
        final rb = PdfMarka.turRengi(b.turler[t.label]);
        expect(ra, rb, reason: '${t.label} rengi sıraya bağlı olmamalı');
        expect(ra, PdfColor.fromInt(t.onLightSurface.toARGB32()),
            reason: 'tek kaynak AssetType kâğıt tonu');
      }
      expect(PdfMarka.turRengi(AssetType.hisse),
          isNot(PdfMarka.turRengi(AssetType.fon)));
      // Türü bilinmeyen satır nötr gri (uydurma renk yok).
      expect(PdfMarka.turRengi(null), PdfMarka.griAcik);
    });

    test('dağılımlı PDF SemiBold ile üretilir', () async {
      ByteData oku(String p) =>
          ByteData.sublistView(File(p).readAsBytesSync());
      final b = portfoyBelgesi(
        lotlar: [
          _lot('h', AssetType.hisse, 200),
          _lot('f', AssetType.fon, 100),
          _lot('a', AssetType.altin, 50),
        ],
        tlYap: (t, _) => t,
        kim: 'demo',
        olusturma: DateTime(2026, 11, 6),
      );
      final pdf = await pdfYaz(b,
          duz: oku('assets/fonts/DMSans-Regular.ttf'),
          kalin: oku('assets/fonts/DMSans-SemiBold.ttf'),
          logo: File('assets/images/sandik_icon.png').readAsBytesSync());
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    });
  });

  group('kaynak taraması', () {
    final kaynaklar = {
      for (final f in Directory('lib/services/disa_aktarim')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        f.path: ekranKaynagiSync(f.path),
    };

    test('sıralı palet ve büyük harf yardımcısı yok', () {
      for (final e in kaynaklar.entries) {
        expect(e.value, isNot(contains('PdfMarka.seri')), reason: e.key);
        expect(e.value, isNot(contains('PdfMarka.buyuk')), reason: e.key);
        expect(e.value, isNot(contains('trBuyuk(')), reason: e.key);
        expect(e.value, isNot(contains("'ÖNE ÇIKANLAR'")), reason: e.key);
        expect(RegExp(r'static\s+\S+\s+(seri|buyuk)\b').hasMatch(e.value),
            isFalse,
            reason: e.key);
      }
    });

    test('PDF kalın yazısı SemiBold, Bold değil', () {
      final s = kaynaklar.entries
          .firstWhere((e) => e.key.endsWith('disa_aktarim_service.dart'))
          .value;
      expect(s, contains('DMSans-SemiBold.ttf'));
      expect(s, isNot(contains('DMSans-Bold.ttf')));
      expect(File('pubspec.yaml').readAsStringSync(),
          contains('assets/fonts/DMSans-SemiBold.ttf'));
    });

    test('PREMIUM rozeti yalnız ilk sayfa bandında', () {
      final s = kaynaklar.entries
          .firstWhere((e) => e.key.endsWith('pdf_marka.dart'))
          .value;
      final sayfaBasi = s.substring(s.indexOf('pw.Widget sayfaBasi('),
          s.indexOf('pw.Widget sayfaSonu('));
      expect(sayfaBasi, isNot(contains('premiumRozeti()')));
      // Tanım dışında tek kullanım: ilk sayfa bandı (`ustBantIcerigi`).
      expect(RegExp(r'premiumRozeti\(\),').allMatches(s).length, 1);
    });

    test('notlarda "tavsiye değildir" tekrarı yok', () {
      for (final ad in ['aylik_rapor_belgesi.dart', 'rapor_belgeleri.dart']) {
        final s = kaynaklar.entries.firstWhere((e) => e.key.endsWith(ad)).value;
        expect(s, isNot(contains('tavsiyesi değildir')), reason: ad);
      }
    });
  });

  test('üst bant 104 pt, içerik bandın içinde', () {
    expect(PdfMarka.bantYuksekligi, 104);
    expect(PdfMarka.bantIcerikYuksekligi,
        lessThan(PdfMarka.bantYuksekligi - PdfMarka.ustBosluk));
  });

  group('puan farkı tek satır', () {
    test('kıyas adıyla cümle, biçim servisin puan gösterimi', () {
      final g = puanGosterimi(-4.3)!;
      final o = YorumOlcumu('kiyas_altin_fark',
          'Portföyün gram altın kıyasına göre farkı', g);
      expect(YorumNotu.farkCumlesi(o), 'Gram altın kıyasına göre $g');
      expect(g, '−4,3 puan');
    });

    test('değer bilinmiyorsa satır yok', () {
      const o = YorumOlcumu('kiyas_altin_fark', 'Fark', '—');
      expect(YorumNotu.farkCumlesi(o), isNull);
    });

    test('PDF\'te "Fark, puan" bloğu yok', () {
      expect(ekranKaynagiSync('lib/services/disa_aktarim/yorum_notu_pdf.dart'),
          isNot(contains("'Fark, puan'")));
    });
  });

  testWidgets('yıllık rapor: tek birincil gönder düğmesi, metin düğmeleri ≥44',
      (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final lotlar = [
      _lot('b', AssetType.hisse, 100, tarih: DateTime(2025, 1, 2)),
      _lot('s', AssetType.hisse, 100,
          kind: AssetKind.sell, satis: 130, tarih: DateTime(2025, 3, 4)),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_Auth.new),
        portfolioProvider.overrideWith(() => _Portfoy(lotlar)),
        premiumKilitliProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        locale: const Locale('tr', 'TR'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
        home: const YillikRaporScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Mali müşavirime gönder'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget,
        reason: 'ekranda tek birincil (dolu) düğme');
    expect(
        find.ancestor(
            of: find.text('Mali müşavirime gönder'),
            matching: find.byType(FilledButton)),
        findsOneWidget);
    for (final metin in ['Yalnız PDF', 'Yalnız Excel']) {
      final dugme = find.ancestor(
          of: find.text(metin), matching: find.byType(TextButton));
      expect(dugme, findsOneWidget, reason: metin);
      final boy = tester.getSize(dugme);
      expect(boy.height, greaterThanOrEqualTo(SandikTouch.min), reason: metin);
      expect(boy.width, greaterThanOrEqualTo(SandikTouch.min), reason: metin);
    }
    expect(find.byType(OutlinedButton), findsNothing,
        reason: 'eski iki düğmeli satır (PDF dolu + Excel çerçeve) kalktı');
  });
}
