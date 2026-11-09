import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';

import 'helpers/kaynak.dart';

/// Admin okuması tek hatada "admin değil" demez (yasin 2026-11-10: "admin
/// hesabımın premium üyeliği gitmiş"). Admin'in Premium'u `is_push_admin()`
/// cevabıdır; eskiden yutulan tek bir zaman aşımı oturum boyunca kilit
/// demekti. Kilitlenen davranış:
///  1. Geçici hata yeniden denenir ve sonraki `true` kazanır.
///  2. `false` cevabı hata değildir: yeniden denenmez.
///  3. Bütün denemeler düşerse `false` (hata fırlatılmaz: Riverpod hatada
///     önceki hesabın değerini taşırdı).
///  4. Servis hatayı yutmaz; yutarsa yeniden deneme hiç çalışmaz.
void main() {
  const hizli = [Duration.zero, Duration.zero];

  test('geçici hata yeniden denenir, sonraki true kazanır', () async {
    var cagri = 0;
    final sonuc = await adminMiOku(() async {
      if (++cagri == 1) throw TimeoutException('ağ');
      return true;
    }, araliklar: hizli);
    expect(sonuc, isTrue);
    expect(cagri, 2);
  });

  test('false cevabı yeniden denenmez', () async {
    var cagri = 0;
    final sonuc = await adminMiOku(() async {
      cagri++;
      return false;
    }, araliklar: hizli);
    expect(sonuc, isFalse);
    expect(cagri, 1);
  });

  test('bütün denemeler düşerse false, hata fırlatılmaz', () async {
    var cagri = 0;
    final sonuc = await adminMiOku(() async {
      cagri++;
      throw TimeoutException('ağ');
    }, araliklar: hizli);
    expect(sonuc, isFalse);
    expect(cagri, hizli.length + 1);
  });

  test('varsayılan: en az iki yeniden deneme', () {
    expect(adminOkumaAraliklari.length, greaterThanOrEqualTo(2));
  });

  test('servis hatayı yutmaz (yutarsa yeniden deneme çalışmaz)', () {
    final kaynak = ekranKaynagiSync('lib/services/supabase_service.dart');
    final bas = kaynak.indexOf('Future<bool> isPushAdmin()');
    expect(bas, greaterThan(0));
    final govde = kaynak.substring(bas, kaynak.indexOf('\n  }', bas));
    expect(govde.contains('catch'), isFalse);
  });
}
