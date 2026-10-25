import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/tefas_nav_gozlem.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/services/seri_disk_depo.dart';

import 'helpers/kaynak.dart';

/// Varlık detayı **GÜNLÜK** (gün içi) sekmesi de önce eski seriyle
/// (2026-10-25, yasin onayı; karar kaydı
/// `HistoryService.getPortfolioHistoryHourlyBreakdownEldeki`).
///
/// Saatlik döküm motoru `seriCek` dışında iki kaynağa daha gider: yurt içi
/// kayıt (altın her gün, döviz hafta sonu) ve TEFAS yayın gözlemi. İkisi de
/// eldeki-kipte ağa ÇIKMAZ; yoksa eski seri hiç gösterilmez (kaynak atlanırsa
/// hesap başka bir merdivenden başka bir sayı çizerdi). Eski seri yalnız
/// bugünden.
void main() {
  late Directory gecici;
  var ag = 0;
  var kayitSorgusu = 0;
  var gozlemSorgusu = 0;
  final b = DateTime.now();
  final gunBasi = DateTime(b.year, b.month, b.day);
  // Saat sahte, "ölçüldüğü an" duvar saatinden: ikisi aynı gün olmalı.
  final simdi = DateTime(b.year, b.month, b.day, 15);

  List<(int, double)> gunIci(double ilk, double son) {
    final out = <(int, double)>[];
    const n = 15 * 12;
    for (var i = 0; i <= n; i++) {
      out.add((
        gunBasi.add(Duration(minutes: 5 * i)).millisecondsSinceEpoch,
        ilk + (son - ilk) * i / n,
      ));
    }
    return out;
  }

  setUp(() {
    HistoryService.clearCache();
    HistoryService.instance.clearTierCache();
    PriceService.instance.sonBilinenFiyatlariTemizle();
    gecici = Directory.systemTemp.createTempSync('gunluk_once_eski');
    HistoryService.kaliciDepo = SeriDiskDepo(kokDizin: () async => gecici);
    HistoryService.gunIciSaat = () => simdi;
    HistoryService.yurtIciSekilAcik = () => false;
    ag = 0;
    kayitSorgusu = 0;
    gozlemSorgusu = 0;
    HistoryService.seriCekici = (sym, range, interval) async {
      ag++;
      if (sym == FiyatKaynagi.xauTry) return gunIci(200000, 199000);
      if (sym == FiyatKaynagi.xauUsd) return gunIci(4000, 3980);
      if (sym == FiyatKaynagi.usdTry) return gunIci(49.5, 49.55);
      if (sym.startsWith('TEFAS:')) {
        return [
          (gunBasi.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
              1.0),
          (gunBasi.millisecondsSinceEpoch, 1.02),
        ];
      }
      return gunIci(300, 310);
    };
    HistoryService.yurtIciKaynagi = (sembol, bas) async {
      kayitSorgusu++;
      return sembol == 'ALTIN_GRAM' ? gunIci(6000, 6020) : const [];
    };
    HistoryService.tefasNavGozlemKaynagi = (kodlar, gun) async {
      gozlemSorgusu++;
      return {
        for (final k in kodlar)
          k: TefasNavGozlem(
              fonKodu: k,
              navTarihi: gunBasi,
              ilkGorulme: gunBasi.add(const Duration(hours: 10))),
      };
    };
  });

  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    HistoryService.gunIciSaat = DateTime.now;
    HistoryService.yurtIciSekilAcik = () => false;
    HistoryService.yurtIciKaynagi = (_, __) async => const [];
    HistoryService.tefasNavGozlemKaynagi = (_, __) async => const {};
    HistoryService.kaliciDepo = null;
    HistoryService.clearCache();
    HistoryService.instance.clearTierCache();
    PriceService.instance.sonBilinenFiyatlariTemizle();
    if (gecici.existsSync()) gecici.deleteSync(recursive: true);
  });

  Asset varlik(String ticker, AssetType tur, double fiyat) =>
      FiyatKaynagi.birimVarlik(Asset(
        id: ticker,
        userId: 'u1',
        name: ticker,
        ticker: ticker,
        type: tur,
        quantity: 2,
        purchasePrice: fiyat,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: fiyat,
        addedDate: DateTime(2000),
      ));

  Future<PortfolioHistoryBreakdown> taze(Asset a) =>
      HistoryService.instance.getPortfolioHistoryHourlyBreakdown([a], 24);
  Future<({PortfolioHistoryBreakdown sonuc, DateTime zaman})?> eldeki(
          Asset a) =>
      HistoryService.instance.getPortfolioHistoryHourlyBreakdownEldeki([a]);

  /// "Uygulama yeniden açıldı": bellek boş, disk dolu.
  Future<void> yenidenAc() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    HistoryService.clearCache();
    HistoryService.instance.clearTierCache();
  }

  test('hisse: bugünün serisi diskten, AĞA ÇIKMADAN; aynı seri', () async {
    final a = varlik('THYAO.IS', AssetType.hisse, 310);
    final t = await taze(a);
    expect(t.total.length, greaterThan(2));
    await yenidenAc();
    ag = 0;
    final e = await eldeki(a);
    expect(ag, 0, reason: 'eski seri yolu ağa çıkmaz');
    expect(e, isNotNull);
    expect(e!.sonuc.total, t.total);
    expect(e.sonuc.seansGunu, gunBasi);
  });

  test('ertesi gün: dünün gün içi serisi eski seri olarak da kullanılmaz',
      () async {
    final a = varlik('THYAO.IS', AssetType.hisse, 310);
    await taze(a);
    await yenidenAc();
    HistoryService.gunIciSaat =
        () => DateTime(b.year, b.month, b.day + 1, 10);
    expect(await eldeki(a), isNull);
  });

  test('altın: yurt içi kayıt diskten (bugünün); kayıt yoksa gösterilmez',
      () async {
    final a = varlik('ALTIN_GRAM', AssetType.altin, 6020);
    final t = await taze(a);
    expect(kayitSorgusu, 1);
    await yenidenAc();
    kayitSorgusu = 0;
    ag = 0;
    final e = await eldeki(a);
    expect(kayitSorgusu, 0, reason: 'yurt içi kaynağa ağdan sorulmaz');
    expect(ag, 0);
    expect(e, isNotNull);
    expect(e!.sonuc.total, t.total,
        reason: 'aynı merdiven, aynı kayıt: ölçülmüş seri');

    // Yurt içi kaydın disk kopyası yok: kaydı atlayıp hesap uluslararası
    // altından BAŞKA bir seri çizerdi — eski seri gösterilmez.
    await yenidenAc();
    for (final f in Directory('${gecici.path}/seri_onbellek').listSync()) {
      final ad = f.uri.pathSegments.last;
      if (ad.startsWith(SeriDiskDepo.dosyaAdi('yurtici|').substring(0, 8))) {
        f.deleteSync();
      }
    }
    expect(await eldeki(a), isNull);
  });

  test('TEFAS fonu: gözlem yalnız bellekte; soğuk açılışta gösterilmez',
      () async {
    final a = varlik('TEFAS:AFA', AssetType.fon, 1.02);
    final t = await taze(a);
    expect(gozlemSorgusu, 1);
    // Bellek sıcak (aynı oturum): gözlem bellekten, NAV süreli önbellekten.
    gozlemSorgusu = 0;
    final sicak = await eldeki(a);
    expect(gozlemSorgusu, 0);
    expect(sicak, isNotNull, reason: 'bugün alınmış gözlem bellekte');
    expect(sicak!.sonuc.total, t.total);

    await yenidenAc();
    gozlemSorgusu = 0;
    ag = 0;
    expect(await eldeki(a), isNull,
        reason: 'gözlemsiz hesap basamağı sabit saate çizerdi');
    expect(gozlemSorgusu, 0);
    expect(ag, 0);
  });

  test('ekran: GÜNLÜK de önce-eski-seri yolunda, seansıyla', () {
    final k = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    expect(k, contains('getPortfolioHistoryHourlyBreakdownEldeki([birim])'));
    expect(k, isNot(contains('if (days == 0) return false;')));
    expect(k, contains('if (days == 0) _gunIciBaslangic = seans;'));
  });
}
