// BIST hisse kataloğu — sunucu → cihaz önbelleği → gömülü liste (0139).
//
// Kovaladığı şeyler:
// 1. Sunucuya ulaşılamazsa liste gömülü listedir; eski davranış birebir.
// 2. Sunucu yeni halka arzı getirince seçici/aramada görünür.
// 3. Yarım/bozuk sunucu yanıtı listeyi küçültmez.
// 4. Soğuk açılışta önbellek anında uygulanır; taze önbellekte sunucuya
//    gidilmez, bayatta gidilir.
// 5. Kodu değişmiş eski hisse içe aktarmada hâlâ tanınır.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/bist_hisseleri.dart';
import 'package:portfoy_takip/services/bist_hisse_katalogu.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, String> sunucuListesi({Map<String, String> ek = const {}}) => {
      ...bist100StocksMap,
      ...ek,
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sunucu yoksa gömülü liste', () async {
    final k = BistHisseKatalogu(sunucu: () async => throw Exception('ağ yok'));
    await k.yukle();
    expect(k.hisseler, same(bist100StocksMap));
    expect(k.surum, 0);
  });

  test('sunucudaki yeni halka arz listeye girer ve önbelleğe yazılır',
      () async {
    final k = BistHisseKatalogu(
      sunucu: () async => sunucuListesi(ek: {'YENIH.IS': 'Yeni Halka Arz'}),
    );
    var bildirim = 0;
    k.addListener(() => bildirim++);
    await k.yukle();
    expect(k.hisseler['YENIH.IS'], 'Yeni Halka Arz');
    expect(k.surum, 1);
    expect(bildirim, 1);

    final prefs = await SharedPreferences.getInstance();
    final ham = jsonDecode(prefs.getString(BistHisseKatalogu.onbellekAnahtari)!)
        as Map<String, dynamic>;
    expect((ham['h'] as Map)['YENIH.IS'], 'Yeni Halka Arz');
  });

  test('yarım sunucu yanıtı listeyi küçültmez', () async {
    final k = BistHisseKatalogu(
      sunucu: () async => {'THYAO.IS': 'Türk Hava Yolları'},
    );
    await k.yukle();
    expect(k.hisseler, same(bist100StocksMap));
  });

  test('kodu değişen hisse seçiciden düşer ama içe aktarmada tanınır',
      () async {
    final liste = sunucuListesi()..remove('KUTPO.IS');
    final k = BistHisseKatalogu(sunucu: () async => liste);
    await k.yukle();
    expect(k.hisseler.containsKey('KUTPO.IS'), isFalse);
    // Gömülü eski kodlar (KOZAL→TRALT) her zaman tanınır.
    expect(k.kodMu('KOZAL'), isTrue);
    expect(k.kodMu('thyao'), isTrue);
    expect(k.kodMu('ALTIN'), isFalse);
  });

  test('soğuk açılış: taze önbellek anında uygulanır, sunucuya gidilmez',
      () async {
    final simdi = DateTime(2026, 10, 10, 9);
    SharedPreferences.setMockInitialValues({
      BistHisseKatalogu.onbellekAnahtari: jsonEncode({
        't': simdi.subtract(const Duration(hours: 2)).toIso8601String(),
        'h': sunucuListesi(ek: {'ONBLK.IS': 'Önbellekten'}),
      }),
    });
    var cagri = 0;
    final k = BistHisseKatalogu(
      saat: () => simdi,
      sunucu: () async {
        cagri++;
        return sunucuListesi();
      },
    );
    await k.yukle();
    expect(k.hisseler['ONBLK.IS'], 'Önbellekten');
    expect(cagri, 0);
  });

  test('bayat önbellekte sunucuya sorulur', () async {
    final simdi = DateTime(2026, 10, 10, 9);
    SharedPreferences.setMockInitialValues({
      BistHisseKatalogu.onbellekAnahtari: jsonEncode({
        't': simdi.subtract(const Duration(days: 1)).toIso8601String(),
        'h': sunucuListesi(),
      }),
    });
    final k = BistHisseKatalogu(
      saat: () => simdi,
      sunucu: () async => sunucuListesi(ek: {'TAZE1.IS': 'Taze'}),
    );
    await k.yukle();
    expect(k.hisseler['TAZE1.IS'], 'Taze');
  });

  test('bozuk önbellek gömülü listede bırakır', () async {
    SharedPreferences.setMockInitialValues({
      BistHisseKatalogu.onbellekAnahtari: '{bozuk',
    });
    final k = BistHisseKatalogu(sunucu: () async => throw Exception('yok'));
    await k.yukle();
    expect(k.hisseler, same(bist100StocksMap));
  });

  test('eşzamanlı yüklemeler tek sunucu çağrısı yapar', () async {
    var cagri = 0;
    final k = BistHisseKatalogu(sunucu: () async {
      cagri++;
      return sunucuListesi();
    });
    await Future.wait([k.yukle(), k.yukle(), k.yukle()]);
    expect(cagri, 1);
  });

  test('arama yeni halka arzı katalog güncellenince bulur', () {
    final k = BistHisseKatalogu.instance;
    addTearDown(k.sifirlaTest);
    expect(SymbolSearchService.instance.yerelAra('yenih'), isEmpty);
    k.uygulaTest(sunucuListesi(ek: {'YENIH.IS': 'Yeni Halka Arz'}));
    final hits = SymbolSearchService.instance.yerelAra('yenih');
    expect(hits.map((h) => h.ticker), contains('YENIH.IS'));
  });
}
