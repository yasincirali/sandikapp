import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/kilit_kapisi.dart';

/// Denetim F2 (2026-09-23): kilitliyken gelen bildirim dokunuşu hedef
/// ekranı kilidin üstüne açıyordu. Kapı, isteği kilit açılana kadar tutar.
void main() {
  test('kilitli değilken ertelemez, çağıran hemen devam eder', () {
    final k = KilitKapisi();
    var calisti = 0;
    expect(k.ertele(() => calisti++), isFalse);
    expect(calisti, 0, reason: 'çalıştırma çağıranın işi');
  });

  test('kilitliyken bekletir, açılınca bir kez çalıştırır', () {
    final k = KilitKapisi()..kilitli.value = true;
    var calisti = 0;
    expect(k.ertele(() => calisti++), isTrue);
    expect(calisti, 0, reason: 'kilit altında ekran açılmaz');
    k.kilitli.value = false;
    expect(calisti, 1);
    k.kilitli.value = true;
    k.kilitli.value = false;
    expect(calisti, 1, reason: 'tek seferlik');
  });

  test('art arda dokunuşlarda yalnızca sonuncusu açılır', () {
    final k = KilitKapisi()..kilitli.value = true;
    final acilan = <String>[];
    k.ertele(() => acilan.add('ilk'));
    k.ertele(() => acilan.add('son'));
    k.kilitli.value = false;
    expect(acilan, ['son']);
  });
}
