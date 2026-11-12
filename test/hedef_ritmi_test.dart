import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/hedef_ritmi.dart';

/// "Plandasın" satırının hesabı (2026-11-12).
///
/// Kilitlenenler:
/// 1. Son 3 TAM takvim ayı; içinde bulunulan ay girmez.
/// 2. Net ekleme = alım − satış (birikim kartının akış kuralı).
/// 3. Defter pencereden kısa → `null` (ilk giriş "eklenen para" sayılmaz).
/// 4. Kıyas yuvarlanmış ortalamayla; net ekleme yoksa eksik = gereken.
void main() {
  Asset alim(DateTime tarih, double tutar) => Asset(
        id: 'b${tarih.millisecondsSinceEpoch}$tutar',
        userId: 'u1',
        notes: '',
        name: 'Test',
        ticker: 'TST',
        type: AssetType.hisse,
        quantity: 1,
        purchasePrice: tutar,
        currentPrice: tutar,
        currency: 'TRY',
        purchaseFxRate: 1,
        addedDate: tarih,
      );

  Asset satis(DateTime tarih, double tutar) => Asset(
        id: 's${tarih.millisecondsSinceEpoch}$tutar',
        userId: 'u1',
        notes: '',
        name: 'Test',
        ticker: 'TST',
        type: AssetType.hisse,
        quantity: 1,
        purchasePrice: tutar,
        currentPrice: tutar,
        sellPrice: tutar,
        currency: 'TRY',
        purchaseFxRate: 1,
        addedDate: tarih,
        kind: AssetKind.sell,
      );

  // Pencere: Ağustos, Eylül, Ekim 2026. Kasım içinde bulunulan ay.
  final now = DateTime(2026, 11, 12, 15);

  group('sonUcAyOrtalamasi', () {
    test('boş defter: yok', () {
      expect(HedefRitmiService.sonUcAyOrtalamasi(const [], now: now), isNull);
    });

    test('defter 3 tam aydan kısa: yok (ilk işlem pencerenin içinde)', () {
      for (final ilk in [DateTime(2026, 8, 1, 9), DateTime(2026, 8, 20)]) {
        expect(
            HedefRitmiService.sonUcAyOrtalamasi([
              alim(ilk, 50000),
              alim(DateTime(2026, 9, 5), 10000),
              alim(DateTime(2026, 10, 5), 10000),
            ], now: now),
            isNull,
            reason: '$ilk');
      }
    });

    test('ilk işlem pencereden önce: ortalama, ilk giriş sayılmaz', () {
      final ort = HedefRitmiService.sonUcAyOrtalamasi([
        alim(DateTime(2026, 7, 31), 500000), // ilk giriş, pencere dışı
        alim(DateTime(2026, 8, 3), 9000),
        alim(DateTime(2026, 9, 3), 12000),
        alim(DateTime(2026, 10, 30), 9000),
      ], now: now);
      expect(ort, 10000);
    });

    test('içinde bulunulan ay girmez', () {
      final ort = HedefRitmiService.sonUcAyOrtalamasi([
        alim(DateTime(2026, 1, 1), 100000),
        alim(DateTime(2026, 9, 3), 30000),
        alim(DateTime(2026, 11, 2), 90000), // Kasım: yok sayılır
      ], now: now);
      expect(ort, 10000);
    });

    test('satışlı ay: alım − satış', () {
      final ort = HedefRitmiService.sonUcAyOrtalamasi([
        alim(DateTime(2026, 1, 1), 100000),
        alim(DateTime(2026, 8, 3), 20000),
        alim(DateTime(2026, 9, 3), 10000),
        satis(DateTime(2026, 9, 20), 16000),
        alim(DateTime(2026, 10, 3), 4000),
      ], now: now);
      expect(ort, 6000); // (20000 + 10000 − 16000 + 4000) ÷ 3
    });

    test('silinmiş eski lot defteri uzatmaz', () {
      final silinmis = alim(DateTime(2026, 1, 1), 1000)
          .copyWithDeletedAt(DateTime(2026, 2, 1));
      expect(
          HedefRitmiService.sonUcAyOrtalamasi([
            silinmis,
            alim(DateTime(2026, 8, 3), 9000),
          ], now: now),
          isNull);
    });
  });

  group('HedefRitmi', () {
    test('ortalama ≥ gereken: plandasın', () {
      final r = HedefRitmi.kur(ortalama: 10000, gereken: 9000)!;
      expect(r.plandasin, isTrue);
      expect(r.eksik, 0);
      expect(HedefRitmi.kur(ortalama: 9000, gereken: 9000)!.plandasin, isTrue);
    });

    test('gerisinde: eksik = gereken − ortalama', () {
      final r = HedefRitmi.kur(ortalama: 10000, gereken: 15000)!;
      expect(r.plandasin, isFalse);
      expect(r.eklemeYok, isFalse);
      expect(r.eksik, 5000);
    });

    test('kıyas ekrandaki yuvarlanmış sayıyla', () {
      // 8.333,6 → ₺8.334 yazılır; "₺8.334 ekledin · ₺1 daha gerek" olmasın.
      final r = HedefRitmi.kur(ortalama: 8333.6, gereken: 8334)!;
      expect(r.ortalama, 8334);
      expect(r.plandasin, isTrue);
    });

    test('net satış ya da sıfır: ekleme yok, eksik = gereken', () {
      for (final o in [0.0, -6000.0]) {
        final r = HedefRitmi.kur(ortalama: o, gereken: 12000)!;
        expect(r.eklemeYok, isTrue, reason: '$o');
        expect(r.plandasin, isFalse);
        expect(r.eksik, 12000);
      }
    });

    test('ortalama ya da gereken yoksa: satır yok', () {
      expect(HedefRitmi.kur(ortalama: null, gereken: 1000), isNull);
      expect(HedefRitmi.kur(ortalama: 1000, gereken: null), isNull);
    });
  });
}
