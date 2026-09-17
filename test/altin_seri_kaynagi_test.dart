import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/price_service.dart';

/// **Altın grafiğindeki sapma neden ARALIKLI?**
///
/// Kullanıcı bildirimi (2026-09-17): "Her zaman da olmuyor, şu anda düzeldi.
/// Sebebi nedir, kök sebebi bul."
///
/// Kök sebep: altın serisinin KAYNAĞI istekten isteğe değişiyordu.
///
///   * `XAUTRY=X` **spot** altındır (ons/TRY, tek istek, çevrim yok),
///   * `GC=F` **COMEX vadeli sözleşmesi**dir — taşıma maliyeti yüzünden
///     spot'un yapısal olarak ~%1-2 üstünde işlem görür ve üstüne bir de
///     `USDTRY=X` çevrimi biner.
///
/// Gün içi yolu spot'u tercih edip boşsa vadeliye düşüyordu; uzun dönem
/// yolları (1H/1A/6A/1Y, takip listesi) ise VADELİYİ TEK KAYNAK sayıyordu.
/// Yahoo `XAUTRY=X` için bazen boş liste/404/429 döner ya da 8 saniyelik
/// çekim sınırını aşar; boş yanıt önbelleğe alınmadığı için her tazelemede
/// zar yeniden atılır. Seri bir açılışta spot, beş dakika sonra vadeli
/// ölçeğinde çiziliyordu — ve serinin son noktası canlı (yurt içi) fiyata
/// sabitlendiği için fark "ŞİMDİ" imlecinde sahte bir düşüş gibi
/// görünüyordu. "Bazen oluyor"un tamamı bu.
///
/// Bu test merdiveni davranış olarak kilitler: ağ yok, karar saf.
void main() {
  // Yolların kendi "en yakın geçmiş kur" kuralının test karşılığı.
  double? kurBul(Map<int, double> kur, int ts) {
    if (kur.isEmpty) return null;
    final keys = kur.keys.toList()..sort();
    double? out;
    for (final k in keys) {
      if (k <= ts) out = kur[k];
    }
    return out ?? kur[keys.first];
  }

  group('kaynak merdiveni', () {
    test('spot varsa SPOT kullanılır — vadeli hiç karışmaz', () {
      final sonuc = altinGramSerisi(
        xauTry: {1: 100000.0, 2: 100500.0},
        // Vadeli seri kasten ÇOK farklı: karışırsa sonuçtan anlaşılsın.
        xauUsd: {1: 5000.0, 2: 5025.0},
        usdTry: {1: 42.0, 2: 42.0},
        kurBul: kurBul,
      );
      expect(sonuc.kaynak, AltinSeriKaynagi.spotTry);
      expect(sonuc.seri[1], closeTo(PriceService.gram22kFromXauTry(100000), 1e-9));
      expect(sonuc.seri.length, 2);
    });

    test('spot BOŞSA vadeliye düşer (kur çevrimiyle)', () {
      final sonuc = altinGramSerisi(
        xauTry: const {},
        xauUsd: {1: 5000.0},
        usdTry: {1: 42.0},
        kurBul: kurBul,
      );
      expect(sonuc.kaynak, AltinSeriKaynagi.vadeliUsd);
      expect(sonuc.seri[1],
          closeTo(PriceService.gram22kFromXauTry(5000 * 42.0), 1e-9));
    });

    test('İKİ KAYNAK TEK SERİDE BİRLEŞMEZ', () {
      // Birleşseydi aradaki vadeli primi serinin ORTASINDA bir basamak
      // olurdu — kullanıcı için okunamaz, sahte bir "hareket".
      // Spot'ta 3, vadelide 4 nokta: kapsam yeterli, spot kazanmalı ve
      // vadelinin fazladan noktası seriye SIZMAMALI.
      final sonuc = altinGramSerisi(
        xauTry: {1: 100000.0, 2: 100000.0, 3: 100000.0},
        xauUsd: {1: 5000.0, 2: 5000.0, 3: 5000.0, 4: 5000.0},
        usdTry: {1: 42.0, 2: 42.0, 3: 42.0, 4: 42.0},
        kurBul: kurBul,
      );
      expect(sonuc.kaynak, AltinSeriKaynagi.spotTry);
      expect(sonuc.seri.keys.toList()..sort(), [1, 2, 3],
          reason: 'Vadeli noktalar spot serisine sızmış.');
      // Değerler de spot'tan: vadeli çevrimi 5000×42 = 210.000 ≠ 100.000.
      for (final v in sonuc.seri.values) {
        expect(v, closeTo(PriceService.gram22kFromXauTry(100000), 1e-9));
      }
    });

    test('kuru bilinmeyen nokta ATLANIR — uydurma kur YOK', () {
      // Eski hâl: 35.0 (günlük yol) ve 40.0 (tier yolu) sabitleri. Kur
      // serisi boş döndüğünde TÜM altın noktaları o uydurma kurla
      // fiyatlanıyor ve seri sessizce ~%17'ye varan sapma taşıyordu.
      final sonuc = altinGramSerisi(
        xauTry: const {},
        xauUsd: {1: 5000.0, 2: 5000.0},
        usdTry: const {},
        kurBul: kurBul,
      );
      expect(sonuc.seri, isEmpty);
      expect(sonuc.kaynak, AltinSeriKaynagi.yok);
      // Sabit kur geri gelmiş olsaydı seri dolu dönerdi ve hiçbir test
      // bunu yakalamazdı — asıl korunan değişmez bu.
    });

    test('hiç veri yoksa boş seri + "yok" kaynağı', () {
      final sonuc = altinGramSerisi(
        xauTry: const {},
        xauUsd: const {},
        usdTry: {1: 42.0},
        kurBul: kurBul,
      );
      expect(sonuc.seri, isEmpty);
      expect(sonuc.kaynak, AltinSeriKaynagi.yok);
    });

    test('spot KISA dönerse vadeliye düşülür — eksik geçmiş de yanlış veri', () {
      // Yahoo aynı range için iki sembole farklı uzunlukta seri verebiliyor.
      // Koşulsuz "spot doluysa spot" kuralı 1Y grafiğini üç noktaya
      // indirebilirdi: sapma yerine eksik geçmiş, aynı sınıf yanlış gösterim.
      final xauUsd = {for (int i = 1; i <= 100; i++) i: 5000.0};
      final usdTry = {for (int i = 1; i <= 100; i++) i: 42.0};
      final kisaSpot = {98: 210000.0, 99: 210000.0, 100: 210000.0};

      expect(
        altinGramSerisi(
                xauTry: kisaSpot,
                xauUsd: xauUsd,
                usdTry: usdTry,
                kurBul: kurBul)
            .kaynak,
        AltinSeriKaynagi.vadeliUsd,
      );

      // Kapsam yeterliyse yine spot kazanır (birkaç eksik bar sorun değil).
      final tamSpot = {for (int i = 1; i <= 90; i++) i: 210000.0};
      expect(
        altinGramSerisi(
                xauTry: tamSpot,
                xauUsd: xauUsd,
                usdTry: usdTry,
                kurBul: kurBul)
            .kaynak,
        AltinSeriKaynagi.spotTry,
      );
    });

    test('spot yolu kur serisine HİÇ bakmaz', () {
      // Spot zaten TRY kotedir; kur serisi boşken de çalışmalı. Aksi halde
      // `USDTRY=X` düştüğünde altın grafiği spot veri varken de boşalırdı.
      final sonuc = altinGramSerisi(
        xauTry: {1: 100000.0},
        xauUsd: const {},
        usdTry: const {},
        kurBul: kurBul,
      );
      expect(sonuc.kaynak, AltinSeriKaynagi.spotTry);
      expect(sonuc.seri.length, 1);
    });
  });

  group('vadeli primi ölçek farkı yaratır', () {
    test('aynı an, iki kaynak, farklı seviye — grafikte basamak demek', () {
      // Vadeli sözleşme spot'un üstünde işlem görür (taşıma maliyeti).
      // Rakamlar temsilîdir; ölçülen şey FARKIN GRAFİĞE YANSIDIĞIDIR.
      const spotOnsTry = 210000.0;
      const vadeliOnsUsd = 5100.0; // × 42 = 214.200 → %2 primli
      const kur = 42.0;

      final spot = altinGramSerisi(
        xauTry: {1: spotOnsTry},
        xauUsd: {1: vadeliOnsUsd},
        usdTry: {1: kur},
        kurBul: kurBul,
      ).seri[1]!;
      final vadeli = altinGramSerisi(
        xauTry: const {},
        xauUsd: {1: vadeliOnsUsd},
        usdTry: {1: kur},
        kurBul: kurBul,
      ).seri[1]!;

      final fark = (vadeli - spot) / spot;
      expect(fark, greaterThan(0.005),
          reason: 'İki kaynak aynı seviyeyi veriyorsa bu test anlamını '
              'yitirmiş demektir.');
      // Ekran görüntüsündeki sahte düşüş de bu mertebedeydi (~%1,7).
    });
  });

  group('DÖRT yol da aynı merdivenden geçer', () {
    // Merdivenin kopyalanması bu arızanın kök sebebiydi: gün içi yolu spot'u
    // biliyordu, diğer üçü bilmiyordu.
    final servis = File('lib/services/history_service.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    test('her altın yolu `altinGramSerisi` çağırır', () {
      final cagri = 'altinGramSerisi('.allMatches(servis).length;
      // 1 tanım + 4 kullanım (gün içi, günlük, tier, tek sembol).
      expect(cagri, greaterThanOrEqualTo(5),
          reason: 'Bir yol merdivenin dışında kalmış — o yolda altın yine '
              'vadeli ölçeğinde çizilir.');
    });

    test('hiçbir yol `GC=F` çekerken `XAUTRY=X` çekmeyi atlamaz', () {
      final gcf = "'GC=F'".allMatches(servis).length;
      final xau = "'XAUTRY=X'".allMatches(servis).length;
      expect(xau, greaterThanOrEqualTo(gcf),
          reason: 'Vadeli çekilip spot çekilmeyen bir yol var.');
    });

    test('altın çevriminde sabit kur varsayılanı KALMADI', () {
      // `usdRate = 35.0` (günlük yol) ve `_closestOrNull(usdMap, ts) ?? 40.0`
      // (tier yolu) tam olarak bu satırlardı.
      expect(servis.contains('double usdRate = 35.0;'), isFalse,
          reason: 'Günlük altın yolunda uydurma kur geri gelmiş.');
      expect(servis.contains('final usdRate = _closestOrNull(usdMap, ts) ?? 40.0;'),
          isFalse,
          reason: 'Tier altın yolunda uydurma kur geri gelmiş.');
    });

    test('kullanılan kaynak DIŞARIDAN görülebilir', () {
      // "Bazen oluyor" tipi bir bildirimde bakılacak yer: hangi kaynak
      // kullanıldı. Yerel bir karar olarak kalırsa bir daha ölçülemez.
      expect(servis.contains('debugSonAltinKaynagi'), isTrue);
    });
  });
}
