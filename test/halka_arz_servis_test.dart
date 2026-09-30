import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/halka_arz.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/services/halka_arz_service.dart';

/// Halka arz servisi ve saf kurallar (F6).
///
/// Servis sırası: bellek (1 sa) → ağ (zaman aşımlı) → dosya/gömülü (yeni
/// olan). Testler ağı `MockClient`, gömülüyü sabit metin, dosyayı geçici
/// klasörle verir; hiçbiri gerçek ağa çıkmaz.
String _json({
  String guncelleme = '2026-09-29',
  int surum = 1,
  List<Map<String, Object?>>? kayitlar,
}) =>
    jsonEncode({
      'surum': surum,
      'guncelleme': guncelleme,
      'kayitlar': kayitlar ??
          [
            {
              'kod': 'TEST',
              'sirket': 'Test A.Ş.',
              'talep_baslangic': '2026-09-01',
              'talep_bitis': '2026-09-03',
              'fiyat': 10.5,
              'dagitim': 'eşit',
              'islem_baslangic': '2026-09-10',
              'pazar': 'Yıldız Pazar',
              'kaynak': 'https://ornek.test/test',
              'guncelleme': guncelleme,
            },
          ],
    });

HalkaArz _arz({
  String? bas,
  String? bit,
  String? islem,
  double? fiyat = 10,
}) =>
    HalkaArz(
      kod: 'ABC',
      sirket: 'Abc A.Ş.',
      kaynak: 'https://ornek.test',
      talepBaslangic: bas == null ? null : HalkaArz.isoGun(bas),
      talepBitis: bit == null ? null : HalkaArz.isoGun(bit),
      islemBaslangic: islem == null ? null : HalkaArz.isoGun(islem),
      fiyat: fiyat,
    );

