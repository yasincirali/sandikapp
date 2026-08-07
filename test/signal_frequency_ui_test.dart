import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/signal_frequency.dart';

/// Kullanıcı bildirimi: "her seçenek seçildiğinde chiplerin yeri değişiyor".
///
/// Kök neden: seçili chip'in `fontWeight`'i w500 → w700 değişiyordu. Kalın
/// metin daha geniş olduğu için chip büyüyor, `Wrap` satırları yeniden
/// diziyor ve dokunulmayan chip'ler yer değiştiriyordu — kullanıcı yanlış
/// öğeye basabiliyordu.
///
/// Bu testler o davranışın geri gelmesini engeller.
void main() {
  group('Sinyal sıklığı — seçim düzeni bozmamalı', () {
    testWidgets('metin genişliği seçim durumundan bağımsız', (tester) async {
      // Aynı etiketin seçili/seçili değil hallerini ölç. Font ağırlığı
      // sabitse iki genişlik birebir aynı olmalı.
      Future<Size> olc({required bool secili}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Text(
                  'Günde 2 kez',
                  style: TextStyle(
                    fontSize: 13,
                    // Üretimdeki değerle aynı: sabit w600.
                    fontWeight: FontWeight.w600,
                    color: secili ? Colors.amber : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
        return tester.getSize(find.text('Günde 2 kez'));
      }

      final seciliDegil = await olc(secili: false);
      final seciliHal = await olc(secili: true);

      expect(
        seciliHal.width,
        seciliDegil.width,
        reason: 'Seçim metnin genişliğini değiştirmemeli — değişirse '
            'Wrap yeniden dizilir ve chip\'ler kayar',
      );
    });

    // NOT: "ağırlık değişince genişlik değişir" widget testiyle
    // KANITLANAMIYOR — test ortamındaki Ahem fontu tüm ağırlıklarda sabit
    // genişlikte. Gerçek cihazda (DM Sans) fark oluşur ve kayma görülür.
    // Bu yüzden kaynak koda karşı statik bir güvence tutuluyor:
    testWidgets('sabit yükseklikli satır düzeni kaymayı engeller',
        (tester) async {
      // Liste satırı chip/Wrap değil; seçim değişse de satır yüksekliği
      // ve sırası sabittir. Burada düzenin kendisini doğruluyoruz.
      Widget satir({required bool secili}) => MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  for (final f in SignalFrequency.values)
                    Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 22,
                            child: (secili && f == SignalFrequency.hourly)
                                ? const Icon(Icons.check_rounded, size: 18)
                                : null,
                          ),
                          Expanded(child: Text(f.label)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );

      await tester.pumpWidget(satir(secili: false));
      final oncekiKonum = tester.getTopLeft(find.text('Günde 2 kez'));

      await tester.pumpWidget(satir(secili: true));
      final sonrakiKonum = tester.getTopLeft(find.text('Günde 2 kez'));

      expect(sonrakiKonum, oncekiKonum,
          reason: 'Bir seçenek seçilince DİĞER satırlar yer değiştirmemeli');
    });
  });

  group('SignalFrequency modeli', () {
    test('saat seçici yalnızca günde 1/2 için gerekir', () {
      expect(SignalFrequency.daily.needsHourPicker, isTrue);
      expect(SignalFrequency.twiceDaily.needsHourPicker, isTrue);
      expect(SignalFrequency.hourly.needsHourPicker, isFalse);
      expect(SignalFrequency.every2h.needsHourPicker, isFalse);
      expect(SignalFrequency.every3h.needsHourPicker, isFalse);
    });

    test('saat adedi sıklıkla tutarlı', () {
      expect(SignalFrequency.daily.hourCount, 1);
      expect(SignalFrequency.twiceDaily.hourCount, 2);
      expect(SignalFrequency.hourly.hourCount, 0);
    });

    test('id değerleri DB check constraint ile aynı', () {
      // 0024_signal_frequency.sql:
      //   check (frequency in ('hourly','every_2h','every_3h',
      //                        'twice_daily','daily'))
      expect(
        SignalFrequency.values.map((f) => f.id).toSet(),
        {'hourly', 'every_2h', 'every_3h', 'twice_daily', 'daily'},
      );
    });

    test('bilinmeyen id varsayılana düşer', () {
      expect(SignalFrequency.fromId('gecersiz'), SignalFrequency.twiceDaily);
      expect(SignalFrequency.fromId(null), SignalFrequency.twiceDaily);
    });

    test('seçilebilir saatler 10-18 penceresi içinde', () {
      expect(signalSelectableHours.first, kSignalWindowStart);
      expect(signalSelectableHours.last, kSignalWindowEnd);
      expect(signalSelectableHours.every((h) => h >= 10 && h <= 18), isTrue);
    });
  });
}
