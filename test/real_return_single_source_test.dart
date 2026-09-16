import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// "Enflasyonun kaç puan önündeyim" — TEK kaynak (2026-09-16).
///
/// Ana ekran rozeti, Performans kartı ve yıl sonu özeti aynı soruya üç ayrı
/// formülle cevap veriyordu (5,7 önde / 1,0 geride). Karar: nominal getiri
/// her yerde `RealReturnService` üzerinden, nakit akışı düzeltmeli 1Y
/// piyasa getirisi. Bu test kaynak taramasıyla o bağı kilitler: yarış
/// ROI'si (`computeROI`, simülasyon) enflasyon yüzeylerine geri sızamaz.
void main() {
  String kod(String yol) => File(yol)
      .readAsLinesSync()
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///');
      })
      .join('\n');

  test('ana ekran rozeti RealReturnService okur, yarış ROI\'sini değil', () {
    final src = kod('lib/widgets/real_return_strip.dart');
    expect(src.contains('RealReturnService.yillik('), isTrue);
    expect(src.contains('computeROI'), isFalse,
        reason: 'simülasyon ROI\'si nakit akışını görmez; rozet '
            'Performans kartından farklı puan söylerdi');
    expect(src.contains('LeaderboardService'), isFalse);
  });

  test('yıl sonu özeti enflasyon farkını piyasa getirisinden alır', () {
    final ekran = kod('lib/screens/recap_screen.dart');
    expect(ekran.contains('RealReturnService.yillikPiyasaGetirisi('), isTrue);
    expect(ekran.contains('marketReturnPct: piyasa'), isTrue);

    final servis = kod('lib/services/recap_service.dart');
    expect(servis.contains('marketReturnPct - inflationPct'), isTrue);
    expect(servis.contains('degisim - inflationPct'), isFalse,
        reason: 'portföy değeri değişimi katkıyı içerir, TÜFE ile '
            'kıyaslanmaz');
  });

  test('servis Performans ile aynı hesabı kullanır', () {
    final src = kod('lib/services/real_return_service.dart');
    expect(src.contains('PeriodSummaryService.compute('), isTrue);
    expect(src.contains('SummaryPeriod.birYil'), isTrue);
    expect(src.contains('donemBaslangici('), isTrue,
        reason: 'pencere Performans 1Y bloğuyla aynı olmalı');
    expect(src.contains('simulate: true'), isFalse,
        reason: 'gerçek seri; simülasyon yarışa ait');
  });
}
