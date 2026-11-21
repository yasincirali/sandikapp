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

    // GA "(not set)" (2026-11-20): kapı ekranları rota değil, adları
    // widget anahtarından gelir.
    test('kök kapı ekranı anahtarıyla sayılır, yalnız değişince', () {
      final kok = _rota('/');
      final kayit = _rota('register');
      o.kokEkran(const ValueKey('splash'));
      o.kokEkran(const ValueKey('karsilama'));
      o.didPush(kayit, kok);
      // Kayıt açıkken kapı yeniden kurulur: aynı kök yeniden sayılmaz.
      o.kokEkran(const ValueKey('karsilama'));
      o.didPop(kayit, kok); // dönüş karşılamayı sayar
      o.kokEkran(const ValueKey('login'));
      o.kokEkran(const ValueKey('yasal-kapi'));
      o.kokEkran(const ValueKey('main')); // sekmeler kendi sayar
      o.sekmeDegisti(0);
      expect(gonderilen, [
        'karsilama',
        'register',
        'karsilama',
        'login',
        'yasal_kapi',
        'sekme_ana',
      ]);
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

  // yasin 2026-11-21: "hangi featureların kullanıldığını net şekilde
  // görmeliyiz". Haftalık rapor ekranı Türkçe adıyla basar; adı sözlükte
  // olmayan yeni ekran raporda çıplak kodla kalırdı, burada kırılır.
  test('her ekran adı haftalık raporun Türkçe ad sözlüğünde', () {
    final rapor = File('tool/ga4_ekran_raporu.py').readAsStringSync();
    final adlar = <String>{
      ...EkranOlcumu.sekmeAdlari.values,
    };
    final rota = RegExp(r"RouteSettings\(\s*name:\s*'([a-z0-9_]+)'");
    final elle = RegExp(r"logScreenView\(\s*screenName:\s*'([a-z0-9_]+)'");
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final s = f.readAsStringSync();
      adlar.addAll(rota.allMatches(s).map((m) => m.group(1)!));
      adlar.addAll(elle.allMatches(s).map((m) => m.group(1)!));
    }
    // Kök kapı ekranları: `_AuthGate` anahtarı, `-` → `_` (kokEkran).
    final kok = RegExp(r"ValueKey\('([a-z_-]+)'\)");
    for (final m in kok.allMatches(File('lib/main.dart').readAsStringSync())) {
      final v = m.group(1)!;
      if (v != 'splash' && v != 'main') adlar.add(v.replaceAll('-', '_'));
    }
    final eksik = [
      for (final a in adlar)
        if (!rapor.contains('"$a": (')) a
    ]..sort();
    expect(eksik, isEmpty,
        reason: 'tool/ga4_ekran_raporu.py EKRANLAR sözlüğüne Türkçe adıyla '
            'ekle (Premium ise True).');
  });
}
