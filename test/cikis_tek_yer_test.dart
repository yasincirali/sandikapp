import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Çıkış yalnız Profil'den (yasin, 2026-10-08: "sadece profilden logoff
/// yapılabilsin"). Ana ekran, Portföy ve Performans çubuklarında çıkış
/// düğmesi yok; giriş akışındaki "vazgeç / başka hesap" çıkışları (OTP,
/// kullanıcı adı, yasal onay kapısı, kilit ekranı) bu kuralın dışında —
/// oturum henüz açılmamış ya da kilitli.
void main() {
  test('çıkış düğmesi yalnız Profil üst çubuğunda', () {
    for (final yol in [
      'lib/screens/home_screen.dart',
      'lib/screens/portfolio_screen.dart',
      'lib/screens/portfolio_performance_screen.dart',
      'lib/screens/settings_screen.dart',
    ]) {
      final k = ekranKaynagiSync(yol);
      expect(k, isNot(contains('SandikLogoutButton(')), reason: yol);
      expect(k, isNot(contains('confirmAndLogout(')), reason: yol);
    }
    expect(ekranKaynagiSync('lib/screens/profile_screen.dart'),
        contains('SandikLogoutButton('));
  });
}
