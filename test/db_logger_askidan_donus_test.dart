import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/db_logger.dart';

/// Askıdan dönüş koruması (2026-09-28 iOS prod kanıtı): istek yoldayken
/// süreç donarsa zaman aşımı öne dönüşte patlar; ağ sağlamdır. Okuma bir
/// kez yeniden denenir, yazma asla.
void main() {
  const sinir = Duration(milliseconds: 20);

  setUp(() => DbLogger.silentInTests = true);
  tearDown(() => DbLogger.saat = DateTime.now);

  /// İlk `saat()` çağrısı istek anı; sonrakiler 7 dk ileride — süreç
  /// arada dondurulmuş gibi.
  void askiyiTaklitEt() {
    final t0 = DateTime(2026, 9, 28, 13, 32, 30);
    var ilk = true;
    DbLogger.saat = () {
      if (ilk) {
        ilk = false;
        return t0;
      }
      return t0.add(const Duration(minutes: 7));
    };
  }

  group('askidanDonusMu', () {
    const t = Duration(seconds: 15);
    test('prod örnekleri askı sayılır', () {
      expect(DbLogger.askidanDonusMu(const Duration(milliseconds: 93133), t), isTrue);
      expect(DbLogger.askidanDonusMu(const Duration(milliseconds: 460491), t), isTrue);
    });
    test('sınırda düşen gerçek bekleme askı sayılmaz', () {
      expect(DbLogger.askidanDonusMu(const Duration(milliseconds: 15020), t), isFalse);
      expect(DbLogger.askidanDonusMu(const Duration(seconds: 20), t), isFalse);
    });
  });

  test('askıdan dönen SELECT bir kez yeniden denenir ve sonuç döner', () async {
    askiyiTaklitEt();
    var cagri = 0;
    final sonuc = await DbLogger.instance.log<int>(
      source: 'test',
      table: 't',
      op: 'SELECT',
      request: const <String, dynamic>{},
      timeout: sinir,
      call: () {
        cagri++;
        return cagri == 1 ? Completer<int>().future : Future.value(42);
      },
    );
    expect(sonuc, 42);
    expect(cagri, 2);
  });

  test('askıdan dönen yazma yeniden denenmez', () async {
    askiyiTaklitEt();
    var cagri = 0;
    await expectLater(
      DbLogger.instance.log<void>(
        source: 'test',
        table: 't',
        op: 'UPDATE',
        request: const <String, dynamic>{},
        timeout: sinir,
        call: () {
          cagri++;
          return Completer<void>().future;
        },
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(cagri, 1);
  });

  test('gerçek zaman aşımı (askı yok) yeniden denenmez', () async {
    var cagri = 0;
    await expectLater(
      DbLogger.instance.log<int>(
        source: 'test',
        table: 't',
        op: 'SELECT',
        request: const <String, dynamic>{},
        timeout: sinir,
        call: () {
          cagri++;
          return Completer<int>().future;
        },
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(cagri, 1);
  });

  test('ikinci deneme de düşerse hata yukarı çıkar', () async {
    askiyiTaklitEt();
    var cagri = 0;
    await expectLater(
      DbLogger.instance.log<int>(
        source: 'test',
        table: 't',
        op: 'SELECT',
        request: const <String, dynamic>{},
        timeout: sinir,
        call: () {
          cagri++;
          return Completer<int>().future;
        },
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(cagri, 2);
  });
}
