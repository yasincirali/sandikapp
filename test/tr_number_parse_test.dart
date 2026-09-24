import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/tr_format.dart';

/// Türkçe sayı girdisinin çözümlenmesi.
///
/// Denetimde (2026-08-11) dört dosyada şu desen bulundu:
/// `double.tryParse(text.replaceAll(',', '.'))`
///
/// Türkçede `.` BİNLİK ayracıdır. Bu desen "1.000" girdisini **1.0** olarak
/// okuyordu ve kullanıcıya hiçbir uyarı vermiyordu — finansal bir uygulamada
/// sessiz veri bozulması. "1.000 lot" yazan kullanıcı portföyüne 1 lot
/// kaydediyordu.
void main() {
  group('binlik ayracı — asıl hata', () {
    test('1.000 → 1000 (eskiden 1.0 idi)', () {
      expect(parseTrNumber('1.000'), 1000);
    });
    test('10.000 → 10000', () {
      expect(parseTrNumber('10.000'), 10000);
    });
    test('1.000.000 → 1000000', () {
      expect(parseTrNumber('1.000.000'), 1000000);
    });
  });

  group('ondalık ayracı', () {
    test('1,5 → 1.5', () => expect(parseTrNumber('1,5'), 1.5));
    test('0,001 → 0.001', () => expect(parseTrNumber('0,001'), 0.001));
    test('100 → 100', () => expect(parseTrNumber('100'), 100));
  });

  group('ikisi birlikte — sonuncusu ondalıktır', () {
    test('1.234,5 → 1234.5 (eskiden null idi)', () {
      expect(parseTrNumber('1.234,5'), 1234.5);
    });
    test('1.000.000,25 → 1000000.25', () {
      expect(parseTrNumber('1.000.000,25'), 1000000.25);
    });
    // İngilizce biçimde yazan kullanıcı da doğru sonuç almalı.
    test('1,234.5 → 1234.5 (İngilizce biçim)', () {
      expect(parseTrNumber('1,234.5'), 1234.5);
    });
  });

  group('yalnızca nokta — belirsizlik', () {
    // Klavyeden ondalık için `.` yazan kullanıcı korunmalı.
    test('1.5 → 1.5 (ondalık; 3 hane değil)', () {
      expect(parseTrNumber('1.5'), 1.5);
    });
    test('16.56 → 16.56 (ondalık)', () {
      expect(parseTrNumber('16.56'), 16.56);
    });
    // Tam 3 hane → binlik.
    test('3.770 → 3770 (binlik)', () {
      expect(parseTrNumber('3.770'), 3770);
    });
    test('0.123 → 0.123 (0 ile başlayan grup binlik olamaz)', () {
      // 2026-09-23'e kadar bilinçli ödünleşimdi: "3 hane → binlik" kuralı
      // tutarlılık için 0.123'ü 123 okuyordu. Denetim (F1/F15) bunun gerçek
      // bir veri bozulması olduğunu gösterdi: "0.125 gram" hızlı girişte
      // 125 gram kaydediliyordu. Hiçbir yazımda "0" bir binlik grubu
      // değildir, ödünleşim kaldırıldı.
      expect(parseTrNumber('0.123'), 0.123);
      expect(parseTrNumber('-0.5'), -0.5);
    });
    test('1234.567 → ondalık (ilk grup 3 haneden uzun)', () {
      expect(parseTrNumber('1234.567'), 1234.567);
    });
    test('-1.000 → -1000 (işaretli binlik)', () {
      expect(parseTrNumber('-1.000'), -1000);
    });
  });

  group('fmtInputTr — alan doldurma gidiş-dönüşü (denetim F1)', () {
    // Önceden doldurulan fiyat `toString()` ile yazılıyordu: `41.235`
    // `parseTrNumber`da binlik sayılıp 41235 kaydediliyordu.
    for (final v in [41.235, 0.123, 2.125, 100.001, 1125.0, 1000.0,
        0.00012345, 3.456, 1234567.891, 12.5]) {
      test('$v alan metninden aynen geri okunur', () {
        final metin = fmtInputTr(v);
        expect(metin.contains('.'), isFalse,
            reason: 'alan metni binlik noktası taşımaz: $metin');
        expect(parseTrNumber(metin), closeTo(v, 1e-9));
      });
    }
    test('biçim', () {
      expect(fmtInputTr(41.235), '41,235');
      expect(fmtInputTr(1000), '1000');
      expect(fmtInputTr(0.5), '0,5');
    });
  });

  group('gürültü ve geçersiz girdi', () {
    test('boşluk ve para birimi temizlenir', () {
      expect(parseTrNumber(' 1.500,75 ₺'), 1500.75);
      expect(parseTrNumber(' 250'), 250);
    });
    test('boş → null', () {
      expect(parseTrNumber(''), isNull);
      expect(parseTrNumber('   '), isNull);
    });
    test('sayı olmayan → null', () {
      expect(parseTrNumber('abc'), isNull);
      expect(parseTrNumber('₺'), isNull);
    });
    test('sonsuz/NaN reddedilir', () {
      expect(parseTrNumber('Infinity'), isNull);
      expect(parseTrNumber('NaN'), isNull);
    });
  });

  group('eski desenin gerçekten kırık olduğu', () {
    // Kanarya: düzeltmenin bir şeyi değiştirdiğini kanıtlar.
    double? eski(String t) => double.tryParse(t.trim().replaceAll(',', '.'));

    test('eski desen 1.000\'i 1.0 okur', () {
      expect(eski('1.000'), 1.0);
      expect(parseTrNumber('1.000'), 1000);
    });
    test('eski desen 1.234,5\'i çözemez', () {
      expect(eski('1.234,5'), isNull);
      expect(parseTrNumber('1.234,5'), 1234.5);
    });
  });

  group('kaynak taraması — eski desen geri gelmesin', () {
    test('form girdilerinde ham replaceAll kullanılmamalı', () {
      // Serbest metin ayrıştırıcıları (hızlı giriş) HARİÇ: onlar binlik
      // ayracını lookahead ile ÖNCEDEN temizliyor, desen orada doğru.
      final offenders = <String>[];
      final pattern = RegExp(r"""replaceAll\(',', '\.'\)""");

      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final src = e.readAsStringSync();
        for (final m in pattern.allMatches(src)) {
          final lineStart = src.lastIndexOf('\n', m.start) + 1;
          final prefix = src.substring(lineStart, m.start);
          if (prefix.trimLeft().startsWith('//')) continue; // yorum
          // ZATEN DOĞRU olan desen: önce binlik noktası siliniyor
          // (`replaceAll('.', '').replaceAll(',', '.')`). Bunlar Türkçeyi
          // doğru çözer; kural yalnızca noktayı KORUYAN kullanımlar için.
          if (prefix.contains("replaceAll('.', '')")) continue;
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${e.path}:$line');
        }
      }

      expect(offenders, isEmpty,
          reason: 'Form girdisi `parseTrNumber` ile çözülmeli; ham desen '
              'Türkçede binlik ayracını ondalık sanır.\n'
              '${offenders.join('\n')}');
    });
  });
}
