import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/varlik_sayfasi.dart'
    show varlikSayfasiDonemleri;
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/tefas_service.dart'
    show tefasGecmisKovasi;
import 'package:portfoy_takip/services/varlik_istatistik.dart';

/// **Aynı katmanın dönemleri geniş pencereden — noktalar birebir aynı**
/// (Ar-Ge 2026-10-24 §3, rapor §2 YAP; karar kaydı
/// `HistoryService.kaynakDonemGunu`).
///
/// Rapor şartı: "6A'nın `5y|1wk`'den kırpılmış hâli bugünkü `6mo|1wk` ile
/// birebir aynı olmalı (ilk mum hizası dahil). Eşit değilse o dönem ayrı
/// istekte kalsın." Ağa çıkılamadığı için Yahoo burada sahte bir
/// sağlayıcıyla taklit edilir (ölçümle tutan model, 2026-09-03: `6mo|1wk`
/// 28, `1y|1wk` 54 nokta):
///   · pencere başı (`period1`) takvimle geriye (`1mo` Mart'ta 28 gün),
///   · haftalık barlar pazartesiye hizalı, İLK bar kısmi ve `period1`'e
///     damgalı,
///   · son satır son işlemin anı (Yahoo'nun "gerçek zaman" satırı).
/// "Bugünkü ayrı istek" = dar range + aynı normalize + aynı kırpma; yeni
/// yol = `getSymbolHistory`. Hafta sonu, tatil ve kısa ayda dar istek
/// pencerenin ilk mumlarını getirmez — o günlerde yeni yol dar isteğe
/// düşmeli (eşitlik yine birebir).
void main() {
  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    HistoryService.pencereSaati = DateTime.now;
    HistoryService.clearCache();
  });

  group('kaynak penceresi', () {
    test('aynı katmanın dönemleri geniş pencereye adaydır', () {
      int k(int g) => HistoryService.kaynakDonemGunu('THYAO.IS', g);
      expect(k(1), 1, reason: 'GÜNLÜK 5 dakikalık, kendi isteği');
      expect(k(7), 7, reason: '1H saatlik, kendi isteği');
      expect(k(30), 90, reason: '1A günlük → 3A penceresi');
      expect(k(90), 90);
      expect(k(180), 1825, reason: '6A haftalık → 5Y penceresi');
      expect(k(365), 1825, reason: '1Y haftalık → 5Y penceresi');
      expect(k(1825), 1825);
      // Katman DEĞİŞMEZ: interval dönemden gelir, yalnız range genişler.
      for (final g in varlikSayfasiDonemleri) {
        expect(
            HistoryService.tierForPeriod(k(g)), HistoryService.tierForPeriod(g),
            reason: '$g gün: kırpılan pencere başka sıklıkta olamaz');
      }
    });

    test('eşitliği kurulamayan kaynaklar hiç birleştirilmez', () {
      for (final s in [
        'ALTIN_GRAM',
        'ALTIN_CEYREK',
        'KRIPTO:BTC',
        'EUROBOND:XS1',
        'MEVDUAT:x',
      ]) {
        for (final g in varlikSayfasiDonemleri) {
          expect(HistoryService.kaynakDonemGunu(s, g), g,
              reason: '$s $g gün: altında spot/vadeli seçimi pencere '
                  'süresine bakar, kriptoda Binance kısmi ilk mum vermez, '
                  'eurobond penceresi ölçülmedi, mevduat adımı pencere '
                  'başından kayar');
        }
      }
    });

    test('hafta içi açılış 4 istek (7 değil)', () async {
      expect(await _istekler(DateTime(2026, 10, 21, 15)), {
        'THYAO.IS|1d|5m',
        'THYAO.IS|1mo|1h',
        'THYAO.IS|3mo|1d',
        'THYAO.IS|5y|1wk',
      });
    });

    test('pazar: 1A ve 1Y eşitlik için kendi isteğine düşer', () async {
      // Son nokta cuma; dar `1mo`/`1y` pencerenin ilk mumunu getirmez.
      final r = await _istekler(DateTime(2026, 10, 25, 15));
      expect(r, containsAll(['THYAO.IS|1mo|1d', 'THYAO.IS|1y|1wk']));
      expect(r, isNot(contains('THYAO.IS|6mo|1wk')),
          reason: '6A hafta sonu da 5Y penceresinden birebir');
    });

    test('TEFAS: dar ve geniş pencere aynı kovadan (aynı ham yanıt)', () {
      // `PriceService._tefasPeriyodFor`: 1mo→1, 3mo→3, 6mo→6, 1y→12, 5y→60.
      expect(tefasGecmisKovasi(1), tefasGecmisKovasi(3));
      expect(tefasGecmisKovasi(6), tefasGecmisKovasi(60));
      expect(tefasGecmisKovasi(12), tefasGecmisKovasi(60));
    });
  });

  group('nokta eşitliği (ilk mum hizası dahil)', () {
    // Üç hafta, her gün başka saat: haftanın günü ilk mumun yerini değiştirir.
    final anlar = [
      for (var g = 0; g < 21; g++)
        DateTime(2026, 10, 5, 9).add(Duration(days: g, hours: g % 9)),
      // Ay/yıl sınırları, artık gün, Şubat'tan sonraki ay.
      DateTime(2026, 1, 2, 12),
      DateTime(2028, 2, 29, 11),
      DateTime(2026, 3, 24, 15),
      DateTime(2026, 3, 1, 10),
      DateTime(2026, 8, 31, 16),
      DateTime(2026, 12, 31, 10),
    ];

    for (final simdi in anlar) {
      test('THYAO.IS 1A/6A/1Y @ $simdi', () async {
        for (final gun in [30, 180, 365]) {
          await _esitMi(simdi, 'THYAO.IS', gun);
        }
      });
    }

    test('USD kote sembol (kurla çevrim kırpmadan ÖNCE) de birebir', () async {
      for (final simdi in anlar.take(8)) {
        for (final gun in [30, 180, 365]) {
          await _esitMi(simdi, 'AAPL', gun);
        }
      }
    });

    test('dokuz gün kapalı piyasa (uzun bayram) da birebir', () async {
      // 19–23 Ekim kapalı; pazar 25 Ekim. Son nokta 16 Ekim.
      final kapali = {
        for (var d = 19; d <= 23; d++) DateTime(2026, 10, d),
      };
      for (final gun in [30, 180, 365]) {
        await _esitMi(DateTime(2026, 10, 25, 12), 'THYAO.IS', gun,
            kapali: kapali);
      }
    });

    test('kripto neden hiç birleştirilmez: kısmi ilk mum yoksa fark', () {
      // Binance `startTime`'dan SONRAKİ ilk tam mumu verir; sunucu `1y`'yi
      // 366 gün sayar. Haftanın bazı günleri dar istekte pencerenin ilk
      // pazartesisi yok, 5y'de var.
      var fark = 0;
      for (var g = 0; g < 7; g++) {
        final simdi = DateTime(2026, 10, 5, 12).add(Duration(days: g));
        final dar = _kirpilmis(simdi, '1y', 365,
            kismiIlk: false, bas: simdi.subtract(const Duration(days: 366)));
        final genis = _kirpilmis(simdi, '5y', 365, kismiIlk: false);
        if (genis.length != dar.length) fark++;
      }
      expect(fark, greaterThan(0));
    });
  });

  group('dönem kapsamı (#242) geniş pencereyle bozulmaz', () {
    test('kırpılan dönemin ilk noktası dönem başında', () async {
      final simdi = DateTime(2026, 10, 21, 15);
      HistoryService.pencereSaati = () => simdi;
      HistoryService.seriCekici = (s, r, i) async => _yahoo(simdi, r, i);
      for (final gun in [30, 90, 180, 365, 1825]) {
        final seri = await HistoryService.instance
            .getSymbolHistory('THYAO.IS', periodDays: gun);
        final ilk = seri.keys.reduce((a, b) => a < b ? a : b);
        final bas = simdi.subtract(Duration(days: gun));
        // Günlükte hafta sonu, haftalıkta pazartesi hizası kadar pay.
        expect(DateTime.fromMillisecondsSinceEpoch(ilk).difference(bas).inDays,
            lessThanOrEqualTo(gun >= 180 ? 7 : 3),
            reason: '$gun gün: ilk nokta dönem başında değil');
        final ist =
            DonemIstatistigi.hesapla(seri, periodDays: gun, simdi: simdi)!;
        expect(ist.kapsamEksik, isFalse, reason: '$gun gün');
      }
    });

    test('kısa geçmişli varlıkta 5Y ve 1Y yine "eksik" der, 6A demez',
        () async {
      // 8 aylık fon: geniş pencere (5y) de 8 ay döner; kırpılmış 6A tam,
      // 1Y/5Y kapsamı eksik. Kural pencereden değil İLK NOKTADAN okur.
      final simdi = DateTime(2026, 10, 21, 15);
      final dogum = DateTime(2026, 2, 21);
      HistoryService.pencereSaati = () => simdi;
      HistoryService.seriCekici = (s, r, i) async => [
            for (final p in _yahoo(simdi, r, i))
              if (p.$1 >= dogum.millisecondsSinceEpoch) p,
          ];
      Future<DonemIstatistigi> ist(int gun) async => DonemIstatistigi.hesapla(
          await HistoryService.instance
              .getSymbolHistory('TEFAS:AFT', periodDays: gun),
          periodDays: gun,
          simdi: simdi)!;
      expect((await ist(180)).kapsamEksik, isFalse);
      expect((await ist(365)).kapsamEksik, isTrue);
      expect((await ist(1825)).kapsamEksik, isTrue);
    });
  });

  group('darPencereBasi temkinli', () {
    test('takvim ile sabit gün sayımının GEÇ olanı', () {
      // 31 Ekim − 1 takvim ayı = 30 Eylül (31 gün) → 30 gün olan geç.
      expect(HistoryService.darPencereBasi('1mo', DateTime(2026, 10, 31, 12)),
          DateTime(2026, 10, 1, 12));
      // 24 Mart − 1 ay = 24 Şubat (28 gün) → takvim geç.
      expect(HistoryService.darPencereBasi('1mo', DateTime(2026, 3, 24, 15)),
          DateTime(2026, 2, 24, 15));
      expect(HistoryService.darPencereBasi('5y', DateTime(2026, 3, 24)), isNull,
          reason: '5Y zaten geniş pencere');
    });
  });
}

