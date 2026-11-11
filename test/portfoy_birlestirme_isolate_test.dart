import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// Portföy serisi birleştirmesi ayrı isolate'te (2026-11-11).
///
/// `getPortfolioHistoryBreakdownAtResolution` serileri çektikten sonra her
/// slot × lot için fiyat arıyor; 40 varlık × 5 yıl günlükte bu adım ana iş
/// parçacığında kare bütçesini (16 ms) çok aşıyordu. Birleştirme saf
/// fonksiyona çıktı ve büyük girdide `Isolate.run`'a (`compute`) gidiyor.
///
/// Kilit: isolate'li ve isolate'siz yol BİREBİR aynı sonucu verir (toplam,
/// tür ve ürün dökümü, pozisyon türü) — tam hassasiyetle, tolerans yok.
/// Ölçüm testi süreyi yalnız yazar (JIT; makineye göre değişir), eşiğin
/// gerekçesi `portfoyBirlesimIsolateEsigi` yorumunda.
void main() {
  const gunMs = 24 * 60 * 60 * 1000;

  /// Demo girdi: [varlik] varlık × 3 lot, [yil] yıl günlük ızgara. Hisse,
  /// USD kote hisse, altın (iki ağırlık), satış, temettü, silinmiş lot ve
  /// seriye sahip olmayan (canlı fiyata düşen) varlık karışık.
  PortfoyBirlesimGirdisi demo(int varlik, int yil) {
    final bugun = DateTime(2026, 11, 11).millisecondsSinceEpoch;
    final bas = bugun - 365 * yil * gunMs;
    Map<int, double> seri(double taban) => {
          for (var g = 0; g <= 365 * yil + 10; g++)
            if (DateTime.fromMillisecondsSinceEpoch(bas + (g - 10) * gunMs)
                    .weekday <
                6)
              bas + (g - 10) * gunMs:
                  taban + (g % 37) * 0.3 + (g % 101 == 0 ? taban * 0.05 : 0),
        };
    final lotlar = <PortfoyBirlesimLotu>[];
    final seriler = <String, Map<int, double>>{};
    for (var i = 0; i < varlik; i++) {
      final altin = i % 10 == 3;
      final usd = !altin && i % 8 == 7;
      final serisiz = i % 13 == 12;
      final ticker = altin
          ? (i % 20 == 3 ? 'ALTIN_CEYREK' : 'ALTIN_GRAM')
          : (usd ? 'US$i' : 'T$i.IS');
      if (!altin && !serisiz) seriler[ticker] = seri(20.0 + i);
      for (var l = 0; l < 3; l++) {
        final satis = l == 2 && i % 5 == 0;
        lotlar.add(PortfoyBirlesimLotu(
          tur: altin ? AssetType.altin : AssetType.hisse,
          ticker: ticker,
          pozisyon: '$ticker|${altin ? 'altin' : 'hisse'}',
          isaretliMiktar: satis ? -(10.0 + l) : 10.0 + l,
          eklenmeMs: bas + (l * 90 + i) * gunMs,
          silinmis: i % 17 == 16 && l == 0,
          miktarNotr: l == 1 && i % 9 == 0,
          seriliFiyat: !altin,
          usd: usd,
          guncelFiyat: 12.5,
          altinAgirligi: i % 20 == 3 ? 1.75 : 1.0,
          altinKalibrasyonu: 1.013,
        ));
      }
    }
    return PortfoyBirlesimGirdisi(
      lotlar: lotlar,
      tickerSerileri: seriler,
      usdSerisi: seri(30.0),
      altinGramSerisi: seri(3000.0),
      bas: bas,
      son: bugun,
      simdi: bugun,
      adimMs: gunMs,
      haftaSonuAtla: false,
      simulate: false,
      canliKur: 34.2,
    );
  }

  String imza(PortfolioHistoryBreakdown b) {
    final sb = StringBuffer();
    for (final e in b.total.entries) {
      sb.write('${e.key}=${e.value};');
    }
    for (final t in b.byType.entries) {
      for (final e in t.value.entries) {
        sb.write('${t.key.name}@${e.key}=${e.value};');
      }
    }
    for (final t in b.byPosition.entries) {
      for (final e in t.value.entries) {
        sb.write('${t.key}@${e.key}=${e.value};');
      }
    }
    for (final e in b.positionType.entries) {
      sb.write('${e.key}:${e.value.name};');
    }
    return sb.toString();
  }

  test('isolate ve senkron yol birebir aynı sonucu verir (40 × 5 yıl)',
      () async {
    final girdi = demo(40, 5);
    expect(girdi.isBuyuklugu,
        greaterThanOrEqualTo(portfoyBirlesimIsolateEsigi),
        reason: 'demo girdi isolate yolunu seçmeli');
    final senkron = portfoySerisiniBirlestir(girdi);
    final isolateda = await portfoySerisiniBirlestirIsolateda(girdi);
    final uygun = await portfoySerisiniBirlestirUygun(girdi);

    expect(senkron.total.length, greaterThan(1000));
    expect(senkron.byType.keys,
        containsAll([AssetType.hisse, AssetType.altin]));
    expect(imza(isolateda), imza(senkron));
    expect(imza(uygun), imza(senkron));
  });

  test('küçük girdi senkron kalır (15 × 1 yıl eşiğin altında)', () {
    expect(demo(15, 1).isBuyuklugu, lessThan(portfoyBirlesimIsolateEsigi));
  });

  test('ölçüm: birleştirme süresi (JIT, yalnız kayıt)', () async {
    for (final (v, y) in [(40, 5), (15, 1)]) {
      final girdi = demo(v, y);
      final sw = Stopwatch();
      final senkron = <int>[];
      final isolateToplam = <int>[];
      final isolateAnaIs = <int>[];
      for (var k = 0; k < 8; k++) {
        // Her turda taze girdi: sıralı anahtar önbelleği (Expando) harita
        // başına tutulur; üretimde de her çekimden sonra yeni harita gelir.
        final g = demo(v, y);
        sw
          ..reset()
          ..start();
        portfoySerisiniBirlestir(g);
        senkron.add(sw.elapsedMicroseconds);

        final g2 = demo(v, y);
        sw
          ..reset()
          ..start();
        final f = portfoySerisiniBirlestirIsolateda(g2);
        isolateAnaIs.add(sw.elapsedMicroseconds);
        await f;
        isolateToplam.add(sw.elapsedMicroseconds);
      }
      // ignore: avoid_print
      print('$v varlık × $y yıl, iş=${girdi.isBuyuklugu} adım | '
          'senkron µs: $senkron | isolate toplam µs: $isolateToplam | '
          'isolate senkron kısım µs: $isolateAnaIs');
    }
  });
}
