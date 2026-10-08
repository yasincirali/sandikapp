import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/seri_disk_depo.dart';

/// **Kaynak düşünce grafik düz çizgiye DÖNMEZ (2026-10-03).**
///
/// "Kripto varlık fiyatı her zaman çekilemiyor … düz çizgiye dönüyor, tüm
/// varlıklar için gerekli bu çözüm" (yasin). Kök neden çekim kapısındaydı:
/// önbellek TTL'i dolunca giriş siliniyor, ardından gelen çekim düşerse kapı
/// BOŞ dönüyor ve varlık `currentPrice` tohumuyla dümdüz çiziliyordu — bir
/// dakika önce elde doğru seri varken. 8 sn'de vazgeçilen yanıt sonra gelse
/// de atılıyordu.
void main() {
  late Directory gecici;

  setUp(() {
    HistoryService.clearCache();
    gecici = Directory.systemTemp.createTempSync('seri_son_iyi');
  });

  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    HistoryService.gunIciSaat = DateTime.now;
    HistoryService.kaliciDepo = null;
    HistoryService.clearCache();
    if (gecici.existsSync()) gecici.deleteSync(recursive: true);
  });

  const seri = [(1000, 10.0), (2000, 11.0), (3000, 12.0)];

  test('önbellek eskidikten sonra çekim BOŞ dönerse son iyi seri çizilir',
      () async {
    var bos = false;
    HistoryService.seriCekici = (s, r, i) async => bos ? const [] : seri;
    expect(await HistoryService.instance.seriCek('KRIPTO:BTC', '1mo'), seri);

    bos = true;
    HistoryService.onbellegiEskit();
    expect(await HistoryService.instance.seriCek('KRIPTO:BTC', '1mo'), seri,
        reason: 'Kaynak bir anlığına boş döndü ve grafik düz çizgiye düştü; '
            'oysa elde bir önceki ölçüm vardı.');
  });

  test('hata da son iyi seriyle karşılanır, negatif önbellekte de', () async {
    var hata = false;
    HistoryService.seriCekici = (s, r, i) async {
      if (hata) throw StateError('429');
      return seri;
    };
    await HistoryService.instance.seriCek('AAPL', '3mo');
    hata = true;
    HistoryService.onbellegiEskit();
    expect(await HistoryService.instance.seriCek('AAPL', '3mo'), seri);
    // İkinci çağrı negatif önbelleğe düşer — orada da son iyi seri.
    expect(await HistoryService.instance.seriCek('AAPL', '3mo'), seri);
  });

  test('zaman aşımı son iyi seriyi döner; geç gelen yanıt atılmaz', () {
    fakeAsync((zaman) {
      var tur = 0;
      final gec = Completer<List<(int, double)>>();
      HistoryService.seriCekici = (s, r, i) {
        tur++;
        return tur == 1 ? Future.value(seri) : gec.future;
      };

      List<(int, double)>? sonuc;
      HistoryService.instance.seriCek('KRIPTO:ETH', '1mo').then((v) => sonuc = v);
      zaman.flushMicrotasks();
      expect(sonuc, seri);

      HistoryService.onbellegiEskit();
      sonuc = null;
      HistoryService.instance.seriCek('KRIPTO:ETH', '1mo').then((v) => sonuc = v);
      zaman.elapse(const Duration(seconds: 9));
      expect(sonuc, seri,
          reason: '8 sn aşımında elde seri varken boş dönülüyor.');

      // Yanıt aşımdan sonra gelir — kapı onu önbelleğe yazmalı.
      const yeni = [(4000, 20.0), (5000, 21.0)];
      gec.complete(yeni);
      zaman.flushMicrotasks();
      sonuc = null;
      HistoryService.instance.seriCek('KRIPTO:ETH', '1mo').then((v) => sonuc = v);
      zaman.flushMicrotasks();
      expect(sonuc, yeni,
          reason: 'Geç gelen yanıt atıldı; sonraki tik yine eski seriyi '
              'ya da düz çizgiyi çizer.');
      expect(tur, 2, reason: 'Geç yanıt önbellekteyken yeniden sorulmamalı.');
    });
  });

  test('uygulama yeniden açıldıktan sonra ilk çekim düşerse diskteki seri',
      () async {
    final depo = SeriDiskDepo(kokDizin: () async => gecici);
    HistoryService.kaliciDepo = depo;
    HistoryService.seriCekici = (s, r, i) async => seri;
    await HistoryService.instance.seriCek('THYAO.IS', '1y', interval: '1d');
    // Diske yazım arka planda; bitmesini bekle.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // "Yeniden açılış": bellek boş, kaynak yanıtsız.
    HistoryService.clearCache();
    HistoryService.seriCekici = (s, r, i) async => const [];
    expect(
        await HistoryService.instance
            .seriCek('THYAO.IS', '1y', interval: '1d'),
        seri);
  });

  test('gün içi: DÜNÜN serisi bugünün yerine çizilmez', () async {
    final dun = DateTime(2026, 10, 2, 15);
    final dunSeri = [
      (dun.millisecondsSinceEpoch, 10.0),
      (dun.add(const Duration(minutes: 5)).millisecondsSinceEpoch, 11.0),
    ];
    var bos = false;
    HistoryService.seriCekici = (s, r, i) async => bos ? const [] : dunSeri;
    HistoryService.gunIciSaat = () => DateTime(2026, 10, 2, 16);
    await HistoryService.instance.seriCek('KRIPTO:BTC', '1d', interval: '5m');

    bos = true;
    HistoryService.onbellegiEskit();
    // Aynı gün: son iyi seri kullanılır.
    expect(
        await HistoryService.instance
            .seriCek('KRIPTO:BTC', '1d', interval: '5m'),
        dunSeri);

    // Ertesi gün: dünün gün içi serisi gün başı referansına karışmasın.
    HistoryService.onbellegiEskit();
    HistoryService.gunIciSaat = () => DateTime(2026, 10, 3, 10);
    expect(
        await HistoryService.instance
            .seriCek('KRIPTO:BTC', '1d', interval: '5m'),
        isEmpty);
  });

  test('mevduat serisi diske yazılmaz (kullanıcıya özel, ağdan gelmez)',
      () async {
    HistoryService.kaliciDepo = SeriDiskDepo(kokDizin: () async => gecici);
    HistoryService.seriCekici = (s, r, i) async => seri;
    await HistoryService.instance.seriCek('MEVDUAT:abc', '1mo');
    await HistoryService.instance.seriCek('USDTRY=X', '1mo');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final dosyalar = Directory('${gecici.path}/seri_onbellek')
        .listSync()
        .map((e) => e.path)
        .toList();
    expect(dosyalar, hasLength(1));
    expect(dosyalar.single, endsWith(SeriDiskDepo.dosyaAdi('USDTRY=X_1mo')));
  });

  group('SeriDiskDepo', () {
    test('yaz → oku aynı seriyi döner; başka anahtar okunmaz', () async {
      final depo = SeriDiskDepo(kokDizin: () async => gecici);
      await depo.yaz('A_1mo', seri);
      expect(await depo.oku('A_1mo'), seri);
      expect(await depo.oku('B_1mo'), isNull);
    });

    test('dosya sayısı sınırlı', () async {
      final depo = SeriDiskDepo(kokDizin: () async => gecici);
      for (var i = 0; i < SeriDiskDepo.azamiDosya + 5; i++) {
        await depo.yaz('S${i}_1mo', seri);
      }
      final n = Directory('${gecici.path}/seri_onbellek').listSync().length;
      expect(n, SeriDiskDepo.azamiDosya);
    });

    test('bozuk dosya sessizce null', () async {
      final depo = SeriDiskDepo(kokDizin: () async => gecici);
      await depo.yaz('A_1mo', seri);
      File('${gecici.path}/seri_onbellek/${SeriDiskDepo.dosyaAdi('A_1mo')}')
          .writeAsStringSync('{bozuk');
      expect(await depo.oku('A_1mo'), isNull);
    });
  });
}
