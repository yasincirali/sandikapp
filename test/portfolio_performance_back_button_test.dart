import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';

/// Kullanıcı bildirimi: "portföy ekranı en üst sağdaki performans butonun
/// açtığı ekranda geri butonu yok, olması gerek".
///
/// Kök neden: `PortfolioPerformanceScreen` İKİ şekilde kullanılıyor —
/// alt menüde sekme olarak ve Portföy ekranından push edilerek. Header
/// sabitti (başlık + çıkış butonu), yani push edildiğinde kullanıcı ekranda
/// kilitli kalıyordu; yalnızca sistem geri hareketiyle çıkabiliyordu.
///
/// iOS'ta bu daha da kritik: donanım geri tuşu yok.
void main() {
  group('PortfolioPerformanceScreen — geri butonu', () {
    test('sekme kullanımında varsayılan olarak KAPALI', () {
      // main_navigation_screen sekmeyi parametresiz oluşturur; sekmede
      // geri butonu olmamalı (gidilecek bir yer yok).
      const sekme = PortfolioPerformanceScreen();
      expect(sekme.showBackButton, isFalse);
    });

    test('push edilirken AÇIK olarak verilebilir', () {
      const pushEdilmis = PortfolioPerformanceScreen(showBackButton: true);
      expect(pushEdilmis.showBackButton, isTrue);
    });

    test('diğer parametreler geri butonundan bağımsız', () {
      // Başka bir ayar verilmesi geri butonunu açmaz; varsayılan kapalı.
      const ekran = PortfolioPerformanceScreen(
        initialView: 'daily',
        initialScrollOffset: 220,
      );
      expect(ekran.showBackButton, isFalse);
      expect(ekran.initialScrollOffset, 220);
      expect(ekran.initialView, 'daily');
    });
  });
}
