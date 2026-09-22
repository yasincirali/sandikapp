import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/price_service.dart';

/// Kullanıcı bildirimi (2026-09-23): *"Ben seçiliyken Bugün kartında −76 ile
/// 366 arasında oynuyor."*
///
/// ## Kök neden
/// `altinKalibrasyonHaritasi` çarpanı serinin SON noktasından türetiyordu.
/// O nokta her fetch'te oynar (vadeli sözleşme sürekli kote edilir) ve çarpan
/// TÜM seriyi ölçeklediği için GÜN BAŞI da her tazelemede yerinden
/// oynuyordu. Sonuç: canlı fiyat hiç değişmeden "bugünkü değişim" salınıyordu.
///
/// Ölçüldü (düzeltme öncesi): canlı çeyrek ₺8.000'de SABİT iken gram
/// serisinin son noktası 4990→5005 arasında oynayınca günlük değişim
/// ₺9.436 → ₺9.887 arasında geziniyordu — **₺451'lik hayalet hareket**.
///
/// ## Düzeltme
/// Çapa olarak serinin İLK noktası (seans başı) alınır. Gün başı seans içinde
/// değişmez; tazeleme uca nokta ekler ama tabanı oynatmaz.
///
/// Bu dosya çarpanın KARARLILIĞINI kilitler. Çapa yeniden son noktaya
/// bağlanırsa ilk test kırılır.
Asset _altin({
  String ticker = 'ALTIN_CEYREK',
  double cur = 8000,
  double qty = 20,
}) =>
    Asset(
      id: 'a_$ticker',
      userId: 'ben',
      name: ticker,
      ticker: ticker,
      type: AssetType.altin,
      subCategory: ticker,
      quantity: qty,
      purchasePrice: 7500,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1,
      currentPrice: cur,
      addedDate: DateTime(2026, 1, 1),
    );

/// Seans başı SABİT, uç oynak — gerçek tazeleme davranışı.
Map<int, double> _seri({required double sonGram, double gunBasiGram = 4980}) => {
      DateTime(2026, 9, 23, 10).millisecondsSinceEpoch: gunBasiGram,
      DateTime(2026, 9, 23, 14).millisecondsSinceEpoch: sonGram,
    };

void main() {
  group('çarpan kararlılığı', () {
    test('serinin UCU oynarken çarpan DEĞİŞMEZ', () {
      // Bu, bildirilen arızanın doğrudan kilidi.
      final carpanlar = <double>{};
      for (final sonGram in [4990.0, 4995.0, 5000.0, 5005.0, 5010.0]) {
        final k = altinKalibrasyonHaritasi(
          assets: [_altin()],
          gramSerisi: _seri(sonGram: sonGram),
          kaynak: AltinSeriKaynagi.vadeliUsd,
        );
        carpanlar.add(k['ALTIN_CEYREK']!);
      }
      expect(carpanlar, hasLength(1),
          reason: 'uç oynadıkça çarpan değişiyorsa gün başı da oynar — '
              'canlı fiyat sabitken sahte günlük hareket görünür');
    });

    test('GÜN BAŞI değişirse çarpan DEĞİŞİR (yeni seans)', () {
      // Kontrol: çapa gerçekten gün başına bağlı mı? Sabit bir sayı
      // döndürseydi bu test de geçerdi — yani test tautolojik değil.
      final a = altinKalibrasyonHaritasi(
        assets: [_altin()],
        gramSerisi: _seri(sonGram: 5000, gunBasiGram: 4980),
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;
      final b = altinKalibrasyonHaritasi(
        assets: [_altin()],
        gramSerisi: _seri(sonGram: 5000, gunBasiGram: 4900),
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;
      expect(a, isNot(closeTo(b, 1e-9)),
          reason: 'çapa gün başıdır — o değişince çarpan da değişmeli');
    });

    test('CANLI fiyat oynayınca çarpan değişir (doğru davranış)', () {
      // `currentPrice` gerçek bir ölçümdür; onun etkisi KALMALI.
      final ucuz = altinKalibrasyonHaritasi(
        assets: [_altin(cur: 8000)],
        gramSerisi: _seri(sonGram: 5000),
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;
      final pahali = altinKalibrasyonHaritasi(
        assets: [_altin(cur: 8200)],
        gramSerisi: _seri(sonGram: 5000),
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;
      expect(ucuz, isNot(closeTo(pahali, 1e-9)));
    });
  });

  group('günlük değişim kararlılığı — uçtan uca', () {
    /// Çarpanla ölçeklenmiş gün başı portföy değeri.
    double gunBasiDeger(double sonGram) {
      final k = altinKalibrasyonHaritasi(
        assets: [_altin()],
        gramSerisi: _seri(sonGram: sonGram),
        kaynak: AltinSeriKaynagi.vadeliUsd,
      )['ALTIN_CEYREK']!;
      final agirlik = PriceService.goldWeightFactor('ALTIN_CEYREK');
      return 4980.0 * agirlik * k * 20;
    }

    test('canlı fiyat SABİTken günlük değişim SALINMAZ', () {
      final degerler = <double>{};
      for (final sonGram in [4990.0, 4995.0, 5000.0, 5005.0]) {
        // Kuruş altı gürültüyü ele — ölçülen şey salınım, yuvarlama değil.
        degerler.add((gunBasiDeger(sonGram) * 100).roundToDouble() / 100);
      }
      expect(degerler, hasLength(1),
          reason: 'ölçüldü (düzeltme öncesi): ₺9.436 → ₺9.887 arası '
              '₺451 hayalet hareket');
    });
  });

  group('bozulmadı (regresyon)', () {
    test('tek noktalı seride çapa yine tanımlı', () {
      final k = altinKalibrasyonHaritasi(
        assets: [_altin()],
        gramSerisi: {DateTime(2026, 9, 23, 14).millisecondsSinceEpoch: 5000.0},
        kaynak: AltinSeriKaynagi.vadeliUsd,
      );
      expect(k['ALTIN_CEYREK'], isNotNull,
          reason: 'ilk == son; çarpan yine hesaplanmalı');
      expect(k['ALTIN_CEYREK'], greaterThan(0));
    });

    test('boş seri boş harita döndürür', () {
      expect(
          altinKalibrasyonHaritasi(
              assets: [_altin()], gramSerisi: const {}),
          isEmpty);
    });

    test('fiyatsız altın çarpan almaz — uydurma yok', () {
      expect(
          altinKalibrasyonHaritasi(
            assets: [_altin(cur: 0)],
            gramSerisi: _seri(sonGram: 5000),
          ),
          isEmpty);
    });

    test('her AYAR kendi çarpanını alır', () {
      final k = altinKalibrasyonHaritasi(
        assets: [
          _altin(ticker: 'ALTIN_GRAM', cur: 5000),
          _altin(ticker: 'ALTIN_CEYREK', cur: 8200),
        ],
        gramSerisi: _seri(sonGram: 5000),
        kaynak: AltinSeriKaynagi.vadeliUsd,
      );
      expect(k.keys, containsAll(['ALTIN_GRAM', 'ALTIN_CEYREK']),
          reason: 'gram ile çeyreğin makası aynı değildir');
    });
  });
}