/// 7 dönemin açılışında giden istek anahtarları (`sembol|range|interval`).
Future<Set<String>> _istekler(DateTime simdi) async {
  HistoryService.clearCache();
  HistoryService.pencereSaati = () => simdi;
  final istekler = <String>{};
  HistoryService.seriCekici = (s, r, i) async {
    istekler.add('$s|$r|$i');
    return _yahoo(simdi, r, i);
  };
  await Future.wait([
    for (final g in varlikSayfasiDonemleri)
      HistoryService.instance.getSymbolHistory('THYAO.IS', periodDays: g),
  ]);
  return istekler;
}

/// Eski yol (dönemin kendi range'i) ile yeni yolun (`getSymbolHistory`)
/// sonuçları, aynı sahte sağlayıcıdan.
Future<void> _esitMi(DateTime simdi, String sym, int gun,
    {Set<DateTime> kapali = const {}}) async {
  HistoryService.clearCache();
  HistoryService.pencereSaati = () => simdi;
  HistoryService.seriCekici = (s, r, i) async =>
      _yahoo(simdi, r, i, kur: s == FiyatKaynagi.usdTry, kapali: kapali);
  final tier = HistoryService.tierForPeriod(gun);
  Map<int, double> norm(List<(int, double)> pts) =>
      {for (final p in pts) tier.normalizeTs(p.$1): p.$2};
  final dar = HistoryService.rangeForPeriod(gun);
  final ham = norm(_yahoo(simdi, dar, tier.yahooInterval, kapali: kapali));
  final Map<int, double> eski;
  if (sym == 'AAPL') {
    // `getSymbolHistory`'nin USD dalı, dar pencereyle elle: canlı kur
    // yokken hizalama etkisiz; en yakın geçmiş kur (`_closestOrNull`).
    final kur =
        norm(_yahoo(simdi, dar, tier.yahooInterval, kur: true, kapali: kapali));
    final kurTs = kur.keys.toList()..sort();
    double kurBul(int ts) {
      double? son;
      for (final k in kurTs) {
        if (k > ts) break;
        son = kur[k];
      }
      return son ?? kur[kurTs.first]!;
    }

    eski = HistoryService.clipToPeriod(
        {for (final e in ham.entries) e.key: e.value * kurBul(e.key)}, gun);
  } else {
    eski = HistoryService.clipToPeriod(ham, gun);
  }
  final yeni =
      await HistoryService.instance.getSymbolHistory(sym, periodDays: gun);

  expect(eski, isNotEmpty);
  expect(yeni.keys.toList()..sort(), eski.keys.toList()..sort(),
      reason: '$sym $gun gün @ $simdi: nokta kümesi (ilk mum dahil) farklı');
  for (final e in eski.entries) {
    expect(yeni[e.key], closeTo(e.value, 1e-9),
        reason: '$sym $gun gün @ $simdi: '
            '${DateTime.fromMillisecondsSinceEpoch(e.key)} değeri farklı');
  }
}

