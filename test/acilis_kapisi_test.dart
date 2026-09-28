import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/acilis_kapisi.dart';

/// Açılış kapısı: hepsi bitince açılır, hata kapıyı kilitlemez, yavaş bir
/// iş ekranı süre sınırından fazla tutmaz (bkz. `acilis_kapisi.dart`).
void main() {
  test('hepsi bitince açılır', () async {
    var acik = false;
    final a = Completer<int>();
    final b = Completer<String>();
    final kapi = acilisKapisi([a.future, b.future]).then((_) => acik = true);
    a.complete(1);
    await Future<void>.delayed(Duration.zero);
    expect(acik, isFalse, reason: 'biri hâlâ sürüyor');
    b.complete('x');
    await kapi;
    expect(acik, isTrue);
  });

  test('hata kapıyı açar, fırlatmaz', () async {
    await expectLater(
        acilisKapisi([Future<int>.error(StateError('ağ'))]), completes);
  });

  test('süre sınırı dolunca açılır', () {
    fakeAsync((fa) {
      var acik = false;
      acilisKapisi([Completer<void>().future]).then((_) => acik = true);
      fa.elapse(acilisSiniri - const Duration(seconds: 1));
      expect(acik, isFalse);
      fa.elapse(const Duration(seconds: 1));
      expect(acik, isTrue);
    });
  });
}
