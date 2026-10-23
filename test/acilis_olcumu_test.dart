import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/acilis_olcumu.dart';
import 'package:portfoy_takip/services/gorunen_hata.dart';

import 'helpers/kaynak.dart';

/// Soğuk açılış ölçümü (`AcilisOlcumu`) ve görünen hata izi
/// (`GorunenHata`) — Ar-Ge 23 Eki 08:45 #1 ve #2.
void main() {
  final o = AcilisOlcumu.instance;
  late List<Map<String, Object>> giden;

  setUp(() {
    o.sifirlaTest();
    giden = [];
    o.gonderTest = giden.add;
  });

  group('AcilisOlcumu', () {
    test('defter + fiyat gelince açılış başına bir kez gönderir', () {
      o.basla();
      o.ilkKare();
      o.defterHazir(onbellekten: false);
      o.fiyatHazir(basarili: true);
      o.fiyatHazir(basarili: true); // nabız turu: yeni olay yok
      expect(giden, hasLength(1));
      final p = giden.single;
      expect(p['defter_kaynagi'], 'sunucu');
      expect(p['fiyat'], 'tamam');
      expect(p.keys,
          containsAll(['ilk_kare_ms', 'defter_ms', 'fiyat_ms', 'platform']));
    });

    test('defter yoksa (oturum yok, boş portföy) hiçbir şey gitmez', () {
      o.basla();
      o.fiyatHazir(basarili: true);
      expect(giden, isEmpty);
    });

    test('saat başlamadıysa (testte, sıcak dönüşte) ölçülmez', () {
      o.defterHazir(onbellekten: false);
      o.fiyatHazir(basarili: true);
      expect(giden, isEmpty);
    });

    test('önbellekten açılış ve hatalı fiyat turu ayrı etiketlenir', () {
      o.basla();
      o.defterHazir(onbellekten: true);
      o.defterHazir(onbellekten: false); // ilk kaynak kalır
      o.fiyatHazir(basarili: false);
      expect(giden.single['defter_kaynagi'], 'onbellek');
      expect(giden.single['fiyat'], 'hata');
    });

    test('parametreler 10 ms\'ye yuvarlanır, kişisel veri taşımaz', () {
      final p = AcilisOlcumu.parametreler(
        ilkKareMs: 434,
        defterMs: 1206,
        fiyatMs: 2895,
        defterKaynagi: 'sunucu',
        fiyatBasarili: true,
        platform: 'ios',
      );
      expect(p, {
        'ilk_kare_ms': 430,
        'defter_ms': 1210,
        'fiyat_ms': 2900,
        'defter_kaynagi': 'sunucu',
        'fiyat': 'tamam',
        'platform': 'ios',
      });
    });

    test('saat main() başında başlar, ilk kare runApp sonrası', () {
      final main = ekranKaynagiSync('lib/main.dart');
      final basla = main.indexOf('AcilisOlcumu.instance.basla()');
      final zone = main.indexOf('await runZonedGuarded');
      expect(basla, greaterThan(0));
      expect(basla, lessThan(zone));
      expect(main, contains('AcilisOlcumu.instance.ilkKare()'));
    });

    test('defter ve fiyat anları portföy sağlayıcısında işaretlenir', () {
      final p = ekranKaynagiSync('lib/providers/portfolio_provider.dart');
      expect(p, contains('defterHazir(onbellekten: true)'));
      expect(p, contains('defterHazir(onbellekten: false)'));
      expect(p, contains('fiyatHazir(basarili: true)'));
      expect(p, contains('fiyatHazir(basarili: false)'));
    });
  });

  group('GorunenHata', () {
    tearDown(GorunenHata.sifirlaTest);

    test('kaydet son zamanı yazar', () {
      GorunenHata.now = () => DateTime(2026, 10, 23, 10);
      expect(GorunenHata.sonMs, isNull);
      GorunenHata.kaydet();
      expect(
          GorunenHata.sonMs, DateTime(2026, 10, 23, 10).millisecondsSinceEpoch);
    });

    test('yalnız kullanıcının gördüğü hatalar yazar', () {
      expect(ekranKaynagiSync('lib/utils/friendly_error.dart'),
          contains('GorunenHata.kaydet()'));
      expect(ekranKaynagiSync('lib/widgets/sandik_error_view.dart'),
          contains('GorunenHata.kaydet()'));
      expect(ekranKaynagiSync('lib/providers/portfolio_provider.dart'),
          contains('GorunenHata.kaydet()'));
      // Sessiz arka plan hataları yazmaz: istem neredeyse hiç sorulmazdı.
      expect(ekranKaynagiSync('lib/services/crash_reporter.dart'),
          isNot(contains('GorunenHata')));
    });

    test('değerlendirme istemi görünen hatayı okur', () {
      expect(ekranKaynagiSync('lib/services/review_prompt_service.dart'),
          contains('sonHataMs: GorunenHata.sonMs'));
    });
  });
}
