import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/sozlesme.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/sozlesme_deposu.dart';

/// BES geçmişi: fonun GERÇEK serisi (kullanıcı kararı 2026-10-04).
///
/// 2026-10-01'de sözleşmenin uygulamaya eklendiği andan önceki günler
/// açılış fiyatıyla DÜZ çiziliyordu. Kullanıcı geri aldı: *"dümdüz
/// gözüküyor, aslında öyle değil değerleri"* ve *"her yerde aynı zaman
/// aralığında aynı kâr zararı ve anlık değer"*. Ölçülen ayrışma (KED, 1H):
/// Performans dökümü +%1,55 (açılıştan bu yana), varlık ekranı −%1,12
/// (fonun haftası). Şimdi her yüzey bugünkü payları fonun gerçek fiyatıyla
/// değerler; pozisyon serisi ile varlık ekranının birim serisi aynı yüzdeyi
/// verir.
void main() {
  final simdi = DateTime.now();
  final bugun = DateTime(simdi.year, simdi.month, simdi.day);
  final giris = DateTime(simdi.year - 3, 1, 15);

  // Sözleşme 20 gün önce eklendi: eski kural bu andan öncesini düz çizerdi.
  final s = Sozlesme(
    id: 'bes-1',
    userId: 'u1',
    tur: SozlesmeTuru.bes,
    kurum: 'Test Emeklilik',
    baslangic: giris,
    fonDagilimi: const [FonPayi(kod: 'AAA', oran: 100)],
    olusturuldu: simdi.subtract(const Duration(days: 20)),
  );

  final lot = Asset(
    id: 'l1',
    userId: 'u1',
    name: 'Test · AAA',
    ticker: '${tefasOneki}AAA',
    type: AssetType.bes,
    subCategory: BesAltKategori.katki,
    quantity: 100,
    purchasePrice: 8,
    currency: 'TRY',
    notes: '',
    isManualPrice: false,
    currentPrice: 12,
    addedDate: giris,
    sozlesmeId: 'bes-1',
  );

  // Fon her gün +%1: düz çizgi kuralı geri gelirse açılıştan önceki günler
  // tek değere çöker ve aşağıdaki beklentiler kırılır.
  final bas = bugun.subtract(const Duration(days: 60));
  final gunler = <(int, double)>[];
  final fiyatlar = <int, double>{};

  setUp(() {
    SozlesmeDeposu.instance.yaz([s], const []);
    gunler.clear();
    fiyatlar.clear();
    var fiyat = 5.0;
    for (var g = 0; g <= 60; g++) {
      final ms = bas.add(Duration(days: g)).millisecondsSinceEpoch;
      gunler.add((ms, fiyat));
      fiyatlar[ms] = fiyat;
      fiyat *= 1.01;
    }
    HistoryService.seriCekici = (sym, range, interval) async =>
        sym == '${tefasOneki}AAA' ? gunler : const [];
    HistoryService.instance.clearTierCache();
  });
  tearDown(() {
    SozlesmeDeposu.instance.temizle();
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    HistoryService.instance.clearTierCache();
  });

  Future<Map<int, double>> seri(Asset a, ResolutionTier tier) async =>
      (await HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
        assets: [a],
        from: bas,
        to: simdi,
        tier: tier,
      ))
          .total;

  test('günlük: açılıştan önceki günler de fonun o günkü fiyatıyla', () async {
    final sonuc = await seri(lot, ResolutionTier.daily);
    // Bugünün slotu canlı fiyata sabitlenebilir; geçmiş günlere bakılır.
    final gecmis = sonuc.entries
        .where((e) => e.key < bugun.millisecondsSinceEpoch)
        .toList();
    expect(gecmis.length, greaterThan(40));
    for (final e in gecmis) {
      expect(e.value, closeTo(100 * fiyatlar[e.key]!, 1e-6),
          reason: 'miktar × fonun o günkü fiyatı — düz çizgi değil');
    }
  });

  test('haftalık: seri düz değil, fonla birlikte yürür', () async {
    final sonuc = await seri(lot, ResolutionTier.weekly);
    final k = sonuc.keys.toList()..sort();
    expect(k.length, greaterThan(4));
    for (var i = 1; i < k.length; i++) {
      expect(sonuc[k[i]]!, greaterThan(sonuc[k[i - 1]]!));
    }
  });

  test('varlık ekranının birim serisi pozisyon serisiyle aynı yüzdeyi verir',
      () async {
    final pozisyon = await seri(lot, ResolutionTier.daily);
    final birim =
        await seri(FiyatKaynagi.birimVarlik(lot), ResolutionTier.daily);
    // Uç canlı fiyata sabitlenebildiği için dünkü slota kadar ölçülür.
    double yuzde(Map<int, double> m) {
      final k = m.keys.where((t) => t < bugun.millisecondsSinceEpoch).toList()
        ..sort();
      return m[k.last]! / m[k.first]! - 1;
    }

    expect(yuzde(birim), closeTo(yuzde(pozisyon), 1e-9),
        reason: 'Σ varlık == Performans tür filtresi');
  });
}