/// [range]'in sahte yanıtı, katmana normalize edilip [gun]'e kırpılmış.
Map<int, double> _kirpilmis(DateTime simdi, String range, int gun,
    {bool kismiIlk = true, DateTime? bas}) {
  final tier = HistoryService.tierForPeriod(gun);
  return HistoryService.clipToPeriod({
    for (final p in _yahoo(simdi, range, tier.yahooInterval,
        kismiIlk: kismiIlk, bas: bas))
      tier.normalizeTs(p.$1): p.$2,
  }, gun);
}

/// Yahoo `range` → `period1` (takvimle geriye; ay sonu taşarsa ayın son
/// günü — dateutil davranışı).
DateTime _period1(DateTime simdi, String range) {
  final ay = switch (range) {
    '1mo' => 1,
    '3mo' => 3,
    '6mo' => 6,
    '1y' => 12,
    '5y' => 60,
    _ => 0,
  };
  if (ay == 0) {
    return range == '1d'
        ? DateTime(simdi.year, simdi.month, simdi.day)
        : simdi.subtract(const Duration(days: 5));
  }
  final hedef = DateTime(simdi.year, simdi.month - ay, 1);
  final sonGun = DateTime(hedef.year, hedef.month + 1, 0).day;
  return DateTime(hedef.year, hedef.month,
      simdi.day > sonGun ? sonGun : simdi.day, simdi.hour, simdi.minute);
}

