import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Altın grafiği MAKUL sürede gelmeli; gelmezse ekran bunu SÖYLEMELİ.
///
/// ## Kullanıcı bildirimi (2026-09-13, ekran görüntüsüyle)
/// "Görseldeki gibi grafiği çizmiyor ama günlük değişimde kâr/zarar
/// yazmış." Sonra: "uzun süre bekleyince geldi, buna çözüm bulmalıyız,
/// kimse bu kadar uzun beklemez."
///
/// Yani veri GELİYORDU — sadece çok geç, ve beklerken ekran bunu
/// söylemiyordu.
///
/// ## Ölçülen üç sebep
///
/// 1. **Altın tek başına İKİ isteği SIRALI yapan türdü.** Gün içi yolu
///    önce `XAUTRY=X` deniyor, boş dönerse `GC=F` istiyordu — ama ikinci
///    istek `if (goldSlots.isEmpty)` dalının içinde olduğu için ancak
///    birincisi TAMAMLANDIKTAN sonra başlıyordu. En kötü 15 + 15 = 30 sn.
///    Diğer türler tek istekle en kötü 15 sn.
///
/// 2. **`history_service.dart`'ta hiç timeout yoktu** (grep: 0 eşleşme).
///    Tek koruma alt katmandaki 15 saniyeydi ve o, sayfa açılışını değil
///    tek bir HTTP çağrısını koruyor.
///
/// 3. **Boş seri "veri var" sayılıyordu.**
///    `getPortfolioHistoryHourlyBreakdown` başarısız çekimde `null` değil
///    BOŞ MAP döndürüyor; ekranın `data == null` kontrolü bunu
///    yakalamıyordu. Sonuç: eksenler ve "AÇILIŞ" etiketi çiziliyor ama
///    çizgi olmuyordu — kullanıcı hata sanıyordu.
void main() {
  final servis = File('lib/services/history_service.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final ekran = File('lib/screens/asset_detail_screen.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  group('altın kaynakları PARALEL çekilir', () {
    test('yedek kaynak önceden başlatılır', () {
      expect(servis.contains('final goldUsdFuture = needsGold'), isTrue,
          reason: 'Yedek altın kaynağı hâlâ gecikmeli başlatılıyor — '
              'en kötü durum 30 saniye kalır.');
    });

    test('yedek dal HAZIR future\'ı bekler, yeni istek AÇMAZ', () {
      expect(servis.contains('final xauUsdPts = await goldUsdFuture;'), isTrue,
          reason: 'İkinci istek hâlâ dal içinde açılıyor (sıralı).');
      // Eski hâl: dalın içinde `getHistorySafe('GC=F')`.
      expect(
        servis.contains("final xauUsdPts = await getHistorySafe('GC=F');"),
        isFalse,
        reason: 'Sıralı çağrı geri gelmiş.',
      );
    });

    test('birincil kaynak hâlâ TERCİH ediliyor', () {
      // Paralel başlatmak, önceliği değiştirmemeli: `XAUTRY=X` doluysa
      // `GC=F` sonucu kullanılmaz (kur çevrimi hatası eklemesin).
      expect(servis.contains('if (goldSlots.isEmpty)'), isTrue,
          reason: 'Öncelik kuralı kaybolmuş — iki kaynak karışır.');
    });
  });

  group('çekim süresi SINIRLI', () {
    test('grafik çekiminde timeout var', () {
      expect(servis.contains('_grafikCekimSuresi'), isTrue,
          reason: 'Timeout yok — yavaş ağda grafik süresiz bekler.');
      expect(servis.contains('.timeout(_grafikCekimSuresi)'), isTrue,
          reason: 'Timeout tanımlı ama UYGULANMIYOR.');
    });

    test('süre alt katmandaki 15 sn\'den KISA', () {
      final m = RegExp(r'_grafikCekimSuresi = Duration\(seconds: (\d+)\)')
          .firstMatch(servis);
      expect(m, isNotNull, reason: 'Süre sabiti bulunamadı.');
      final sn = int.parse(m!.group(1)!);
      expect(sn, lessThan(15),
          reason: 'Üst sınır alt katmandan kısa olmalı, yoksa etkisiz.');
      expect(sn, greaterThanOrEqualTo(5),
          reason: 'Çok kısa süre yavaş ağda grafiği tümden boşaltır.');
    });

    test('zaman aşımı HATA gibi değil, KARAR gibi ele alınır', () {
      // Timeout'ta boş liste dönüyor; üst katman yedek kaynağa ya da
      // `currentPrice` seed'ine düşüyor.
      expect(servis.contains('on TimeoutException'), isTrue,
          reason: 'Zaman aşımı ayrı yakalanmıyor.');
    });
  });

  group('boş seri "veri var" SAYILMAZ', () {
    test('iki noktadan az seri yükleme/boş durum gösterir', () {
      expect(ekran.contains('data == null || data.length < 2'), isTrue,
          reason: 'Boş seri hâlâ grafiğe gidiyor — eksen çizilir, çizgi '
              'çizilmez, kullanıcı bunu hata sanar.');
    });

    test('çekim SÜRERKEN spinner gösterilir', () {
      expect(ekran.contains('waiting\n                            ? const CustomLoadingView()'),
          isTrue,
          reason: 'Bekleme görünmüyor.');
    });

    test('çekim BİTTİ ve boşsa dürüst mesaj — sonsuz spinner YOK', () {
      expect(ekran.contains('fiyat geçmişi şu an '), isTrue,
          reason: 'Veri hiç gelmeyecekken bile spinner dönüyor.');
    });
  });
}
