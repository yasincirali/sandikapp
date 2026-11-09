import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/price_service.dart';

/// **Altının GÜNLÜK'ü tek kaynaktan: yurt içi kayıt** (2026-10-19).
///
/// Kullanıcı bildirimi: *"bir açtığımda portföyüm %1 eksi, bir açtığımda
/// artı"*. Ölçüldü (sunucu kaydı): Kapalıçarşı kapanınca 22 ayar +%0,01'de
/// dondu, uluslararası altın −%0,5'e indi. Gün başı, o oturumda ayarın
/// günlük yüzdesi gelip gelmediğine göre ya yurt içi kotasyondan ya da
/// uluslararası serinin ilk noktasından alınıyordu. Kilitlenen:
///   · hafta içi, bayrak KAPALI olsa da altın kayıttan çizilir;
///   · sonuç günlük yüzdenin o oturumda gelip gelmemesine BAĞLI DEĞİL;
///   · kayıt yoksa eski yol (uydurma nokta yok);
///   · döviz bu karara girmez (hafta içi seri canlıyken kayıt sorulmaz).
void main() {
  // Pazartesi 21:00 — Kapalıçarşı kapalı, uluslararası altın açık.
  final simdi = DateTime(2026, 10, 19, 21, 0);
  final gunBasi = DateTime(2026, 10, 19);
  const adim = Duration(minutes: 5);

  List<(int, double)> seri(
      DateTime bas, DateTime son, double ilk, double sonDeger) {
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

  var kayitSorgusu = <String>[];
  late Map<String, List<(int, double)>> kayit;

  setUp(() {
    HistoryService.clearCache();
    PriceService.instance.sonBilinenFiyatlariTemizle();
    HistoryService.gunIciSaat = () => simdi;
    HistoryService.yurtIciSekilAcik = () => false;
    kayitSorgusu = [];
    HistoryService.yurtIciKaynagi = (sembol, bas) async {
      kayitSorgusu.add(sembol);
      expect(bas, gunBasi, reason: 'yalnızca bugün istenir');
      return kayit[sembol] ?? const [];
    };
    // Uluslararası altın gün boyu −%0,5 düşüyor; dolar canlı.
    HistoryService.seriCekici = (sym, range, interval) async {
      if (sym == FiyatKaynagi.xauTry) {
        return seri(gunBasi, simdi, 200000, 199000);
      }
      if (sym == FiyatKaynagi.usdTry) {
        return seri(gunBasi, simdi, 49.5, 49.55);
      }
      return const [];
    };
  });
  tearDown(() {
    HistoryService.gunIciSaat = DateTime.now;
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    HistoryService.yurtIciSekilAcik = () => false;
    HistoryService.yurtIciKaynagi = (_, __) async => const [];
    HistoryService.clearCache();
    PriceService.instance.sonBilinenFiyatlariTemizle();
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

  Future<({double ilk, double son})> ciz(Asset a) async {
    HistoryService.clearCache();
    final b = await HistoryService.instance
        .getPortfolioHistoryHourlyBreakdown([a], 24);
    final u = PeriodSummaryService.uclar(b.total,
        fromMs: gunBasi.millisecondsSinceEpoch,
        toMs: simdi.millisecondsSinceEpoch)!;
    return (ilk: u.first, son: u.last);
  }

  // 22 ayar: 17:00'ye kadar hafif yükseliş, sonra donmuş (+%0,01).
  const dun = 6020.38;
  const canli = 6021.04;
  List<(int, double)> gramKaydi() => [
        ...seri(gunBasi, DateTime(2026, 10, 19, 17), dun, canli),
        ...seri(DateTime(2026, 10, 19, 17, 5), simdi, canli, canli),
      ];

  test('günlük yüzde HİÇ gelmemişken: gün başı yurt içi kayıttan', () async {
    kayit = {'ALTIN_GRAM': gramKaydi()};
    final c = await ciz(varlik('ALTIN_GRAM', AssetType.altin, canli));
    expect(c.ilk, closeTo(2 * dun, 0.01),
        reason: 'uluslararası serinin ilk noktası (−%0,5) değil');
    expect(c.son, closeTo(2 * canli, 0.01));
    expect(kayitSorgusu, ['ALTIN_GRAM'], reason: 'bayrak kapalı olsa da');
  });

  test('günlük yüzde geldiğinde de AYNI sonuç — açılış sırası fark etmez',
      () async {
    kayit = {'ALTIN_GRAM': gramKaydi()};
    final yuzdesiz = await ciz(varlik('ALTIN_GRAM', AssetType.altin, canli));
    PriceService.instance
        .testIcinKotasyonYaz('ALTIN_GRAM', canli, gunlukPct: 0.01);
    final yuzdeli = await ciz(varlik('ALTIN_GRAM', AssetType.altin, canli));
    expect(yuzdeli.ilk, closeTo(yuzdesiz.ilk, 0.01));
    expect(yuzdeli.son, closeTo(yuzdesiz.son, 0.01));
    expect((yuzdeli.son - yuzdeli.ilk).sign, (canli - dun).sign,
        reason: 'işaret yurt içi fiyatın işareti');
  });

  test('kayıt yoksa eski yol — gün başı uluslararası şekilden', () async {
    kayit = const {};
    final c = await ciz(varlik('ALTIN_GRAM', AssetType.altin, canli));
    expect(c.son, closeTo(2 * canli, 0.01));
    expect(c.ilk, greaterThan(c.son),
        reason: 'eski davranış: uluslararası düşüş (değişmedi)');
  });

  test('döviz: hafta içi seri canlıyken kayıt sorulmaz', () async {
    kayit = {'USDTRY=X': seri(gunBasi, simdi, 49.5, 49.6)};
    await ciz(varlik('USDTRY=X', AssetType.doviz, 49.55));
    expect(kayitSorgusu, isEmpty);
  });
}
