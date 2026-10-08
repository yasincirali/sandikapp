import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/csv_import_service.dart';
import 'package:portfoy_takip/services/ekstre/tablo_anlama.dart';
import 'package:portfoy_takip/services/ekstre/tablo_okuyucular.dart';

/// Mağaza görsellerinin demo portföyü (`store_listing/DEMO_PORTFOY.md` v4).
///
/// Neden test: bu CSV'ler gerçek iPhone'da "Ekstreden içe aktar" ile
/// yüklenir ve 5. kare o ekranın kendisidir. Ayrıştırıcı değişip bir satır
/// yanlış türe düşerse (çıplak "BTC" fon, "Çeyrek Altın" gram) bunu çekim
/// günü telefonda görmek yerine burada görelim.
void main() {
  final bugun = DateTime(2026, 10, 3);

  CsvImportResult oku(String yol) {
    final bayt = Uint8List.fromList(File(yol).readAsBytesSync());
    final anlamlar = tablolariAnla(tablolariOku(bayt));
    expect(anlamlar, isNotEmpty, reason: '$yol tablo olarak anlaşılmadı');
    return CsvImportService.parse(anlamlar.first.kanonikMetin(), today: bugun);
  }

  test('ana demo: 7 satır, 5 tür, hepsi alış, hatasız', () {
    final r = oku('store_listing/demo_portfoy_v4.csv');
    expect(r.errors, isEmpty);
    expect(r.rows.map((x) => (x.type, x.quantity, x.price, x.satis)), [
      (AssetType.altin, 20.0, 7850.0, false),
      (AssetType.fon, 32000.0, 4.30, false),
      (AssetType.fon, 70000.0, 0.69, false),
      (AssetType.hisse, 620.0, 148.0, false),
      (AssetType.doviz, 2200.0, 38.50, false),
      (AssetType.hisse, 550.0, 93.50, false),
      (AssetType.kripto, 0.025, 3000000.0, false),
    ]);
    expect(r.rows.first.subCategory, 'Çeyrek Altın');
  });

  test('Ayşe: 24 ayar gram, euro, ortak KCHOL', () {
    final r = oku('store_listing/demo_portfoy_v4_ayse.csv');
    expect(r.errors, isEmpty);
    expect(r.rows.map((x) => (x.type, x.quantity, x.price)), [
      (AssetType.altin, 40.0, 5050.0),
      (AssetType.doviz, 1500.0, 48.80),
      (AssetType.hisse, 150.0, 150.0),
    ]);
    expect(r.rows.first.ticker, isNot('ALTIN_GRAM'),
        reason: '24 ayar 22 ayar gram sembolüne düşmemeli');
    expect(r.rows.last.ticker, 'KCHOL.IS');
  });
}
