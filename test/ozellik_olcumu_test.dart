import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/config/pref_keys.dart';
import 'package:portfoy_takip/services/deep_link_router.dart';
import 'package:portfoy_takip/services/ozellik_olcumu.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Ar-Ge 25 Eki §3: dün gelen özelliklerin kullanımı, günde bir olay.
void main() {
  group('olay sözleşmesi', () {
    test('özellik kodları sabit (Firebase panosu bunlara bağlı)', () {
      expect(Ozellik.values.map((o) => o.kod), [
        'hizli_hesap',
        'takip_sirasi',
        'tutar_kipi',
        'bize_yaz',
        'yatay_grafik',
        'cizim',
        'varlik_widget',
        'grafik_paylas',
        'takip_onerisi',
        'takip_alarm_cani',
      ]);
    });

    test('olay adı ve kodlar Firebase sınırında (≤40, küçük harf + _)', () {
      final bicim = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
      expect(bicim.hasMatch('ozellik_kullanildi'), isTrue);
      for (final o in Ozellik.values) {
        expect(bicim.hasMatch(o.kod), isTrue, reason: o.kod);
      }
      final k = ekranKaynagiSync('lib/services/analytics_service.dart');
      expect(k, contains("_log('ozellik_kullanildi', {'ozellik': ozellik.kod})"));
    });
  });

  group('günde bir kez (TR günü)', () {
    late List<Ozellik> giden;
    late DateTime an;
    late OzellikOlcumu olcum;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      giden = [];
      an = DateTime.utc(2026, 10, 25, 9);
      olcum = OzellikOlcumu(gonder: (o) async => giden.add(o), saat: () => an);
    });

    test('aynı gün ikinci kullanım gitmez, özellikler ayrı sayılır', () async {
      expect(await olcum.kullanildi(Ozellik.cizim), isTrue);
      expect(await olcum.kullanildi(Ozellik.cizim), isFalse);
      expect(await olcum.kullanildi(Ozellik.bizeYaz), isTrue);
      expect(giden, [Ozellik.cizim, Ozellik.bizeYaz]);
    });

    test('eşzamanlı iki dokunuş tek olay', () async {
      await Future.wait([
        olcum.kullanildi(Ozellik.takipSirasi),
        olcum.kullanildi(Ozellik.takipSirasi),
      ]);
      expect(giden, [Ozellik.takipSirasi]);
    });

    test('ertesi gün yeniden gider', () async {
      await olcum.kullanildi(Ozellik.cizim);
      an = an.add(const Duration(days: 1));
      expect(await olcum.kullanildi(Ozellik.cizim), isTrue);
      expect(giden.length, 2);
    });

    test('işaret diskte: yeni süreçte aynı gün gitmez', () async {
      await olcum.kullanildi(Ozellik.hizliHesap);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('${PrefKeys.ozellikOlcumuPrefix}hizli_hesap'),
          '2026-10-25');
      final yeni =
          OzellikOlcumu(gonder: (o) async => giden.add(o), saat: () => an);
      expect(await yeni.kullanildi(Ozellik.hizliHesap), isFalse);
      expect(giden.length, 1);
    });

    test('gün sınırı TR saatine göre (UTC 21:00 = TR gece yarısı)', () {
      expect(OzellikOlcumu.gunAnahtari(DateTime.utc(2026, 10, 25, 20, 59)),
          '2026-10-25');
      expect(OzellikOlcumu.gunAnahtari(DateTime.utc(2026, 10, 25, 21)),
          '2026-10-26');
    });
  });

  group('kişisel veri yok', () {
    List<File> libDosyalari() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('çağrılar yalnız sabit enum değeri geçirir', () {
      final cagri = RegExp(r'OzellikOlcumu\.say\(([^)]*)\)');
      final kullanilan = <String>{};
      for (final f in libDosyalari()) {
        for (final m in cagri.allMatches(f.readAsStringSync())) {
          final arg = m.group(1)!.trim();
          expect(RegExp(r'^Ozellik\.\w+$').hasMatch(arg), isTrue,
              reason: '${f.path}: $arg');
          kullanilan.add(arg);
        }
      }
      // Her özellik (dokuz) gerçekten bir çağrı noktasında sayılıyor.
      for (final o in Ozellik.values) {
        expect(kullanilan, contains('Ozellik.${o.name}'), reason: o.name);
      }
    });

    test('olay metodu yalnız enum alır, yalnız ölçüm sınıfından çağrılır', () {
      final k = ekranKaynagiSync('lib/services/analytics_service.dart');
      expect(k, contains('logOzellikKullanildi(Ozellik ozellik)'));
      for (final f in libDosyalari()) {
        final p = f.path.replaceAll(r'\', '/');
        if (p.endsWith('services/analytics_service.dart') ||
            p.endsWith('services/ozellik_olcumu.dart')) {
          continue;
        }
        expect(f.readAsStringSync(), isNot(contains('logOzellikKullanildi')),
            reason: p);
      }
    });

    test('olay parametresinde kod dışında alan yok', () {
      final k = ekranKaynagiSync('lib/services/analytics_service.dart');
      final i = k.indexOf("_log('ozellik_kullanildi'");
      final govde = k.substring(i, k.indexOf(';', i));
      expect(RegExp(r"'\w+':").allMatches(govde).length, 1);
    });
  });

  group('widget_tapped yüzeyi', () {
    test('tek varlık widget\'ı ayrı yüzey, diğerleri home_widget', () {
      expect(
          DeepLinkRouter.widgetYuzeyi(
              Uri.parse('sandik://varlik-widget?homeWidget=1')),
          'varlik_widget');
      expect(
          DeepLinkRouter.widgetYuzeyi(
              Uri.parse('sandik://widget/home?homeWidget=1')),
          'home_widget');
      expect(DeepLinkRouter.widgetYuzeyi(Uri.parse('https://varlik-widget')),
          'home_widget');
    });

    test('iki dokunuş yolu (soğuk ve sıcak) yüzeyi URI\'den alır', () {
      final k = ekranKaynagiSync('lib/services/home_widget_service.dart');
      expect(k, isNot(contains("recordWidgetTap(surface: 'home_widget')")));
      expect(RegExp(r'_dokunusuSay\(uri\)').allMatches(k).length, 2);
      expect(k, contains('DeepLinkRouter.widgetYuzeyi(uri)'));
    });
  });
}
