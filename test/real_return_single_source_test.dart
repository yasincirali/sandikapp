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
    // 2026-09-16'da `yillikPiyasaGetirisi` + `inflationForPeriod` ikilisi
    // TEK çağrıya indi: iki ayrı çağrı iki ayrı pencere demekti
    // (bkz. 'yıl sonu özeti TEK pencereden okur').
    expect(ekran.contains('RealReturnService.yillik('), isTrue);
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
    expect(src.contains('simulate: true'), isFalse,
        reason: 'gerçek seri; simülasyon yarışa ait');
  });

  // ── Pencere hizalaması (2026-09-16) ───────────────────────────────────
  //
  // TÜFE ve nominal AYNI aralığı ölçmek zorunda. Nominal pencereyi
  // takvimden (bugünden geriye) kurmak, TÜFE'nin son açıklanmış aya kadar
  // gelen penceresiyle örtüşmüyordu; 1A'da hiç kesişmiyordu. Sayısal kanıt
  // `inflation_window_alignment_test.dart`'ta — burası bağın kaynakta
  // kopmamasını kilitler.

  test('nominal pencere TÜFE penceresinden gelir, takvimden değil', () {
    final src = kod('lib/services/real_return_service.dart');
    expect(src.contains('InflationService.instance.pencere('), isTrue,
        reason: 'uçlar TÜFE penceresinden okunmalı');
    expect(src.contains('w.seriBaslangici'), isTrue);
    expect(src.contains('w.seriBitisi'), isTrue);
    expect(src.contains('donemBaslangici('), isFalse,
        reason: 'takvimden türetilen pencere TÜFE ile örtüşmüyor — '
            'hizalama `InflationWindow` üzerinden yapılır');
  });

  test('Performans kartı nominali TÜFE penceresinde yeniden hesaplar', () {
    final src = kod('lib/screens/portfolio_performance/ozet_yan_veri.dart');
    expect(src.contains('RealReturnService.piyasaGetirisi('), isTrue,
        reason: 'dönem kartının getirisi TÜFE penceresine ait değil');
    expect(src.contains('InflationService.instance.pencere('), isTrue);
    expect(src.contains('inflationForPeriod('), isFalse,
        reason: 'yüzde tek başına gelirse uçlar bilinmez ve hizalama '
            'yapılamaz');
  });

  test('1H enflasyonla kıyaslanmaz — aylık gösterge, haftalık pencere', () {
    // `aySayisi(7)` tabanı 1'e kırpıyor: kapı olmasa bir HAFTALIK getiri
    // bir AYLIK TÜFE ile kıyaslanırdı. Kart 1H'de çizilmiyor ama paylaşım
    // metni enflasyon bağlanmış özetten üretiliyordu.
    final src = kod('lib/screens/portfolio_performance/ozet_yan_veri.dart');
    expect(src.contains('SummaryPeriod.birHafta'), isTrue,
        reason: '1H, GÜNLÜK ile birlikte TÜFE kapısının arkasında olmalı');
  });

  test('yıl sonu özeti TEK pencereden okur', () {
    final src = kod('lib/screens/recap_screen.dart');
    expect(src.contains('RealReturnService.yillik('), isTrue);
    expect(src.contains('inflationForPeriod('), isFalse,
        reason: 'ayrı çağrı = ayrı pencere; ikisi tek kaynaktan gelmeli');
  });
}
