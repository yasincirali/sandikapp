import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/screens/add_watchlist_screen.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/services/varlik_istatistik.dart';
import 'package:portfoy_takip/utils/chart_axis.dart';
import 'package:portfoy_takip/utils/money_format.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/donem_istatistik.dart';

import 'helpers/kaynak.dart';

/// 2026-09-29 emülatör testi, G1 grubu (yön, eksen, getiri tutarlılığı):
///   #1  varlık ekranı dönem satırı: yüzdenin yönü tutardan alınıyordu,
///   #5  yönlü yüzde eski biçimde ("%-3,77", "%+107,05", "-10%", "-2,5%"),
///   #7  Y ekseninde tekrar eden etiket ("₺1,39M" ×4, "₺1 | ₺1"),
///   #13 aramada dolar kuru "$49,00",
///   #15 fon karnesi getirisi ile dönem çipi farkı — kaynak dipnotu,
///   #21 tarih ekseninde "Oca 26" (26 Ocak gibi okunuyor).
void main() {
  setUpAll(() async => initializeDateFormatting('tr_TR'));

  List<File> libDosyalari() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.replaceAll('\\', '/').contains('/generated/'))
      .toList();

  String yorumsuz(String kaynak) => kaynak
      .split('\n')
      .where((s) => !s.trimLeft().startsWith('//'))
      .join('\n');

  group('#5 yönlü yüzde tek kaynak — fmtPctIsaretli', () {
    test('lib/ içinde `showSign` kalmadı (parametre kaldırıldı)', () {
      final kalan = [
        for (final f in libDosyalari())
          if (yorumsuz(f.readAsStringSync()).contains('showSign:')) f.path,
      ];
      expect(kalan, isEmpty,
          reason: 'yönlü yüzde yalnız `fmtPctIsaretli` ile yazılır');
    });

    test('İngilizce sıra "12,3%" / "-10%" biçimi kalmadı', () {
      // `…}%'` ya da `toStringAsFixed(n)}%` — yüzde işareti SONDA, eksi
      // tire. Türkçe biçim "−%10" başa yazar.
      final desen = RegExp(r"(fmtNum\([^)]*\)|toStringAsFixed\([^)]*\))\}%'");
      final kalan = [
        for (final f in libDosyalari())
          for (final m in desen.allMatches(yorumsuz(f.readAsStringSync())))
            '${f.path}: ${m.group(0)}',
      ];
      expect(kalan, isEmpty);
    });

    test('bulguda adı geçen yüzeyler ortak biçimi çağırır', () {
      for (final (yol, beklenen) in [
        ('lib/widgets/donem_istatistik.dart', 'fmtPctIsaretli(ist.enBuyukDususPct)'),
        ('lib/widgets/donem_secici.dart', 'fmtPctIsaretli(g, digits: 1)'),
        ('lib/widgets/fiyat_grafigi.dart', 'fmtPctIsaretli(pct)'),
        ('lib/screens/add_watchlist_screen.dart', 'fmtPctIsaretli(pct)'),
        ('lib/widgets/percent_comparison_chart.dart',
            'fmtPctIsaretli(v, digits: eksen.ondalik)'),
        ('lib/widgets/yaris_sahnesi.dart', 'fmtPctIsaretli(v, digits: 1)'),
        ('lib/widgets/fon_karnesi_karti.dart',
            'fmtPctIsaretli(sira.getiri), fmtPctIsaretli(sira.ortanca)'),
        ('lib/widgets/leaderboard_hero_card.dart',
            'fmtPctIsaretli(best.myRoi!, digits: 1)'),
        ('lib/screens/asset_detail_screen.dart', 'fmtPctIsaretli(spot.y - 100)'),
      ]) {
        expect(ekranKaynagiSync(yol).contains(beklenen), isTrue,
            reason: '$yol: $beklenen');
      }
    });

    testWidgets('istatistik ızgarası: "−%8,48", "%-8,48" değil', (t) async {
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: Scaffold(
          body: DonemIstatistikIzgarasi(
            ist: const DonemIstatistigi(
              ilk: 100,
              son: 96.23,
              yuksek: 104,
              dusuk: 95,
              enBuyukDususPct: -8.48,
              oynaklikPct: 20,
            ),
            gun: 365,
            donemPct: 107.05,
            bugunPct: -3.77,
          ),
        ),
      ));
      expect(find.text('−%8,48'), findsOneWidget);
      expect(find.text('+%107,05'), findsOneWidget);
      expect(find.text('−%3,77'), findsOneWidget);
      expect(find.textContaining('%-'), findsNothing);
      expect(find.textContaining('%+'), findsNothing);
    });
  });

  group('#1 varlık ekranı kâr/zarar satırı — her sayı kendi yönünde', () {
    String tl(double v) => fmtTRY(v);
    // 2026-10-05: dönem satırı 2026-10-04'ten beri yüzdeyi yazmıyor
    // (`yuzdesiz`); "fiyat" etiketi (`yuzdeEtiketi`, `posPeriodPriceMove`)
    // bayrak `varlik_islem_cubugu` ile kalktı. İşaret kuralı yüzdeli
    // satırlarda (toplam kâr/zarar) aynen geçerli; burada etiketsiz sınanır.

    test('bugün alınan fon 1H düştü: yüzde EKSİ, tutar ₺0 nötr', () {
      // Emülatör: "1H kâr/zarar +₺0 · +%7,55" yeşil (fon düşmüştü).
      final k = kazancSatiri(tutar: 0.2, yuzde: -7.55, tutarMetni: tl)!;
      expect(k.metin, '₺0 · −%7,55');
      expect(k.yon, 0, reason: '₺0 kazanç değil — renk nötr');
    });

    test('tutar ile yüzde zıt yönde: ikisi de kendi işaretini taşır', () {
      // Dönem içinde ucuzdan alım: ürün düştü ama alım fiyatından kâr.
      final k = kazancSatiri(tutar: 150, yuzde: -2.5, tutarMetni: tl)!;
      expect(k.metin, '+₺150 · −%2,50');
      expect(k.yon, 1, reason: 'renk "kâr/zarar"ın, yani tutarın yönü');
    });

    test('zarar: tipografik eksi, renk kayıp', () {
      final k = kazancSatiri(tutar: -368, yuzde: -4.1, tutarMetni: tl)!;
      expect(k.metin, '−₺368 · −%4,10');
      expect(k.yon, -1);
    });

    test('ikisi de sıfıra yuvarlanıyorsa "Değişim yok" (null)', () {
      expect(kazancSatiri(tutar: 0.3, yuzde: 0.001, tutarMetni: tl), isNull);
    });

    test('kart dönem satırı yüzdesiz; eski abs() kalmadı', () {
      final src = yorumsuz(
          ekranKaynagiSync('lib/screens/asset_detail_screen.dart'));
      expect(src.contains('yuzdesiz: true'), isTrue);
      expect(src.contains('fmtPct(yuzde.abs()'), isFalse);
      expect(src.contains('fmtPct(pct.abs())'), isFalse);
      expect(src.contains('fmtPct(pnl.pnlPct.abs())'), isFalse);
    });
  });

  group('#7 Y ekseni — komşu etiketler ayırt edilir', () {
    List<String> etiketler(String Function(double) f, double alt, double adim,
            int n) =>
        [for (var i = 0; i < n; i++) f(alt + i * adim)];

    test('₺1,39M portföy, ₺2.500 adım: dört farklı etiket', () {
      // Emülatör: "₺1,39M | ₺1,39M | ₺1,39M | ₺1,39M" (Performans GÜNLÜK).
      final e = etiketler((v) => fmtTRYAxis(v, 2500), 1385000, 2500, 4);
      expect(e.toSet().length, 4, reason: '$e');
      final eski = etiketler(fmtTRYCompact, 1385000, 2500, 4);
      expect(eski.toSet().length, lessThan(4),
          reason: 'eski biçimleyici tekrar ediyordu: $eski');
    });

    test('baz birimde de (BazPara.axis) aynı kural', () {
      const usd = BazPara(BaseCurrency.usd, 40);
      final e = etiketler((v) => usd.axis(v, 2500 * 40), 1385000 * 40.0,
          2500 * 40, 4);
      expect(e.toSet().length, 4, reason: '$e');
    });

    test('₺1 civarı birim fiyat, 0,25 adım: "₺1 | ₺1" değil', () {
      final e = etiketler((v) => fmtTRYAxis(v, 0.25), 0.75, 0.25, 3);
      expect(e, ['₺0,75', '₺1,00', '₺1,25']);
    });

    test('adım kademenin tavanını aşarsa kısaltmasız yazılır', () {
      final e = etiketler((v) => fmtTRYAxis(v, 50), 1390000, 50, 3);
      expect(e.toSet().length, 3, reason: '$e');
      expect(e.first, '₺1.390.000');
    });

    test('yeterli olduğu yerde eski kısa biçim korunur', () {
      expect(fmtTRYAxis(2450000, 80000), '₺2,45M');
      expect(fmtTRYAxis(1500, 400), '₺1,5K');
    });

    test('eksenOndaligi adımı TAM gösterir', () {
      expect(eksenOndaligi(0.25), 2);
      expect(eksenOndaligi(2.5), 1);
      expect(eksenOndaligi(5), 0);
      expect(eksenOndaligi(0.005), 3);
      expect(eksenOndaligi(0.1, enAz: 1), 1);
    });

    test('grafikler eksende adıma duyarlı biçimleyiciyi çağırır', () {
      final perf =
          ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
      expect(perf.contains('_fmtY(val, yInterval)'), isTrue);
      expect(perf.contains('.axis(val, adim)'), isTrue);
      final detay = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
      expect(detay.contains('fmtTRYAxis('), isTrue);
      expect(detay.contains(': fmtTRYCompact(fromY(value))'), isFalse);
      expect(ekranKaynagiSync('lib/widgets/fiyat_grafigi.dart')
          .contains('eksenOndaligi(bant.interval)'), isTrue);
    });
  });

  group('#21 tarih ekseni — kısa yıl gün sanılmasın', () {
    test('uzun pencere: "Oca \'26"', () {
      final e = zamanEtiketi(DateTime(2026, 1, 15), spanGun: 500, gunIci: false);
      expect(e, "Oca '26");
    });

    test('başka yıldaki gün: "3 Oca \'25"', () {
      final yil = DateTime.now().year - 1;
      final e = zamanEtiketi(DateTime(yil, 1, 3), spanGun: 90, gunIci: false);
      expect(e, "3 Oca '${(yil % 100).toString().padLeft(2, '0')}");
    });

    test('varlık detayı ortak kuralı çağırır (kopya kalmadı)', () {
      final src = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
      expect(src.contains("DateFormat('MMM yy'"), isFalse);
      expect(src.contains('zamanEtiketi(date'), isTrue);
    });
  });

  group('#13 kotasyon sembolü — kur çiftinin fiyatı karşı parada', () {
    test('kotasyonSembolu', () {
      expect(kotasyonSembolu('USDTRY=X', 'TRY'), '₺');
      expect(kotasyonSembolu('EURTRY=X', 'EUR'), '₺');
      expect(kotasyonSembolu('XAUUSD=X', 'USD'), '\$');
      expect(kotasyonSembolu('BZ=F', 'USD'), '\$');
      expect(kotasyonSembolu('THYAO.IS', 'TRY'), '₺');
      // Miktar sembolü değişmedi: "$100" tutan dolar.
      expect(currencySymbolFor('USDTRY=X', 'TRY'), '\$');
    });

    test('arama satırı: dolar "₺49,00"', () {
      const k = VarlikKimligi(
          ticker: 'USDTRY=X',
          name: 'Amerikan Doları',
          type: AssetType.doviz,
          currency: 'TRY');
      final m = aramaFiyatMetni(
          k, const YahooQuote(symbol: 'USDTRY=X', regularMarketPrice: 49));
      expect(m, '₺49,00');
    });

    test('varlık sayfası da kotasyon sembolüyle yazar', () {
      final src = ekranKaynagiSync('lib/screens/varlik_sayfasi.dart');
      expect(src.contains('kotasyonSembolu(k.ticker, k.currency)'), isTrue);
    });
  });

  test('#15 fon karnesi dipnotu getirinin kaynağını ve farkı söyler', () {
    final tr = lookupAppLocalizations(const Locale('tr')).fundReportFootnote;
    expect(tr, contains("TEFAS'ın açıkladığı"));
    expect(tr, contains('dönem getirisinden'));
    final en = lookupAppLocalizations(const Locale('en')).fundReportFootnote;
    expect(en, contains('published by TEFAS'));
  });
}
