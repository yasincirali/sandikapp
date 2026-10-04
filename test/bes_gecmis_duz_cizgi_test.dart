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

  // 2026-10-04 kullanıcı bildirimi: Performans 1H dökümünde "BES › KED
  // +%1,55", aynı fonun varlık ekranı −%1,12. Varlık ekranı serisini
  // `FiyatKaynagi.birimVarlik` ile çekiyor; sentetik lot `sozlesmeId`
  // taşımadığı için açılış kuralı uygulanmıyor, açılıştan önceki günler
  // fonun kendi serisiyle çiziliyordu. İki ekran aynı pencerede aynı
  // yüzdeyi vermeli (Σ varlık == Performans tür filtresi).
  test('varlık ekranının birim serisi de açılıştan önce düz', () async {
    final gunler = <(int, double)>[];
    final bas = DateTime(simdi.year, simdi.month, simdi.day)
        .subtract(const Duration(days: 60));
    var fiyat = 5.0;
    for (var g = 0; g <= 60; g++) {
      gunler.add((bas.add(Duration(days: g)).millisecondsSinceEpoch, fiyat));
      fiyat *= 1.01;
    }
    HistoryService.seriCekici = (sym, range, interval) async =>
        sym == '${tefasOneki}AAA' ? gunler : const [];

    Future<Map<int, double>> seri(Asset a) async =>
        (await HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
          assets: [a],
          from: bas,
          to: simdi,
          tier: ResolutionTier.daily,
        ))
            .total;

    final pozisyon = await seri(lot());
    final birim = await seri(FiyatKaynagi.birimVarlik(lot()));
    double yuzde(Map<int, double> m) {
      final k = m.keys.toList()..sort();
      return m[k.last]! / m[k.first]! - 1;
    }

    expect(yuzde(birim), closeTo(yuzde(pozisyon), 1e-9),
        reason: 'varlık ekranı ile Performans dökümü aynı yüzdeyi vermeli');
  });

  // 2026-10-04: varlık ekranında 1H/1A/3A "+%1,5", 6A/1Y/5Y "%0,0". Haftalık
  // bar haftanın SON kapanışını taşıyor; açılış fiyatı diye o okunuyordu.
  test('haftalık katman: düz çizgi açılış GÜNÜNÜN fiyatında', () async {
    final bugun = DateTime(simdi.year, simdi.month, simdi.day);
    // Açılış haftanın ortasında (Salı): haftanın kapanışından ayrışsın.
    final g = bugun.subtract(const Duration(days: 21));
    final sali = g.subtract(Duration(days: g.weekday - 2));
    SozlesmeDeposu.instance.yaz([
      Sozlesme(
        id: 'bes-2',
        userId: 'u1',
        tur: SozlesmeTuru.bes,
        kurum: 'Test Emeklilik',
        baslangic: giris,
        fonDagilimi: const [FonPayi(kod: 'AAA', oran: 100)],
        olusturuldu: sali.add(const Duration(hours: 12)),
      ),
    ], const []);
    final gunler = <(int, double)>[];
    final bas = bugun.subtract(const Duration(days: 60));
    var fiyat = 5.0;
    double? acilisFiyati;
    for (var i = 0; i <= 60; i++) {
      final d = bas.add(Duration(days: i));
      gunler.add((d.millisecondsSinceEpoch, fiyat));
      if (d == sali) acilisFiyati = fiyat;
      fiyat *= 1.01;
    }
    HistoryService.seriCekici = (sym, range, interval) async =>
        sym == '${tefasOneki}AAA' ? gunler : const [];
    HistoryService.instance.clearTierCache();

    final sonuc =
        await HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
      assets: [lot(sozlesmeId: 'bes-2')],
      from: bas,
      to: simdi,
      tier: ResolutionTier.weekly,
    );
    final once = [
      for (final e in sonuc.total.entries)
        if (e.key < sali.millisecondsSinceEpoch) e.value,
    ];
    expect(once, isNotEmpty);
    for (final v in once) {
      expect(v, closeTo(100 * acilisFiyati!, 1e-6));
    }
  });
}
