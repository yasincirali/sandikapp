import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/tazelik_ritmi.dart';

import 'helpers/kaynak.dart';

/// Kullanıcı bildirimi (2026-09-23, TestFlight): *"Hâlâ zaman zaman fark
/// oluyor, özellikle ana sayfa Bugün ile Performans günlük arasında, ama
/// ortaklarda fark olmuyor — logged-in user'ın portföyünde sorun oluyor."*
///
/// ## Kök neden: seri YAŞI
/// İki yüzey aynı hesabı yapıyor ama serileri farklı yaştaydı:
///
///   * Performans → `Timer.periodic(30 sn)` `_intradayKey`'i düşürür,
///     `FutureBuilder` seriyi YENİDEN çeker. Yaş her zaman ≤ 30 sn.
///   * Bugün kartı → `_seri` alanına BİR KEZ yazılıyordu (`_istendi`) ve
///     yalnızca defter imzası değişince yeniden yükleniyordu. Fiyat
///     tazelemesi kartı yeniden BUILD ediyor ama `_seri` aynı kalıyordu.
///
/// Gün başı (`open`) serinin ilk noktasından gelir. Seri eskidikçe o nokta
/// Performans'ınkinden ayrışıyor; canlı uç (`last`) ikisinde de güncel
/// olduğu için DEĞİŞİM farklı çıkıyor.
///
/// ## Neden yalnızca "Ben" kapsamında
/// Ortak lot'larının `currentPrice`'ı RLS yüzünden sunucuya yazılamaz;
/// `refreshPrices` onları ancak bellekte günceller. Ortak görünümünde canlı
/// uç pek oynamadığı için bayat taban fark yaratmıyor. Kendi portföyünde
/// fiyat her 30 sn'de güncelleniyor: uç oynuyor, taban sabit kalıyor.
Asset _lot({double cur = 120}) => Asset(
      id: 'b1',
      userId: 'ben',
      name: 'THYAO',
      ticker: 'THYAO',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1,
      currentPrice: cur,
      addedDate: DateTime(2026, 1, 1),
    );

