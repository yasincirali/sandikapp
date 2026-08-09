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
      // Tam ekran grafik yolu showBackButton VERMEZ (kendi kapatma butonu
      // var, ikisi birden çift buton olurdu) ama diğer ayarları geçer.
      const tamEkran = PortfolioPerformanceScreen(
        initialView: 'daily',
        initialScrollOffset: 220,
      );
      expect(tamEkran.showBackButton, isFalse,
          reason: 'FullscreenChartRoute kendi kapatma butonunu sağlıyor');
      expect(tamEkran.initialScrollOffset, 220);
      expect(tamEkran.initialView, 'daily');
    });
  });
}
