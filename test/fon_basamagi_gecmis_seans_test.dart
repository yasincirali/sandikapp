import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// Fon basamağı GEÇMİŞ bir seans çizilirken de gizlenmeli.
///
/// ## Kullanıcı bildirimi (2026-09-13, ikinci kez, ekran görüntüsüyle)
/// "Performans ekranı günlük grafikte hâlâ çizgi hâlinde değil de bir
/// düşüş var gibi gösteriyor, özellikle tüm fonlarda. Kâr/zararı da
/// ayrıca gösteriyor."
///
/// Bir önceki düzeltme (`fon_basamagi_nav_gunu_test.dart`) basamağı
/// NAV'ın yayın günü çizilen günle uyuşmadığında gizliyordu. Doğruydu ama
/// YETMEDİ — çünkü çizilen gün "bugün" değil.
///
/// ## Ölçüm
/// `dayStart = seansGunu(...)` → Pazar günü **Cuma 11 Eylül**'ü döner.
/// TEFAS'ın son NAV'ı da Cuma 11 Eylül. Yani iki tarih UYUŞUYOR, kapı
/// açılıyor ve basamak çiziliyor.
///
/// Gerçek TEFAS ölçümü (2026-09-13 Pazar, `fonFiyatBilgiGetir`, AFT):
///   10 Eyl Per → 1,022627
///   11 Eyl Cum → 1,000902   = −%2,12
///
/// Basamak `dayStart + 10:00` = **Cuma 10:00**'a düşüyor. Eksen Cuma'dan
/// Pazar'a uzandığı için bu, grafiğin SOL UCUNDA dik bir uçurum olarak
/// görünüyor — kullanıcının ekran görüntüsündeki tam olarak budur.
///
/// ## Neden yanlış
/// Cuma'nın NAV hareketi Cuma'nın seansına aittir ve "günlük değişim"
/// olarak göstermek başlı başına doğru. Ama kullanıcı Pazar günü bakıyor:
/// ekranda "11 Eylül · son seans" yazarken grafiğin ucu CANLI toplama
/// sabitleniyor. Sonuç, kapanmış bir seansın içine bugünün ucunu bağlayan
/// melez bir seri.
///
/// Karar: geçmiş bir seans çizilirken fon SABİT çizilir. Basamak yalnızca
/// seans BUGÜNSE anlamlı — o zaman "bugün şu an itibarıyla" okunur.
void main() {
  group('gunIciFonBirimFiyati — sözleşme', () {
    const onceki = 1.022627; // AFT 10 Eyl (ölçülen)
    const guncel = 1.000902; // AFT 11 Eyl (ölçülen)

    test('oncekiNav null ise SABİT — basamak yok', () {
      final basamak = DateTime(2026, 9, 11, 10).millisecondsSinceEpoch;
      final erken = gunIciFonBirimFiyati(
        guncelNav: guncel,
        oncekiNav: null,
        slotTs: DateTime(2026, 9, 11, 9).millisecondsSinceEpoch,
        basamakTs: basamak,
      );
      final gec = gunIciFonBirimFiyati(
        guncelNav: guncel,
        oncekiNav: null,
        slotTs: DateTime(2026, 9, 11, 20).millisecondsSinceEpoch,
        basamakTs: basamak,
      );
      expect(erken, gec, reason: 'seri düz olmalı');
      expect(erken, guncel);
    });

    test('basamakTs null ise SABİT', () {
      final v = gunIciFonBirimFiyati(
        guncelNav: guncel,
        oncekiNav: onceki,
        slotTs: DateTime(2026, 9, 11, 9).millisecondsSinceEpoch,
        basamakTs: null,
      );
      expect(v, guncel);
    });

    test('ikisi de VARSA basamak çizilir — hafta içi davranışı', () {
      // Regresyon kapısı: düzeltme yalnızca GEÇMİŞ seansı etkilemeli.
      final basamak = DateTime(2026, 9, 11, 10).millisecondsSinceEpoch;
      final erken = gunIciFonBirimFiyati(
        guncelNav: guncel,
        oncekiNav: onceki,
        slotTs: DateTime(2026, 9, 11, 9).millisecondsSinceEpoch,
        basamakTs: basamak,
      );
      final gec = gunIciFonBirimFiyati(
        guncelNav: guncel,
        oncekiNav: onceki,
        slotTs: DateTime(2026, 9, 11, 11).millisecondsSinceEpoch,
        basamakTs: basamak,
      );
      expect(erken, onceki);
      expect(gec, guncel);
      expect(erken, isNot(gec), reason: 'basamak kaybolmuş');
    });
  });

  group('seansGunu — çizilen gün BUGÜN mü', () {
    test('Pazar günü CUMA döner — basamağın kapısı burada', () {
      // Bu, hatanın kök sebebi: `dayStart` bugün değil, son seans.
      // NAV günü de Cuma olduğu için eski kapı (navGunu == dayStart)
      // AÇIK kalıyordu.
      final pazar = DateTime(2026, 9, 13, 20, 15);
      final cumaVeri = DateTime(2026, 9, 11, 18).millisecondsSinceEpoch;
      final gun = HistoryService.seansGunu(now: pazar, enSonVeriTs: cumaVeri);

      expect(gun, DateTime(2026, 9, 11),
          reason: 'Pazar günü çizilen seans Cuma olmalı');
      expect(gun.day == pazar.day, isFalse,
          reason: 'çizilen gün bugün DEĞİL — basamak bu yüzden gizlenmeli');
    });

    test('hafta içi BUGÜNÜ döner — basamak açık kalmalı', () {
      final cuma = DateTime(2026, 9, 11, 14);
      final bugunVeri = DateTime(2026, 9, 11, 13).millisecondsSinceEpoch;
      final gun = HistoryService.seansGunu(now: cuma, enSonVeriTs: bugunVeri);

      expect(gun, DateTime(2026, 9, 11));
      expect(gun.day == cuma.day, isTrue,
          reason: 'seans bugünse basamak anlamlıdır');
    });
  });

  group('kapı GEÇMİŞ SEANSI da eler', () {
    // `getPortfolioHistoryHourlyBreakdown` ağ çağırıyor; kapının varlığı
    // kaynaktan doğrulanıyor. İddia BİÇİME değil mantığın VARLIĞINA bakar
    // (`dart format` sarma noktasını kaydırabiliyor).
    final tek = File('lib/services/history_service.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\s+'), ' ');

    test('`gecmisSeans` basamak kapısına bağlı', () {
      expect(tek.contains('final navBugunMu = !gecmisSeans && navGunu != null'),
          isTrue,
          reason: 'Geçmiş seans elenmiyor — Cuma\'nın basamağı Pazar '
              'grafiğinin sol ucunda uçurum olarak görünür.');
    });

    test('yalnızca yayın gününe bakan eski kapı GERİ GELMEZ', () {
      expect(tek.contains('final navBugunMu = navGunu != null'), isFalse,
          reason: 'Kapı yayın gününe indirgenmiş — `dayStart` bugün '
              'olmadığı için bu koşul hafta sonu AÇIK kalır.');
    });
  });
}
