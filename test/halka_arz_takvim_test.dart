import 'dart:convert' show utf8;

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/halka_arz.dart';
import 'package:portfoy_takip/services/halka_arz_takvim.dart';

HalkaArz _arz(
        {DateTime? talepBitis,
        DateTime? islem,
        String sirket = 'Örnek A.Ş.'}) =>
    HalkaArz(
      kod: 'NETGL',
      sirket: sirket,
      kaynak: 'https://ornek.test/netgl',
      talepBitis: talepBitis,
      islemBaslangic: islem,
    );

String? _ics(HalkaArz a) => halkaArzIcs(
      arz: a,
      talepSonBaslik: '${a.kod} talep son günü',
      islemBaslik: '${a.kod} işlem başlangıcı',
      simdi: DateTime.utc(2026, 11, 8, 7, 5, 9),
    );

/// Katlanmış satırları açar (RFC 5545 §3.1).
List<String> _acik(String ics) =>
    ics.replaceAll('\r\n ', '').split('\r\n')..removeLast();

void main() {
  test('iki tarih: iki tüm gün etkinliği, DTEND ertesi gün, kararlı UID', () {
    final ics = _ics(_arz(
      talepBitis: DateTime(2026, 11, 30),
      islem: DateTime(2026, 12, 31),
    ))!;
    final s = _acik(ics);
    expect(s.first, 'BEGIN:VCALENDAR');
    expect(s.last, 'END:VCALENDAR');
    expect(s.where((x) => x == 'BEGIN:VEVENT'), hasLength(2));
    expect(s, contains('DTSTART;VALUE=DATE:20261130'));
    expect(s, contains('DTEND;VALUE=DATE:20261201'));
    // Ay ve yıl taşması.
    expect(s, contains('DTSTART;VALUE=DATE:20261231'));
    expect(s, contains('DTEND;VALUE=DATE:20270101'));
    expect(s, contains('UID:NETGL-talep-son-20261130@sandik'));
    expect(s, contains('UID:NETGL-islem-baslangic-20261231@sandik'));
    expect(s, contains('DTSTAMP:20261108T070509Z'));
    expect(s, contains('SUMMARY:NETGL talep son günü'));
    expect(s, contains('SUMMARY:NETGL işlem başlangıcı'));
    expect(s, contains('URL:https://ornek.test/netgl'));
  });

  test('tek tarih: bilinmeyen tarih için etkinlik yazılmaz', () {
    final ics = _ics(_arz(islem: DateTime(2026, 12, 3)))!;
    expect('BEGIN:VEVENT'.allMatches(ics), hasLength(1));
    expect(ics, isNot(contains('talep son')));
    expect(ics, contains('DTSTART;VALUE=DATE:20261203'));
    expect(
        halkaArzTakvimeEklenebilir(_arz(islem: DateTime(2026, 12, 3))), isTrue);
  });

  test('tarih yoksa null ve düğme koşulu false', () {
    expect(_ics(_arz()), isNull);
    expect(halkaArzTakvimeEklenebilir(_arz()), isFalse);
  });

  test('satır sonları CRLF, çıplak LF yok', () {
    final ics = _ics(_arz(talepBitis: DateTime(2026, 11, 30)))!;
    expect(ics.endsWith('\r\n'), isTrue);
    expect(RegExp(r'(?<!\r)\n').hasMatch(ics), isFalse);
  });

  test('kaçış: virgül, noktalı virgül, ters bölü ve satır sonu', () {
    expect(icsKacis(r'a,b;c\d' '\ne'), r'a\,b\;c\\d\ne');
    final ics = _ics(_arz(
      talepBitis: DateTime(2026, 11, 30),
      sirket: 'Ak; Kara, Ltd',
    ))!;
    expect(_acik(ics),
        contains(r'DESCRIPTION:Ak\; Kara\, Ltd\nhttps://ornek.test/netgl'));
  });

  test('75 okteti aşan satır katlanır, UTF-8 karakter bölünmez', () {
    final uzun = 'DESCRIPTION:${'ğüşİçö' * 20}';
    final k = icsKatla(uzun);
    final parcalar = k.split('\r\n');
    expect(parcalar.length, greaterThan(1));
    for (final p in parcalar) {
      expect(utf8.encode(p).length, lessThanOrEqualTo(75));
    }
    for (final p in parcalar.skip(1)) {
      expect(p.startsWith(' '), isTrue);
    }
    expect(k.replaceAll('\r\n ', ''), uzun);
    expect(icsKatla('KISA:satir'), 'KISA:satir');
  });
}
