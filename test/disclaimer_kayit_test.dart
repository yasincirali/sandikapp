import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/disclaimer_service.dart';

import 'helpers/kaynak.dart';

/// Yasal uyarı onay kaydı — 2026-09-23 denetimi U18.
///
/// İki ekran `app_version: '1.0.0+1'`, `locale: 'tr_TR'` ve iOS dışı her şeye
/// 'android' yazıyor, hatayı `catch (_) {}` ile yutuyordu.
void main() {
  group('platformEtiketi', () {
    test('mobil', () {
      expect(DisclaimerService.platformEtiketi(TargetPlatform.iOS, web: false),
          'ios');
      expect(
          DisclaimerService.platformEtiketi(TargetPlatform.android, web: false),
          'android');
    });

    test('web ve masaüstü "android" DEĞİL', () {
      expect(
          DisclaimerService.platformEtiketi(TargetPlatform.android, web: true),
          'web');
      expect(DisclaimerService.platformEtiketi(TargetPlatform.macOS, web: false),
          'macos');
      expect(
          DisclaimerService.platformEtiketi(TargetPlatform.windows, web: false),
          'windows');
      expect(
          DisclaimerService.platformEtiketi(TargetPlatform.fuchsia, web: false),
          'other');
    });
  });

  test('ekranlar sabit sürüm/dil/platform yazmaz, hatayı yutmaz', () {
    for (final yol in const [
      'lib/screens/disclaimer_acceptance_screen.dart',
      'lib/screens/otp_verification_screen.dart',
    ]) {
      final src = ekranKaynagiSync(yol);
      expect(src, isNot(contains("'1.0.0+1'")), reason: yol);
      expect(src, isNot(contains("locale: 'tr_TR'")), reason: yol);
      expect(src, isNot(contains("Platform.isIOS ? 'ios' : 'android'")),
          reason: yol);
      expect(src, contains('kabulKaydet('), reason: yol);
      expect(src, contains('Localizations.localeOf(context)'), reason: yol);
    }
  });

  test('kabulKaydet gerçek sürümü okur ve hatayı raporlar', () {
    final src = ekranKaynagiSync('lib/services/disclaimer_service.dart');
    final start = src.indexOf('Future<bool> kabulKaydet(');
    final body = src.substring(start, src.indexOf('\n  }\n', start));
    expect(body, contains('_surumEtiketi()'));
    expect(body, contains('platformEtiketi(defaultTargetPlatform)'));
    expect(body, contains('CrashReporter.report('));
    expect(src, contains('PackageInfo.fromPlatform()'));
  });
}
