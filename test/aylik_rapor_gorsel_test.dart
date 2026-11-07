@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/analiz_provider.dart';
import 'package:portfoy_takip/providers/aylik_rapor_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/analiz_notu_screen.dart';
import 'package:portfoy_takip/screens/aylik_rapor_screen.dart';
import 'package:portfoy_takip/services/aylik_rapor_kalemleri.dart';
import 'package:portfoy_takip/services/aylik_rapor_ozeti.dart';
import 'package:portfoy_takip/services/disa_aktarim/aylik_rapor_belgesi.dart';
import 'package:portfoy_takip/services/disa_aktarim/pdf_yazici.dart';
import 'package:portfoy_takip/services/varlik_analizi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';

/// Aylık rapor ve not sayfası GÖRSEL önizlemesi (2026-11-07, yasin: "not
/// sayfası da rapor pdf'i de anlaşılır olmalı"). Assert etmez; `gorsel`
/// etiketi varsayılanda atlanır.
///   flutter test --run-skipped --dart-define=CIKTI=build/gorsel \
///     test/aylik_rapor_gorsel_test.dart
/// "Önce" görüntüleri aynı veriyle taban commit'te (eski API) üretildi.
const _cikti = String.fromEnvironment('CIKTI', defaultValue: 'build/gorsel');
final _ay = DateTime.utc(2026, 10, 1);

Asset _lot(String t, AssetType tur, String ad) => Asset(
    id: t, userId: 'u', name: ad, ticker: t, type: tur, quantity: 10,
    purchasePrice: 100, currency: 'TRY', notes: '', addedDate: DateTime(2026, 8, 1));

AnalizOzeti _oz(String t, String rozet, String baslik) => AnalizOzeti(
    ticker: t, donem: _ay, baslik: baslik, rozet: rozet, maddeSayisi: 2,
    veriBaslangic: DateTime.utc(2026, 10, 1), veriBitis: DateTime.utc(2026, 10, 31));

final _ozet = AylikRaporOzeti(
  bas: DateTime(2026, 10), bit: DateTime(2026, 10, 31), surenAy: false,
  varliklar: [
    AyinVarligi(anahtar: positionKey(_lot('THYAO.IS', AssetType.hisse, 'Türk Hava Yolları')),
        tur: AssetType.hisse, ad: 'Türk Hava Yolları', pct: 8.2, piyasaTRY: 820),
    AyinVarligi(anahtar: positionKey(_lot('AAPL', AssetType.hisse, 'Apple')),
        tur: AssetType.hisse, ad: 'Apple', pct: 4.1, piyasaTRY: 1230),
    AyinVarligi(anahtar: positionKey(_lot('TEFAS:TTE', AssetType.fon, 'İş Portföy BIST Teknoloji')),
        tur: AssetType.fon, ad: 'İş Portföy BIST Teknoloji', pct: 2.4, piyasaTRY: 310),
    AyinVarligi(anahtar: positionKey(_lot('ALTIN_GRAM24', AssetType.altin, 'Gram altın')),
        tur: AssetType.altin, ad: 'Gram altın', pct: -1.5, piyasaTRY: -150),
  ],
  akis: const AyinParaAkisi(alimTRY: 10000, alimSayisi: 2),
  gelismeler: const [],
  fiyatTarihi: DateTime(2026, 10, 31, 18),
);

final _thyaoNot = VarlikNotu.satirdan({
  'ticker': 'THYAO.IS', 'tur': 'aylik', 'donem': '2026-10-01',
  'baslik': 'THYAO hissesinde Ekim boyunca işlem hacmi önceki ortalamanın 1,6 katına çıktı.',
  'rozet': 'olagandisi_hacim',
  'maddeler': [
    {'metin': 'Ay boyunca fiyat +%8,2 değişti.', 'kanit': ['fiyat_degisim']},
    {'metin': 'Ortalama günlük işlem hacmi ₺9,10Mr oldu; önceki 20 günün ortalaması ₺5,70Mr idi.', 'kanit': ['gunluk_hacim', 'ortalama_hacim']},
  ],
  'girdi': {
    'kod': 'THYAO', 'baslangic': '2026-10-01', 'bitis': '2026-10-31',
    'olcumler': [
      {'anahtar': 'fiyat_degisim', 'ad': 'Dönemde fiyat değişimi', 'gosterim': '+%8,2', 'kaynak': 'Yahoo Finance', 'tarih': '2026-10-31', 'deger': 0.082},
      {'anahtar': 'gunluk_hacim', 'ad': 'Dönemde ortalama günlük işlem hacmi', 'gosterim': '₺9,10Mr', 'kaynak': 'Yahoo Finance', 'tarih': '2026-10-31', 'deger': 9.1e9},
      {'anahtar': 'ortalama_hacim', 'ad': 'Önceki 20 günün ortalama günlük hacmi', 'gosterim': '₺5,70Mr', 'kaynak': 'Yahoo Finance', 'tarih': '2026-09-30', 'deger': 5.7e9},
    ],
  },
})!;

final _notlar = {
  'THYAO.IS': _oz('THYAO.IS', 'olagandisi_hacim', _thyaoNot.baslik),
  'TEFAS:TTE': _oz('TEFAS:TTE', 'sakin', 'TTE fonuna Ekim boyunca ₺120,4M net para girdi.'),
  'HISSE:AAPL': _oz('HISSE:AAPL', 'hareketli', 'AAPL ayı son 52 haftanın en yüksek kapanışıyla bitirdi.'),
  'ALTIN:GRAM': _oz('ALTIN:GRAM', 'sakin', 'Gram altında ay sakin geçti; fiyat −%1,4 değişti.'),
};

