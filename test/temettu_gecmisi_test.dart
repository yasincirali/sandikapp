import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/temettu_gecmisi.dart';

import 'helpers/kaynak.dart';

/// Temettü yakalama — istemcinin saf katmanı (plan §F5).
///
/// Kilitlenenler: (1) Yahoo olayı → öneri, geçersiz tutar öneri doğurmaz;
/// (2) hak tarihinde lot — o gün alan almaz, o gün satan alır, temettü
/// miktara girmez, başka sahip/sembol karışmaz; (3) kayıt eşleme bire bir;
/// (4) stopaj bilinmiyorsa öneri tutarı YOK: alan boş, brüt yalnız dayanak (#12).

Asset _satir({
  required String id,
  String userId = 'u1',
  String ticker = 'THYAO.IS',
  AssetType type = AssetType.hisse,
  String currency = 'TRY',
  double quantity = 100,
  AssetKind kind = AssetKind.buy,
  DateTime? tarih,
  double dividendAmount = 0,
  DateTime? deletedAt,
  bool manuel = false,
}) =>
    Asset(
      id: id,
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: quantity,
      purchasePrice: 10,
      currency: currency,
      notes: '',
      currentPrice: 12,
      addedDate: tarih ?? DateTime.utc(2025, 6, 1, 9),
      kind: kind,
      dividendAmount: dividendAmount,
      deletedAt: deletedAt,
      isManualPrice: manuel,
    );

DateTime _gun(int y, int m, int d) => DateTime.utc(y, m, d);

Map<String, dynamic> _yahoo(List<(String, Object?)> olaylar) {
  final div = <String, dynamic>{};
  for (final (gun, tutar) in olaylar) {
    // BIST hak kullanımı Yahoo'da seans açılışı civarı (06:30 UTC) damgalı.
    final sn = DateTime.parse('${gun}T06:30:00Z').millisecondsSinceEpoch ~/ 1000;
    div['$sn'] = {'date': sn, 'amount': tutar};
  }
  return {
    'chart': {
      'result': [
        {
          'events': {'dividends': div}
        }
      ]
    }
  };
}