/// Deterministik günlük kapanış — tarihe bağlı (pencereden bağımsız).
double _kapanis(DateTime gun, {bool kur = false}) {
  final i =
      DateTime(gun.year, gun.month, gun.day).difference(DateTime(2020)).inDays;
  final v = 100 + i * 0.07 + (i * 7919 % 113) / 10.0;
  return kur ? 20 + v / 50 : v;
}

/// Yahoo benzeri yanıt: işlem günleri (hafta içi, [kapali] hariç), günlük ya
/// da pazartesiye hizalı haftalık barlar; ilk haftalık bar kısmi ve
/// `period1`'e damgalı; son satır son işlemin anı.
///
/// [kismiIlk] `false`: Binance gibi, `period1`'den SONRAKİ ilk tam mumdan.
List<(int, double)> _yahoo(DateTime simdi, String range, String? interval,
    {bool kur = false,
    bool kismiIlk = true,
    DateTime? bas,
    Set<DateTime> kapali = const {}}) {
  final p1 = bas ?? _period1(simdi, range);
  final gunler = <DateTime>[];
  for (var d = DateTime(p1.year, p1.month, p1.day);
      !d.isAfter(simdi);
      d = DateTime(d.year, d.month, d.day + 1)) {
    if (d.weekday >= DateTime.saturday || kapali.contains(d)) continue;
    gunler.add(DateTime(d.year, d.month, d.day, 7));
  }
  if (gunler.isEmpty) return const [];
  final out = <(int, double)>[];
  if (interval == '1wk') {
    final gruplar = <DateTime, DateTime>{}; // pazartesi → haftanın son günü
    for (final g in gunler) {
      gruplar[DateTime(g.year, g.month, g.day - (g.weekday - 1))] = g;
    }
    var ilk = true;
    for (final e in gruplar.entries) {
      final kismi = ilk && p1.isAfter(e.key);
      ilk = false;
      if (kismi && !kismiIlk) continue;
      out.add((
        (kismi ? p1 : e.key).millisecondsSinceEpoch,
        _kapanis(e.value, kur: kur)
      ));
    }
  } else {
    for (final g in gunler) {
      out.add((g.millisecondsSinceEpoch, _kapanis(g, kur: kur)));
    }
  }
  final son = gunler.last;
  final sonGun = DateTime(son.year, son.month, son.day);
  final an = DateTime(simdi.year, simdi.month, simdi.day) == sonGun
      ? simdi
      : DateTime(son.year, son.month, son.day, 17);
  out.add((an.millisecondsSinceEpoch, _kapanis(son, kur: kur)));
  return out;
}
