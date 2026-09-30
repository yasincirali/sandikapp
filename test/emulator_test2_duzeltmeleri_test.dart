import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/services/auth_service.dart';

import 'helpers/kaynak.dart';

/// 2026-09-29 emülatör testi 2 (oturumsuz akışlar, demo, halka arz)
/// bulgularından koordinatörün düzelttikleri.
void main() {
  test('#11 giriş formu e-postayı kayıtla AYNI kuralla doğrular', () {
    // "a@" eskiden yalnız '@' arandığı için geçiyordu.
    expect(AuthService.eMailGecerliMi('a@'), isFalse);
    expect(AuthService.eMailGecerliMi('ad@ornek.com'), isTrue);
    final kaynak = ekranKaynagiSync('lib/screens/login_screen.dart');
    expect(kaynak.contains('AuthService.eMailGecerliMi('), isTrue);
    expect(kaynak.contains("!v.contains('@')"), isFalse);
  });

  test('#14 oturumsuzken db_logs yazımı denenmez (RLS 42501)', () {
    final kaynak = ekranKaynagiSync('lib/services/db_logger.dart')
        .replaceAll('\r\n', '\n');
    final kapi = kaynak.indexOf('if (uid == null) return;');
    final yazim = kaynak.indexOf(".from('db_logs').insert(");
    expect(kapi, greaterThan(0));
    expect(yazim, greaterThan(kapi),
        reason: 'uid kapısı yazımdan ÖNCE olmalı');
  });

  test('#15 işlem gören halka arzda "işlem başlayana kadar" cümlesi yok', () {
    final tr = lookupAppLocalizations(const Locale('tr'));
    expect(tr.ipoParticipateHintTraded.contains('başlayana kadar'), isFalse);
    final kaynak = ekranKaynagiSync('lib/screens/halka_arz_screen.dart');
    expect(
        kaynak.contains(
            'durum == HalkaArzDurumu.islemGoruyor\n                        ? l.ipoParticipateHintTraded'
                .replaceAll('\n', kaynak.contains('\r\n') ? '\r\n' : '\n')),
        isTrue);
  });
}
