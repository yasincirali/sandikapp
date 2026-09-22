import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';

/// Kullanıcı isteği (2026-09-23): *"getirdiği temettüyü de portföy sayfasında
/// collapsable içerisinde varsa gösterilmeli toplam temettü."*
///
/// Üst kart portföy GENELİ temettüyü "Bunun temettüsü" satırıyla açıklıyordu
/// ama POZİSYON bazında bu bilgi hiçbir yerde yoktu: "bu hisseden ne temettü
/// aldım" sorusunun cevabı yalnızca hareket geçmişini elle toplayarak
/// bulunabiliyordu.
///
/// ## Bu dosya neyi kilitler
/// 1. Satır YALNIZCA temettü varsa çıkar (boş "₺0" gürültüdür).
/// 2. Pozisyon satırlarının toplamı ÜST KARTLA tutar — "Σ parça == bütün".
/// 3. Tamamen satılmış pozisyonun temettüsü kaybolmaz.
Asset _lot({
  required String id,
  String ticker = 'THYAO',
  String userId = 'ben',
  double qty = 10,
  double buy = 100,
  double cur = 120,
  AssetKind kind = AssetKind.buy,
  double? sellPrice,
  double dividend = 0,
  double fx = 1,
  String currency = 'TRY',
}) =>
    Asset(
      id: id,
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: buy,
      currency: currency,
      notes: '',
      isManualPrice: false,
      purchaseFxRate: fx,
      currentPrice: cur,
      addedDate: DateTime(2026, 1, 1),
      kind: kind,
      sellPrice: sellPrice,
      dividendAmount: dividend,
    );

/// `_AssetDetailsPanel` ile AYNI hesap (`totalDividendTRY(position.lots)`).
double _panelTemettusu(Position p) => totalDividendTRY(p.lots);

void main() {
  group('satır görünürlüğü', () {
    test('temettü YOKSA satır çıkmaz', () {
      final p = aggregatePositions([_lot(id: 'b1')]).single;
      expect(_panelTemettusu(p), 0.0,
          reason: 'eşik 0,005 — satır çizilmemeli');
    });

    test('temettü VARSA satır çıkar', () {
      final p = aggregatePositions([
        _lot(id: 'b1'),
        _lot(id: 'd1', qty: 0, kind: AssetKind.dividend, dividend: 250),
      ]).single;
      expect(_panelTemettusu(p), 250.0);
    });

    test('silinmiş temettü sayılmaz', () {
      final silinmis = Asset(
        id: 'd1',
        userId: 'ben',
        name: 'THYAO',
        ticker: 'THYAO',
        type: AssetType.hisse,
        quantity: 0,
        purchasePrice: 0,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        purchaseFxRate: 1,
        currentPrice: 0,
        addedDate: DateTime(2026, 1, 1),
        kind: AssetKind.dividend,
        dividendAmount: 250,
        deletedAt: DateTime(2026, 6, 1),
      );
      final p = aggregatePositions([_lot(id: 'b1'), silinmis]).single;
      expect(_panelTemettusu(p), 0.0,
          reason: 'silinen temettü cebe girmemiş sayılır');
    });
  });

  group('Σ parça == bütün', () {
    test('pozisyon satırlarının toplamı ÜST KARTLA tutar', () {
      final assets = [
        _lot(id: 'b1', ticker: 'THYAO'),
        _lot(
            id: 'd1',
            ticker: 'THYAO',
            qty: 0,
            kind: AssetKind.dividend,
            dividend: 250),
        _lot(id: 'b2', ticker: 'KCHOL'),
        _lot(
            id: 'd2',
            ticker: 'KCHOL',
            qty: 0,
            kind: AssetKind.dividend,
            dividend: 130),
      ];
      final st = PortfolioState(assets: assets);

      final panelToplami = aggregatePositions(assets)
          .fold<double>(0, (t, p) => t + _panelTemettusu(p));

      expect(panelToplami, closeTo(st.totalDividend, 0.01),
          reason: 'panel satırları üst kartı açıklamalı; ayrışırsa '
              'kullanıcı toplayıp tutturamaz');
      expect(st.totalDividend, 380.0);
    });

    test('TRY ölçeğinde — döviz pozisyonunda kur uygulanır', () {
      // `position.totalDividend` alım para birimindedir; panel TRY gösterir.
      // Yanlış alan kullanılsaydı USD bir hissede rakam 40 kat küçük çıkardı.
      final p = aggregatePositions([
        _lot(id: 'b1', currency: 'USD', fx: 40),
        _lot(
            id: 'd1',
            currency: 'USD',
            fx: 40,
            qty: 0,
            kind: AssetKind.dividend,
            dividend: 10),
      ]).single;
      expect(_panelTemettusu(p), 400.0,
          reason: '10 USD × 40 = ₺400 (ödeme günü kuruyla)');
      expect(p.totalDividend, 10.0,
          reason: 'ham alan USD kalır — panel bunu KULLANMAMALI');
    });
  });

  group('kapanmış pozisyon', () {
    test('tamamen satılan pozisyon listeden düşer ama temettü ÜST KARTTA kalır',
        () {
      final assets = [
        _lot(id: 'b1', qty: 10),
        _lot(id: 's1', qty: 10, kind: AssetKind.sell, sellPrice: 130),
        _lot(id: 'd1', qty: 0, kind: AssetKind.dividend, dividend: 250),
      ];
      final st = PortfolioState(assets: assets);

      expect(aggregatePositions(assets), isEmpty,
          reason: 'elde hiçbir şey yok — panel satırı da yok');
      expect(st.totalDividend, 250.0,
          reason: 'temettü cebe girmişti; üst kartta GÖRÜNMELİ');
    });
  });

  group('sahip sınırı', () {
    test('ortağın temettüsü benim satırıma girmez', () {
      final ben = [
        _lot(id: 'b1', userId: 'ben'),
        _lot(
            id: 'd1',
            userId: 'ben',
            qty: 0,
            kind: AssetKind.dividend,
            dividend: 100),
      ];
      final ortak = [
        _lot(id: 'o1', userId: 'ortak'),
        _lot(
            id: 'od1',
            userId: 'ortak',
            qty: 0,
            kind: AssetKind.dividend,
            dividend: 60),
      ];

      // Panel her sahibin KENDİ pozisyonunu çizer.
      final benimPozisyonlar = aggregatePositionsByOwner([ben]);
      final benimToplam = benimPozisyonlar.fold<double>(
          0, (t, p) => t + _panelTemettusu(p));
      expect(benimToplam, 100.0, reason: 'ortağın ₺60ı benim satırımda olamaz');

      // Birlikte görünümünde ikisi ayrı satır, toplamları tutar.
      final birlikte = aggregatePositionsByOwner([ben, ortak]);
      final birlikteToplam =
          birlikte.fold<double>(0, (t, p) => t + _panelTemettusu(p));
      expect(birlikteToplam, 160.0);
    });
  });
}
