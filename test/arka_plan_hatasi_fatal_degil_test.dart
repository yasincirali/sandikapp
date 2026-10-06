import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:portfoy_takip/services/crash_reporter.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthRetryableFetchException, FunctionException, PostgrestException;

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
      // Üretim raporu 2026-09-19 bu tipti (`IOClient.send`).
      expect(
        CrashReporter.agHatasiMi(ClientException(
            'Connection closed before full header was received')),
        isTrue,
      );
      // Metin taraması SINIF ADI ÖNEKİNE bağlı; `toString()`'i ezen bir alt
      // sınıf o önekten geçmez. Tip kontrolü kuralı ayakta tutar.
      expect(CrashReporter.agHatasiMi(_SessizClientException('boom')), isTrue,
          reason: 'sınıflandırma metne değil TİPE de bakmalı');
    });

    test('program hataları ağ hatası DEĞİLDİR — fatal kalmalı', () {
      expect(CrashReporter.agHatasiMi(ArgumentError('null ticker')), isFalse);
      expect(CrashReporter.agHatasiMi(StateError('build sırasında')), isFalse);
      expect(CrashReporter.agHatasiMi(RangeError('index')), isFalse);
      expect(CrashReporter.agHatasiMi(Exception('beklenmeyen')), isFalse);
      expect(CrashReporter.agHatasiMi(null), isFalse);
    });
  });

  group('CrashReporter.geciciSunucuHatasiMi / fatalMi', () {
    // Üretim raporu 2026-10-06 (Android): "Fatal Exception: FlutterError:
    // PostgrestException(message: , code: 504, details: Gateway Timeout)
    // — Error thrown runZonedGuarded".
    test('ağ geçidi zaman aşımı geçicidir, fatal değildir', () {
      const e504 = PostgrestException(
          message: '', code: '504', details: 'Gateway Timeout');
      expect(CrashReporter.geciciSunucuHatasiMi(e504), isTrue);
      expect(CrashReporter.fatalMi(e504), isFalse);
      for (final kod in ['502', '503', '522', '524', 'PGRST003']) {
        expect(
          CrashReporter.fatalMi(PostgrestException(message: '', code: kod)),
          isFalse,
          reason: kod,
        );
      }
      expect(
        CrashReporter.fatalMi(FunctionException(status: 503)),
        isFalse,
      );
      expect(
        CrashReporter.fatalMi(AuthRetryableFetchException()),
        isFalse,
      );
      // Tipi kaybolmuş, metne çevrilmiş hâl.
      expect(
        CrashReporter.fatalMi(
            'PostgrestException(message: , code: 504, details: Gateway Timeout, hint: null)'),
        isFalse,
      );
    });

    test('bizim hatamız olan sunucu yanıtları fatal kalır', () {
      // RLS / şema / kısıt / SQL hatası: kod düzeltilmeli, gizlenmemeli.
      for (final kod in ['42501', '42P01', '23505', 'PGRST116', '400', '500']) {
        expect(
          CrashReporter.fatalMi(PostgrestException(message: 'x', code: kod)),
          isTrue,
          reason: kod,
        );
      }
      expect(CrashReporter.fatalMi(FunctionException(status: 500)), isTrue);
      expect(CrashReporter.fatalMi(StateError('build')), isTrue);
    });

    test('agHatasiMi 504\'ü TANIMAZ — servislerin davranışı değişmedi', () {
      expect(
        CrashReporter.agHatasiMi(
            const PostgrestException(message: '', code: '504')),
        isFalse,
      );
      expect(CrashReporter.fatalMi(TimeoutException('15 sn')), isFalse);
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

    test('global handler fatal kararını fatalMi\'ye sorar', () {
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
        'fatal: CrashReporter.fatalMi('.allMatches(main).length,
        greaterThanOrEqualTo(3),
        reason: 'FlutterError.onError, PlatformDispatcher.onError ve '
            'runZonedGuarded — üçü de sınıflandırmadan geçmeli.',
      );
    });

    test('varlık kaydetme ekranı hatayı yakalar', () {
      // `onPressed: _save` future'ı kimse beklemiyor; genel `catch`
      // olmadan ağ hatası zone handler'ına düşüp ÇÖKME sayılıyordu ve
      // kullanıcı kaydın olmadığını hiç öğrenmiyordu.
      final kaynak =
          File('lib/screens/add_asset_screen.dart').readAsStringSync();
      expect(
        kaynak.contains("reason: 'AddAssetScreen.save'"),
        isTrue,
        reason: 'kayıt hatası Crashlytics\'e bildirilmeli',
      );
      expect(kaynak.contains('friendlyError(e)'), isTrue,
          reason: 'kullanıcı kaydın olmadığını görmeli');
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

/// `toString()`'i sınıf adını yazmayacak şekilde ezen bir `ClientException`.
/// Metin taramasının tek başına neden yetmediğini gösterir.
class _SessizClientException extends ClientException {
  _SessizClientException(super.message);
  @override
  String toString() => message;
}
