import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/price_service.dart';

/// truncgil `v4/today.json` KESİK geliyor — birincil kaynak boşuna düşmesin.
///
/// Ölçüm (2026-09-17): gövde sunucu tarafında 6.805 baytta kesiliyor
/// (`Content-Length` de 6805, son giriş `"Chang` ile yarım; üç ardışık
/// istekte aynı). `jsonDecode` reddedince altın ve döviz o turda yedeğe
/// (Yahoo paritesi / er-api, ~%1,8 farklı ölçek) iniyordu. `OlcekHafizasi`
/// oranı ancak bir birincil gözlemden öğrenebilir; kaynak kalıcı kesikse hiç
/// öğrenemez. Gövde kurtarılınca birincil fiyat elde kalır, yedek hiç
/// devreye girmez.
void main() {
  // Gerçek v4 yapısı: düz sözlük, her giriş düz alanlar (iç içe nesne yok).
  const tamGovde = '{"Update_Date":"2026-09-17 19:12:01",'
      '"USD":{"Buying":48.6717,"Type":"Currency","Selling":48.6767,"Change":0.04},'
      '"EUR":{"Buying":55.9754,"Type":"Currency","Selling":55.9906,"Change":0.28},'
      '"YIA":{"Buying":6212.28,"Type":"Gold","Name":"22AYARBILEZIK","Selling":6219.29,"Change":0.59},'
      '"GRAMPALADYUM":{"Buying":2019.87,"Type":"Palladium","Name":"GRAMPALADYUM","Selling":2028.42,"Change":1.43}}';

  group('kesik truncgil gövdesi', () {
    test('tam gövde düz jsonDecode ile birebir aynı', () {
      final beklenen = jsonDecode(tamGovde) as Map<String, dynamic>;
      expect(PriceService.parseTruncgilBody(tamGovde), equals(beklenen));
    });

    test('kesik gövdeden bütün girişler kurtarılır, yarım giriş atılır', () {
      // Gerçek arıza: gövde son girişin ortasında, `"Chang` ile bitiyor.
      final kesik = tamGovde.substring(0, tamGovde.indexOf('"Change":1.43'));
      expect(() => jsonDecode(kesik), throwsFormatException,
          reason: 'fikstür gerçekten kesik olmalı');

      final d = PriceService.parseTruncgilBody(kesik);
      expect(d['USD'], isA<Map<String, dynamic>>());
      expect((d['USD'] as Map<String, dynamic>)['Buying'], 48.6717);
      expect((d['YIA'] as Map<String, dynamic>)['Buying'], 6212.28,
          reason: 'altın anahtarı kesim noktasından önce — kurtarılmalı');
      expect(d.containsKey('GRAMPALADYUM'), isFalse,
          reason: 'yarım kalan giriş uydurulmamalı');
    });

    test('JSON olmayan gövde (HTML hata sayfası) kurtarılmaya çalışılmaz', () {
      const html = '<html><body>"USD":{"Buying":1}</body></html>';
      expect(() => PriceService.parseTruncgilBody(html),
          throwsFormatException,
          reason: 'çöp sayfadan tesadüfen eşleşen bir çift fiyat üretmemeli');
    });

    test('hiç giriş kurtarılamazsa hata yayılır', () {
      expect(() => PriceService.parseTruncgilBody('{"USD":{"Buy'),
          throwsFormatException);
    });

    test('ağ yolu kurtarıcı ayrıştırıcıyı kullanır', () {
      final src = File('lib/services/price_service.dart').readAsStringSync();
      expect(src.contains('return parseTruncgilBody(res.body);'), isTrue,
          reason: 'truncgil çekimi düz jsonDecode\'a geri dönmüş — kesik '
              'gövde yine yedeğe düşürür');
    });
  });
}
