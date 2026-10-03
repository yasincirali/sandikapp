import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/price_service.dart';

/// **Hafta sonu GÜNLÜK: altın/döviz şekli yurt içi kayıttan** (2026-10-03).
///
/// Kullanıcı sorusu: *"Neden düz çizgi peki. Değeri oynak değil mi?"* —
/// karar: *"Evet bunu yapalım ama fiyat tutarlı ve doğru şeyi göstermeli."*
///
/// Uluslararası seri (Yahoo) Cuma gece yarısı susar; Cumartesi'nin her
/// slotu Cuma kapanışını taşıyordu. Sunucu artık ekrandaki kotasyonu beş
/// dakikada bir kaydediyor (`yurt_ici_kotasyon`, 0101). Kilitlenen:
///   · seri sustuysa şekil yurt içi kayıttan, uçlar ekrandaki fiyatla aynı;
///   · seri canlıysa (hafta içi) kayıt HİÇ sorulmaz — davranış birebir eski;
///   · bayrak kapalıyken hafta sonu eskisi gibi düz;
///   · dünün kaydı bugüne karışmaz, iki noktadan az kayıt şekil sayılmaz.
void main() {
  // Cumartesi 14:00 — saat sabit (duvar saatine bağlı test hafta içi
  // koşulduğunda hafta sonu dalını hiç çalıştırmazdı).
  final cumartesi = DateTime(2026, 10, 3, 14, 0);
  final cumartesiBasi = DateTime(2026, 10, 3);
  final cuma = DateTime(2026, 10, 2);
  const adim = Duration(minutes: 5);

  int norm(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime(d.year, d.month, d.day, d.hour, (d.minute ~/ 5) * 5)
        .millisecondsSinceEpoch;
  }

  /// [bas]–[son] arası 5 dk'lık noktalar, [ilk] → [sonDeger] doğrusal.
  List<(int, double)> seri(DateTime bas, DateTime son, double ilk,
      double sonDeger) {
    final out = <(int, double)>[];
    final n = son.difference(bas).inMinutes ~/ 5;
    var t = bas;
    var i = 0;
    while (!t.isAfter(son)) {
      out.add((t.millisecondsSinceEpoch, ilk + (sonDeger - ilk) * i / n));
      t = t.add(adim);
      i++;
    }
    return out;
  }

  test('test günü gerçekten Cumartesi', () {
    expect(cumartesi.weekday, DateTime.saturday);
  });

  group('saf karar: FiyatKaynagi.yurtIciGunIciSekli', () {
    final cumaSeri = {
      for (final p in seri(cuma.add(const Duration(hours: 10)),
          cumartesiBasi.subtract(adim), 100, 101))
        p.$1: p.$2,
    };
    final bugunKayit =
        seri(cumartesiBasi, cumartesi, 41.0, 41.4);

    test('uluslararası seri sustuysa bugünün kaydı döner', () {
      final s = FiyatKaynagi.yurtIciGunIciSekli(
          uluslararasi: cumaSeri,
          yurtIci: bugunKayit,
          simdi: cumartesi,
          normalize: norm)!;
      expect(s.length, bugunKayit.length);
      expect(s[cumartesiBasi.millisecondsSinceEpoch], 41.0);
    });

    test('uluslararası seri canlıysa null — hafta içi davranış değişmez', () {
      final canli = {
        for (final p in seri(cumartesi.subtract(const Duration(hours: 2)),
            cumartesi, 100, 101))
          p.$1: p.$2,
      };
      expect(
          FiyatKaynagi.yurtIciGunIciSekli(
              uluslararasi: canli,
              yurtIci: bugunKayit,
              simdi: cumartesi,
              normalize: norm),
          isNull);
    });

    test('spot altının gece molası (≤ 90 dk) susma sayılmaz', () {
      final son = cumartesi.subtract(const Duration(minutes: 85));
      expect(
          FiyatKaynagi.uluslararasiSustu(
              {son.millisecondsSinceEpoch: 1.0}, cumartesi),
          isFalse);
      expect(FiyatKaynagi.uluslararasiSustu(const {}, cumartesi), isTrue,
          reason: 'Yahoo hiç veri vermediyse de susmuştur');
    });

    test('dünün kaydı bugüne KARIŞMAZ; gelecek damga alınmaz', () {
      final s = FiyatKaynagi.yurtIciGunIciSekli(
          uluslararasi: cumaSeri,
          yurtIci: [
            (cuma.add(const Duration(hours: 23)).millisecondsSinceEpoch, 40.0),
            ...bugunKayit,
            (cumartesi.add(const Duration(hours: 1)).millisecondsSinceEpoch,
                99.0),
          ],
          simdi: cumartesi,
          normalize: norm)!;
      expect(s.values.contains(40.0), isFalse);
      expect(s.values.contains(99.0), isFalse);
    });

    test('iki noktadan az ya da bozuk kayıt şekil değildir', () {
      expect(
          FiyatKaynagi.yurtIciGunIciSekli(
              uluslararasi: cumaSeri,
              yurtIci: [(cumartesiBasi.millisecondsSinceEpoch, 41.0)],
              simdi: cumartesi,
              normalize: norm),
          isNull);
      expect(
          FiyatKaynagi.yurtIciGunIciSekli(
              uluslararasi: cumaSeri,
              yurtIci: [
                (cumartesiBasi.millisecondsSinceEpoch, 0.0),
                (cumartesi.millisecondsSinceEpoch, double.nan),
              ],
              simdi: cumartesi,
              normalize: norm),
          isNull,
          reason: 'uydurma nokta yok');
    });

    test('kayıtlı semboller: tüm altın ayarları + üç TL döviz', () {
      for (final t in ['ALTIN_GRAM', 'ALTIN_CEYREK', 'USDTRY=X', 'EURTRY=X',
          'GBPTRY=X']) {
        expect(FiyatKaynagi.yurtIciKayitli(t), isTrue, reason: t);
      }
      expect(FiyatKaynagi.yurtIciKayitli('THYAO.IS'), isFalse);
      expect(FiyatKaynagi.yurtIciKayitli('CHFTRY=X'), isFalse,
          reason: 'truncgil\'den fiyatlanmayan döviz kaydedilmez');
    });
  });

  group('MOTOR: Cumartesi GÜNLÜK', () {
    var bayrak = true;
    var kayitSorgusu = 0;
    late Map<String, List<(int, double)>> kayit;

    setUp(() {
      HistoryService.clearCache();
      HistoryService.gunIciSaat = () => cumartesi;
      HistoryService.yurtIciSekilAcik = () => bayrak;
      kayitSorgusu = 0;
      HistoryService.yurtIciKaynagi = (sembol, bas) async {
        kayitSorgusu++;
        expect(bas, cumartesiBasi, reason: 'yalnızca bugün istenir');
        return kayit[sembol] ?? const [];
      };
      // Yahoo: Cuma seansı, Cuma gece yarısında biter.
      HistoryService.seriCekici = (sym, range, interval) async {
        final cumaSeansi = seri(cuma.add(const Duration(hours: 10)),
            cumartesiBasi.subtract(adim), 0, 0);
        if (sym == FiyatKaynagi.xauTry) {
          return [for (final p in cumaSeansi) (p.$1, 150000.0)];
        }
        if (sym == FiyatKaynagi.usdTry) {
          return [for (final p in cumaSeansi) (p.$1, 41.0)];
        }
        return const [];
      };
    });
    tearDown(() {
      HistoryService.gunIciSaat = DateTime.now;
      HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
      HistoryService.yurtIciSekilAcik = () => false;
      HistoryService.clearCache();
      PriceService.instance.sonBilinenFiyatlariTemizle();
      bayrak = true;
    });

    Asset varlik(String ticker, AssetType tur, double canli) => Asset(
          id: ticker,
          userId: 'u1',
          name: ticker,
          ticker: ticker,
          type: tur,
          quantity: 2,
          purchasePrice: canli,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: canli,
          addedDate: DateTime(2000),
        );

    Future<({double ilk, double son, Set<double> degerler})> ciz(
        Asset a) async {
      final b = await HistoryService.instance
          .getPortfolioHistoryHourlyBreakdown([a], 24);
      final u = PeriodSummaryService.uclar(b.total,
          fromMs: cumartesiBasi.millisecondsSinceEpoch,
          toMs: cumartesi.millisecondsSinceEpoch)!;
      return (
        ilk: u.first,
        son: u.last,
        degerler: b.total.entries
            .where((e) => e.key >= cumartesiBasi.millisecondsSinceEpoch)
            .map((e) => e.value)
            .toSet(),
      );
    }

    test('altın: şekil kayıttan, gün başı ve uç ekrandaki kotasyon', () async {
      const canli = 6060.0;
      kayit = {'ALTIN_GRAM': seri(cumartesiBasi, cumartesi, 6000, canli)};
      PriceService.instance
          .testIcinKotasyonYaz('ALTIN_GRAM', canli, gunlukPct: 0.5);
      final c = await ciz(varlik('ALTIN_GRAM', AssetType.altin, canli));
      expect(c.ilk, closeTo(2 * 6000, 0.01),
          reason: 'gün başı Cumartesi 00:00 kotasyonu');
      expect(c.son, closeTo(2 * canli, 0.01), reason: 'uç = ekrandaki fiyat');
      expect(c.degerler.length, greaterThan(10), reason: 'çizgi düz değil');
      expect(kayitSorgusu, 1);
    });

    test('dolar: şekil kayıttan', () async {
      const canli = 41.4;
      kayit = {'USDTRY=X': seri(cumartesiBasi, cumartesi, 41.0, canli)};
      final c = await ciz(varlik('USDTRY=X', AssetType.doviz, canli));
      expect(c.ilk, closeTo(2 * 41.0, 1e-6));
      expect(c.son, closeTo(2 * canli, 1e-6));
      expect(c.degerler.length, greaterThan(10));
    });

    test('bayrak kapalı: eski davranış (düz), kayıt sorulmaz', () async {
      bayrak = false;
      const canli = 41.4;
      kayit = {'USDTRY=X': seri(cumartesiBasi, cumartesi, 41.0, canli)};
      final c = await ciz(varlik('USDTRY=X', AssetType.doviz, canli));
      expect(kayitSorgusu, 0);
      // Eski davranış: gün boyu Cuma kapanışı, yalnızca uç canlı fiyat.
      expect(c.ilk, closeTo(2 * 41.0, 1e-6));
      expect(c.degerler.length, lessThanOrEqualTo(2),
          reason: 'eski davranış: düz çizgi + canlı uç');
    });

    test('kayıt boşsa eski davranış — uydurma nokta yok', () async {
      const canli = 41.4;
      kayit = const {};
      final c = await ciz(varlik('USDTRY=X', AssetType.doviz, canli));
      expect(kayitSorgusu, 1);
      expect(c.degerler.length, lessThanOrEqualTo(2));
    });

    test('hafta içi seri canlıyken kayıt HİÇ sorulmaz', () async {
      final persembe = DateTime(2026, 10, 1, 14, 0);
      HistoryService.gunIciSaat = () => persembe;
      HistoryService.seriCekici = (sym, range, interval) async {
        if (sym == FiyatKaynagi.usdTry) {
          return seri(DateTime(2026, 10, 1), persembe, 41.0, 41.2);
        }
        return const [];
      };
      kayit = {'USDTRY=X': seri(DateTime(2026, 10, 1), persembe, 41.0, 41.4)};
      await HistoryService.instance.getPortfolioHistoryHourlyBreakdown(
          [varlik('USDTRY=X', AssetType.doviz, 41.2)], 24);
      expect(kayitSorgusu, 0);
    });
  });
}