final Map<String, NotPozisyonu> _pozisyonlar = {
  for (final v in _ozet.varliklar)
    v.anahtar: (
      notAnahtari: switch (v.tur) {
        AssetType.altin => 'ALTIN:GRAM',
        AssetType.fon => 'TEFAS:TTE',
        _ => v.ad == 'Apple' ? 'HISSE:AAPL' : 'THYAO.IS',
      },
      tur: v.tur,
      ad: switch (v.ad) {
        'Türk Hava Yolları' => 'THYAO',
        'Apple' => 'AAPL',
        'İş Portföy BIST Teknoloji' => 'TTE',
        _ => 'Altın',
      },
    ),
};

Future<void> _fontlar() async {
  final dm = FontLoader(kSandikFontFamily);
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    dm.addFont(rootBundle.load('assets/fonts/DMSans-$w.ttf'));
  }
  await dm.load();
  final ikon = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await ikon.load();
}

Future<void> _yaz(WidgetTester tester, Key k, String ad) async {
  await tester.runAsync(() async {
    final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
    final img = await b.toImage(pixelRatio: 2.0);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$_cikti/$ad.png')..createSync(recursive: true);
    f.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Widget _uygulama(Widget home, List<Override> o) => ProviderScope(
      overrides: o,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await _fontlar();
  });

  testWidgets('sonra: rapor ekranı', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 1500 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = Key('g');
    await tester.pumpWidget(RepaintBoundary(key: k, child: _uygulama(AylikRaporScreen(donem: _ay), [
      tutulanNotAnahtarlariProvider.overrideWithValue(
          ['THYAO.IS', 'TEFAS:TTE', 'HISSE:AAPL', 'ALTIN:GRAM']),
      notPozisyonlariProvider.overrideWith((ref, l) => _pozisyonlar),
      notOzetleriProvider.overrideWith((ref, a) async => _notlar),
      aylikRaporOzetiProvider.overrideWith((ref, d) async => _ozet),
      radarKilitliProvider.overrideWithValue(false),
    ])));
    await tester.pumpAndSettle();
    await _yaz(tester, k, 'sonra_rapor_ekrani');
  });

  testWidgets('sonra: not sayfası', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 900 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = Key('g');
    await tester.pumpWidget(RepaintBoundary(key: k, child: _uygulama(
        AnalizNotuScreen(ticker: 'THYAO.IS', tur: 'aylik', donem: _ay, kod: 'THYAO', baslik: _thyaoNot.baslik), [
      radarKilitliProvider.overrideWithValue(false),
      varlikNotuProvider.overrideWith((ref, a) async => _thyaoNot),
    ])));
    await tester.pumpAndSettle();
    await _yaz(tester, k, 'sonra_not_sayfasi');
  });

  test('sonra: pdf', () async {
    ByteData oku(String yol) => ByteData.sublistView(File(yol).readAsBytesSync());
    final l = AppLocalizationsTr();
    final k = raporKalemleri(
      notlar: _notlar.values.toList(),
      varliklar: _ozet.varliklar,
      pozisyonlar: _pozisyonlar,
      varlikAdi: (v) => _pozisyonlar[v.anahtar]!.ad,
      notAdi: notKodu,
    );
    String? aralik(AnalizOzeti n) => l.anzAylikNotVerisi('1-31 Ekim 2026');
    final b = aylikRaporBelgesi(
      donem: DateTime(2026, 10),
      kapsam: '1 Ekim – 31 Ekim 2026',
      notlar: [
        for (final x in k.onemli)
          AylikRaporNotu(
            kod: x.ad,
            tur: x.tur?.labelOf(l),
            baslik: x.not!.baslik,
            rozet: x.not!.ticker == 'THYAO.IS' ? l.rdrRozetHacim : l.rdrRozetHareketli,
            neOldu: x.varlik == null
                ? null
                : l.anzAylikNeOldu(fmtPctIsaretli(x.varlik!.pct, digits: 1),
                    isaretliTL(x.varlik!.piyasaTRY)),
            aralik: aralik(x.not!),
            maddeler: x.not!.ticker == 'THYAO.IS'
                ? [for (final m in _thyaoNot.maddeler) m.metin]
                : const ['Ay boyunca fiyat +%4,1 değişti.'],
          ),
      ],
      satirlar: [
        for (final x in k.diger)
          AylikRaporNotu(
            kod: x.ad,
            tur: x.tur?.labelOf(l),
            baslik: x.not?.baslik ?? '',
            neOldu: x.varlik == null
                ? null
                : '${fmtPctIsaretli(x.varlik!.pct, digits: 1)} · ${isaretliTL(x.varlik!.piyasaTRY)}',
            aralik: x.not == null ? null : aralik(x.not!),
          ),
      ],
      akis: _ozet.akis,
      ozetCumlesi: 'Notu çıkan 4 varlığından 2 tanesinde ay boyunca belirgin hareket oldu.',
      eksikCumlesi: null,
      haberCumlesi: '${l.anzAylikHaberYok} ${l.anzAylikKaynak}.',
      kim: 'demo',
      olusturma: DateTime(2026, 11, 1, 9),
      getiriPct: 3.1,
    );
    final pdf = await pdfYaz(b,
        duz: oku('assets/fonts/DMSans-Regular.ttf'),
        kalin: oku('assets/fonts/DMSans-SemiBold.ttf'),
        logo: File('assets/images/sandik_icon.png').readAsBytesSync());
    File('$_cikti/sonra_rapor.pdf')
      ..createSync(recursive: true)
      ..writeAsBytesSync(pdf);
  });
}
