import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/services/ayar_olcumu.dart';
import 'package:portfoy_takip/services/dil_olcumu.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart';
import 'package:portfoy_takip/widgets/hesap_silme_nedeni_sheet.dart';

import 'helpers/kaynak.dart';

/// Ar-Ge 21 Eki "yap" partisi (yasin: "şerh düştüklerim dışında yap"):
/// hesap silme nedeni, ayar sayımı, dil ölçümü, güvenli yeniden kurma.
void main() {
  group('hesap silme nedeni', () {
    Widget sahne({double olcek = 1}) => MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 900),
              textScaler: TextScaler.linear(olcek),
            ),
            child: const Scaffold(
                body: SingleChildScrollView(child: HesapSilmeNedeniSheet())),
          ),
        );

    testWidgets('dört neden ve Kapat görünür', (t) async {
      await t.pumpWidget(sahne());
      expect(find.byType(OutlinedButton), findsNWidgets(4));
      expect(find.text('Kapat'), findsOneWidget);
      expect(find.text('Artık kullanmıyorum'), findsOneWidget);
    });

    testWidgets('3.1× yazıda 320 pt taşmıyor', (t) async {
      await t.pumpWidget(sahne(olcek: 3.1));
      expect(t.takeException(), isNull);
    });

    test('analitik kodları sabit, çeviriden bağımsız', () {
      expect(HesapSilmeNedeni.values.map(hesapSilmeNedeniKodu), [
        'kullanmiyorum',
        'eksik_ozellik',
        'fiyat_sorunu',
        'baska_uygulama',
      ]);
    });

    test('silme yolunda adım yok: soru silmeden SONRA, kimlik önce düşer', () {
      final k = ekranKaynagiSync('lib/screens/settings_screen.dart');
      final sil = k.indexOf('deleteAccount(password: password)');
      final kimlik = k.indexOf('setUserId(null)', sil);
      final sayfa = k.indexOf('hesapSilindiSayfasi(context)', sil);
      expect(sil, greaterThan(0));
      expect(kimlik, greaterThan(sil));
      expect(sayfa, greaterThan(kimlik));
    });
  });

  group('ayar sayımı', () {
    setUp(AyarOlcumu.sifirlaTest);

    test('aynı anahtar oturumda bir kez sayılır', () {
      AyarOlcumu.degisti('tema');
      AyarOlcumu.degisti('tema');
      AyarOlcumu.degisti('dil');
      expect(AyarOlcumu.sayilanlar, {'tema', 'dil'});
    });

    test('değer değil yalnız ad gönderilir', () {
      final k = ekranKaynagiSync('lib/providers/preferences_provider.dart');
      final cagrilar =
          RegExp(r'AyarOlcumu\.degisti\(([^)]*)\)').allMatches(k).toList();
      expect(cagrilar.length, greaterThanOrEqualTo(6));
      for (final m in cagrilar) {
        expect(m.group(1), isNot(contains('value')));
        expect(m.group(1), isNot(contains('_key')),
            reason: 'kişiye özel önekli anahtar değil, gövdesi');
      }
    });
  });

  group('dil ölçümü', () {
    test('seçim varsa o; sistemse cihaz dili; desteklenmeyen dil Türkçe', () {
      expect(
          DilOlcumu.uygulamaDili(const Locale('en', 'US'), const Locale('tr')),
          'en');
      expect(
          DilOlcumu.uygulamaDili(const Locale('tr', 'TR'), const Locale('en')),
          'tr');
      expect(DilOlcumu.uygulamaDili(null, const Locale('en')), 'en');
      expect(DilOlcumu.uygulamaDili(null, const Locale('de')), 'tr');
    });
  });

  group('alarmı yeniden kurma', () {
    PriceAlert alarm(String yon) => PriceAlert(
          id: 'a1',
          userId: 'u1',
          symbol: 'THYAO',
          label: 'THY',
          targetPrice: 300,
          direction: yon,
          enabled: true,
          createdAt: DateTime(2026, 1, 1),
        );

    test('fiyat eşiğin ötesindeyse aynı eşik hemen çalar', () {
      expect(alarmHemenCalarMi(alarm('above'), 310), isTrue);
      expect(alarmHemenCalarMi(alarm('above'), 300), isTrue);
      expect(alarmHemenCalarMi(alarm('above'), 290), isFalse);
      expect(alarmHemenCalarMi(alarm('below'), 290), isTrue);
      expect(alarmHemenCalarMi(alarm('below'), 310), isFalse);
    });

    test('fiyat bilinmiyorsa karar yok (eski davranış)', () {
      expect(alarmHemenCalarMi(alarm('above'), 0), isFalse);
    });

    testWidgets('ön dolu sayfa eski eşiği gösterir', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: const Scaffold(
          body: AlarmKurSheet(
            adaylar: [AlarmAdayi('THYAO', 'THY', 310)],
            sabit: true,
            baslangicHedef: 300,
          ),
        ),
      ));
      expect(find.text('300,00'), findsOneWidget);
    });

    test('şerit ve Alarmlar ekranı aynı yardımcıyı kullanır', () {
      expect(ekranKaynagiSync('lib/widgets/alarm_seridi.dart'),
          contains('alarmiYenidenKur('));
      expect(ekranKaynagiSync('lib/screens/price_alerts_screen.dart'),
          contains('alarmiYenidenKur('));
    });
  });
}
