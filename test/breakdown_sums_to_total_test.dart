import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// **Değişmez: tür dökümünün toplamı portföy toplamını TUTAR.**
///
/// Kullanıcı şikâyeti (2026-09-01): "performans ekranında zaman aralığı
/// seçildiğinde alttaki kategori kâr/zararlarını topladığımda en tepedeki
/// genel totale ulaşmıyorum."
///
/// ## Kök neden
/// İki kart İKİ FARKLI veri kaynağı kullanıyordu:
///   · üst kart → `getPortfolioHistoryAtResolution` (zoom controller, tier'lı)
///   · döküm    → tür başına ayrı `getPortfolioHistory(assets, periodDays)`
/// Farklı pencere, farklı çözünürlük, farklı "kapsanan slot" kümesi. İki
/// hesabın tutması için hiçbir yapısal sebep yoktu — sadece umut vardı.
///
/// ## Çözüm
/// `getPortfolioHistoryBreakdownAtResolution` toplamı ve dağılımı TEK
/// döngüde üretir. Bu testler o değişmezi kilitler; ayrı bir kod yoluyla
/// yeniden hesaplamazlar (yeniden hesaplasalardı aynı tuzağa düşerlerdi),
/// **servisin kendi çıktısını** denetlerler.
///
/// Ağ yok: fiyat serisi çözülemeyen varlıklar `currentPrice`'a düşer
/// (`getPortfolioHistoryAtResolution` içindeki "son çare" dalı), bu yüzden
/// deterministik bir seri elde ederiz.

