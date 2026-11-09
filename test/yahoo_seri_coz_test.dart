import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/price_service.dart';

/// Yahoo grafik yanıtı ayrıştırıcıları. `yahooSeriCoz`: gün içi seanslı
/// enstrümanda önceki kapanış ilk barın bir
/// slot öncesine eklenir (gerekçe fonksiyonun başında).
void main() {
  Map<String, dynamic> yanit(String? tur, {double? onceki}) => {
        'chart': {
          'result': [
            {
              'meta': {
                if (tur != null) 'instrumentType': tur,
                if (onceki != null) 'chartPreviousClose': onceki,
              },
              'timestamp': [1000, 1300, 1600],
              'indicators': {
                'quote': [
                  {'close': [296.0, null, 300.0]}
                ]
              },
            }
          ]
        }
      };

  test('hisse gün içi: önceki kapanış ilk barın bir slot öncesinde', () {
    final s = yahooSeriCoz(yanit('EQUITY', onceki: 294.12), gunIci: true);
    expect(s, [
      (1000000 - 300000, 294.12),
      (1000000, 296.0),
      (1600000, 300.0),
    ]);
  });

  test('ETF ve endeks de seanslı', () {
    for (final t in ['ETF', 'INDEX']) {
      expect(yahooSeriCoz(yanit(t, onceki: 10), gunIci: true), hasLength(3));
    }
  });

  test('döviz, vadeli, gün içi olmayan aralık, kapanışsız yanıt: dokunulmaz',
      () {
    expect(yahooSeriCoz(yanit('CURRENCY', onceki: 41), gunIci: true),
        hasLength(2));
    expect(yahooSeriCoz(yanit('FUTURE', onceki: 41), gunIci: true),
        hasLength(2));
    expect(yahooSeriCoz(yanit('EQUITY', onceki: 294), gunIci: false),
        hasLength(2));
    expect(yahooSeriCoz(yanit('EQUITY'), gunIci: true), hasLength(2));
    expect(yahooSeriCoz(yanit('EQUITY', onceki: 0), gunIci: true),
        hasLength(2));
    expect(yahooSeriCoz(yanit(null, onceki: 294), gunIci: true), hasLength(2));
  });

  test('boş yanıt boş', () {
    expect(yahooSeriCoz(const {}, gunIci: true), isEmpty);
  });

  group('yahooGrafikKotasyonu (toplu uç düşünce yedek yol)', () {
    Map<String, dynamic> kotasyon(Map<String, dynamic> meta) => {
          'chart': {
            'result': [
              {'meta': meta}
            ]
          }
        };

    test('yüzde aynı yanıtın önceki kapanışından', () {
      final q = yahooGrafikKotasyonu('THYAO.IS', kotasyon({
        'regularMarketPrice': 300.0,
        'chartPreviousClose': 294.12,
        'currency': 'TRY',
      }))!;
      expect(q.regularMarketPrice, 300.0);
      expect(q.regularMarketChangePercent, closeTo(1.9992, 1e-4));
      expect(q.currency, 'TRY');
    });

    test('önceki kapanış yoksa yüzde yok (uydurma yok)', () {
      final q = yahooGrafikKotasyonu(
          'THYAO.IS', kotasyon({'regularMarketPrice': 300.0}))!;
      expect(q.regularMarketChangePercent, isNull);
      expect(
          yahooGrafikKotasyonu('THYAO.IS', kotasyon({
            'regularMarketPrice': 300.0,
            'chartPreviousClose': 0,
          }))!
              .regularMarketChangePercent,
          isNull);
    });

    test('fiyat yoksa kotasyon yok', () {
      expect(yahooGrafikKotasyonu('X', kotasyon({'chartPreviousClose': 1})),
          isNull);
      expect(yahooGrafikKotasyonu('X', const {}), isNull);
    });
  });
}
