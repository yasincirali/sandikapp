import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';

/// **Değişmez:** gün içi seriye hangi lot'un gireceğine TEK yer karar verir
/// (`FiyatKaynagi.seriyeGirer`).
///
/// ## Neden (kullanıcı bildirimi, 2026-09-22)
/// "ana sayfa günlük ben tabıyla performans tabındaki günlük ben kâr zarar
/// tutarsız."
///
/// Aynı defterden İKİ FARKLI seri çekiliyordu:
///   * Bugün kartı / `IntradaySeriesCache` → `state.activeAssets` (hepsi)
///   * Performans → ekranın KENDİ `isRenderable` kopyası (alt küme)
///
/// Ölçüldü: beş lotluk bir defterde Bugün kartı 5, Performans 2 lot ile
/// seri çekiyordu. Fiyatsız/tickersız lot'lar (elle fiyatlı fon, `diger`,
/// sembolsüz hisse) yalnızca birinde vardı; iki seri farklı olunca kâr/zarar
/// da farklı çıkıyordu — "Ben" kapsamında bile.
///
/// Bu, `fiyat_kaynagi.dart` sözleşmesinin (1) maddesinin ihlaliydi: bir
/// varlığın hangi seriden besleneceğine yalnızca orası karar verir. Ekranın
/// kendi kopyasını tutması, bu projede tekrar eden hata sınıfının bir
/// örneğiydi: **kod çalışıyor, sayı yanlış ve sessiz.**
Asset _lot({
  required String ticker,
  required AssetType type,
  double currentPrice = 0,
  bool manual = false,
  double qty = 10,
}) =>
    Asset(
      id: '$ticker-${type.name}-$qty',
      userId: 'ben',
      name: ticker.isEmpty ? 'isimsiz' : ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: manual,
      purchaseFxRate: 1,
      currentPrice: currentPrice,
      addedDate: DateTime(2026, 1, 1),
    );

void main() {
  group('seriyeGirer — kuralın kendisi', () {
    test('canlı fiyatı olan her lot girer', () {
      expect(
          FiyatKaynagi.seriyeGirer(
              _lot(ticker: 'THYAO', type: AssetType.hisse, currentPrice: 120)),
          isTrue);
      // Tür fark etmez: fiyat varsa çizilebilir.
      expect(
          FiyatKaynagi.seriyeGirer(
              _lot(ticker: '', type: AssetType.diger, currentPrice: 5)),
          isTrue);
    });

    test('miktarsız lot girmez', () {
      expect(
          FiyatKaynagi.seriyeGirer(_lot(
              ticker: 'THYAO',
              type: AssetType.hisse,
              currentPrice: 120,
              qty: 0)),
          isFalse);
    });

    test('altın fiyatsız da girer — seri gram22k\'dan türetilir', () {
      expect(
          FiyatKaynagi.seriyeGirer(
              _lot(ticker: 'ALTIN_GRAM', type: AssetType.altin)),
          isTrue);
    });

    test('sembolsüz hisse/emtia/döviz girmez', () {
      for (final t in [AssetType.hisse, AssetType.emtia, AssetType.doviz]) {
        expect(FiyatKaynagi.seriyeGirer(_lot(ticker: '', type: t)), isFalse,
            reason: '$t sembolsüz fiyatlanamaz');
      }
    });

    test('elle fiyatlanan fon girmez — yayımlanmış NAV serisi yok', () {
      expect(
          FiyatKaynagi.seriyeGirer(_lot(
              ticker: 'TEFAS:ABC', type: AssetType.fon, manual: true)),
          isFalse);
      expect(
          FiyatKaynagi.seriyeGirer(
              _lot(ticker: 'TEFAS:ABC', type: AssetType.fon)),
          isTrue);
    });

    test('diger türü fiyatsız girmez', () {
      expect(FiyatKaynagi.seriyeGirer(_lot(ticker: '', type: AssetType.diger)),
          isFalse);
    });
  });

  group('üç yüzey de AYNI kuralı kullanır', () {
    String oku(String yol) => File(yol)
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\s+'), ' ');

    test('Performans ekranı yerel kopya TUTMAZ', () {
      final src = oku('lib/screens/portfolio_performance_screen.dart');
      expect(src.contains('const isRenderable = FiyatKaynagi.seriyeGirer;'),
          isTrue,
          reason: 'eleme sözleşmeden gelmeli');
      // Eski yerel kopyanın imzası geri gelmesin.
      expect(src.contains('bool isRenderable(Asset a) {'), isFalse,
          reason: 'ekran kendi merdivenini kurmamalı '
              '(fiyat_kaynagi sözleşmesi, madde 1)');
    });

    test('Bugün kartı elemeyi uygular', () {
      final src = oku('lib/widgets/bugun_karti.dart');
      expect(src.contains('.where(FiyatKaynagi.seriyeGirer)'), isTrue,
          reason: 'ham activeAssets gönderilirse Performans\'tan '
              'farklı seri çıkar');
    });

    test('IntradaySeriesCache ("Ben" yolu) elemeyi uygular', () {
      final src = oku('lib/services/daily_summary.dart');
      expect(src.contains('.where(FiyatKaynagi.seriyeGirer)'), isTrue,
          reason: '"Ben" kapsamı bu önbellekten beslenir; eleme yoksa '
              'ana sayfa ile Performans ayrışır');
    });
  });

  test('değişmez: aynı defter → aynı lot kümesi', () {
    final defter = [
      _lot(ticker: 'THYAO', type: AssetType.hisse, currentPrice: 120),
      _lot(ticker: '', type: AssetType.hisse),
      _lot(ticker: 'TEFAS:ABC', type: AssetType.fon, manual: true),
      _lot(ticker: '', type: AssetType.diger),
      _lot(ticker: 'ALTIN_GRAM', type: AssetType.altin),
    ];

    final gecen = defter.where(FiyatKaynagi.seriyeGirer).toList();
    // Hangi yüzey olursa olsun bu küme aynı olmalı.
    expect(gecen.length, 2);
    expect(gecen.map((a) => a.ticker).toSet(), {'THYAO', 'ALTIN_GRAM'});
    // Eskiden Bugün kartı 5, Performans 2 lot gönderiyordu.
    expect(defter.length - gecen.length, 3,
        reason: 'ayrışan lot sayısı — eleme tek yerden gelmezse '
            'iki yüzey bu kadar lot farkıyla seri çeker');
  });
}
