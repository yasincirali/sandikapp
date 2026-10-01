import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/sozlesme.dart';
import 'package:portfoy_takip/services/bes_acilis.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/sozlesme_deposu.dart';

/// BES geçmişi: açılıştan önce DÜZ çizgi (kullanıcı kararı 2026-10-01).
///
/// *"Geçmiş kâr zararımı fon değerlerine göre değil, eklendiği günkü ana
/// para, devlet katkısı ve kârla girdirtip düz çizgi gösterelim."*
/// Açılış lotları giriş tarihli yazılır; açılış anından önceki her slot
/// açılış fiyatıyla değerlenir, sonrası fon serisiyle yürür.
void main() {
  final simdi = DateTime.now();
  final giris = DateTime(simdi.year - 3, 1, 15);
  final acilis = simdi.subtract(const Duration(days: 20));

  final s = Sozlesme(
    id: 'bes-1',
    userId: 'u1',
    tur: SozlesmeTuru.bes,
    kurum: 'Test Emeklilik',
    baslangic: giris,
    fonDagilimi: const [FonPayi(kod: 'AAA', oran: 100)],
    olusturuldu: acilis,
  );

  Asset lot({DateTime? tarih, String? sozlesmeId = 'bes-1'}) => Asset(
        id: 'l1',
        userId: 'u1',
        name: 'Test · AAA',
        ticker: '${tefasOneki}AAA',
        type: AssetType.bes,
        subCategory: BesAltKategori.katki,
        quantity: 100,
        // Ana para 800, açılıştaki birikim 100 × 10 = 1000 → kâr 200.
        purchasePrice: 8,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 12,
        addedDate: tarih ?? giris,
        sozlesmeId: sozlesmeId,
      );

  setUp(() => SozlesmeDeposu.instance.yaz([s], const []));
  tearDown(() {
    SozlesmeDeposu.instance.temizle();
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
  });

  group('BesAcilis.fiyatAni', () {
    test('açılıştan önce açılış anı, sonra kendisi', () {
      final a = lot();
      final once = acilis.subtract(const Duration(days: 300));
      final sonra = acilis.add(const Duration(days: 2));
      expect(BesAcilis.fiyatAni(a, once.millisecondsSinceEpoch),
          acilis.millisecondsSinceEpoch);
      expect(BesAcilis.fiyatAni(a, sonra.millisecondsSinceEpoch),
          sonra.millisecondsSinceEpoch);
    });

    test('BES değilse, sözleşmesiz ya da açılış anı bilinmiyorsa dokunmaz',
        () {
      final ts = giris.millisecondsSinceEpoch;
      final hisse = Asset(
        id: 'h',
        userId: 'u1',
        name: 'THYAO',
        ticker: 'THYAO.IS',
        type: AssetType.hisse,
        quantity: 1,
        purchasePrice: 1,
        currency: 'TRY',
        notes: '',
        sozlesmeId: 'bes-1',
      );
      expect(BesAcilis.fiyatAni(hisse, ts), ts);
      expect(BesAcilis.fiyatAni(lot(sozlesmeId: null), ts), ts);
      expect(
          BesAcilis.fiyatAni(lot(), ts, sozlesme: (_) => null), ts);
    });
  });

  test('seri: açılıştan önce düz (açılış değeri), sonra fon serisiyle', () async {
    // Fon serisi her gün +%1 — eski yol bunu geçmişe uygulayıp açılıştan
    // önce sahte bir düşüş çizerdi.
    final gunler = <(int, double)>[];
    final bas = DateTime(simdi.year, simdi.month, simdi.day)
        .subtract(const Duration(days: 60));
    var fiyat = 5.0;
    for (var g = 0; g <= 60; g++) {
      final d = bas.add(Duration(days: g));
      gunler.add((d.millisecondsSinceEpoch, fiyat));
      fiyat *= 1.01;
    }
    HistoryService.seriCekici = (sym, range, interval) async =>
        sym == '${tefasOneki}AAA' ? gunler : const [];

    final sonuc =
        await HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
      assets: [lot()],
      from: bas,
      to: simdi,
      tier: ResolutionTier.daily,
    );
    final acilisGunu = DateTime(acilis.year, acilis.month, acilis.day)
        .millisecondsSinceEpoch;
    final once = {
      for (final e in sonuc.total.entries)
        if (e.key < acilisGunu) e.key: e.value,
    };
    final sonra = {
      for (final e in sonuc.total.entries)
        if (e.key > acilisGunu) e.key: e.value,
    };
    expect(once, isNotEmpty);
    expect(sonra, isNotEmpty);
    // Açılıştan önce tek bir değer: düz çizgi = açılış günündeki değer.
    final acilisDegeri = sonuc.total[acilisGunu]!;
    for (final v in once.values) {
      expect(v, closeTo(acilisDegeri, 1e-6));
    }
    // Sonrası fon serisiyle artar.
    final sonraKeys = sonra.keys.toList()..sort();
    expect(sonra[sonraKeys.last]!, greaterThan(acilisDegeri));
  });

  test('eski kayıt (lot açılış anında) — kural etkisiz, seri eskisi gibi',
      () async {
    final gunler = <(int, double)>[];
    final bas = DateTime(simdi.year, simdi.month, simdi.day)
        .subtract(const Duration(days: 40));
    for (var g = 0; g <= 40; g++) {
      gunler.add((bas.add(Duration(days: g)).millisecondsSinceEpoch, 10.0 + g));
    }
    HistoryService.seriCekici = (sym, range, interval) async =>
        sym == '${tefasOneki}AAA' ? gunler : const [];
    final sonuc =
        await HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
      assets: [lot(tarih: acilis)],
      from: bas,
      to: simdi,
      tier: ResolutionTier.daily,
    );
    final acilisMs = acilis.millisecondsSinceEpoch;
    // Açılıştan önce lot yok: o slotlarda BES değeri yok (0).
    expect(
        sonuc.total.entries
            .where((e) => e.key < acilisMs - const Duration(days: 1).inMilliseconds)
            .every((e) => e.value == 0),
        isTrue);
  });
}
