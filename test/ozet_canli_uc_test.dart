import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';

import 'helpers/kaynak.dart';

/// Özet'in sağ ucu CANLI toplam — 2026-09-24 dört ekran çapraz kontrolü.
///
/// ## Ölçülen arıza (web derlemesi, sahte fiyat, iki hisse)
/// 1H: Grafik "piyasa +₺306", Özet "−₺5.069", ana sayfa "geçen hafta
/// −%5,50". Fark (₺5.375) bugün alınan lot'ların değeriydi.
///
/// Seri son slotunu `normalizeTs(now)`'a kurar (günlük katmanda bugün
/// 00:00); o damgadan sonra alınan lot son noktada YOK ama katkıya GİRİYOR.
/// Grafik ucu canlı toplama bağlıyor, Özet bağlamıyordu.
void main() {
  Asset lot(String id, double qty, double fiyat, DateTime t) => Asset(
        id: id,
        userId: 'u',
        name: id,
        ticker: 'THYAO.IS',
        type: AssetType.hisse,
        quantity: qty,
        purchasePrice: fiyat,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: fiyat,
        addedDate: t,
        kind: AssetKind.buy,
      );

  final now = DateTime(2026, 9, 24, 14);
  // 100 lot 17 Eyl'de 300'den; bugün 14:00'e kadar 310. Bugün 11:00'de
  // 20 lot daha 305'ten alındı.
  final lotlar = [
    lot('eski', 100, 300, DateTime(2026, 9, 10)),
    lot('bugun', 20, 305, DateTime(2026, 9, 24, 11)),
  ];
  // Günlük katman: son slot BUGÜN 00:00 — bugünkü alım içinde yok.
  final bd = PortfolioHistoryBreakdown(
    total: {
      DateTime(2026, 9, 17).millisecondsSinceEpoch: 100 * 300.0,
      DateTime(2026, 9, 24).millisecondsSinceEpoch: 100 * 306.0,
    },
    byType: const {},
    byPosition: const {},
    positionType: const {},
  );
  const canli = 120 * 310.0; // 37.200

  test('canlı uç verilince piyasa = gerçek fiyat hareketi', () {
    final s = PeriodSummaryService.compute(
      period: SummaryPeriod.birHafta,
      assets: lotlar,
      breakdown: bd,
      now: now,
      canliSon: canli,
    );
    // 100 lot 300 → 310 (+1.000) ve 20 lot 305 → 310 (+100).
    expect(s.katkiTRY, 20 * 305.0);
    expect(s.sonTRY, canli);
    expect(s.piyasaTRY, closeTo(1100, 1e-6));
  });

  test('canlı uç yoksa bayat son slot bugünkü alımı eksi yazar (eski arıza)',
      () {
    final s = PeriodSummaryService.compute(
      period: SummaryPeriod.birHafta,
      assets: lotlar,
      breakdown: bd,
      now: now,
    );
    // 30.600 − 30.000 − 6.100 = −5.500: alımın değeri kadar eksik.
    expect(s.piyasaTRY, closeTo(-5500, 1e-6));
  });

  test('tür dökümü kartı üst kartla AYNI taban anını ve canlı ucu kullanır',
      () {
    String kod(String yol) => ekranKaynagiSync(yol)
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    // Ölçüldü (2026-09-24, 1A): satırlar +₺5.113, üst kart +₺18.198 —
    // satırlar serinin kırpılmamış ilk/son noktasını alıyordu.
    final kart = kod('lib/screens/portfolio_performance/tur_dokumu_karti.dart');
    expect(kart.contains('if (k > widget.tabanMs) break;'), isTrue,
        reason: 'dönem başı üst kartın taban anından okunmalı');
    expect(kart.contains('widget.canliDeger?.call(lotlar)'), isTrue,
        reason: 'uç canlı olmalı — serinin son slotu bugünkü alımı içermez');
    expect(kart.contains('PeriodSummaryService.grafikKatkisi('), isTrue,
        reason: 'akış kuralı üst kartla TEK fonksiyon');
    final kartlar = kod('lib/screens/portfolio_performance/kartlar.dart');
    expect(kartlar.contains('tabanMs: ep.firstTs!'), isTrue);
    expect(
        kartlar.contains(
            'canliDeger: (lotlar) => DailySummary.kapsamToplami(pState, lotlar)'),
        isTrue);
    // Üst kart da aynı akış fonksiyonunu çağırır.
    expect(
        kartlar.split('PeriodSummaryService.grafikKatkisi(').length - 1, 1);
  });

  test('bugüne kadar süren her çağıran canlı ucu geçer', () {
    String kod(String yol) => ekranKaynagiSync(yol)
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    // Tüm `lib/` taranır — yeni bir çağıran eklendiğinde de unutulmasın
    // (kod incelemesi 2026-09-24: isteğe bağlı parametre kolay atlanır).
    // İstisnalar gerekçeli:
    const istisna = {
      // Pencere GEÇMİŞTE biter (TÜFE'nin son açıklanan ayı).
      'lib/services/real_return_service.dart',
      // Hiçbir yerde çağrılmayan eski bileşen (`kapsam_enflasyon_seridi_test`).
      'lib/widgets/weekly_summary_chip.dart',
    };
    final dosyalar = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\\', '/'))
        .where((y) => y.endsWith('.dart') && !istisna.contains(y));
    var bulunan = 0;
    for (final yol in dosyalar) {
      final s = kod(yol);
      final cagri = s.split('PeriodSummaryService.compute(').skip(1);
      for (final c in cagri) {
        bulunan++;
        final govde = c.substring(0, c.indexOf(');'));
        expect(govde.contains('canliSon:'), isTrue,
            reason: '$yol: compute canlı uç almadan çağrılıyor');
      }
    }
    expect(bulunan, greaterThanOrEqualTo(3));
  });
}
