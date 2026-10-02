import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Diskten yüklenen altın fiyatı "yüzde tam mı" kararını bozmaz (2026-10-02
/// müşteri testi).
///
/// Soğuk açılışta önceki oturumun birincil fiyatları diskten okunuyor; yüzde
/// taşımıyorlar. Dün izlenmiş, bugün istenmeyen bir ayar (Cumhuriyet) bayrağı
/// `false`'ta tutuyor, açılışın ilk gün içi serisi altını eski yoldan,
/// nabız serisi ürün bazlı yoldan kuruyordu: Bugün kartı önce −₺12.295,
/// 30 sn sonra +₺3.175. Bayrak yalnızca bu oturumda canlı görülen ayarlara
/// bakar.
PriceService get ps => PriceService.instance;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ps.sonBilinenFiyatlariTemizle();
  });

  void diskte(Map<String, double> fiyatlar) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'son_birincil_fiyat_v1': jsonEncode({
        for (final e in fiyatlar.entries) e.key: {'p': e.value, 'ts': ts},
      }),
    });
  }

  test('yalnız diskten bilinen ayar bayrağı düşürmez', () async {
    diskte({'ALTIN_CUMHURIYET': 43965});
    await ps.birincilHafizayiYukle();
    ps.testIcinKotasyonYaz('ALTIN_GRAM', 6042.03, gunlukPct: 0.96);
    ps.testIcinKotasyonYaz('ALTIN_GRAM24', 6533.57, gunlukPct: -0.88);

    expect(ps.sonBilinenFiyat('ALTIN_CUMHURIYET'), 43965,
        reason: 'ölçek hafızası diskteki fiyatı okumaya devam eder');
    expect(ps.altinGunlukYuzdeTam, isTrue);
  });

  test('canlı görülen ama yüzdesi olmayan ayar bayrağı yine düşürür', () async {
    SharedPreferences.setMockInitialValues({});
    await ps.birincilHafizayiYukle();
    ps.testIcinKotasyonYaz('ALTIN_GRAM', 6042.03, gunlukPct: 0.96);
    ps.testIcinKotasyonYaz('ALTIN_CUMHURIYET', 43965);

    expect(ps.altinGunlukYuzdeTam, isFalse,
        reason: '"ya hep ya hiç" kuralı canlı ayarlar için aynen geçerli');
  });

  test('diskten gelen ayar canlı kotasyon alınca sayılmaya başlar', () async {
    diskte({'ALTIN_CUMHURIYET': 43965});
    await ps.birincilHafizayiYukle();
    ps.testIcinKotasyonYaz('ALTIN_GRAM', 6042.03, gunlukPct: 0.96);
    ps.testIcinKotasyonYaz('ALTIN_CUMHURIYET', 44000);

    expect(ps.altinGunlukYuzdeTam, isFalse);
  });

  test('hiç canlı altın yoksa karar verilmez', () async {
    diskte({'ALTIN_GRAM': 6042.03});
    await ps.birincilHafizayiYukle();
    expect(ps.altinGunlukYuzdeTam, isFalse);
  });
}
