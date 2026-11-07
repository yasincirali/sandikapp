import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/hafta_ozeti_provider.dart';
import 'package:portfoy_takip/services/aylik_rapor_ozeti.dart';
import 'package:portfoy_takip/services/fon_akisi.dart';
import 'package:portfoy_takip/services/hisse_hacmi.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/varlik_analizi.dart';

/// Aylık raporun sayısal bölümleri (yasin 2026-11-07: "tüm varlıkların …
/// para giriş çıkışları, önemli … detaylar da olmalı"). Saf fonksiyonlar:
/// uydurma yok, veri yoksa satır yok, net katkı Performans'la aynı tanım.
Asset _lot(
  String id, {
  String ticker = 'THYAO.IS',
  AssetType tur = AssetType.hisse,
  AssetKind kind = AssetKind.buy,
  double miktar = 10,
  double fiyat = 100,
  double? satis,
  double temettu = 0,
  required DateTime tarih,
  DateTime? silindi,
}) =>
    Asset(
      id: id,
      userId: 'u',
      name: ticker,
      ticker: ticker,
      type: tur,
      quantity: miktar,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      kind: kind,
      sellPrice: satis,
      dividendAmount: temettu,
      addedDate: tarih,
      deletedAt: silindi,
    );

void main() {
  final bas = DateTime(2026, 10, 1);
  final bit = DateTime(2026, 10, 31);

  group('pencere', () {
    test('kapanmış ay: ayın son günü', () {
      final (b, e, suren) =
          AylikRaporOzeti.pencere(DateTime(2026, 10), DateTime(2026, 11, 7));
      expect(
          (b, e, suren), (DateTime(2026, 10), DateTime(2026, 10, 31), false));
    });
    test('süren ay: bugün', () {
      final (b, e, suren) = AylikRaporOzeti.pencere(
          DateTime(2026, 11), DateTime(2026, 11, 7, 15));
      expect((b, e, suren), (DateTime(2026, 11), DateTime(2026, 11, 7), true));
    });
  });

  group('ayinParaAkisi', () {
    final lotlar = [
      _lot('a1', tarih: DateTime(2026, 9, 30, 23)), // ay öncesi
      _lot('a2', tarih: DateTime(2026, 10, 1, 0, 0, 1)), // ilk gün
      _lot('a3', tarih: DateTime(2026, 10, 31, 23, 59)), // son gün
      _lot('s1',
          kind: AssetKind.sell,
          miktar: 4,
          satis: 130,
          tarih: DateTime(2026, 10, 15)),
      _lot('t1',
          kind: AssetKind.dividend,
          miktar: 0,
          temettu: 250,
          tarih: DateTime(2026, 10, 20)),
      _lot('x1',
          tarih: DateTime(2026, 10, 10),
          silindi: DateTime(2026, 10, 11)), // silinmiş: sayılmaz
      _lot('a4', tarih: DateTime(2026, 11, 1)), // ay sonrası
    ];

    test('ay içi alım, satış, temettü; silinmiş ve ay dışı yok', () {
      final a = ayinParaAkisi(lotlar, bas, bit);
      expect(a.alimSayisi, 2);
      expect(a.alimTRY, 2000);
      expect(a.satisSayisi, 1);
      expect(a.satisTRY, 520);
      expect(a.temettuSayisi, 1);
      expect(a.temettuTRY, 250);
      expect(a.netTRY, 2000 - 520 - 250);
    });

    test('net = Performans köprüsünün "Net katkın" tanımı (tek hesap)', () {
      final a = ayinParaAkisi(lotlar, bas, bit);
      expect(
          a.netTRY,
          closeTo(
              PeriodSummaryService.netInflow(lotlar, bas, bit,
                  temettuCikis: true),
              1e-9));
    });

    test('akış yoksa boş (bölüm çizilmez)', () {
      expect(ayinParaAkisi([lotlar.first], bas, bit).bos, isTrue);
    });
  });

  group('ayinVarliklari', () {
    int ms(int g) => DateTime(2026, 10, g).millisecondsSinceEpoch;
    final thy = _lot('a1', tarih: DateTime(2026, 9, 1));
    final altin = _lot('g1',
        ticker: 'GC=F', tur: AssetType.altin, tarih: DateTime(2026, 9, 1));

    test('serisi olan her varlık bir satır; serisi olmayan yok', () {
      final r = ayinVarliklari(
        byPosition: {
          positionKey(thy): {ms(1): 1000, ms(31): 1100},
          positionKey(altin): {ms(1): 2000, ms(31): 1900},
        },
        positionType: {
          positionKey(thy): AssetType.hisse,
          positionKey(altin): AssetType.altin,
        },
        lotlar: [
          thy,
          altin,
          _lot('e1', ticker: 'AFT', tarih: DateTime(2026, 9, 1))
        ],
        bas: bas,
        son: DateTime(2026, 10, 31, 23, 59),
      );
      expect(r.map((v) => v.anahtar), [positionKey(thy), positionKey(altin)]);
      expect(r.first.pct, closeTo(10, 1e-9));
      expect(r.first.piyasaTRY, closeTo(100, 1e-9));
      expect(r.last.pct, closeTo(-5, 1e-9));
      expect(r.last.tur, AssetType.altin);
    });

    test('tek noktalı ya da boş seri satır üretmez (uydurma yok)', () {
      final r = ayinVarliklari(
        byPosition: {positionKey(thy): {}},
        positionType: const {},
        lotlar: [thy],
        bas: bas,
        son: bit,
      );
      expect(r, isEmpty);
    });
  });

  group('ayinGelismeleri', () {
    test('ay dışı olay düşer, yeniden eskiye, temettü defterden', () {
      final g = ayinGelismeleri(
        bas: bas,
        bit: bit,
        fonOlaylari: {
          'TTE': [
            FonBalinaOlayi(
                tarih: DateTime.utc(2026, 10, 12),
                tutar: 85e6,
                buyuklukOrani: 0.031,
                sapmaKati: 3),
            FonBalinaOlayi(
                tarih: DateTime.utc(2026, 9, 29),
                tutar: -40e6,
                buyuklukOrani: 0.02,
                sapmaKati: 3),
          ],
        },
        hacimOlaylari: {
          'BTC': [
            HacimOlayi(
                tarih: DateTime.utc(2026, 10, 20),
                yukselis: false,
                paraHacmi: 2.6e9,
                ortalamaKati: 2.4,
                fiyatDegisim: -0.041),
          ],
        },
        dolarKodlari: const {'BTC'},
        lotlar: [
          _lot('t1',
              kind: AssetKind.dividend,
              miktar: 0,
              temettu: 1250,
              tarih: DateTime(2026, 10, 5)),
        ],
      );
      expect(g.map((x) => (x.kod, x.tur)), [
        ('BTC', AyinGelismeTuru.hacimDusus),
        ('TTE', AyinGelismeTuru.fonGiris),
        ('THYAO', AyinGelismeTuru.temettu),
      ]);
      expect(g[0].dolar, isTrue);
      expect(g[1].tutar, 85e6);
      expect(g[2].tutar, 1250);
    });

    test('olay yoksa boş', () {
      expect(ayinGelismeleri(bas: bas, bit: bit), isEmpty);
    });
  });

  test('notVeriAraligi: en erken → en geç; aralıksız notta null', () {
    AnalizOzeti n(DateTime? b, DateTime? e) => AnalizOzeti(
        ticker: 'X',
        donem: DateTime.utc(2026, 10),
        baslik: 'b',
        rozet: 'sakin',
        maddeSayisi: 1,
        veriBaslangic: b,
        veriBitis: e);
    expect(
        notVeriAraligi([
          n(DateTime.utc(2026, 10, 2), DateTime.utc(2026, 10, 30)),
          n(DateTime.utc(2026, 10, 1), DateTime.utc(2026, 10, 29)),
        ]),
        (DateTime.utc(2026, 10, 1), DateTime.utc(2026, 10, 30)));
    expect(notVeriAraligi([n(null, null)]), isNull);
  });

  test('isaretliTL', () {
    expect(isaretliTL(1250), '+₺1.250');
    expect(isaretliTL(-480), '−₺480');
    expect(isaretliTL(0.2), '₺0');
  });

  test('haftaAraligi: fonun son haftası + hissenin son 7 günü', () {
    expect(haftaAraligi(const []), isNull);
    final p =
        aggregatePositions([_lot('a1', tarih: DateTime(2026, 9, 1))]).single;
    final fon = HaftaSatiri(
        pozisyon: p,
        tur: HaftaVarlikTuru.fon,
        anahtar: 'TEFAS:TTE',
        rozet: HaftaRozeti.sakin,
        onem: 0,
        fon: FonAkisOzeti(
          haftalar: const [],
          sonHaftaNet: 1,
          sonHaftaIlkGun: DateTime(2026, 11, 3),
          veriTarihi: DateTime(2026, 11, 5),
          buyukluk: 100,
          yatirimci: null,
          yatirimciDegisimi: null,
          olaylar: const [],
        ));
    final gun =
        HacimGunu(tarih: DateTime(2026, 11, 6), kapanis: 10, paraHacmi: 1e6);
    final hisse = hacimSatiri(
        p,
        'THYAO.IS',
        HacimOzeti(
            gunler: [gun],
            sonGun: gun,
            ortalama: null,
            kat: null,
            fiyatDegisim: null,
            olaylar: const []),
        kripto: false);
    expect(haftaAraligi([fon, hisse]),
        (DateTime(2026, 10, 31), DateTime(2026, 11, 6)));
  });
}
