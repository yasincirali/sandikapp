import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';

/// Ana ekran boş durumu AÇIK POZİSYONA bakar, ham satır sayısına değil.
///
/// ## Ölçülen arıza (kullanıcı bildirimi + ekran görüntüsü, 2026-09-16)
/// Tamamı satılmış bir portföyde ekran kendi içinde çelişiyordu:
///
///   TOPLAM NET VARLIK  ₺0
///   ▲ 2,64 puan enflasyonun öndesin      ← sıfır lirayla?
///   ▲ Bu hafta piyasadan %82,3 artı      ← sıfır lirayla?
///
/// Sebep: kapı `myState.assets.isEmpty` idi ve ham defter alım + satım
/// satırlarını tutuyor. Net miktar sıfır olsa bile liste "boş değil"
/// çıkıyor, şeritler çiziliyordu.
void main() {
  Asset lot({
    required String id,
    required AssetKind kind,
    required double qty,
    DateTime? tarih,
    DateTime? deletedAt,
  }) =>
      Asset(
        id: id,
        userId: 'u',
        name: 'AVOD',
        ticker: 'AVOD.IS',
        type: AssetType.hisse,
        quantity: qty,
        purchasePrice: 3910,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 3910,
        addedDate: tarih ?? DateTime(2026, 9, 16),
        kind: kind,
        deletedAt: deletedAt,
      );

  group('boşluk ölçüsü', () {
    test('tamamı satılmış portföy BOŞ sayılır', () {
      // Ekran görüntüsündeki durum: 1.000 lot alım + 1.000 lot satım.
      final defter = [
        lot(id: 'alim', kind: AssetKind.buy, qty: 1000),
        lot(id: 'satim', kind: AssetKind.sell, qty: 1000),
      ];
      expect(defter.isEmpty, isFalse, reason: 'ham defter dolu — eski kapı');
      expect(aktifLotlar(defter), isEmpty,
          reason: 'net miktar sıfır; bugünkü mülkiyet yok');
    });

    test('kısmen satılmış portföy BOŞ DEĞİL', () {
      final defter = [
        lot(id: 'alim', kind: AssetKind.buy, qty: 1000),
        lot(id: 'satim', kind: AssetKind.sell, qty: 400),
      ];
      expect(aktifLotlar(defter), isNotEmpty,
          reason: '600 lot duruyor — şeritler çizilmeli');
    });

    test('silinmiş varlık da BOŞ sayılır', () {
      final defter = [
        lot(
          id: 'alim',
          kind: AssetKind.buy,
          qty: 1000,
          deletedAt: DateTime(2026, 9, 16),
        ),
      ];
      expect(aktifLotlar(defter), isEmpty);
    });

    test('hiç kayıt yoksa BOŞ — ilk kullanım', () {
      expect(aktifLotlar(const <Asset>[]), isEmpty);
    });

    test('açık pozisyon varsa BOŞ DEĞİL', () {
      expect(
        aktifLotlar([lot(id: 'a', kind: AssetKind.buy, qty: 100)]),
        isNotEmpty,
      );
    });
  });

  group('kaynak kilidi', () {
    test('ana ekran aktifLotlar ile ölçer, assets.isEmpty ile değil', () {
      final src = File('lib/screens/home_screen.dart').readAsStringSync();
      expect(src.contains('aktifLotlar(myState.assets).isEmpty'), isTrue,
          reason: 'boşluk ölçüsü bugünkü mülkiyeti sormalı');
      expect(src.contains('ownView && myState.assets.isEmpty'), isFalse,
          reason: 'ham defter satılmış lotları da sayıyor — çelişki doğurur');
    });
  });
}
