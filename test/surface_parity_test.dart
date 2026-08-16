import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/utils/tr_format.dart';

/// Uygulama DIŞI iki yüzeyin BİREBİR aynı rakamı göstermesi.
///
/// Kilit ekranı (Live Activity) ve ana ekran widget'ı aynı anda, yan yana
/// görülebilir. Farklı rakam gösterirlerse kullanıcı hangisine güveneceğini
/// bilemez — "uygulama bozuk" der.
///
/// İkisi de [DailySummary] üzerinden hesaplar. Bu dosya hesabın KENDİSİNİ
/// kilitler; iki servisin ona bağlı kaldığını da ayrıca doğrular.
///
/// ## Neden ortak katman
/// Önce yalnızca Live Activity doğru hesaplıyordu; widget kendi hesabını
/// yapıyor ve üç yerde ayrışıyordu:
///   1. `state.gainLoss` — ömürlük getiriyi "günlük" diye gösteriyordu,
///   2. `state.totalValue` — satış lot'larını toplama geri ekliyordu,
///   3. ham seri — sıfır slotlar grafiği düz çizgiye eziyordu.

Asset _lot({
  required String id,
  required double quantity,
  required AssetKind kind,
  double purchasePrice = 200,
  double currentPrice = 300,
  DateTime? addedDate,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO',
      type: AssetType.hisse,
      quantity: quantity,
      purchasePrice: purchasePrice,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: currentPrice,
      addedDate: addedDate ?? DateTime(2026, 1, 1),
      kind: kind,
    );

PortfolioState _state(List<Asset> assets) => PortfolioState(
      assets: assets,
      usdTry: 42.0,
      eurTry: 46.0,
      gbpTry: 54.0,
    );

void main() {
  group('canlı toplam — satış lot işareti', () {
    // `Asset.totalValue` (= quantity * currentPrice) İŞARETSİZDİR ve satış
    // lot'unun miktarı da pozitiftir. Ham toplama (`state.totalValue`)
    // güvenmek satılan miktarı düşmek yerine GERİ EKLER.
    //
    // Serinin diğer ucu `HistoryService`'ten gelir ve orada satış
    // `signedQtyOnSlot` ile doğru şekilde `-quantity` sayılır. İki uç zıt
    // işaret kuralı kullandığında `last - open` farkı anlamsızlaşır.

    test('satılan miktar toplamdan DÜŞÜLÜR, eklenmez', () {
      // 100 alındı, 40 satıldı → net 60 × ₺300 = ₺18.000.
      // Ham toplam (eski davranış) 140 × 300 = ₺42.000 verirdi.
      final state = _state([
        _lot(id: 'b1', quantity: 100, kind: AssetKind.buy),
        _lot(id: 's1', quantity: 40, kind: AssetKind.sell),
      ]);

      expect(DailySummary.liveTotalTRY(state), 18000.0);
      expect(DailySummary.liveTotalTRY(state), lessThan(state.totalValue),
          reason: 'satış lot u portföy değerini büyütemez');
    });

    test('satış yokken ham toplamla aynı sonucu verir', () {
      // Düzeltme, satış yapmamış kullanıcıyı ETKİLEMEMELİ.
      final state = _state([_lot(id: 'b1', quantity: 100, kind: AssetKind.buy)]);

      expect(DailySummary.liveTotalTRY(state), state.totalValue);
      expect(DailySummary.liveTotalTRY(state), 30000.0);
    });

    test('tamamı satılmış pozisyon toplama girmez', () {
      final state = _state([
        _lot(id: 'b1', quantity: 100, kind: AssetKind.buy),
        _lot(id: 's1', quantity: 100, kind: AssetKind.sell),
      ]);

      expect(DailySummary.liveTotalTRY(state), 0.0);
    });
  });

  group('günlük değişim — ömürlük getiriden AYRI', () {
    test('gösterilen rakam GÜNLÜK, ömürlük getiri DEĞİL', () {
      // Kurulum: ₺200'den alınmış, şimdi ₺300 → ömürlük getiri +₺10.000.
      // Ama gün başı ₺29.000'di → GÜNLÜK değişim yalnızca +₺1.000.
      //
      // Widget eskiden burada +₺10.000 (%50) yazıyordu.
      final now = DateTime.now();
      final state = _state([_lot(id: 'b1', quantity: 100, kind: AssetKind.buy)]);
      final series = {
        now.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch:
            29000.0,
        now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch:
            29500.0,
      };

      final s = DailySummary.from(state: state, series: series, now: now);

      expect(s.totalTRY, 30000.0);
      expect(s.changeTRY, 1000.0, reason: '30.000 − 29.000 = günlük +₺1.000');
      expect(s.changeTRY, isNot(10000.0),
          reason: 'ömürlük getiri günlük diye gösterilemez');
      expect(s.changePct, closeTo(3.448, 0.01));
    });

    test('bugün yapılan alım KÂR gibi görünmez', () {
      // Gerçek kullanıcı hatası: uygulama %0,03 derken yüzey %6,19 "kâr"
      // gösteriyordu. Ham uçtan uca fark bugün yatırılan parayı da içerir.
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9);
      final state = _state([
        _lot(id: 'b1', quantity: 100, kind: AssetKind.buy),
        // Bugün ₺6.000'lik alım: 20 × ₺300.
        _lot(
          id: 'b2',
          quantity: 20,
          kind: AssetKind.buy,
          purchasePrice: 300,
          addedDate: today,
        ),
      ]);

      // Gün başı ₺30.000; alım sonrası toplam ₺36.000.
      final series = {
        now.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch:
            30000.0,
        now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch:
            36000.0,
      };

      final s = DailySummary.from(state: state, series: series, now: now);

      // 120 × ₺300 = ₺36.000 toplam; fiyat hiç hareket etmedi.
      expect(s.totalTRY, 36000.0);
      expect(s.changeTRY, 0.0,
          reason: 'yatırılan para kazanç değildir');
      expect(s.changePct, 0.0);
    });

    test('ölçüldü ama sıfırsa isFlat — yön taşımaz', () {
      // Piyasa kapalıyken fiyat hareket etmez ve değişim gerçekten sıfır
      // olur. Bu bir ÖLÇÜMDÜR (hasChange true) ama YÖNÜ yoktur: işaretli
      // `-₺0` yazmak kullanıcıya kayıp gibi okunur.
      final now = DateTime.now();
      final state = _state([_lot(id: 'b1', quantity: 100, kind: AssetKind.buy)]);
      final series = {
        now.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch:
            30000.0,
        now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch:
            30000.0,
      };

      final s = DailySummary.from(state: state, series: series, now: now);

      expect(s.hasChange, isTrue, reason: 'sıfır da bir ölçümdür');
      expect(s.isFlat, isTrue);
      expect(s.changeTRY, 0.0);
    });

    test('gerçek hareket isFlat DEĞİLDİR', () {
      final now = DateTime.now();
      final state = _state([_lot(id: 'b1', quantity: 100, kind: AssetKind.buy)]);
      final s = DailySummary.from(
        state: state,
        series: {
          now.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch:
              29000.0,
          now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch:
              29500.0,
        },
        now: now,
      );

      expect(s.isFlat, isFalse);
    });

    test('ölçüm yoksa uydurma sıfır DÖNMEZ', () {
      // Sıfır bir ÖLÇÜMDÜR ("bugün değişmedi"); ölçümsüzlükle
      // karıştırılırsa kullanıcı yeşil bir "+%0,00" görür ve gerçek sanır.
      final state = _state([_lot(id: 'b1', quantity: 100, kind: AssetKind.buy)]);

      final s = DailySummary.from(
        state: state,
        series: const {},
        now: DateTime.now(),
      );

      expect(s.hasChange, isFalse);
      expect(s.changeTRY, isNull);
      expect(s.changePct, isNull);
      expect(s.totalTRY, 30000.0,
          reason: 'değişim ölçülemese de toplam bilinir');
    });
  });

  group('grafik ekseni — iki sınır AYIRT EDİLEBİLİR olmalı', () {
    // Eksenin işi "hangi tutar aralığında gezindi" sorusunu yanıtlamak.
    // İki sınır aynı metne düşerse eksen hiçbir şey söylemez.

    setUpAll(() async => initializeDateFormatting('tr_TR'));

    test('dar bantta ondalık artar', () {
      // Gerçek emülatör verisi: ₺2.489.186 ± %0,1 → ~₺4.978'lik bant.
      // `fmtTRYCompact` ikisini de "₺2,49M" yapıyordu.
      const v = 2489186.40;
      const pad = v * 0.001;
      const lo = v - pad;
      const hi = v + pad;

      final alt = fmtTRYAxis(lo, hi - lo);
      final ust = fmtTRYAxis(hi, hi - lo);

      expect(alt, isNot(ust),
          reason: 'iki sınır aynı metne düşerse eksen anlamsız');
      expect(fmtTRYCompact(lo), fmtTRYCompact(hi),
          reason: 'eski biçimlendirici ikisini de aynı gösteriyordu');
    });

    test('geniş bantta sade kalır', () {
      // Gerçek hareketli gün: ₺2,45M–₺2,53M. Burada iki ondalık yeter;
      // gereksiz basamak dar eksende gürültüdür.
      final alt = fmtTRYAxis(2450000, 80000);
      final ust = fmtTRYAxis(2530000, 80000);

      expect(alt, '₺2,45M');
      expect(ust, '₺2,53M');
    });

    test('küçük portföyde de ayrışır', () {
      final alt = fmtTRYAxis(1000, 40);
      final ust = fmtTRYAxis(1040, 40);
      expect(alt, isNot(ust));
    });
  });

  group('eksen bandı — asgari genişlik', () {
    // Eksen yalnızca veriye göre ölçeklenirse, yatay giden bir portföydeki
    // minicik dalgalanma tuvalin tamamına yayılır.
    //
    // ÖLÇÜLEN gerçek vaka (emülatör, 2026-08-16 22:46): ₺2,486M'lik
    // portföyde kapanışa yakın ₺1.100'lük salınım. Bant ₺4.000 genişken
    // grafiğin üçte birini kaplıyordu: rakam "+%0,04" derken grafik
    // "çöküş" gösteriyordu — aynı yüzeyde iki çelişen mesaj.

    /// Üretimdeki kuralın aynısı — bant hesabı.
    ({double lo, double hi}) band(List<double> v) {
      final mn = v.reduce((a, b) => a < b ? a : b);
      final mx = v.reduce((a, b) => a > b ? a : b);
      final span = mx - mn;
      final minSpan = mx.abs() * 0.005;
      final eff = span < minSpan ? minSpan : span;
      final mid = (mx + mn) / 2;
      return (lo: mid - eff / 2 * 1.25, hi: mid + eff / 2 * 1.25);
    }

    test('küçük salınım tuvali doldurmaz', () {
      // Emülatörden alınan gerçek seri ucu.
      final values = [
        2486107.0, 2486107.0, 2486107.0, 2485342.0,
        2485002.0, 2485257.0, 2486404.0, 2487315.0,
      ];

      final b = band(values);
      final span = b.hi - b.lo;
      const hareket = 2487315.0 - 2485002.0; // ~₺2.313

      // Hareket bandın YARISINDAN azını kaplamalı — grafikte makul bir
      // dalgalanma gibi görünsün, felaket gibi değil.
      expect(hareket / span, lessThan(0.5),
          reason: '%0,09luk hareket grafiğin yarısını kaplayamaz');
    });

    test('GERÇEK büyük hareket bandı genişletir', () {
      // Taban yalnızca küçük hareketlerde devreye girmeli; %2lik gerçek
      // bir düşüş kırpılmamalı.
      final values = [2500000.0, 2450000.0];

      final b = band(values);

      expect(b.lo, lessThan(2450000.0), reason: 'gerçek hareket kırpılamaz');
      expect(b.hi, greaterThan(2500000.0));
    });

    test('bant verinin ORTASINA yerleşir', () {
      // Taban devredeyken çizgi yukarı/aşağı kaymamalı.
      final values = [1000000.0, 1000100.0];

      final b = band(values);
      final mid = (b.lo + b.hi) / 2;

      expect(mid, closeTo(1000050.0, 1.0));
    });
  });

  group('grafik — uygulamanın GÜNLÜK grafiğiyle aynı kurallar', () {
    final now = DateTime.now();
    int ago(int minutes) =>
        now.subtract(Duration(minutes: minutes)).millisecondsSinceEpoch;

    test('sıfır değerli slotlar atlanır', () {
      // Borsa açılmadan önceki boş slotlar. Bırakılırsa çizilen aralık
      // 0'dan başlar ve gerçek gün içi hareket düz çizgiye ezilir —
      // widget grafiğinin "hep aynı" görünmesinin sebebi buydu.
      final values = DailySummary.dayValues(
        {ago(40): 0.0, ago(30): 0.0, ago(20): 1000.0, ago(10): 1100.0},
        now,
        0,
      );

      expect(values, [1000.0, 1100.0]);
    });

    test('gelecekteki slotlar kırpılır', () {
      final values = DailySummary.dayValues(
        {
          ago(20): 1000.0,
          ago(10): 1050.0,
          now.add(const Duration(hours: 2)).millisecondsSinceEpoch: 9999.0,
        },
        now,
        0,
      );

      expect(values, [1000.0, 1050.0],
          reason: 'olmamış bir saatin değeri grafiğe girmemeli');
    });

    test('son nokta canlı toplama sabitlenir', () {
      // Yapılmazsa yüzey son slotta donmuş görünür ve grafiğin ucu
      // rakamla ayrışır.
      // Son slot TAZE (2 dk) — canlı değerle ezilir.
      final values =
          DailySummary.dayValues({ago(20): 1000.0, ago(2): 1050.0}, now, 1234.0);

      expect(values.last, 1234.0);
    });

    test('kuruşluk fark DÜZ sayılır — uçta sahte düşüş olmaz', () {
      // Gerçek vaka (emülatörde görüldü): ₺2.489.186,40 → ₺2.489.186,35.
      // 5 kuruşluk fark mutlak `1e-9` eşiğini aştığı için "hareket"
      // sayılıyor, normalize aralık 0,05'e oturuyor ve bu 5 kuruş
      // tuvalin TAMAMINA yayılıyordu: düz bir günde grafiğin ucu
      // tepeden dibe iniyordu.
      final values = [2489186.40, 2489186.40, 2489186.35];

      expect(DailySummary.isVisuallyFlat(values), isTrue,
          reason: '2,5 milyonda 5 kuruş hareket değil, yuvarlama gürültüsü');
    });

    test('gerçek hareket DÜZ sayılmaz', () {
      // Eşik gerçek hareketi de yutmamalı — aksi halde düzeltme kendi
      // başına bir regresyon olurdu. 2,5 milyonda ₺500 gerçek hareket.
      final values = [2489186.0, 2489486.0, 2489686.0];

      expect(DailySummary.isVisuallyFlat(values), isFalse);
    });

    test('küçük portföyde de göreli çalışır', () {
      // Eşik ÖLÇEĞE göre: ₺100'lük portföyde ₺10 gerçek hareket.
      expect(DailySummary.isVisuallyFlat([100.0, 110.0]), isFalse);
      // Aynı portföyde 0,00001 TL fark gürültüdür.
      expect(DailySummary.isVisuallyFlat([100.0, 100.00001]), isTrue);
    });

    test('BAYAT seri canlı değerle EZİLMEZ — sahte sıçrama olmaz', () {
      // Kullanıcının bulduğu hata: piyasa kapandıktan saatler sonra
      // grafiğin ucunda dikey bir sıçrama görünüyordu — uygulamanın kendi
      // günlük grafiğinde OLMAYAN bir sıçrama.
      //
      // Sebep: serinin iki ucu farklı kaynaklardan geliyor. Seri
      // `HistoryService`'ten (Yahoo intraday) gelir ve kapanışta donar;
      // canlı toplam ise `Asset.currentPrice`'tan hesaplanır ve akşam
      // boyu güncellenir. Son noktayı KOŞULSUZ ezmek, saatler önceki bir
      // slota bugünkü canlı değeri yazıyordu.
      //
      // Uygulamanın grafiği bu yüzden 5 dakikalık tazelik eşiği kullanıyor.
      final values = DailySummary.dayValues(
        {ago(240): 1000.0, ago(180): 1000.0},
        now,
        1200.0, // canlı değer çok farklı
      );

      expect(values.last, 1000.0,
          reason: '3 saatlik bayat slota canlı değer yazılamaz');
      expect(values.last, isNot(1200.0));
    });

    test('TAZE seri canlı değerle ezilir', () {
      // Kural tersine de işlemeli: seri güncelken uç canlı değere
      // oturmalı, yoksa yüzey son slotta donmuş görünür.
      final values = DailySummary.dayValues(
        {ago(20): 1000.0, ago(3): 1010.0},
        now,
        1015.0,
      );

      expect(values.last, 1015.0);
    });

    test('grafiğin ucu ile toplam AYNI değerdir', () {
      // Kullanıcı çizginin bittiği yeri görüp rakamı okur; ikisi
      // ayrışırsa yüzey kendi içinde çelişir.
      final state = _state([_lot(id: 'b1', quantity: 100, kind: AssetKind.buy)]);
      final s = DailySummary.from(
        state: state,
        series: {ago(20): 29000.0, ago(2): 29500.0},
        now: now,
      );

      expect(s.sparkline.last, s.totalTRY);
    });
  });
}
