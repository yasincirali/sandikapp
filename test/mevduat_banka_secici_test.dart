import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/mevduat_bankasi.dart';
import 'package:portfoy_takip/providers/mevduat_banka_provider.dart';
import 'package:portfoy_takip/screens/add_asset/mevduat_formu.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mevduat banka seçici + faiz önerisi + not (bayrak `mevduat_banka_secici`,
/// yasin 2026-10-09).
///
/// Kilitlenenler:
///   · TCMB ortalaması BİLEŞİK; forma BASİT yıllık olarak girer (çevirmeden
///     yazmak 32 günlükte getiriyi ~7 puan şişirirdi);
///   · elle yazılan oranın üstüne öneri bir daha yazılmaz;
///   · katılım bankası / vadesiz / verisi olmayan dilimde sayı uydurulmaz;
///   · liste yoksa da kullanıcı yazdığı adı kullanabilir;
///   · bayrak kapalıyken form birebir eski.
const _akbank = MevduatBankasi(kod: 'akbank', ad: 'Akbank', katilim: false);
const _kuveyt =
    MevduatBankasi(kod: 'kuveytturk', ad: 'Kuveyt Türk', katilim: true);
const _qnb = MevduatBankasi(
    kod: 'qnb', ad: 'QNB', katilim: false, digerAdlar: ['Finansbank']);

final _hafta = DateTime(2026, 10, 2);
final _ortalamalar = {
  'ay1': MevduatFaizOrtalamasi(
      dilim: 'ay1', yillikBilesik: 45, veriTarihi: _hafta),
  'ay3': MevduatFaizOrtalamasi(
      dilim: 'ay3', yillikBilesik: 44, veriTarihi: _hafta),
};