Asset _lot({
  required String id,
  required AssetType type,
  required double qty,
  required double price,
  required DateTime added,
  String ticker = '',
  String? subCategory,
  AssetKind kind = AssetKind.buy,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: ticker.isEmpty ? id : ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: price,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      purchaseFxRate: 1.0,
      currentPrice: price,
      addedDate: added,
      kind: kind,
      subCategory: subCategory,
    );

void main() {
  final now = DateTime.now();
  final from = now.subtract(const Duration(days: 60));

  /// Fiyat serisi ÇEKİLEMEYEN varlıklar: `isManualPrice` + boş/bilinmeyen
  /// ticker → servis `currentPrice`'a düşer. Ağ çağrısı yapılmaz.
  final assets = <Asset>[
    _lot(
      id: 'a1',
      type: AssetType.altin,
      qty: 10,
      price: 4000,
      added: from.subtract(const Duration(days: 10)),
      subCategory: 'gram',
    ),
    _lot(
      id: 'a2',
      type: AssetType.altin,
      qty: 4,
      price: 6500,
      added: from.subtract(const Duration(days: 10)),
      subCategory: 'çeyrek',
    ),
    _lot(
      id: 'h1',
      type: AssetType.hisse,
      qty: 100,
      price: 50,
      added: from.subtract(const Duration(days: 10)),
      ticker: 'ZZZTEST1',
    ),
    _lot(
      id: 'h2',
      type: AssetType.hisse,
      qty: 20,
      price: 300,
      added: from.subtract(const Duration(days: 10)),
      ticker: 'ZZZTEST2',
    ),
  ];

  Future<PortfolioHistoryBreakdown> load({bool simulate = false}) =>
      HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
        assets: assets,
        from: from,
        to: now,
        tier: ResolutionTier.daily,
        simulate: simulate,
      );

  group('Σ tür == toplam', () {
    test('her slot için türlerin toplamı portföy toplamını verir', () async {
      final b = await load();
      expect(b.total, isNotEmpty, reason: 'seri üretilemediyse test anlamsız');

      for (final ts in b.total.keys) {
        double sum = 0;
        for (final series in b.byType.values) {
          sum += series[ts] ?? 0;
        }
        expect(sum, closeTo(b.total[ts]!, 0.01),
            reason: 'ts=$ts için tür toplamı portföy toplamını tutmuyor');
      }
    });

    test('dönem başı ve dönem sonu uçları da tutar', () async {
      // Kartın fiilen gösterdiği iki nokta bunlar — asıl kullanıcı şikâyeti
      // toplam değil bu uçlar üzerindendi.
      final b = await load();
      final ts = b.total.keys.toList()..sort();

      for (final anchor in [ts.first, ts.last]) {
        double sum = 0;
        for (final series in b.byType.values) {
          sum += series[anchor] ?? 0;
        }
        expect(sum, closeTo(b.total[anchor]!, 0.01));
      }
    });

    test('DEĞİŞİM de tutar — Σ(tür değişimi) == toplam değişim', () async {
      // Kart tutarları `son − ilk` olarak gösterir. Uçlar tuttuğu için
      // farkların da tutması gerekir; kullanıcının topladığı şey tam olarak
      // bu sütun.
      final b = await load();
      final ts = b.total.keys.toList()..sort();
      final toplamDegisim = b.total[ts.last]! - b.total[ts.first]!;

      double sum = 0;
      for (final series in b.byType.values) {
        final s = series.keys.toList()..sort();
        if (s.length < 2) continue;
        sum += series[s.last]! - series[s.first]!;
      }
      expect(sum, closeTo(toplamDegisim, 0.01));
    });

    test('simülasyon modunda da tutar', () async {
      final b = await load(simulate: true);
      final ts = b.total.keys.toList()..sort();
      double sum = 0;
      for (final series in b.byType.values) {
        sum += series[ts.last] ?? 0;
      }
      expect(sum, closeTo(b.total[ts.last]!, 0.01));
    });
  });

  group('Σ ürün == tür', () {
    test('bir türün ürünleri o türün toplamını verir', () async {
      // Collapsible kartın alt satırları. Altın iki alt kategoriye (gram,
      // çeyrek), hisse iki ticker'a ayrılır.
      final b = await load();

      for (final t in b.byType.keys) {
        final kids = [
          for (final e in b.byPosition.entries)
            if (b.positionType[e.key] == t) e.value,
        ];
        expect(kids, isNotEmpty, reason: '$t için ürün serisi yok');

        for (final ts in b.byType[t]!.keys) {
          double sum = 0;
          for (final k in kids) {
            sum += k[ts] ?? 0;
          }
          expect(sum, closeTo(b.byType[t]![ts]!, 0.01),
              reason: '$t / ts=$ts için ürün toplamı tür toplamını tutmuyor');
        }
      }
    });

    test('altın alt kategorileri AYRI satırlar — ticker ile birleşmez', () async {
      // Gram ve Çeyrek aynı `GC=F` serisinden türetilir ama farklı ağırlık
      // katsayısı taşır. `positionKey` ile ayrıldıkları için iki satırdır;
      // ticker ile gruplansaydı tek satıra düşer ve "çeyrek mi gram mı
      // kazandırdı" sorusu cevapsız kalırdı.
      final b = await load();
      final altinKeys = [
        for (final e in b.positionType.entries)
          if (e.value == AssetType.altin) e.key,
      ];
      expect(altinKeys.length, 2);
    });

    test('her pozisyonun bir türü vardır', () async {
      final b = await load();
      for (final k in b.byPosition.keys) {
        expect(b.positionType[k], isNotNull,
            reason: 'ürün satırı hangi başlığın altına gireceğini bilmeli');
      }
    });
  });

  group('gün içi (GÜNLÜK sekmesi) — ayrı kod yolu', () {
    // Gün içi seri `getPortfolioHistoryHourlyBreakdown`'dan gelir; diğer
    // periyotlardan TAMAMEN ayrı bir fonksiyondur (5 dk grid, seans saatleri,
    // eksik-kapsam elemesi, canlı toplam ezmesi). Tür dökümü kartı bu sekmede
    // hiç görünmüyordu çünkü o yol dağılım taşımıyordu.
    //
    // Kendi değişmez testleri şart: bir yolu düzeltmek diğerini düzeltmez.
    Future<PortfolioHistoryBreakdown> loadHourly() =>
        HistoryService.instance.getPortfolioHistoryHourlyBreakdown(assets, 24);

    test('dağılım DOLU döner — kart artık beslenebiliyor', () async {
      final b = await loadHourly();
      expect(b.total, isNotEmpty);
      expect(b.byType, isNotEmpty,
          reason: 'boş dağılım = kart gün içinde yine görünmez');
      expect(b.byPosition, isNotEmpty);
    });

    test('her slot için Σ tür == toplam', () async {
      final b = await loadHourly();
      for (final ts in b.total.keys) {
        double sum = 0;
        for (final series in b.byType.values) {
          sum += series[ts] ?? 0;
        }
        expect(sum, closeTo(b.total[ts]!, 0.01), reason: 'ts=$ts');
      }
    });

    test('SON nokta da tutar — canlı toplam ezmesine rağmen', () async {
      // Gün içi seride son slot canlı portföy toplamıyla eziliyor. Dağılım
      // aynı oranda ölçeklenmezse tam da kartın okuduğu uçta ayrışırdı.
      final b = await loadHourly();
      final ts = b.total.keys.toList()..sort();
      double sum = 0;
      for (final series in b.byType.values) {
        sum += series[ts.last] ?? 0;
      }
      expect(sum, closeTo(b.total[ts.last]!, 0.01));
    });

    test('son slotta her tür KENDİ değerini taşır — çapraz bulaşma yok',
        () async {
      // **Asıl senkron hatası (2026-09-01).** Son slot canlı toplamla
      // eziliyordu ve dağılım tek bir `liveTotal / before` çarpanıyla
      // ölçekleniyordu. Bu, bir türdeki hareketi TÜM türlere yayıyordu:
      // altın düşünce, fiyatı hiç değişmemiş fon da düşmüş görünüyordu.
      // Toplam tutuyordu ama satırlar yalan söylüyordu — kullanıcının
      // "alttakiler üsttekiyle senkron değil" dediği şey buydu.
      //
      // Fiyatı sabit tutulan bir varlık, son slotta TAM olarak kendi
      // değerini göstermeli.
      final sabitFiyatli = [
        _lot(
          id: 'sabit',
          type: AssetType.fon,
          qty: 1000,
          price: 25,
          added: from.subtract(const Duration(days: 10)),
          ticker: 'ZZSABIT',
        ),
        _lot(
          id: 'oynak',
          type: AssetType.altin,
          qty: 50,
          price: 4000,
          added: from.subtract(const Duration(days: 10)),
          subCategory: 'gram',
        ),
      ];
      final b = await HistoryService.instance
          .getPortfolioHistoryHourlyBreakdown(sabitFiyatli, 24);
      final ts = b.total.keys.toList()..sort();

      expect(b.byType[AssetType.fon]![ts.last], closeTo(25000, 0.01),
          reason: 'fonun fiyatı değişmedi — değeri de değişmemeli');
      double sum = 0;
      for (final s in b.byType.values) {
        sum += s[ts.last] ?? 0;
      }
      expect(sum, closeTo(b.total[ts.last]!, 0.01),
          reason: 'çapraz bulaşma giderilirken toplam bozulmamalı');
    });

    test('Σ ürün == tür', () async {
      final b = await loadHourly();
      for (final t in b.byType.keys) {
        final kids = [
          for (final e in b.byPosition.entries)
            if (b.positionType[e.key] == t) e.value,
        ];
        for (final ts in b.byType[t]!.keys) {
          double sum = 0;
          for (final k in kids) {
            sum += k[ts] ?? 0;
          }
          expect(sum, closeTo(b.byType[t]![ts]!, 0.01), reason: '$t / ts=$ts');
        }
      }
    });
  });

  group('kalibrasyon — sentetik "Diğer" satırı YOK', () {
    /// Ekrandaki `_calibrate` ile birebir aynı aritmetik.
    ///
    /// Üst kartın son noktası canlı toplamla ezilir (`currentTotalOverride`),
    /// tür serileri ham gelir. Aradaki fark eskiden "Diğer" adlı sentetik bir
    /// satıra yazılıyordu — ama `AssetType.diger` ZATEN gerçek bir kategori,
    /// dolayısıyla aynı adı taşıyan iki satır çıkıyordu. Artık artık türlerin
    /// ağırlığınca dağıtılıyor.
    ({List<double> first, List<double> last}) kalibre({
      required List<double> seriFirst,
      required List<double> seriLast,
      required double ustKartFirst,
      required double ustKartLast,
    }) {
      final sumF = seriFirst.fold(0.0, (a, b) => a + b);
      final sumL = seriLast.fold(0.0, (a, b) => a + b);
      final kF = sumF.abs() > 0.01 ? ustKartFirst / sumF : 1.0;
      final kL = sumL.abs() > 0.01 ? ustKartLast / sumL : 1.0;
      return (
        first: [for (final v in seriFirst) v * kF],
        last: [for (final v in seriLast) v * kL],
      );
    }

    test('kalibre edilmiş satırların toplamı üst kartı TAM tutar', () {
      final r = kalibre(
        seriFirst: [40000, 30000, 10000],
        seriLast: [44000, 31000, 9500],
        // Canlı toplam serinin son noktasından biraz farklı — gerçek durum.
        ustKartFirst: 80000,
        ustKartLast: 85000,
      );
      expect(r.first.fold(0.0, (a, b) => a + b), closeTo(80000, 0.01));
      expect(r.last.fold(0.0, (a, b) => a + b), closeTo(85000, 0.01));
    });

    test('türler arası ORANLAR bozulmaz', () {
      // Kalibrasyon toplamı düzeltir ama "hangi tür ne kadar kazandırdı"
      // bilgisini değiştirmemeli — aksi halde rakamları düzeltirken anlamı
      // bozmuş olurduk.
      const seri = [40000.0, 30000.0, 10000.0];
      final r = kalibre(
        seriFirst: seri,
        seriLast: seri,
        ustKartFirst: 96000, // ×1.2
        ustKartLast: 96000,
      );
      expect(r.first[0] / r.first[1], closeTo(seri[0] / seri[1], 1e-9));
      expect(r.first[1] / r.first[2], closeTo(seri[1] / seri[2], 1e-9));
    });

    test('artık YOKSA değerler aynen kalır', () {
      const seri = [50000.0, 30000.0];
      final r = kalibre(
        seriFirst: seri,
        seriLast: seri,
        ustKartFirst: 80000,
        ustKartLast: 80000,
      );
      expect(r.first[0], closeTo(50000, 0.01));
      expect(r.first[1], closeTo(30000, 0.01));
    });

    test('sıfır seride bölme yok', () {
      final r = kalibre(
        seriFirst: [0, 0],
        seriLast: [0, 0],
        ustKartFirst: 1000,
        ustKartLast: 1000,
      );
      // Çarpan 1'e sabitlenir; NaN/Infinity üretilmez.
      expect(r.first.every((v) => v.isFinite), isTrue);
      expect(r.last.every((v) => v.isFinite), isTrue);
    });
  });

  group('boş girdi', () {
    test('varlık yoksa boş dağılım döner', () async {
      final b =
          await HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
        assets: const [],
        from: from,
        to: now,
        tier: ResolutionTier.daily,
      );
      expect(b.total, isEmpty);
      expect(b.byType, isEmpty);
      expect(b.byPosition, isEmpty);
    });
  });
}
