import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Altın sembolü → truncgil anahtarı eşlemesi İKİ yerde yaşıyor:
///   · istemci: `PriceService._truncgilGoldKeys` (ekranda görünen fiyat)
///   · sunucu:  `_shared/live_prices.ts` `GOLD_KEYS` (fiyat alarmı)
///
/// İkisi ayrışırsa alarm, kullanıcının EKRANDA gördüğünden farklı bir
/// fiyatla tetiklenir. 2026-09-15'te tam bu oldu: sunucu `GRA` (24 ayar)
/// okurken istemci 22 ayar gösteriyordu; 6.270 hedefli alarm 6.710'da
/// erken çaldı. Yorumlar "BİREBİR aynı olmalı" diyordu ama hiçbir şey bunu
/// zorlamıyordu. (TECHNICAL_DEBT kanarya kaydı, öneri 3.)
void main() {
  test('istemci ve sunucu altın anahtarları birebir aynı', () {
    final dart = _dartHaritasi(
      File('lib/services/price_service.dart').readAsStringSync(),
    );
    final ts = _tsHaritasi(
      File('supabase/functions/_shared/live_prices.ts').readAsStringSync(),
    );
    expect(dart, isNotEmpty, reason: '_truncgilGoldKeys bulunamadı');
    expect(ts, isNotEmpty, reason: 'GOLD_KEYS bulunamadı');
    expect(
      dart,
      equals(ts),
      reason: 'Alarm, uygulamada GÖRÜNEN fiyatla tetiklenmeli. '
          'Birini değiştirdiysen diğerini de değiştir.',
    );
    // Ayar tuzağı: ALTIN_GRAM 22 ayardır (asset_categories "22 Ayar Gram Altın").
    expect(dart['ALTIN_GRAM'], 'YIA',
        reason: 'GRA = GRAMALTIN adı ama 24 ayar HAS altın; ada değil ayara bak.');
  });
}

/// `static const _truncgilGoldKeys = <String, String>{ 'A': 'B', ... };`
Map<String, String> _dartHaritasi(String kaynak) {
  final blok = RegExp(
    r"_truncgilGoldKeys\s*=\s*<String,\s*String>\{([\s\S]*?)\};",
  ).firstMatch(kaynak);
  if (blok == null) return {};
  return _ciftler(blok.group(1)!, RegExp(r"'([A-Z_]+)'\s*:\s*'([A-Z]+)'"));
}

/// `const GOLD_KEYS: Record<string, string> = { A: 'B', ... };`
Map<String, String> _tsHaritasi(String kaynak) {
  final blok = RegExp(
    r"const GOLD_KEYS[^{]*\{([\s\S]*?)\};",
  ).firstMatch(kaynak);
  if (blok == null) return {};
  return _ciftler(blok.group(1)!, RegExp(r"^\s*([A-Z_]+)\s*:\s*'([A-Z]+)'", multiLine: true));
}

Map<String, String> _ciftler(String govde, RegExp rx) {
  final temiz = govde
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
  return {for (final m in rx.allMatches(temiz)) m.group(1)!: m.group(2)!};
}
