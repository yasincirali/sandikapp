import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/crash_reporter.dart';

/// Üretim çökmesinin (Crashlytics, 2026-09-19) tekrar etmemesi için ratchet.
///
/// Rapor: "Fatal Exception: FlutterError → `Future.timeout` → `DbLogger.log`
/// → `SupabaseService.updateAsset`". Gerçekte bir çökme YOKTU: `refreshPrices`
/// fiyatı sunucuya `await`siz yazıyordu, `DbLogger.defaultTimeout` (15 sn)
/// dolunca doğan `TimeoutException`'ı kimse yakalamıyordu, hata zone
/// handler'ına düşüp `fatal: true` kaydediliyordu. Uygulama çalışmaya devam
/// ediyor ama Crashlytics çökme sayıyordu.
///
/// Üç iddia birlikte korur:
///   1. `unawaited()` hatayı YUTMAZ — helper'ın var olma sebebi bu.
///   2. `CrashReporter.arkaPlan` yutar.
///   3. Ağ hatası fatal DEĞİLDİR ve global handler'lar kararı buradan sorar.
void main() {
  group('CrashReporter.agHatasiMi', () {
    test('bağlantı kaynaklı hatalar ağ hatasıdır', () {
      expect(CrashReporter.agHatasiMi(TimeoutException('15 sn')), isTrue);
      expect(
        CrashReporter.agHatasiMi(const SocketException('Failed host lookup')),
        isTrue,
      );
      expect(
        CrashReporter.agHatasiMi(const HttpException('sunucu yok')),
        isTrue,
      );
      // Crashlytics'te gördüğümüz metin, tip bilgisi kaybolmuş hâlde.
      expect(
        CrashReporter.agHatasiMi('TimeoutException after 0:00:15.000000'),
        isTrue,
      );
      expect(
        CrashReporter.agHatasiMi('ClientException: Connection closed'),
        isTrue,
      );
    });

    test('program hataları ağ hatası DEĞİLDİR — fatal kalmalı', () {
      expect(CrashReporter.agHatasiMi(ArgumentError('null ticker')), isFalse);
      expect(CrashReporter.agHatasiMi(StateError('build sırasında')), isFalse);
      expect(CrashReporter.agHatasiMi(RangeError('index')), isFalse);
      expect(CrashReporter.agHatasiMi(Exception('beklenmeyen')), isFalse);
      expect(CrashReporter.agHatasiMi(null), isFalse);
    });
  });

  group('arka plan hatası zone handler\'a düşmez', () {
    test('çıplak unawaited() hatayı YUTMAZ (helper\'ın gerekçesi)', () async {
      final zoneyeDusen = await _zonedaCalistir(() {
        // Çökme öncesi koddaki desen: hata sahibi olmayan bir future.
        unawaited(Future<void>.error(TimeoutException('yazma')));
      });
      expect(
        zoneyeDusen,
        isA<TimeoutException>(),
        reason: 'unawaited yalnızca lint susturur; hata zone handler\'ına '
            'düşer ve orada ÇÖKME olarak kaydedilirdi.',
      );
    });

    test('CrashReporter.arkaPlan hatayı yutar', () async {
      final zoneyeDusen = await _zonedaCalistir(() {
        CrashReporter.arkaPlan(
          Future<void>.error(TimeoutException('yazma')),
          reason: 'test',
        );
      });
      expect(zoneyeDusen, isNull);
    });
  });

  group('kaynak ratchet', () {
    test('Supabase yazmaları await/unawaited/arkaPlan olmadan çağrılmaz', () {
      final yazmaRx = RegExp(
        r'SupabaseService\.instance\.'
        r'(insert|update|upsert|delete|softDelete|restore)\w*\(',
      );
      final sucustu = <String>[];
      for (final dosya in _dartDosyalari('lib')) {
        final satirlar = dosya.readAsLinesSync();
        for (var i = 0; i < satirlar.length; i++) {
          if (_yorum(satirlar[i])) continue;
          final m = yazmaRx.firstMatch(satirlar[i]);
          if (m == null) continue;
          final onek = satirlar[i].substring(0, m.start);
          final oncekiSatir = i > 0 ? satirlar[i - 1].trimRight() : '';
          final sahipli = onek.contains('await ') ||
              onek.contains('unawaited(') ||
              onek.contains('return ') ||
              onek.contains('=') ||
              oncekiSatir.endsWith('arkaPlan(') ||
              oncekiSatir.endsWith('=>');
          if (!sahipli) sucustu.add('${dosya.path}:${i + 1}  ${satirlar[i].trim()}');
        }
      }
      expect(
        sucustu,
        isEmpty,
        reason: 'Sahipsiz future hata verirse zone handler onu ÇÖKME sayar. '
            'Bekle (`await`), ya da `CrashReporter.arkaPlan(...)` ile ver.',
      );
    });

    test('global handler fatal kararını agHatasiMi\'ye sorar', () {
      final main = File('lib/main.dart')
          .readAsLinesSync()
          .where((l) => !_yorum(l))
          .join('\n');
      expect(
        main.contains('fatal: true'),
        isFalse,
        reason: 'Her hata fatal yazılırsa timeout gibi bağlantı sorunları '
            'çökmesiz kullanıcı oranını düşürür.',
      );
      expect(
        'fatal: !CrashReporter.agHatasiMi('.allMatches(main).length,
        greaterThanOrEqualTo(3),
        reason: 'FlutterError.onError, PlatformDispatcher.onError ve '
            'runZonedGuarded — üçü de sınıflandırmadan geçmeli.',
      );
    });

    test('refreshPrices fiyat yazımını başıboş bırakmaz', () {
      final kaynak =
          File('lib/providers/portfolio_provider.dart').readAsStringSync();
      expect(
        RegExp(r'^\s+SupabaseService\.instance\.updateAsset\(asset\);',
                multiLine: true)
            .hasMatch(kaynak),
        isFalse,
        reason: 'Çökmenin kaynağı tam olarak bu satırdı.',
      );
      expect(kaynak.contains('_fiyatlariYaz('), isTrue);
    });
  });
}

/// Yorum satırı mı? Kaynak tarayan iddialar dokümantasyondaki ÖRNEĞİ
/// (bu düzeltmenin karar kaydı dahil) ihlal sanmasın.
bool _yorum(String satir) {
  final t = satir.trimLeft();
  return t.startsWith('//') || t.startsWith('*') || t.startsWith('/*');
}

/// [govde]'yi izole bir zone'da çalıştırır, yakalanmayan hatayı döndürür.
Future<Object?> _zonedaCalistir(void Function() govde) async {
  Object? yakalanan;
  final bitti = Completer<void>();
  runZonedGuarded(() {
    govde();
    // Mikro-task turu bitsin; hata bu arada zone'a düşer.
    Timer(const Duration(milliseconds: 30), bitti.complete);
  }, (e, st) {
    yakalanan ??= e;
  });
  await bitti.future;
  return yakalanan;
}

Iterable<File> _dartDosyalari(String kok) sync* {
  for (final e in Directory(kok).listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}