void main() {
  final simdi = DateTime.utc(2025, 9, 1, 12);
  final thyao = _satir(id: 'a');

  group('trGunu', () {
    test('UTC 21:30 → TR ertesi gün', () {
      expect(trGunu(DateTime.utc(2025, 6, 15, 21, 30)), _gun(2025, 6, 16));
      expect(trGunu(DateTime.utc(2025, 6, 15, 20, 30)), _gun(2025, 6, 15));
    });
  });

  group('olaylariAyristir', () {
    test('pencere içi olaylar, yeniden eskiye', () {
      final o = TemettuGecmisi.olaylariAyristir(
        _yahoo([('2025-06-16', 3.442), ('2024-12-02', 1.5)]),
        simdi: simdi,
      );
      expect(o, [
        TemettuOlayi(hakTarihi: _gun(2025, 6, 16), tutarPay: 3.442),
        TemettuOlayi(hakTarihi: _gun(2024, 12, 2), tutarPay: 1.5),
      ]);
    });

    test('365 günden eski olay atılır', () {
      final o = TemettuGecmisi.olaylariAyristir(
          _yahoo([('2024-08-01', 2.0)]),
          simdi: simdi);
      expect(o, isEmpty);
    });

    test('okunamayan / sıfır / negatif tutar ÖNERİ DOĞURMAZ', () {
      final o = TemettuGecmisi.olaylariAyristir(
        _yahoo([
          ('2025-06-10', 'abc'),
          ('2025-06-11', 0),
          ('2025-06-12', -1),
          ('2025-06-13', null),
        ]),
        simdi: simdi,
      );
      expect(o, isEmpty);
    });

    test('bozuk gövde → boş', () {
      expect(TemettuGecmisi.olaylariAyristir(null, simdi: simdi), isEmpty);
      expect(TemettuGecmisi.olaylariAyristir({'chart': 1}, simdi: simdi),
          isEmpty);
      expect(
          TemettuGecmisi.olaylariAyristir({
            'chart': {'result': <Object>[]}
          }, simdi: simdi),
          isEmpty);
    });
  });

  group('hak tarihinde lot', () {
    final hak = _gun(2025, 6, 16);

    test('hak gününden ÖNCE alınan lot sayılır', () {
      expect(TemettuGecmisi.hakTarihindekiLot([thyao], thyao, hak), 100);
    });

    test('hak günü ve sonrası alım hak kazandırmaz', () {
      final d = [
        thyao,
        _satir(id: 'b', quantity: 50, tarih: DateTime.utc(2025, 6, 16, 8)),
        _satir(id: 'c', quantity: 25, tarih: DateTime.utc(2025, 7, 1)),
      ];
      expect(TemettuGecmisi.hakTarihindekiLot(d, thyao, hak), 100);
    });

    test('hak günü satış hakkı düşürmez; öncesindeki düşürür', () {
      final d = [
        thyao,
        _satir(
            id: 's1',
            kind: AssetKind.sell,
            quantity: 30,
            tarih: DateTime.utc(2025, 6, 10)),
        _satir(
            id: 's2',
            kind: AssetKind.sell,
            quantity: 70,
            tarih: DateTime.utc(2025, 6, 16, 8)),
      ];
      expect(TemettuGecmisi.hakTarihindekiLot(d, thyao, hak), 70);
    });

    test('TR gece yarısı: 15 Haziran 23:30 TR alımı hak kazandırır', () {
      final a = _satir(id: 'a', tarih: DateTime.utc(2025, 6, 15, 20, 30));
      expect(TemettuGecmisi.hakTarihindekiLot([a], a, hak), 100);
      final b = _satir(id: 'b', tarih: DateTime.utc(2025, 6, 15, 21, 30));
      expect(TemettuGecmisi.hakTarihindekiLot([b], b, hak), 0);
    });

    test('temettü satırı miktara GİRMEZ; silinen lot sayılmaz', () {
      final d = [
        thyao,
        _satir(
            id: 'd',
            kind: AssetKind.dividend,
            quantity: 999,
            tarih: DateTime.utc(2025, 5, 1)),
        _satir(id: 'x', quantity: 40, deletedAt: DateTime.utc(2025, 8, 1)),
        _satir(id: 't', kind: AssetKind.deleteLog, quantity: 40),
      ];
      expect(TemettuGecmisi.hakTarihindekiLot(d, thyao, hak), 100);
    });

    test('başka sahip ve başka sembol karışmaz', () {
      final d = [
        thyao,
        _satir(id: 'o', userId: 'ortak', quantity: 500),
        _satir(id: 'e', ticker: 'EREGL.IS', quantity: 700),
      ];
      expect(TemettuGecmisi.hakTarihindekiLot(d, thyao, hak), 100);
    });
  });

  group('satırlar ve eşleme', () {
    final olaylar = [
      TemettuOlayi(hakTarihi: _gun(2025, 6, 16), tutarPay: 3.442),
      TemettuOlayi(hakTarihi: _gun(2024, 12, 2), tutarPay: 1.5),
    ];

    test('hak tarihinde lot yoksa satır yok', () {
      // Alım 2025-06-01: Aralık 2024 olayında lot yok.
      final s = TemettuGecmisi.satirlar(
          varlik: thyao, defter: [thyao], olaylar: olaylar);
      expect(s, hasLength(1));
      expect(s.single.olay.hakTarihi, _gun(2025, 6, 16));
      expect(s.single.lot, 100);
      expect(s.single.brut, closeTo(344.2, 1e-9));
      expect(s.single.kaydedildi, isFalse);
    });

    test('pencere içindeki kayıt olayı karşılar', () {
      final kayit = _satir(
          id: 'd',
          kind: AssetKind.dividend,
          quantity: 0,
          dividendAmount: 292.57,
          tarih: DateTime.utc(2025, 6, 18, 9));
      final s = TemettuGecmisi.satirlar(
          varlik: thyao, defter: [thyao, kayit], olaylar: olaylar);
      expect(s.single.kaydedildi, isTrue);
      expect(s.single.kayit!.id, 'd');
    });

    test('pencere dışı kayıt (60 günden geç) karşılamaz', () {
      final kayit = _satir(
          id: 'd',
          kind: AssetKind.dividend,
          quantity: 0,
          tarih: DateTime.utc(2025, 8, 20));
      final s = TemettuGecmisi.satirlar(
          varlik: thyao, defter: [thyao, kayit], olaylar: olaylar);
      expect(s.single.kaydedildi, isFalse);
    });

    test('eşleme BİRE BİR: tek kayıt iki olayı birden karşılamaz', () {
      final eski = _satir(id: 'a', tarih: DateTime.utc(2024, 1, 1));
      final iki = [
        TemettuOlayi(hakTarihi: _gun(2025, 6, 16), tutarPay: 2),
        TemettuOlayi(hakTarihi: _gun(2025, 5, 20), tutarPay: 1),
      ];
      final kayit = _satir(
          id: 'd',
          kind: AssetKind.dividend,
          quantity: 0,
          tarih: DateTime.utc(2025, 6, 17, 9));
      final s = TemettuGecmisi.satirlar(
          varlik: eski, defter: [eski, kayit], olaylar: iki);
      expect(s.map((x) => x.kaydedildi), [true, false],
          reason: 'kayıt en yakın olaya (16 Haziran) gider');
    });

    test('bugün KAPALI pozisyonun geçmiş temettüsü yine görünür', () {
      final d = [
        thyao,
        _satir(
            id: 's',
            kind: AssetKind.sell,
            quantity: 100,
            tarih: DateTime.utc(2025, 8, 1)),
      ];
      final s = TemettuGecmisi.satirlar(
          varlik: thyao, defter: d, olaylar: olaylar);
      expect(s.single.lot, 100);
    });

    test('kaydedilen toplam: son 12 ay, yalnız bu pozisyon', () {
      final d = [
        thyao,
        _satir(
            id: 'd1',
            kind: AssetKind.dividend,
            quantity: 0,
            dividendAmount: 100,
            tarih: DateTime.utc(2025, 6, 18)),
        _satir(
            id: 'd2',
            kind: AssetKind.dividend,
            quantity: 0,
            dividendAmount: 50,
            tarih: DateTime.utc(2024, 6, 18)),
        _satir(
            id: 'd3',
            ticker: 'EREGL.IS',
            kind: AssetKind.dividend,
            quantity: 0,
            dividendAmount: 70,
            tarih: DateTime.utc(2025, 6, 18)),
      ];
      expect(
          TemettuGecmisi.kaydedilenToplam(d, thyao, simdi: simdi), 100);
    });
  });

  group('öneri tutarı', () {
    test('stopaj bilinmiyorsa tutar YOK (brüt "net" diye önerilmez, #12)', () {
      final t = TemettuGecmisi.oneriTutari(344.2, null);
      expect(t.tutar, isNull);
      expect(t.net, isFalse);
    });

    test('stopaj biliniyorsa net', () {
      final t = TemettuGecmisi.oneriTutari(100, 0.15);
      expect(t.tutar, closeTo(85, 1e-9));
      expect(t.net, isTrue);
    });

    test('geçersiz oran → öneri tutarı yok', () {
      expect(TemettuGecmisi.oneriTutari(100, 1.5).net, isFalse);
      expect(TemettuGecmisi.oneriTutari(100, 1.5).tutar, isNull);
      expect(TemettuGecmisi.oneriTutari(100, -0.1).net, isFalse);
      expect(TemettuGecmisi.oneriTutari(100, double.nan).net, isFalse);
    });
  });

  group('TemettuOnerisi.fromPush', () {
    test('sunucu verisi (temettu-yakala › temettuVerisi) okunur', () {
      final o = TemettuOnerisi.fromPush({
        'type': 'temettu',
        'ticker': 'THYAO.IS',
        'hak_tarihi': '2025-06-16',
        'tutar_pay': '3.442',
        'lot': '100',
      })!;
      expect(o.ticker, 'THYAO.IS');
      expect(o.hakTarihi, _gun(2025, 6, 16));
      expect(o.brut, closeTo(344.2, 1e-9));
    });

    test('eksik / bozuk alan → null (yarım veriyle diyalog açılmaz)', () {
      Map<String, dynamic> m(Map<String, dynamic> d) => {
            'ticker': 'THYAO.IS',
            'hak_tarihi': '2025-06-16',
            'tutar_pay': '3.442',
            'lot': '100',
            ...d,
          };
      expect(TemettuOnerisi.fromPush(m({'ticker': ''})), isNull);
      expect(TemettuOnerisi.fromPush(m({'hak_tarihi': '16.06.2025'})), isNull);
      expect(TemettuOnerisi.fromPush(m({'hak_tarihi': '2025-02-31'})), isNull);
      expect(TemettuOnerisi.fromPush(m({'tutar_pay': 'abc'})), isNull);
      expect(TemettuOnerisi.fromPush(m({'tutar_pay': '0'})), isNull);
      expect(TemettuOnerisi.fromPush(m({'lot': '-5'})), isNull);
    });
  });

  group('sembol kararı fiyat_kaynagi\'nda', () {
    test('yalnız TRY kote BIST hissesi', () {
      expect(FiyatKaynagi.temettuSembolu(thyao), 'THYAO.IS');
      expect(FiyatKaynagi.temettuSembolu(_satir(id: 'x', ticker: 'thyao.is')),
          'THYAO.IS');
      expect(
          FiyatKaynagi.temettuSembolu(
              _satir(id: 'x', ticker: 'AAPL', currency: 'USD')),
          isNull);
      expect(
          FiyatKaynagi.temettuSembolu(
              _satir(id: 'x', ticker: 'TCELL.IS', currency: 'USD')),
          isNull);
      expect(
          FiyatKaynagi.temettuSembolu(
              _satir(id: 'x', ticker: 'AFA', type: AssetType.fon)),
          isNull);
      expect(FiyatKaynagi.temettuSembolu(_satir(id: 'x', manuel: true)),
          isNull);
    });
  });

  group('TemettuGecmisiService', () {
    test('events=div ister, sembol başına önbellekler', () async {
      var cagri = 0;
      Uri? son;
      final s = TemettuGecmisiService(
        client: MockClient((req) async {
          cagri++;
          son = req.url;
          return http.Response(
              jsonEncode(_yahoo([('2025-06-16', 3.442)])), 200);
        }),
      );
      final a = await s.olaylariCek('THYAO.IS', simdi: simdi);
      final b = await s.olaylariCek('THYAO.IS', simdi: simdi);
      expect(a, hasLength(1));
      expect(b, same(a));
      expect(cagri, 1);
      expect(son!.path, '/v8/finance/chart/THYAO.IS');
      expect(son!.queryParameters['events'], 'div');
    });

    test('HTTP hatası / bozuk gövde → boş liste, fırlatmaz', () async {
      final s500 = TemettuGecmisiService(
          client: MockClient((_) async => http.Response('x', 500)));
      expect(await s500.olaylariCek('THYAO.IS', simdi: simdi), isEmpty);
      final bozuk = TemettuGecmisiService(
          client: MockClient((_) async => http.Response('{bozuk', 200)));
      expect(await bozuk.olaylariCek('THYAO.IS', simdi: simdi), isEmpty);
    });
  });

  group('bağlantı noktaları (kaynak)', () {
    test('push ve çan AYNI yere gider: ön dolu diyalog', () {
      final ns = ekranKaynagiSync('lib/services/notification_service.dart');
      expect(ns.contains('type == temettuType'), isTrue);
      expect(ns.contains('TemettuOnerisi.fromPush(data)'), isTrue);
      expect(ns.contains('showDividendDialog(context, asset:'), isTrue);
      final home = ekranKaynagiSync('lib/screens/home_screen.dart');
      expect(home.contains('case AppNotification.temettu:'), isTrue);
      expect(home.contains('openTemettuOnerisi(oneri)'), isTrue);
    });

    test('varlık ekranına giriş TEK satır, kart yalnız kendi varlığında', () {
      final ad = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
      expect(
          RegExp(r'_temettuKarti\(').allMatches(ad).length, 2,
          reason: 'tanım (ozet.dart) + tek çağrı (build)');
      expect(ad.contains('if (isOwnAsset && pState != null) _temettuKarti(pState)'),
          isTrue);
    });

    test('öneri kaydı yazmaz: kayıt yalnız addDividend yolundan', () {
      for (final f in [
        'lib/services/temettu_gecmisi.dart',
        'lib/widgets/temettu_gecmisi_karti.dart',
      ]) {
        final src = ekranKaynagiSync(f);
        expect(src.contains('insertAsset'), isFalse, reason: f);
        expect(src.contains('SupabaseService'), isFalse, reason: f);
      }
    });
  });
}
