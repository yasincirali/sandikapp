import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/models/sozlesme.dart';
import 'package:portfoy_takip/providers/sozlesme_provider.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/mevduat_hesabi.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/services/sozlesme_deposu.dart';
import 'package:portfoy_takip/widgets/sozlesme_karti.dart';

/// Mevduat ve BES'in lot defterine ve fiyat yoluna oturuşu (0088).
///
/// Kilitlenen karar: sözleşmeli türler YENİ bir fiyatlama biçimi değildir;
/// fon gibi birim değerli varlıktır (`AssetType.fiyatlamaTuru`) ve sembol
/// öneki kaynağı seçer. Motorlara tür dalı eklenmez (0058 dersi).
void main() {
  const sid = '9f1c2e7a-0000-4000-8000-000000000001';

  Asset lot({
    required AssetType type,
    required String ticker,
    double qty = 1,
    double price = 1,
    double current = 1,
    String? sub,
    String? sozlesmeId,
    AssetKind kind = AssetKind.buy,
  }) =>
      Asset(
        id: '$ticker-$sub-$qty-${kind.name}',
        userId: 'u',
        name: 'x',
        ticker: ticker,
        type: type,
        quantity: qty,
        purchasePrice: price,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: current,
        subCategory: sub,
        sozlesmeId: sozlesmeId,
        kind: kind,
      );

  test('fiyatlama türü: BES ve mevduat fon yolundan, görünüm kendi türünde', () {
    expect(AssetType.bes.fiyatlamaTuru, AssetType.fon);
    expect(AssetType.mevduat.fiyatlamaTuru, AssetType.fon);
    expect(AssetType.hisse.fiyatlamaTuru, AssetType.hisse);
    expect(AssetType.bes.sozlesmeli && AssetType.mevduat.sozlesmeli, isTrue);
    expect(AssetType.fon.sozlesmeli, isFalse);
  });

  test('mevduat ve BES seriye girer ve kendi sembolünden beslenir', () {
    final m = lot(
        type: AssetType.mevduat, ticker: mevduatSembolu(sid), current: 0);
    final b = lot(type: AssetType.bes, ticker: 'TEFAS:AH5', current: 0);
    expect(FiyatKaynagi.seriyeGirer(m), isTrue);
    expect(FiyatKaynagi.seriyeGirer(b), isTrue);
    expect(FiyatKaynagi.seriSembolleri(m), [mevduatSembolu(sid)]);
    expect(FiyatKaynagi.seriSembolleri(b), ['TEFAS:AH5']);
  });

  test('mevduat sembolü: büyük harfe çevrilse de sözleşme id\'si çözülür', () {
    expect(mevduatSozlesmeId(mevduatSembolu(sid).toUpperCase()), sid);
    expect(mevduatSozlesmeId('TEFAS:AH5'), isNull);
  });

  test('BES pozisyonu: kendi katkın ile devlet katkısı AYNI fonda ayrı', () {
    final k = lot(type: AssetType.bes, ticker: 'TEFAS:AH5', sub: 'katki');
    final d = lot(type: AssetType.bes, ticker: 'TEFAS:AH5', sub: 'dk');
    expect(positionKey(k) == positionKey(d), isFalse);
    expect(positionKey(k), 'bes|TEFAS:AH5|sub:katki|TRY',
        reason: 'Sunucu eşi `positions.ts` aynı çekirdeği üretir.');
    expect(aggregatePositions([k, d]).length, 2);
  });

  test('sozlesme_id yalnız doluyken yazılır (0088 öncesi sunucu kırılmasın)', () {
    final duz = lot(type: AssetType.hisse, ticker: 'THYAO.IS');
    expect(duz.toSupabase().containsKey('sozlesme_id'), isFalse);
    final m = lot(
        type: AssetType.mevduat, ticker: mevduatSembolu(sid), sozlesmeId: sid);
    expect(m.toSupabase()['sozlesme_id'], sid);
    final geri = Asset.fromSupabase(m.toSupabase());
    expect(geri.sozlesmeId, sid);
    expect(geri.type, AssetType.mevduat);
    expect(geri.copyWithDeletedAt(DateTime(2026)).sozlesmeId, sid);
  });

  test('sözleşme satırı gidiş-dönüş; tarih saat dilimiyle kaymaz', () {
    final s = Sozlesme(
      id: sid,
      userId: 'u',
      tur: SozlesmeTuru.bes,
      kurum: 'Anadolu Hayat',
      baslangic: DateTime(2019, 5, 10),
      aylikKatki: 5000,
      katkiGunu: 15,
      fonDagilimi: const [FonPayi(kod: 'AH5', oran: 60), FonPayi(kod: 'AEA', oran: 40)],
      dkFonKodu: 'AEK',
    );
    final m = s.toSupabase();
    expect(m['baslangic'], '2019-05-10');
    final g = Sozlesme.fromSupabase(m);
    expect(g.baslangic, DateTime(2019, 5, 10));
    expect(g.fonDagilimi.map((f) => f.kod), ['AH5', 'AEA']);
    expect(g.dkFonKodu, 'AEK');
    // Mevduat satırı BES alanı yazmaz (0088 `sozlesmeler_bes_alanlari`).
    final mv = Sozlesme(
            id: 'x',
            userId: 'u',
            tur: SozlesmeTuru.mevduat,
            kurum: 'Enpara',
            baslangic: DateTime(2026, 9, 1))
        .toSupabase();
    expect(mv['fon_dagilimi'], isNull);
  });

  group('PriceService mevduat yönlendirmesi', () {
    setUp(() {
      SozlesmeDeposu.instance.temizle();
      final bas = DateTime.now().subtract(const Duration(days: 10));
      final gun = DateTime(bas.year, bas.month, bas.day);
      SozlesmeDeposu.instance.yaz([
        Sozlesme(
            id: sid,
            userId: 'u',
            tur: SozlesmeTuru.mevduat,
            kurum: 'Enpara',
            baslangic: gun),
      ], [
        // Günlük faizli: değer her gün artar (vadelide vade içinde düz,
        // bkz. aşağıdaki vadeli test).
        MevduatDonemi(
          id: 'd',
          sozlesmeId: sid,
          baslangic: gun,
          vadeSonu: null,
          yillikFaiz: 42,
          stopaj: 17.5,
        ),
      ]);
    });

    test('vadeli: vade içinde kotasyon anaparada, değişim 0', () async {
      final bas = DateTime.now().subtract(const Duration(days: 10));
      final gun = DateTime(bas.year, bas.month, bas.day);
      SozlesmeDeposu.instance.yaz([
        Sozlesme(
            id: sid,
            userId: 'u',
            tur: SozlesmeTuru.mevduat,
            kurum: 'Enpara',
            baslangic: gun),
      ], [
        MevduatDonemi(
          id: 'd',
          sozlesmeId: sid,
          baslangic: gun,
          vadeSonu: gun.add(const Duration(days: 32)),
          yillikFaiz: 42,
          stopaj: 17.5,
        ),
      ]);
      final sembol = mevduatSembolu(sid).toUpperCase();
      final q = await PriceService.instance.fetchQuotes([sembol]);
      expect(q[sembol]!.regularMarketPrice, 1.0);
      expect(q[sembol]!.regularMarketChangePercent, 0);
    });

    test('kotasyon ağa çıkmadan sözleşmeden gelir', () async {
      final sembol = mevduatSembolu(sid).toUpperCase();
      final q = await PriceService.instance.fetchQuotes([sembol]);
      final p = q[sembol]!.regularMarketPrice!;
      final beklenen = SozlesmeDeposu.instance
          .mevduatBirimDegeri(sembol, DateTime.now())!;
      expect(p, closeTo(beklenen, 1e-6));
      expect(p, greaterThan(1));
      expect(q[sembol]!.regularMarketChangePercent, greaterThan(0));
    });

    test('seri sözleşmeden, istenen pencerede', () async {
      final s = await PriceService.instance
          .fetchHistoryAtInterval(mevduatSembolu(sid), '1mo', '1d');
      expect(s, isNotEmpty);
      // Izgara adımı günün saatine oturur: ilk nokta sözleşme başından
      // en çok bir gün sonradır — değer 1,0 ile bir günlük tahakkuk arası.
      expect(s.first.$2,
          inInclusiveRange(1.0, 1 + 0.42 * 0.825 / 365 + 1e-9),
          reason: 'Sözleşme başından önce nokta yok; seri 1,0 civarında başlar.');
      expect(s.last.$2, greaterThan(s.first.$2));
    });

    test('bilinmeyen sözleşme kotasyon DÖNDÜRMEZ (uydurma yok)', () async {
      final q = await PriceService.instance
          .fetchQuotes([mevduatSembolu('yok-boyle-bir-id')]);
      expect(q, isEmpty);
    });
  });

  test('BES dökümü: katkı + devlet + getiri == toplam; çıkışta hak ediş payı',
      () {
    final s = Sozlesme(
      id: sid,
      userId: 'u',
      tur: SozlesmeTuru.bes,
      kurum: 'X',
      baslangic: DateTime(2019, 5, 10),
    );
    // Kendi: 10.000 pay × 0,03 = 300 değer, maliyet 200.
    // Devlet: 2.000 pay × 0,03 = 60 değer, maliyet 50.
    final lotlar = [
      lot(type: AssetType.bes, ticker: 'TEFAS:AH5', sub: 'katki',
          qty: 10000, price: 0.02, current: 0.03, sozlesmeId: sid),
      lot(type: AssetType.bes, ticker: 'TEFAS:AEK', sub: 'dk',
          qty: 2000, price: 0.025, current: 0.03, sozlesmeId: sid),
    ];
    final d = besDokumu(s, lotlar, DateTime(2026, 9, 30));
    expect(d.toplam, closeTo(360, 1e-9));
    expect(d.katki, closeTo(200, 1e-9));
    expect(d.devlet, closeTo(50, 1e-9));
    expect(d.katki + d.devlet + d.getiri, closeTo(d.toplam, 1e-9));
    expect(d.hakEdis, 35);
    expect(d.eldeKalan, closeTo(300 + 60 * 0.35, 1e-9));
  });

  test('mevduat birim değeri lot miktarıyla portföy tutarını verir', () {
    final bas = DateTime(2026, 9, 1);
    final d = [
      MevduatDonemi(
          id: 'd',
          sozlesmeId: sid,
          baslangic: bas,
          vadeSonu: bas.add(const Duration(days: 32)),
          yillikFaiz: 42,
          stopaj: 17.5),
    ];
    final b = MevduatHesabi.birimDeger(d, bas.add(const Duration(days: 32)))!;
    final a = lot(
        type: AssetType.mevduat,
        ticker: mevduatSembolu(sid),
        qty: 250000,
        price: 1,
        current: b);
    expect(a.totalCost, 250000);
    expect(a.totalValue - a.totalCost, closeTo(7594.52, 0.01));
  });

  test('hızlı alımla sözleşme kimliksiz yazılmış mevduat lotu sözleşmeye sayılır',
      () {
    final s = Sozlesme(
      id: sid,
      userId: 'u',
      tur: SozlesmeTuru.mevduat,
      kurum: 'Banka',
      baslangic: DateTime(2026, 9, 1),
    );
    final bagli = lot(
        type: AssetType.mevduat, ticker: mevduatSembolu(sid), sozlesmeId: sid);
    // Eski sürümün "+" ile yazdığı lot: sembol var, sozlesme_id yok.
    final yetim =
        lot(type: AssetType.mevduat, ticker: mevduatSembolu(sid), qty: 2);
    final baska = lot(
        type: AssetType.mevduat,
        ticker: mevduatSembolu('00000000-0000-4000-8000-000000000002'),
        qty: 3);
    expect(sozlesmeLotuMu(bagli, s), isTrue);
    expect(sozlesmeLotuMu(yetim, s), isTrue);
    expect(sozlesmeLotuMu(baska, s), isFalse);

    // BES'te sembol sözleşmeye özgü değil: yalnız kimlik sayılır.
    final bes = Sozlesme(
      id: sid,
      userId: 'u',
      tur: SozlesmeTuru.bes,
      kurum: 'Emeklilik',
      baslangic: DateTime(2026, 1, 1),
    );
    expect(sozlesmeLotuMu(lot(type: AssetType.bes, ticker: 'TEFAS:AH5'), bes),
        isFalse);
    expect(
        sozlesmeLotuMu(
            lot(type: AssetType.bes, ticker: 'TEFAS:AH5', sozlesmeId: sid),
            bes),
        isTrue);
  });
}
