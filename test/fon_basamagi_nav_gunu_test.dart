import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// Fon NAV basamağı YALNIZCA o günün NAV'ı yayınlandıysa çizilir.
///
/// ## Kullanıcı bildirimi (2026-09-13, ekran görüntüsüyle)
/// "Günlük grafikte 13 Eylül için fonlarımda bir düşüş görülüyor. Piyasa
/// kapalı değil miydi, güncel datada nasıl düşmüş olabilir?"
///
/// Haklıydı. Üstelik AYNI ekranda "altın için gün içi veri alınamadı,
/// sabit çizildi" uyarısı duruyordu — iki ifade çelişiyordu.
///
/// ## Ölçüm (gerçek TEFAS API, 2026-09-13 Pazar)
/// `fonFiyatBilgiGetir` → AFT son iki NAV noktası:
///
///   10 Eylül Perşembe → 1,022627
///   11 Eylül Cuma     → 1,000902     = **−%2,12**
///
/// Ekranda görünen rakamla BİREBİR aynı. Yani düşüş gerçekti, sadece
/// YANLIŞ GÜNE yerleştirilmişti: Cuma'nın hareketi Pazar'ın grafiğinde
/// çiziliyordu.
///
/// ## Kök sebep
/// `fonOncekiNav` serinin son iki noktasını karşılaştırıyordu — bunların
/// hangi güne ait olduğuna BAKMADAN. TEFAS hafta sonu/tatilde NAV
/// yayınlamıyor, dolayısıyla "son iki nokta" her zaman "bugün ve dün"
/// anlamına gelmiyor.
void main() {
  final servis = File('lib/services/history_service.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  group('NAV yayın tarihi İZLENİYOR', () {
    test('son NAV\'ın günü saklanıyor', () {
      expect(servis.contains('final fonSonNavGunu = <String, DateTime>{}'),
          isTrue,
          reason: 'Yayın tarihi takip edilmiyor — basamak her zaman '
              'çizilir.');
    });

    test('tarih GÜN başına normalize ediliyor', () {
      // Saat/dakika taşırsa karşılaştırma hiçbir zaman tutmaz.
      expect(
        servis.contains('DateTime(sonGun.year, sonGun.month, sonGun.day)'),
        isTrue,
        reason: 'Tarih gün başına çekilmiyor.',
      );
    });
  });

  group('basamak KOŞULLU çiziliyor', () {
    test('NAV günü ile çizilen gün karşılaştırılıyor', () {
      expect(servis.contains('final navBugunMu = navGunu != null &&'), isTrue,
          reason: 'Karşılaştırma yok.');
      expect(servis.contains('navGunu.day == dayStart.day'), isTrue,
          reason: 'Gün karşılaştırması eksik.');
    });

    test('NAV bugüne ait DEĞİLSE basamak yok', () {
      expect(
        servis.contains('oncekiNav: navBugunMu ? fonOncekiNav[a.ticker] : null'),
        isTrue,
        reason: 'Basamak koşulsuz çiziliyor — hafta sonu Cuma\'nın '
            'hareketi bugünmüş gibi görünür.',
      );
    });

    test('koşulsuz eski hâl GERİ GELMEZ', () {
      expect(servis.contains('oncekiNav: fonOncekiNav[a.ticker],'), isFalse,
          reason: 'Koşulsuz basamak geri gelmiş.');
    });
  });

  test('`gunIciFonBirimFiyati` null oncekiNav\'da SABİT çizer', () {
    // Düzeltmenin dayandığı sözleşme: `oncekiNav` null ise basamak yok.
    // Bu davranış değişirse düzeltme sessizce etkisiz kalır.
    const guncel = 1.000902; // AFT, 11 Eyl (ölçülen gerçek değer)
    final acilis = gunIciFonBirimFiyati(
      guncelNav: guncel,
      oncekiNav: null,
      slotTs: DateTime(2026, 9, 13, 0, 0).millisecondsSinceEpoch,
      basamakTs: DateTime(2026, 9, 13, 10, 0).millisecondsSinceEpoch,
    );
    final kapanis = gunIciFonBirimFiyati(
      guncelNav: guncel,
      oncekiNav: null,
      slotTs: DateTime(2026, 9, 13, 20, 0).millisecondsSinceEpoch,
      basamakTs: DateTime(2026, 9, 13, 10, 0).millisecondsSinceEpoch,
    );

    expect(acilis, kapanis,
        reason: 'oncekiNav null iken seri DÜZ olmalı — basamak çizilirse '
            'hafta sonu sahte hareket görünür.');
    expect(acilis, guncel);
  });

  test('oncekiNav VARSA basamak hâlâ çiziliyor — hafta içi bozulmadı', () {
    // Regresyon kapısı: düzeltme yalnızca kapalı günleri etkilemeli.
    // Ölçülen gerçek değerler: 10 Eyl → 11 Eyl.
    const onceki = 1.022627;
    const guncel = 1.000902;
    final basamak = DateTime(2026, 9, 11, 10, 0).millisecondsSinceEpoch;

    final acilis = gunIciFonBirimFiyati(
      guncelNav: guncel,
      oncekiNav: onceki,
      slotTs: DateTime(2026, 9, 11, 9, 0).millisecondsSinceEpoch,
      basamakTs: basamak,
    );
    final sonra = gunIciFonBirimFiyati(
      guncelNav: guncel,
      oncekiNav: onceki,
      slotTs: DateTime(2026, 9, 11, 11, 0).millisecondsSinceEpoch,
      basamakTs: basamak,
    );

    expect(acilis, onceki, reason: 'Yayından önce önceki NAV çizilmeli.');
    expect(sonra, guncel, reason: 'Yayından sonra güncel NAV çizilmeli.');
    expect(acilis, isNot(sonra), reason: 'Basamak kaybolmuş.');
  });
}
