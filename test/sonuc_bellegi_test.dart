import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/sonuc_bellegi.dart';

/// `SonucBellegi` — Performans › Özet'in titremesiz geçişinin dayanağı
/// (kullanıcı bildirimi 2026-10-02: "grafikten özete geçerken ekran flick
/// oluyor; Özet'te diğer filtrelere tıklayınca titreme oluyor").
///
/// Ekran her dönem/kapsam dokunuşunda yeni bir State kurar; o State'in
/// iskeletsiz açılabilmesi belleğin sonucu EŞZAMANLI vermesine, ısıtma ile
/// ekranın isteğinin TEK isteğe inmesine bağlı.
void main() {
  test('yazılan sonuç eşzamanlı okunur; tazelik süre dolunca düşer', () async {
    var simdi = DateTime(2026, 10, 2, 12);
    final b = SonucBellegi<int>(
      tazelik: const Duration(minutes: 1),
      azami: 4,
      saat: () => simdi,
    );
    expect(b.oku('a'), isNull);
    expect(b.taze('a'), isFalse);

    await b.yukle('a', () async => 7);
    expect(b.oku('a'), 7, reason: 'ikinci açılış beklemeden okur');
    expect(b.taze('a'), isTrue);

    simdi = simdi.add(const Duration(minutes: 2));
    expect(b.oku('a'), 7,
        reason: 'bayat girdi yine gösterilir — iskelete dönmek titremedir');
    expect(b.taze('a'), isFalse, reason: 'ama arkada tazelenmeli');
  });

  test('aynı anahtara eşzamanlı iki istek TEK çağrıya iner', () async {
    final b = SonucBellegi<int>(tazelik: const Duration(minutes: 1), azami: 4);
    var cagri = 0;
    final tamam = Completer<int>();
    Future<int> cek() {
      cagri++;
      return tamam.future;
    }

    final f1 = b.yukle('k', cek); // ısıtma
    final f2 = b.yukle('k', cek); // ekranın kendi isteği
    tamam.complete(3);
    expect(await f1, 3);
    expect(await f2, 3);
    expect(cagri, 1);

    // İstek bitince kayıt düşer: sonraki yükleme yeniden çağırır.
    await b.yukle('k', () async {
      cagri++;
      return 4;
    });
    expect(cagri, 2);
    expect(b.oku('k'), 4);
  });

  test('saklanmaya değmeyen (boş) sonuç döner ama yazılmaz', () async {
    final b = SonucBellegi<List<int>>(
      tazelik: const Duration(minutes: 1),
      azami: 4,
      saklanir: (v) => v.isNotEmpty,
    );
    expect(await b.yukle('bos', () async => const []), isEmpty);
    expect(b.oku('bos'), isNull,
        reason: 'ağ yokken gelen boş seri "veri" sayılırsa iskelet kapısı '
            'açılmaz ve boş özet çizilir');
  });

  test('hata çağırana ulaşır, bellek ve uçuşan kayıt kirlenmez', () async {
    final b = SonucBellegi<int>(tazelik: const Duration(minutes: 1), azami: 4);
    await expectLater(
        b.yukle('h', () async => throw StateError('ağ')), throwsStateError);
    expect(b.oku('h'), isNull);
    expect(await b.yukle('h', () async => 1), 1,
        reason: 'başarısız istek kalıcı olarak takılı kalmamalı');
  });

  test('azami aşılınca en eski girdi atılır; yeniden yazılan tazelenir',
      () async {
    final b = SonucBellegi<int>(tazelik: const Duration(minutes: 1), azami: 2);
    b.yaz('a', 1);
    b.yaz('b', 2);
    b.yaz('a', 11); // a artık en yeni
    b.yaz('c', 3);
    expect(b.uzunluk, 2);
    expect(b.oku('b'), isNull, reason: 'en eski b atılmalı');
    expect(b.oku('a'), 11);
    expect(b.oku('c'), 3);
  });

  test('temizle her şeyi bırakır', () {
    final b = SonucBellegi<int>(tazelik: const Duration(minutes: 1), azami: 4)
      ..yaz('a', 1);
    b.temizle();
    expect(b.oku('a'), isNull);
  });
}
