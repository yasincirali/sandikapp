import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// Mevduat varlık sayfası (2026-10-01 emülatör testi).
///
/// Portföy satırından açılan sayfa `Position.asDisplayAsset()` ile kurulur.
/// İki hata birlikte görüldü: sözleşme kimliği taşınmadığı için dönem kartı
/// (vade, faiz, yenileme) hiç çizilmiyordu; başlık da `MEVDUAT:<uuid>`
/// sembolünden uuid'i yazıyordu.

const _sozlesme = '587b6d74-64b8-4c46-bbee-5946db29cf4f';

Asset _mevduatLotu({AssetType type = AssetType.mevduat, String? ticker}) =>
    Asset(
      id: 'lot-1',
      userId: 'u1',
      name: 'Enpara · Vadeli',
      ticker: ticker ?? mevduatSembolu(_sozlesme),
      type: type,
      quantity: 250000,
      purchasePrice: 1,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 1.3696,
      lastUpdated: DateTime(2026, 10, 1),
      addedDate: DateTime(2025, 3, 1),
      sozlesmeId: _sozlesme,
    );

void main() {
  test('asDisplayAsset sözleşme kimliğini taşır — dönem kartı bulunur', () {
    final p = aggregatePositions([_mevduatLotu()]).single;
    expect(p.asDisplayAsset().sozlesmeId, _sozlesme,
        reason: 'SozlesmeKarti kimlik null ise hiç çizilmez');
  });

  test('BES lotunda da taşınır', () {
    final p = aggregatePositions(
            [_mevduatLotu(type: AssetType.bes, ticker: 'TEFAS:AH5')])
        .single;
    expect(p.asDisplayAsset().sozlesmeId, _sozlesme);
  });

  group('kısa etiket', () {
    VarlikKimligi kimlik(String ticker, AssetType type) => VarlikKimligi(
          ticker: ticker,
          name: 'Enpara · Vadeli',
          type: type,
          currency: 'TRY',
        );

    test('mevduatta sözleşme uuid değil ad gösterilir', () {
      expect(kimlik(mevduatSembolu(_sozlesme), AssetType.mevduat).kisaEtiket,
          'Enpara · Vadeli');
    });

    test('BES lotunda fon kodu gösterilmeye devam eder', () {
      expect(kimlik('TEFAS:AH5', AssetType.bes).kisaEtiket, 'AH5');
    });
  });

  group('yenilemeden sonra seri önbelleği', () {
    tearDown(() {
      HistoryService.clearCache();
      HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    });

    test('sembolUnut eski seriyi atar — yeni dönem grafiğe yansır', () async {
      final sym = mevduatSembolu(_sozlesme);
      var birim = 1.37;
      HistoryService.seriCekici =
          (s, range, interval) async => [(1, birim), (2, birim)];

      final ilk = await HistoryService.instance.seriCek(sym, '1mo');
      birim = 1.41; // yeni dönem eklendi
      final onbellekten = await HistoryService.instance.seriCek(sym, '1mo');
      expect(onbellekten.last.$2, ilk.last.$2,
          reason: 'TTL içinde önbellek döner — hatanın kaynağı');

      HistoryService.instance.sembolUnut(sym);
      final taze = await HistoryService.instance.seriCek(sym, '1mo');
      expect(taze.last.$2, 1.41);
    });

    test('başka sembolün önbelleğine dokunmaz', () async {
      var birim = 100.0;
      HistoryService.seriCekici =
          (s, range, interval) async => [(1, birim)];
      await HistoryService.instance.seriCek('THYAO.IS', '1mo');
      birim = 200;
      HistoryService.instance.sembolUnut(mevduatSembolu(_sozlesme));
      final thy = await HistoryService.instance.seriCek('THYAO.IS', '1mo');
      expect(thy.single.$2, 100);
    });
  });
}
