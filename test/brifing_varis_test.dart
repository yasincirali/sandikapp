import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Günlük brifingin varış yeri — push ve çan AYNI fonksiyondan (#16).
///
/// Emülatör testi #16 (2026-09-29): "ARDYZ son kapanışta %5,8 yükseldi"
/// bildirimi çandan Performans › Özet'e, push'tan ana ekrana gidiyordu;
/// anlatılan hisse ikisinde de yoktu. Şimdi iki yol da
/// `NotificationService.openDailyBrief`'i çağırır: hisse brifingi (sunucu
/// `ticker` ekler) → o varlığın ekranı, ortak / eski kayıt → Özet.
///
/// Push ve çan widget ağacı dışından (navigatorKey, provider container)
/// çalıştığı için davranış kaynak düzeyinde sabitlenir; sunucu tarafı
/// (`briefVerisi`, metin) `supabase/tests/daily_brief_test.ts`'de.
void main() {
  final ns = ekranKaynagiSync('lib/services/notification_service.dart')
      .replaceAll('\r\n', '\n');
  final home =
      ekranKaynagiSync('lib/screens/home_screen.dart').replaceAll('\r\n', '\n');

  test('push dalı openDailyBrief çağırır (ana ekranda kalmaz)', () {
    final i = ns.indexOf('if (type == dailyBriefType)');
    expect(i, greaterThan(-1));
    final dal = ns.substring(i, ns.indexOf('}', i));
    expect(dal.contains('openDailyBrief(data)'), isTrue);
    expect(ns.contains('if (type == dailyBriefType) return;'), isFalse,
        reason: 'brifing push\'u yine ana ekranda bırakılıyor');
  });

  test('çan dalı AYNI fonksiyonu çağırır', () {
    final i = home.indexOf('case AppNotification.dailyBrief:');
    expect(i, greaterThan(-1),
        reason: 'brifing haftalık özetle aynı case\'te birleşmemeli');
    final dal = home.substring(i, home.indexOf('case ', i + 10));
    expect(dal.contains('NotificationService.instance.openDailyBrief(b.data)'),
        isTrue);
    expect(dal.contains('PortfolioPerformanceScreen'), isFalse);
  });

  test('hisse brifingi varlığa, bulunamazsa Özet\'e; diğerleri Özet\'e', () {
    final i = ns.indexOf('void openDailyBrief(');
    expect(i, greaterThan(-1));
    final govde = ns.substring(i, ns.indexOf('\n  }\n', i));
    expect(govde.contains("data['variant']?.toString() == 'mover'"), isTrue);
    expect(govde.contains("data['ticker']"), isTrue);
    expect(govde.contains('openPriceAlertAsset(ticker'), isTrue,
        reason: 'varlık eşlemesi alarmla aynı yoldan (GÜNLÜK sekmesi)');
    expect(govde.contains('onNotFound: () => _openOzet()'), isTrue,
        reason: 'satılmış hisse → hata ekranı değil Özet');
    expect(govde.contains('_openOzet();'), isTrue);
  });

  test('sunucu hisse brifingine ticker ekler, push ve çan aynı veriyi taşır',
      () {
    final fn = ekranKaynagiSync('supabase/functions/daily-brief/index.ts')
        .replaceAll('\r\n', '\n');
    expect(fn.contains('d.ticker = ticker.trim();'), isTrue);
    // Çan kaydı ve FCM data'sı TEK `veri` nesnesinden.
    expect(RegExp(r'data: veri,').allMatches(fn).length, 2);
  });
}
