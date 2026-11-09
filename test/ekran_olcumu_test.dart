import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/ekran_olcumu.dart';

/// Ekran ölçümü (2026-10-19): sadeleştirme kararları hangi ekranın
/// açıldığına dayanır. İki şey kilitli: gözlemcinin ne saydığı ve her
/// `adaptiveRoute` çağrısının bir ad taşıması (adsız rota ölçüde görünmez;
/// Android `--obfuscate` derlendiği için sınıf adından türetilemez).
PageRoute<void> _rota(String? ad) => MaterialPageRoute<void>(
      settings: RouteSettings(name: ad),
      builder: (_) => const SizedBox(),
    );

void main() {
  group('EkranOlcumu', () {
    late List<String> gonderilen;
    late EkranOlcumu o;
    setUp(() {
      gonderilen = [];
      o = EkranOlcumu(gonder: gonderilen.add);
    });

    test('adlı sayfa açılınca sayılır, kök ve adsız rota sayılmaz', () {
      o.didPush(_rota('/'), null);
      o.didPush(_rota(null), null);
      o.didPush(_rota('asset_detail'), null);
      expect(gonderilen, ['asset_detail']);
    });

    test('sheet/dialog sayılmaz, kapanınca alttaki ekran yeniden sayılmaz', () {
      final alt = _rota('asset_detail');
      o.didPush(alt, null);
      final sheet = ModalBottomSheetRoute<void>(
        builder: (_) => const SizedBox(),
        isScrollControlled: false,
        settings: const RouteSettings(name: 'sheet'),
      );
      o.didPush(sheet, alt);
      o.didPop(sheet, alt);
      expect(gonderilen, ['asset_detail']);
    });

    test('geri dönülen ekran sayılır; köke dönüş açık sekmeyi sayar', () {
      final kok = _rota('/');
      o.sekmeDegisti(1);
      final detay = _rota('asset_detail');
      o.didPush(detay, kok);
      final grafik = _rota('portfolio_performance');
      o.didPush(grafik, detay);
      o.didPop(grafik, detay);
      o.didPop(detay, kok);
      expect(gonderilen, [
        'sekme_portfoy',
        'asset_detail',
        'portfolio_performance',
        'asset_detail',
        'sekme_portfoy',
      ]);
    });

    test('aynı sekmeye yeniden dokunuş ve Ekle düğmesi sayılmaz', () {
      o.sekmeDegisti(0);
      o.sekmeDegisti(0);
      o.sekmeDegisti(2);
      o.sekmeDegisti(3);
      expect(gonderilen, ['sekme_ana', 'sekme_performans']);
    });

    test('oturum kapalıyken köke (giriş ekranı) dönüş sekme sayılmaz', () {
      o.sekmeDegisti(0);
      o.sekmelerKapandi();
      final kok = _rota('/');
      final kayit = _rota('register');
      o.didPush(kayit, kok);
      o.didPop(kayit, kok);
      expect(gonderilen, ['sekme_ana', 'register']);
    });
  });

  test('her adaptiveRoute çağrısı ekran adı taşır', () {
    final eksik = <String>[];
    final desen = RegExp(r'adaptiveRoute(<[^>()]*(?:<[^>]*>)?[^>()]*>)?\(');
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('theme/sandik.dart')) continue; // tanım
      final s = f.readAsStringSync();
      for (final m in desen.allMatches(s)) {
        // Çağrının kapanış parantezine kadar.
        var d = 0, j = m.end - 1;
        for (; j < s.length; j++) {
          if (s[j] == '(') d++;
          if (s[j] == ')' && --d == 0) break;
        }
        if (!s.substring(m.end, j).contains('settings:')) {
          final satir = '\n'.allMatches(s.substring(0, m.start)).length + 1;
          eksik.add('${f.path}:$satir');
        }
      }
    }
    expect(eksik, isEmpty,
        reason: 'adaptiveRoute(settings: const RouteSettings(name: '
            "'ekran_adi'), …) yaz; ad ekran ölçümünde görünür (EkranOlcumu).");
  });
}
