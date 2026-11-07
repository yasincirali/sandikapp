import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/notification_service.dart';

/// Mevduat vadesi doldu push'u (0174, `calendar-nudge` › `deposit_matured`).
///
/// Sunucu ve istemci an adını ayrı yazıyor; biri değişirse push gider ama
/// dokunuş Portföy'e değil hiçbir yere götürmez ve bunu hiçbir şey
/// yakalamaz. `NotificationService` Firebase/Supabase istediği için dal
/// kaynaktan doğrulanır.
void main() {
  test('an adı sunucuyla aynı', () {
    final sunucu =
        File('supabase/functions/calendar-nudge/index.ts').readAsStringSync();
    expect(NotificationService.mevduatVadeOccasion, 'deposit_matured');
    expect(sunucu,
        contains("MEVDUAT_VADE = '${NotificationService.mevduatVadeOccasion}'"));
  });

  test('push ve çan dokunuşu Portföy sekmesine gider', () {
    for (final yol in [
      'lib/services/notification_service.dart',
      'lib/screens/home_screen.dart',
    ]) {
      final kod = File(yol).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
      expect(
        kod,
        matches(RegExp(r'mevduatVadeOccasion[^;]*?\{?[^;]*?'
            r'sekmeIstegi\.value = MainNavigationScreen\.portfoySekmesi')),
        reason: '$yol: deposit_matured dalı Portföy sekmesini açmıyor',
      );
    }
  });

  test('migration: defter yalnız service_role, cron 09:30 TR', () {
    final sql = File('supabase/migrations/0174_mevduat_vade_bildirimi.sql')
        .readAsStringSync();
    expect(sql, contains('revoke all on table public.mevduat_vade_bildirim_log '
        'from public, anon, authenticated'));
    expect(sql, contains("'30 6 * * *'"));
    expect(sql, contains("'occasion', 'deposit_matured'"));
  });
}
