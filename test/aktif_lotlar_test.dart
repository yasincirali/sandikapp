import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';

/// Net miktarı 0'a düşmüş pozisyonlar ÖN YÜZDE görünmemeli —
/// ama GEÇMİŞ bozulmamalı.
///
/// ## Kullanıcı bildirimi (TestFlight 2026-09-11)
/// Tamamen satılan bir hisse portföyde "hayalet" olarak yaşamaya devam
/// ediyordu: fiyat alarmı adayı olarak çıkıyor, takip listesine eklemeyi
/// engelliyor, karşılaştırma listesinde görünüyordu.
///
/// ## Neden `deletedAt` DEĞİL
/// Kapanmış pozisyonun lot'ları GEÇMİŞİN kendisidir: `HistoryService` her
/// gün için "o gün geçerli net miktar"ı bu satırlardan kuruyor. Alım
/// lot'una `deletedAt` basmak `isActive`'i false yapar ve satıştan ÖNCEKİ
/// dönem grafikten + tüm periyot hesaplarından kaybolur — satılmış varlık
/// hiç alınmamış gibi görünür.
///
/// Bu yüzden kapanmışlık DB'ye YAZILMIYOR, okuma anında türetiliyor.
/// Aşağıdaki son grup tam olarak bunu kilitliyor.
Asset _lot({
  required String id,
  required AssetKind kind,
  required double qty,
  String ticker = 'THYAO.IS',
  AssetType type = AssetType.hisse,
  DateTime? tarih,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Test',
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      kind: kind,
      addedDate: tarih ?? DateTime(2026, 1, 1),
    );

void main() {
  group('kapanmış pozisyon ön yüzden DÜŞER', () {
    test('tamamı satılmış hisse elenir', () {
      final defter = [
        _lot(id: 'a1', kind: AssetKind.buy, qty: 10),
        _lot(id: 's1', kind: AssetKind.sell, qty: 10),
      ];
      expect(aktifLotlar(defter), isEmpty,
          reason: 'Net 0 pozisyon hâlâ aktif sayılıyor.');
    });

    test('KISMEN satılmış pozisyon KALIR', () {
      // Asıl risk: fazla eleme. 10 alıp 4 satan kullanıcı 6 lot tutuyor.
      final defter = [
        _lot(id: 'a1', kind: AssetKind.buy, qty: 10),
        _lot(id: 's1', kind: AssetKind.sell, qty: 4),
      ];
      expect(aktifLotlar(defter).length, 2,
          reason: 'Kısmen satılmış pozisyon yanlışlıkla elendi.');
    });

    test('hiç satılmamış pozisyon KALIR', () {
      final defter = [_lot(id: 'a1', kind: AssetKind.buy, qty: 10)];
      expect(aktifLotlar(defter).length, 1);
    });

    test('sadece temettü satırı olan pozisyon elenir', () {
      // `quantity: 0` temettü satırı tek başına "varlık var" demek değil.
      final defter = [_lot(id: 'd1', kind: AssetKind.dividend, qty: 0)];
      expect(aktifLotlar(defter), isEmpty);
    });

    test('silinmiş lot zaten elenir (`deletedAt`)', () {
      final defter = [
        _lot(id: 'a1', kind: AssetKind.buy, qty: 10)
            .copyWithDeletedAt(DateTime(2026, 2, 1)),
      ];
      expect(aktifLotlar(defter), isEmpty);
    });

    test('bir sembol kapalı, diğeri açık — yalnızca kapalı düşer', () {
      final defter = [
        _lot(id: 'a1', kind: AssetKind.buy, qty: 10, ticker: 'THYAO.IS'),
        _lot(id: 's1', kind: AssetKind.sell, qty: 10, ticker: 'THYAO.IS'),
        _lot(id: 'a2', kind: AssetKind.buy, qty: 5, ticker: 'GARAN.IS'),
      ];
      final aktif = aktifLotlar(defter);
      expect(aktif.length, 1);
      expect(aktif.single.ticker, 'GARAN.IS');
    });
  });

  group('GEÇMİŞ bozulmaz — defter olduğu gibi durur', () {
    test('kapanmış pozisyonun lot\'ları SİLİNMEZ', () {
      final defter = [
        _lot(id: 'a1', kind: AssetKind.buy, qty: 10),
        _lot(id: 's1', kind: AssetKind.sell, qty: 10),
      ];
      // `aktifLotlar` bir FİLTRE döndürür; kaynağa dokunmaz.
      expect(aktifLotlar(defter), isEmpty);
      expect(defter.length, 2, reason: 'Ham defter değiştirilmiş.');
      expect(defter.every((l) => l.isActive), isTrue,
          reason: 'Kapanmış pozisyona `deletedAt` basılmış — satıştan '
              'önceki dönem grafikten kaybolur.');
    });

    test('kapanmışlık DB alanı DEĞİL — `deletedAt` null kalır', () {
      final alim = _lot(id: 'a1', kind: AssetKind.buy, qty: 10);
      final satis = _lot(id: 's1', kind: AssetKind.sell, qty: 10);
      aktifLotlar([alim, satis]);

      expect(alim.deletedAt, isNull);
      expect(satis.deletedAt, isNull);
      expect(alim.isActive, isTrue,
          reason: 'Alım lot\'u pasifleştirilmiş; `HistoryService` o günleri '
              'artık hesaplayamaz.');
    });
  });

  group('çağrı yerleri ham listeyi GEZMİYOR', () {
    String oku(String yol) =>
        File(yol).readAsStringSync().replaceAll('\r\n', '\n');

    test('fiyat alarmı adayları', () {
      final k = oku('lib/screens/price_alerts_screen.dart');
      expect(k.contains('aktifLotlar('), isTrue,
          reason: 'Satılmış hisse yine alarm adayı olur.');
    });

    test('takip listesine ekleme', () {
      final k = oku('lib/screens/add_watchlist_screen.dart');
      expect(k.contains('aktifLotlar('), isTrue,
          reason: 'Satılmış hisse "zaten portföyünde" diye takip '
              'listesine eklenemez.');
    });

    test('karşılaştırma seçici', () {
      final k = oku('lib/screens/asset_detail_screen.dart');
      expect(k.contains('aktifLotlar('), isTrue,
          reason: 'Satılmış varlık karşılaştırma listesinde çıkar.');
    });
  });
}
