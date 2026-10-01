import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/tefas_service.dart';

/// Devlet katkısı fonu tanıma (2026-10-01 emülatör testi).
///
/// TEFAS'taki gerçek adlarda "DEVLET" geçmez; seçici yalnız "DEVLET KATKI"
/// aradığı için hiçbir fonu tanımıyor, BES formunda devlet katkısı
/// girilemiyordu. Adlar TEFAS `fonGetiriBazliBilgiGetir` (EMK, islem: 0)
/// yanıtından birebir alındı.
void main() {
  test('TEFAS katkı fonu adları tanınır', () {
    for (final ad in const [
      'AGESA HAYAT VE EMEKLİLİK A.Ş. KATKI EMEKLİLİK YATIRIM FONU',
      'AGESA HAYAT VE EMEKLİLİK A.Ş. KATILIM KATKI EMEKLİLİK YATIRIM FONU',
      'ANADOLU HAYAT EMEKLİLİK A.Ş. KATKI EMEKLİLİK YATIRIM FONU',
    ]) {
      expect(devletKatkisiAdiMi(ad), isTrue, reason: ad);
    }
  });

  test('eski "DEVLET KATKISI" biçimi ve küçük harfli önbellek kaydı', () {
    expect(devletKatkisiAdiMi('X EMEKLİLİK DEVLET KATKISI FONU'), isTrue);
    expect(devletKatkisiAdiMi('agesa katkı emeklilik yatırım fonu'), isTrue);
  });

  test('katılımcının kendi fonları katkı fonu sayılmaz', () {
    for (final ad in const [
      'AGESA HAYAT VE EMEKLİLİK A.Ş. ALTIN KATILIM EMEKLİLİK YATIRIM FONU',
      'AGESA HAYAT VE EMEKLİLİK A.Ş. HİSSE SENEDİ EMEKLİLİK YATIRIM FONU',
      'ALLIANZ YAŞAM VE EMEKLİLİK A.Ş. KATILIM STANDART EMEKLİLİK YATIRIM FONU',
    ]) {
      expect(devletKatkisiAdiMi(ad), isFalse, reason: ad);
    }
  });
}