void main() {
  final seansGunu = DateTime(2026, 9, 23);
  final simdi = DateTime(2026, 9, 23, 14, 0);

  group('bayat taban ÖLÇÜLDÜ (düzeltmenin gerekçesi)', () {
    test('seri eskidikçe iki yüzey AYRIŞIR', () {
      // **Mekanizma (ölçüldü):** gün içi veri ÇEKİLEMİYORSA
      // (`seriCek ... 0 nokta` — altında yaşanan durum) her slot
      // `assetSeedTRY` ile doldurulur ve o da `a.currentPrice`'a düşer.
      // Yani seri, o anki canlı fiyat seviyesinde DÜZ BİR PLATODUR.
      //
      // `refreshPrices` her 30 sn'de `currentPrice`'ı günceller. Seri
      // YENİDEN çekilirse taban da uçla birlikte yükselir ve değişim
      // sıfır kalır. ÇEKİLMEZSE taban eski fiyatta çakılı kalır ama
      // canlı uç yükselir — aradaki makas "bugünkü kâr" diye görünür.
      //
      // İki yüzey farklı anlarda tazelediği için tabanları ayrışıyordu.
      final st = PortfolioState(assets: [_lot(cur: 126)]);

      // Bugün kartı (ESKİ davranış): seri sabah ₺120 iken çekilmiş.
      final bayatSeri = {
        seansGunu.add(const Duration(hours: 10)).millisecondsSinceEpoch: 1200.0,
        seansGunu.add(const Duration(hours: 13)).millisecondsSinceEpoch: 1200.0,
      };
      // Performans: seri az önce ₺126 iken tazelenmiş.
      final tazeSeri = {
        seansGunu.add(const Duration(hours: 10)).millisecondsSinceEpoch: 1260.0,
        seansGunu.add(const Duration(hours: 13)).millisecondsSinceEpoch: 1260.0,
      };

      final kart = DailySummary.from(
          state: st, series: bayatSeri, now: simdi, seansGunu: seansGunu);
      final perf = DailySummary.from(
          state: st, series: tazeSeri, now: simdi, seansGunu: seansGunu);

      // İkisi de AYNI canlı toplamı görüyor...
      expect(kart.totalTRY, perf.totalTRY);
      // ...ama değişim ₺60 vs ₺0 — taban farklı anlardan geldi.
      expect(kart.changeTRY, closeTo(60, 0.01));
      expect(perf.changeTRY, closeTo(0, 0.01));
      expect(kart.changeTRY, isNot(closeTo(perf.changeTRY!, 0.01)),
          reason: 'ölçülen fark — bu testin varlık sebebi');
    });

    test('AYNI yaştaki seri → AYNI değişim', () {
      final st = PortfolioState(assets: [_lot(cur: 126)]);
      final seri = {
        seansGunu.add(const Duration(hours: 10)).millisecondsSinceEpoch: 1200.0,
        seansGunu.add(const Duration(hours: 13, minutes: 59))
            .millisecondsSinceEpoch: 1260.0,
      };
      final a = DailySummary.from(
          state: st, series: seri, now: simdi, seansGunu: seansGunu);
      final b = DailySummary.from(
          state: st,
          series: seri,
          now: simdi,
          seansGunu: seansGunu,
          kapsamLotlari: [_lot(cur: 126)]);
      expect(a.changeTRY, closeTo(b.changeTRY!, 0.01),
          reason: 'aynı seri → aynı sayı; fark yalnızca YAŞTAN gelir');
    });
  });

  group('düzeltme: kart ORTAK NABZI dinler', () {
    test('kendi sayacını KURMAZ, nabzı dinler', () {
      // **Değişti (2026-09-23):** önce kendi `Timer`'ını kuruyordu. Aynı
      // ritim YETMEDİ — sayaç mount anında kurulduğu için yüzeyler FARKLI
      // FAZDA çalışıyordu (ana sayfa t=0, Performans t=12 → 12 sn fark).
      // Artık sayaç uygulamada, yüzeyler yalnızca dinliyor
      // (bkz. `tazelik_nabzi_test`).
      final src = ekranKaynagiSync('lib/widgets/bugun_karti.dart');
      expect(src.contains('TazelikRitmi.nabiz.dinle('), isTrue,
          reason: 'kendi sayacını kuran yüzey faz kaydırır');
      expect(src.contains('_nabziBirak?.call()'), isTrue,
          reason: 'dinleyici dispose\'da bırakılmalı (sızıntı)');
    });

    test('yalnızca GÜN İÇİ seri tazelenir — diğer iki satır değil', () {
      // Reel getiri ve haftalık özet günde bir kez değişir; 30 saniyede bir
      // çekmek boşuna ağ trafiği olurdu.
      final src = ekranKaynagiSync('lib/widgets/bugun_karti.dart');
      expect(src.contains('Future<void> _seriyiTazele()'), isTrue);
      // Tick `_yukle`'yi DEĞİL, dar kapsamlı tazelemeyi çağırmalı.
      //
      // Boşlukları tek boşluğa indirerek arıyoruz: `dart format` satır
      // sonlarını değiştirdiğinde birebir eşleşme SAHTE kırılır (bu
      // projede dört test tam olarak böyle kırılmıştı).
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains('TazelikRitmi.nabiz.dinle(() { '
              'if (!mounted) return; _seriyiTazele();'),
          isTrue,
          reason: 'nabız üç yüklemeyi birden tetiklerse gereksiz istek doğar');
    });

    test('Performans tick\'i ile AYNI sabitten besleniyor', () {
      // Değer karşılaştırması — kaynak metni değil.
      expect(TazelikRitmi.yuzey, TazelikRitmi.temel);
      final perfSrc =
          ekranKaynagiSync('lib/screens/portfolio_performance/seriler.dart');
      expect(perfSrc.contains('TazelikRitmi.nabiz.dinle('), isTrue,
          reason: 'iki yüzey AYNI nabzı dinlemeli; ayrı sayaçlar '
              'sessizce ayrışabilir');
    });
  });
}