void main() {
  group('durum — saf kural', () {
    final a = _arz(bas: '2026-09-09', bit: '2026-09-11', islem: '2026-09-17');
    DateTime g(int ay, int gun, [int saat = 12]) =>
        DateTime(2026, ay, gun, saat);

    test('talep başlamadan önce → yaklaşan', () {
      expect(HalkaArzService.durum(a, g(9, 8, 23)), HalkaArzDurumu.yaklasan);
    });
    test('talep aralığında (iki uç dahil, gün bazlı) → talep toplanıyor', () {
      expect(HalkaArzService.durum(a, g(9, 9, 0)),
          HalkaArzDurumu.talepToplaniyor);
      expect(HalkaArzService.durum(a, g(9, 11, 23)),
          HalkaArzDurumu.talepToplaniyor,
          reason: 'son gün akşamı hâlâ talep günü');
    });
    test('talep bitti, işlem başlamadı → işlem görmeyi bekliyor', () {
      expect(HalkaArzService.durum(a, g(9, 12)), HalkaArzDurumu.islemBekliyor);
      expect(HalkaArzService.durum(a, g(9, 16, 23)),
          HalkaArzDurumu.islemBekliyor);
    });
    test('işlem başlangıç günü ve sonrası → işlem görüyor', () {
      expect(HalkaArzService.durum(a, g(9, 17, 0)),
          HalkaArzDurumu.islemGoruyor);
      expect(HalkaArzService.durum(a, g(12, 1)), HalkaArzDurumu.islemGoruyor);
    });
    test('talep bitti ama işlem tarihi yok → bekliyor (tahmin yok)', () {
      final b = _arz(bas: '2026-09-09', bit: '2026-09-11');
      expect(HalkaArzService.durum(b, g(10, 30)), HalkaArzDurumu.islemBekliyor);
    });
    test('hiç tarih yok → bilinmiyor', () {
      expect(HalkaArzService.durum(_arz(), g(9, 29)), HalkaArzDurumu.bilinmiyor);
    });
    test('yalnız talep başı biliniyor: yalnız o gün kesin', () {
      final b = _arz(bas: '2026-09-09');
      expect(HalkaArzService.durum(b, g(9, 8)), HalkaArzDurumu.yaklasan);
      expect(HalkaArzService.durum(b, g(9, 9)), HalkaArzDurumu.talepToplaniyor);
      expect(HalkaArzService.durum(b, g(9, 10)), HalkaArzDurumu.bilinmiyor);
    });
  });

  group('katılım yardımcıları', () {
    test('katılım yalnızca dağıtım belli olduktan sonra kaydedilir', () {
      expect(halkaArzKatilimKaydedilebilir(HalkaArzDurumu.islemGoruyor), isTrue);
      expect(halkaArzKatilimKaydedilebilir(HalkaArzDurumu.islemBekliyor), isTrue);
      expect(halkaArzKatilimKaydedilebilir(HalkaArzDurumu.talepToplaniyor),
          isFalse);
      expect(halkaArzKatilimKaydedilebilir(HalkaArzDurumu.yaklasan), isFalse);
      expect(halkaArzKatilimKaydedilebilir(HalkaArzDurumu.bilinmiyor), isFalse);
    });
    test('alış tarihi: işlem başladıysa işlem günü, yoksa bugün', () {
      final a = _arz(bas: '2026-09-09', bit: '2026-09-11', islem: '2026-09-17');
      expect(halkaArzAlisTarihi(a, DateTime(2026, 9, 29, 15)),
          DateTime(2026, 9, 17));
      expect(halkaArzAlisTarihi(a, DateTime(2026, 9, 14, 15)),
          DateTime(2026, 9, 14),
          reason: 'işlem gelecekte — form ileri tarih kabul etmez');
      expect(halkaArzAlisTarihi(_arz(), DateTime(2026, 9, 14, 15)),
          DateTime(2026, 9, 14));
    });
  });

  group('model okuma', () {
    test('ISO gün: takvimde olmayan gün ve başka biçimler reddedilir', () {
      expect(HalkaArz.isoGun('2026-09-29'), DateTime(2026, 9, 29));
      expect(HalkaArz.isoGun('2026-02-30'), isNull);
      expect(HalkaArz.isoGun('2026-9-1'), isNull);
      expect(HalkaArz.isoGun('2026-09-29T10:00:00Z'), isNull);
    });
    test('kaynaksız ya da tarihi bozuk kayıt listeye girmez', () {
      final l = HalkaArzListesi.fromJson(
        jsonDecode(_json(kayitlar: [
          {'kod': 'AAA', 'sirket': 'A', 'kaynak': 'https://x.test'},
          {'kod': 'BBB', 'sirket': 'B'},
          {
            'kod': 'CCC',
            'sirket': 'C',
            'kaynak': 'https://x.test',
            'talep_bitis': '2026-13-01',
          },
        ])),
        HalkaArzKaynagi.ag,
      )!;
      expect(l.kayitlar.map((e) => e.kod), ['AAA']);
    });
    test('fiyat 0 ya da negatif "bilinmiyor" okunur (uydurma değer yok)', () {
      final l = HalkaArzListesi.fromJson(
        jsonDecode(_json(kayitlar: [
          {'kod': 'AAA', 'sirket': 'A', 'kaynak': 'https://x', 'fiyat': 0},
        ])),
        HalkaArzKaynagi.ag,
      )!;
      expect(l.kayitlar.single.fiyat, isNull);
      expect(l.kayitlar.single.sembol, 'AAA.IS');
    });
    test('desteklenmeyen şema sürümü reddedilir', () {
      expect(
          HalkaArzListesi.fromJson(
              jsonDecode(_json(surum: 2)), HalkaArzKaynagi.ag),
          isNull);
    });
    test('gruplar sabit sırada; boş grup dönmez', () {
      final g = halkaArzGruplari([
        _arz(bas: '2026-09-01', bit: '2026-09-03', islem: '2026-09-10'),
        _arz(bas: '2026-10-05', bit: '2026-10-07'),
        _arz(bas: '2026-09-28', bit: '2026-09-30'),
      ], DateTime(2026, 9, 29));
      expect(g.keys.toList(), [
        HalkaArzDurumu.talepToplaniyor,
        HalkaArzDurumu.yaklasan,
        HalkaArzDurumu.islemGoruyor,
      ]);
    });
  });

  group('ekleme formu ön dolumu (isteğe bağlı parametreler)', () {
    final simdi = DateTime(2026, 9, 29, 9);

    test('prefillDate yokken eski davranış: tarih bugün', () {
      final s = AddAssetFormState.initial(
        prefillTicker: 'NETGL.IS',
        prefillType: AssetType.hisse,
        now: simdi,
      );
      expect(s.addedDate, simdi);
    });

    test('prefillDate verilince açılış tarihi o gün; düzenleme yine kazanır',
        () {
      final s = AddAssetFormState.initial(
        prefillTicker: 'NETGL.IS',
        prefillType: AssetType.hisse,
        prefillDate: DateTime(2026, 9, 17),
        now: simdi,
      );
      expect(s.addedDate, DateTime(2026, 9, 17));
      expect(s.isBist100, isTrue);
      expect(s.bist100Ticker, 'NETGL.IS');
      // Kayıt adı hisse listesinden gelir — kod değil şirket adı yazılır.
      expect(s.resolveIdentity(nameText: '', tickerText: '').name,
          'Net Global Endüstriyel');
    });
  });

  group('servis — okuma sırası', () {
    late Directory klasor;
    late File dosya;
    var saat = DateTime(2026, 9, 29, 10);

    setUp(() {
      klasor = Directory.systemTemp.createTempSync('halka_arz_test');
      dosya = File('${klasor.path}/cache.json');
      saat = DateTime(2026, 9, 29, 10);
    });
    tearDown(() async {
      // Dosyaya yazma arka planda sürüyor olabilir (Windows dosyayı açıkken
      // silmez); kısa bekleyip dene, olmazsa geçici klasörü OS'a bırak.
      for (var i = 0; i < 20; i++) {
        try {
          if (klasor.existsSync()) klasor.deleteSync(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }
    });

    HalkaArzService servis(
      http.Client client, {
      String? gomulu,
      Duration zamanAsimi = const Duration(seconds: 2),
    }) =>
        HalkaArzService(
          client: client,
          gomuluYukle: () async =>
              gomulu ?? (throw StateError('gömülü yok')),
          onbellekDosyasi: () async => dosya,
          saat: () => saat,
          zamanAsimi: zamanAsimi,
        );

    Future<void> dosyaYazilsin() async {
      for (var i = 0; i < 50 && !dosya.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('ağ başarılı → ağ listesi; gövde dosyaya da yazılır', () async {
      var istek = 0;
      final s = servis(MockClient((r) async {
        istek++;
        expect(r.url.toString(), HalkaArzService.uzakAdres);
        return http.Response.bytes(utf8.encode(_json()), 200);
      }));
      final l = await s.yukle();
      expect(l.kaynak, HalkaArzKaynagi.ag);
      expect(l.kayitlar.single.sirket, 'Test A.Ş.', reason: 'UTF-8 çözülmeli');
      expect(istek, 1);
      await dosyaYazilsin();
      expect(dosya.existsSync(), isTrue);
    });

    test('bellek önbelleği 1 saat: arada ağa çıkılmaz, zorla çıkılır',
        () async {
      var istek = 0;
      final s = servis(MockClient((r) async {
        istek++;
        return http.Response.bytes(utf8.encode(_json()), 200);
      }));
      await s.yukle();
      saat = saat.add(const Duration(minutes: 59));
      await s.yukle();
      expect(istek, 1);
      await s.yukle(zorla: true);
      expect(istek, 2);
      saat = saat.add(const Duration(hours: 2));
      await s.yukle();
      expect(istek, 3);
    });

    test('ağ yok, dosya yok → gömülü kopya (çevrimdışı ilk açılış)', () async {
      final s = servis(
        MockClient((r) async => throw const SocketException('ağ yok')),
        gomulu: _json(guncelleme: '2026-09-20'),
      );
      final l = await s.yukle();
      expect(l.kaynak, HalkaArzKaynagi.gomulu);
      expect(l.guncelleme, DateTime(2026, 9, 20));
    });

    test('zaman aşımı → çevrimdışı yol', () async {
      final s = servis(
        MockClient((r) => Completer<http.Response>().future),
        gomulu: _json(),
        zamanAsimi: const Duration(milliseconds: 50),
      );
      expect((await s.yukle()).kaynak, HalkaArzKaynagi.gomulu);
    });

    test('HTTP 404 ve şemaya uymayan gövde → çevrimdışı yol', () async {
      final s404 = servis(MockClient((r) async => http.Response('', 404)),
          gomulu: _json());
      expect((await s404.yukle()).kaynak, HalkaArzKaynagi.gomulu);
      final sSema = servis(
          MockClient((r) async => http.Response.bytes(utf8.encode(_json(surum: 9)), 200)),
          gomulu: _json());
      expect((await sSema.yukle()).kaynak, HalkaArzKaynagi.gomulu);
    });

    test('dosya gömülüden YENİ ise dosya, ESKİ ise gömülü kazanır', () async {
      final agYok = MockClient((r) async => throw http.ClientException('x'));
      dosya.writeAsStringSync(_json(guncelleme: '2026-09-25'));
      final yeniDosya =
          await servis(agYok, gomulu: _json(guncelleme: '2026-09-20')).yukle();
      expect(yeniDosya.kaynak, HalkaArzKaynagi.onbellek);

      final yeniGomulu =
          await servis(agYok, gomulu: _json(guncelleme: '2026-09-28')).yukle();
      expect(yeniGomulu.kaynak, HalkaArzKaynagi.gomulu,
          reason: 'uygulama güncellemesi daha yeni kopya getirdi');
    });

    test('çevrimdışı sonuç belleğe yazılmaz: bağlantı gelince ağ denenir',
        () async {
      var agVar = false;
      final s = servis(
        MockClient((r) async {
          if (!agVar) throw const SocketException('yok');
          return http.Response.bytes(utf8.encode(_json()), 200);
        }),
        gomulu: _json(guncelleme: '2026-09-01'),
      );
      expect((await s.yukle()).kaynak, HalkaArzKaynagi.gomulu);
      agVar = true;
      expect((await s.yukle()).kaynak, HalkaArzKaynagi.ag);
    });

    test('hiçbir kaynak yoksa hata fırlar (ekran hata görünümü gösterir)',
        () async {
      final s = servis(MockClient((r) async => http.Response('', 500)));
      await expectLater(s.yukle(), throwsStateError);
    });
  });
}
