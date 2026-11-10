import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/deep_link_service.dart';

/// App Store In-App Event taslakları (`etkinlikler.json`).
///
/// ASC sınırları kurulumda (tool/asc_in_app_events.py) 409 ile döner ve o
/// an düzeltmek etkinlik gününe sıkışır; burada önceden yakalanır. Derin
/// bağlantının uygulamada karşılığı yoksa etkinliğe dokunan kullanıcı
/// boş bir açılışa düşer: her bağlantı köprüde bir hedef bulmalı.
void main() {
  final tanim = jsonDecode(
    File('store_listing/ios/in_app_events/etkinlikler.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final etkinlikler =
      (tanim['etkinlikler'] as List).cast<Map<String, dynamic>>();

  test('referanslar tekil', () {
    final r = etkinlikler.map((e) => e['referans']).toList();
    expect(r.toSet().length, r.length);
  });

  test('metin sınırları: ad 30, kısa 50, uzun 120', () {
    for (final e in etkinlikler) {
      final metin = (e['metin'] as Map).cast<String, dynamic>();
      for (final MapEntry(key: dil, value: m) in metin.entries) {
        final ref = '${e['referans']} $dil';
        expect((m['ad'] as String).length, lessThanOrEqualTo(30), reason: ref);
        expect((m['kisa'] as String).length, lessThanOrEqualTo(50),
            reason: ref);
        expect((m['uzun'] as String).length, lessThanOrEqualTo(120),
            reason: ref);
      }
    }
  });

  test('takvim: yayın ≤ 14 gün önce, başlangıç bitişten önce', () {
    for (final e in etkinlikler) {
      final yayin = DateTime.parse(e['yayin_baslangic'] as String);
      final bas = DateTime.parse(e['etkinlik_baslangic'] as String);
      final bit = DateTime.parse(e['etkinlik_bitis'] as String);
      expect(bas.difference(yayin).inDays, inInclusiveRange(0, 14),
          reason: '${e['referans']}');
      expect(bas.isBefore(bit), isTrue, reason: '${e['referans']}');
    }
  });

  test('her derin bağlantı uygulamada bir hedef bulur', () {
    final s = DeepLinkService.withHandler((_) {});
    for (final e in etkinlikler) {
      expect(s.handle(Uri.parse(e['derin_baglanti'] as String)), isTrue,
          reason: '${e['referans']}: ${e['derin_baglanti']}');
    }
  });
}