void main() {
  group('model', () {
    test('harf rozeti: kısaltma, iki kelime, bitişik ad, "Bank" atılır', () {
      String r(String ad) =>
          MevduatBankasi(kod: 'x', ad: ad, katilim: false).rozet;
      expect(r('QNB'), 'QNB');
      expect(r('HSBC'), 'HSBC');
      expect(r('ICBC Turkey'), 'ICBC');
      expect(r('Garanti BBVA'), 'GB');
      expect(r('Yapı Kredi'), 'YK');
      expect(r('Ziraat Bankası'), 'Z');
      expect(r('İş Bankası'), 'İ');
      expect(r('DenizBank'), 'D');
      expect(r('Burgan Bank'), 'B');
      expect(r('Ziraat Katılım'), 'ZK');
    });

    test('arama Türkçe katlanır ve diğer adlara bakar', () {
      expect(_qnb.eslesir('finans'), isTrue);
      expect(_kuveyt.eslesir('turk'), isTrue);
      expect(_akbank.eslesir('garanti'), isFalse);
      expect(_akbank.eslesir(''), isTrue);
    });

    test('vade dilimi sınırları (32 gün = "1 aya kadar")', () {
      expect(mevduatVadeDilimi(null), isNull);
      expect(mevduatVadeDilimi(1), 'ay1');
      expect(mevduatVadeDilimi(32), 'ay1');
      expect(mevduatVadeDilimi(33), 'ay3');
      expect(mevduatVadeDilimi(92), 'ay3');
      expect(mevduatVadeDilimi(181), 'ay6');
      expect(mevduatVadeDilimi(366), 'yil1');
      expect(mevduatVadeDilimi(730), 'yil1_ustu');
    });

    test('bileşik → basit: 32 günde %45 bileşik ≈ %37,77 basit; 365 günde eşit',
        () {
      expect(bilesiktenBasitYillik(45, 32), closeTo(37.77, 0.01));
      expect(bilesiktenBasitYillik(45, 365), closeTo(45, 1e-9));
    });

    test('varsayılan faiz: katılım/vadesiz/dilim yok/banka yok → null', () {
      expect(
          mevduatVarsayilanFaiz(
                  banka: _akbank, gun: 32, ortalamalar: _ortalamalar)
              ?.oran,
          closeTo(37.77, 0.01));
      expect(
          mevduatVarsayilanFaiz(
              banka: _kuveyt, gun: 32, ortalamalar: _ortalamalar),
          isNull);
      expect(
          mevduatVarsayilanFaiz(
              banka: _akbank, gun: null, ortalamalar: _ortalamalar),
          isNull);
      expect(
          mevduatVarsayilanFaiz(
              banka: _akbank, gun: 181, ortalamalar: _ortalamalar),
          isNull);
      expect(
          mevduatVarsayilanFaiz(
              banka: null, gun: 32, ortalamalar: _ortalamalar),
          isNull);
    });

    test('ortalama satırı: faizsiz ya da 45 günden bayatsa okunmaz', () {
      final simdi = DateTime(2026, 10, 9);
      expect(
          MevduatFaizOrtalamasi.fromMap({
            'vade_dilimi': 'ay1',
            'yillik_faiz': 45.1,
            'veri_tarihi': '2026-10-02',
            'durum': 'ok',
          }, simdi: simdi)
              ?.yillikBilesik,
          45.1);
      expect(
          MevduatFaizOrtalamasi.fromMap({
            'vade_dilimi': 'ay1',
            'yillik_faiz': null,
            'veri_tarihi': null,
            'durum': 'seri_bos',
          }, simdi: simdi),
          isNull);
      expect(
          MevduatFaizOrtalamasi.fromMap({
            'vade_dilimi': 'ay1',
            'yillik_faiz': 45.1,
            'veri_tarihi': '2026-07-01',
            'durum': 'evds_hata',
          }, simdi: simdi),
          isNull);
    });

    test('banka satırı: tür ve diğer adlar', () {
      final b = MevduatBankasi.fromMap({
        'kod': 'qnb',
        'ad': 'QNB',
        'tur': 'mevduat',
        'diger_adlar': ['Finansbank', ''],
      })!;
      expect(b.katilim, isFalse);
      expect(b.digerAdlar, ['Finansbank']);
      expect(MevduatBankasi.fromMap({'kod': '', 'ad': 'X'}), isNull);
    });
  });

  group('form', () {
    Future<void> ac(WidgetTester tester,
        {bool bayrak = true,
        List<MevduatBankasi> bankalar = const [_akbank, _qnb, _kuveyt],
        double genislik = 390,
        double yaziOlcegi = 1}) async {
      await initializeDateFormatting('tr_TR');
      SharedPreferences.setMockInitialValues({});
      RemoteConfigService.testAcik = bayrak ? {'mevduat_banka_secici'} : {};
      addTearDown(() => RemoteConfigService.testAcik = {});
      tester.view.physicalSize = Size(genislik * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          mevduatKaynaklariProvider.overrideWith(
              (ref) async => (bankalar: bankalar, ortalamalar: _ortalamalar)),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(yaziOlcegi)),
            child: const Scaffold(
              body: SingleChildScrollView(child: MevduatFormu()),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    TextField alan(WidgetTester tester, int i) =>
        tester.widgetList<TextField>(find.byType(TextField)).elementAt(i);

    // Sıra (bayrak açık): banka, anapara, yıllık, aylık, stopaj, not.
    String yillik(WidgetTester t) => alan(t, 2).controller!.text;
    String aylik(WidgetTester t) => alan(t, 3).controller!.text;

    Future<void> bankaSec(WidgetTester tester, String ad) async {
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(ad).last);
      await tester.pumpAndSettle();
    }

    testWidgets('bayrak kapalı: eski form (serbest banka, tek faiz alanı)',
        (tester) async {
      await ac(tester, bayrak: false);
      expect(find.text('Aylık brüt (%)'), findsNothing);
      expect(find.text('Not'), findsNothing);
      expect(find.text('Yıllık faiz (brüt, %)'), findsOneWidget);
    });

    testWidgets('banka seçilince 32 gün için basit yıllık + aylık önerilir',
        (tester) async {
      await ac(tester);
      expect(yillik(tester), isEmpty);
      await bankaSec(tester, 'Akbank');
      expect(yillik(tester), '37,77');
      expect(aylik(tester), '3,15');
      expect(find.textContaining('Piyasa ortalaması (TCMB'), findsOneWidget);
      // Vade 92 gün → 3 aylık dilim.
      await tester.tap(find.text('92 gün'));
      await tester.pumpAndSettle();
      expect(yillik(tester), isNot('37,77'));
      expect(yillik(tester), isNotEmpty);
    });

    testWidgets('elle yazılan oran korunur; aylık ↔ yıllık iki yönlü',
        (tester) async {
      await ac(tester);
      await bankaSec(tester, 'Akbank');
      await tester.enterText(find.byWidget(alan(tester, 3)), '4');
      await tester.pumpAndSettle();
      expect(yillik(tester), '48');
      expect(find.textContaining('Bu oranı sen girdin'), findsOneWidget);
      await tester.tap(find.text('92 gün'));
      await tester.pumpAndSettle();
      await bankaSec(tester, 'QNB');
      expect(yillik(tester), '48');
    });

    testWidgets('katılım bankası: öneri yazılmaz, eski öneri silinir',
        (tester) async {
      await ac(tester);
      await bankaSec(tester, 'Akbank');
      expect(yillik(tester), isNotEmpty);
      await bankaSec(tester, 'Kuveyt Türk');
      expect(yillik(tester), isEmpty);
      expect(
          find.textContaining('kâr payı önceden belli değil'), findsOneWidget);
    });

    testWidgets('liste boşsa yazılan ad kullanılır, faiz uydurulmaz',
        (tester) async {
      await ac(tester, bankalar: const []);
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Liste şu an yüklenemedi'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Mahalle Bankası');
      await tester.pumpAndSettle();
      await tester.tap(find.text('"Mahalle Bankası" olarak kullan'));
      await tester.pumpAndSettle();
      expect(find.text('Mahalle Bankası'), findsOneWidget);
      expect(yillik(tester), isEmpty);
    });

    testWidgets('320pt × 3.0 taşmaz (bayrak açık)', (tester) async {
      await ac(tester, genislik: 320, yaziOlcegi: 3);
      await bankaSec(tester, 'Akbank');
      expect(tester.takeException(), isNull);
    });
  });
}
