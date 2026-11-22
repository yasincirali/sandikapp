import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/sinyal_on_ayar_provider.dart';
import 'package:portfoy_takip/services/ozellik_olcumu.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';
import 'package:portfoy_takip/widgets/sandik_segment.dart';

import 'helpers/kaynak.dart';

/// Ar-Ge 22 Kas 12:03: sinyal ve gösterge Premium'u (ön ayar eşleşmesi,
/// kilit simgesi, satın alma sonrası kaydın sürmesi, ölçüm).
SinyalOnAyar? _esle(int slot) => sinyalOnAyarEslesen(
      esikler: const {},
      zamanlamalar: const {},
      gostergeler: {
        for (final t in sinyalOnAyarTurleri)
          t: TechnicalAnalysisService.defaultEnabledFor(t),
      },
      slot: slot,
    );

void main() {
  group('1. ön ayar eşleşmesi kısılmış zamanlamayla', () {
    test('ücretsiz (slot 1): varsayılan kayıt Dengeli değil', () {
      expect(_esle(1), isNot(SinyalOnAyar.dengeli));
    });
    test('Premium / paywall kapalı (sınırsız): Dengeli', () {
      expect(_esle(1 << 30), SinyalOnAyar.dengeli);
    });
  });

  testWidgets('2. kilitli segment etiketi simge + semantics taşır', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Builder(
              builder: (c) =>
                  sandikKilitliSegmentEtiketi(c, 'Dengeli', kilitli: true)),
          Builder(
              builder: (c) =>
                  sandikKilitliSegmentEtiketi(c, 'Az', kilitli: false)),
        ]),
      ),
    ));
    final ikon = find.byIcon(Icons.lock_outline_rounded);
    expect(ikon, findsOneWidget, reason: 'yalnız kilitli etiket simge çizer');
    expect(t.widget<Icon>(ikon).semanticLabel, isNotEmpty);
    expect(find.text('Dengeli'), findsOneWidget);
  });

  test('2. iki kart da kilit yardımcısını kullanır', () {
    for (final y in [
      'lib/screens/signal_settings_screen.dart',
      'lib/widgets/bildirim_on_ayar_karti.dart',
    ]) {
      expect(ekranKaynagiSync(y), contains('sandikKilitliSegmentEtiketi'));
    }
  });

  test('3. özel gösterge Kaydet kilidi canlı okur, satın alınca sürer', () {
    final k = ekranKaynagiSync('lib/screens/ozel_gosterge_screen.dart');
    expect(k, contains('widget.kilitli && ref.read(premiumKilitliProvider)'));
    expect(k, contains('aldi != true && ref.read(premiumKilitliProvider)'));
  });

  test('4. gösterge alarmı ve çizgi alarmı paywall sonrası sürer', () {
    final a = ekranKaynagiSync('lib/widgets/alarm_kur_sheet.dart');
    expect(a, contains('_gostergeKilidiniAc'));
    expect(a, isNot(contains('widget.gostergeKilitli)')));
    final c = ekranKaynagiSync('lib/widgets/tam_ekran/cizim_alarm_dugmesi.dart');
    expect(c, contains('aldi != true && ref.read(premiumKilitliProvider)'));
  });

  test('5. özel gösterge ölçümü tanımlı ve kayıtta sayılır', () {
    expect(Ozellik.values.map((e) => e.name), contains('ozelGosterge'));
    expect(ekranKaynagiSync('lib/screens/ozel_gosterge_screen.dart'),
        contains('OzellikOlcumu.say(Ozellik.ozelGosterge)'));
  });
}
