import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// **Grafik çekimlerinin TEK kapısı — performans sözleşmesi.**
///
/// Dört grafik yolu üç ayrı yerel closure ile çekim yapıyordu. Üçü de aynı
/// işi yapıyor görünüyordu ama ayrışmışlardı ve her ayrışma ölçülebilir bir
/// maliyetti:
///
///   1. **Timeout yalnızca birinde vardı.** 2026-09-13'te konan 8 saniyelik
///      üst sınır gün içi ve günlük yollarda hiç uygulanmıyordu; oralarda tek
///      koruma alt katmandaki 15 saniyeydi. "Kimse bu kadar beklemez"
///      şikâyeti o yollarda hâlâ geçerliydi.
///   2. **Uçuşan istek tekilleştirmesi hiçbirinde yoktu.** Takip listesinde
///      10 satır aynı anda `USDTRY=X` isterse 10 ayrı HTTP çağrısı gidiyordu.
///   3. **Boş yanıt hatırlanmıyordu.** Veri VERMEYEN bir sembol her
///      tazelemede yeniden isteniyor, her seferinde timeout'a kadar
///      bekletiyordu — altın kaynağının "bazen spot, bazen vadeli"
///      savrulmasının yakıtı da buydu.
///
/// Testler ağa çıkmaz: çekim kapısı `HistoryService.seriCekici` ile enjekte
/// edilir (`tefasNavGozlemKaynagi` ile aynı desen).
void main() {
  late List<String> cagrilar;

  setUp(() {
    HistoryService.clearCache();
    cagrilar = [];
  });

  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    HistoryService.clearCache();
  });

  void kaynak(
    Future<List<(int, double)>> Function(String sym) yanit,
  ) {
    HistoryService.seriCekici = (sym, range, interval) {
      cagrilar.add('$sym|$range|${interval ?? "-"}');
      return yanit(sym);
    };
  }

  group('uçuşan istek tekilleştirmesi', () {
    test('aynı anda 10 çağrı TEK isteğe biner', () async {
      final tamamlayici = Completer<List<(int, double)>>();
      kaynak((_) => tamamlayici.future);

      final futures = [
        for (var i = 0; i < 10; i++)
          HistoryService.instance.seriCek(FiyatKaynagi.usdTry, '1mo'),
      ];
      tamamlayici.complete([(1, 42.0)]);
      final sonuclar = await Future.wait(futures);

      expect(cagrilar.length, 1,
          reason: 'Takip listesindeki her satır için ayrı HTTP çağrısı '
              'gidiyor — kapı tekilleştirmiyor.');
      for (final s in sonuclar) {
        expect(s, [(1, 42.0)]);
      }
    });

    test('istek bitince kayıt düşer — sonraki çağrı yeniden çeker', () async {
      kaynak((_) async => [(1, 42.0)]);
      await HistoryService.instance.seriCek('AAPL', '1mo');
      HistoryService.clearCache();
      await HistoryService.instance.seriCek('AAPL', '1mo');
      expect(cagrilar.length, 2,
          reason: 'Uçuşan istek haritası sızdırıyor — sembol bir daha hiç '
              'tazelenmez.');
    });
  });

  group('önbellek', () {
    test('ikinci çağrı ağa ÇIKMAZ', () async {
      kaynak((_) async => [(1, 100.0)]);
      await HistoryService.instance.seriCek('THYAO.IS', '1mo');
      await HistoryService.instance.seriCek('THYAO.IS', '1mo');
      expect(cagrilar.length, 1);
    });

    test('farklı range/interval AYRI anahtar', () async {
      kaynak((_) async => [(1, 100.0)]);
      await HistoryService.instance.seriCek('THYAO.IS', '1mo');
      await HistoryService.instance.seriCek('THYAO.IS', '3mo');
      await HistoryService.instance
          .seriCek('THYAO.IS', '3mo', interval: '1wk');
      expect(cagrilar.length, 3,
          reason: 'Anahtar çakışırsa bir dönem başka dönemin verisini çizer.');
    });
  });

  group('negatif önbellek', () {
    test('boş yanıt kısa süre tekrar SORULMAZ', () async {
      kaynak((_) async => const []);
      await HistoryService.instance.seriCek(FiyatKaynagi.xauTry, '1d');
      await HistoryService.instance.seriCek(FiyatKaynagi.xauTry, '1d');
      await HistoryService.instance.seriCek(FiyatKaynagi.xauTry, '1d');
      expect(cagrilar.length, 1,
          reason: 'Veri vermeyen sembol her tazelemede yeniden sorulup '
              'timeout\'a kadar bekletiyor.');
    });

    test('boş yanıt KALICI önbelleğe girmez — veri gelince kullanılır',
        () async {
      // Negatif önbellek 60 sn; TTL dolmadan doğrudan ölçemeyiz ama
      // `clearCache` sonrası yeni verinin ALINDIĞINI doğrulayabiliriz.
      // Asıl korunan değişmez: boşluk kalıcı bir "bu sembol yok" kaydına
      // dönüşmemeli.
      var bos = true;
      kaynak((_) async => bos ? const [] : [(1, 42.0)]);
      expect(await HistoryService.instance.seriCek('X', '1mo'), isEmpty);
      bos = false;
      HistoryService.clearCache();
      expect(await HistoryService.instance.seriCek('X', '1mo'), isNotEmpty);
    });

    test('hata da boş sayılır — istisna yukarı SIZMAZ', () async {
      kaynak((_) async => throw StateError('ağ yok'));
      expect(await HistoryService.instance.seriCek('X', '1mo'), isEmpty);
    });
  });

  group('zaman aşımı', () {
    test('yanıt gelmezse kapı 8 saniyede boş döner', () {
      // Gerçek 8 saniye beklenmez: `fake_async` zamanı ileri sarar.
      // Ölçülen şey `_grafikCekimSuresi`nin bu kapıda UYGULANDIĞI —
      // gün içi ve günlük yollarda eskiden hiç uygulanmıyordu ve kullanıcı
      // alt katmandaki 15 saniyeyi bekliyordu.
      fakeAsync((zaman) {
        HistoryService.seriCekici =
            (sym, range, interval) => Completer<List<(int, double)>>().future;

        Object? sonuc;
        HistoryService.instance.seriCek('DONMUS', '1mo').then((v) => sonuc = v);

        zaman.elapse(const Duration(seconds: 7));
        zaman.flushMicrotasks();
        expect(sonuc, isNull, reason: 'Sınırdan önce vazgeçilmemeli.');

        zaman.elapse(const Duration(seconds: 2));
        zaman.flushMicrotasks();
        expect(sonuc, isEmpty,
            reason: 'Üst sınır uygulanmıyor — kullanıcı boş ekrana bakıyor.');
      });
    });

    test('zaman aşımı negatif önbelleğe yazar — peş peşe donma olmaz', () {
      fakeAsync((zaman) {
        var istek = 0;
        HistoryService.seriCekici = (sym, range, interval) {
          istek++;
          return Completer<List<(int, double)>>().future;
        };

        HistoryService.instance.seriCek('DONMUS', '1mo');
        zaman.elapse(const Duration(seconds: 9));
        zaman.flushMicrotasks();

        HistoryService.instance.seriCek('DONMUS', '1mo');
        zaman.flushMicrotasks();

        expect(istek, 1,
            reason: 'Donan sembol her tazelemede yeniden sorulursa her '
                'seferinde 8 saniye kaybedilir.');
      });
    });
  });
}
