import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart' show positionKey;
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/price_service.dart';

import 'helpers/kaynak.dart';

/// **Varlık ekranı = 1 birimin grafiği; tutar = piyasa etkisi**
/// (kullanıcı kararı, 2026-09-23).
///
/// > *"Portföyden varlığa girildiğinde zaman aralığına göre 1 gram ya da
/// > bir lot varlığın grafiğini göstermeli, diğer alanlarda da kazanç
/// > hesaplanarak yazılmalı. Varlık ekranındaki altın grafiği ve değişimi
/// > ile performans ekranında altın seçtiğimde, dönem içi eklemeler dışında
/// > aynı farkı görmem lazım — piyasa etkisi olarak."*
///
/// ## Neden bu dosya iki eski testin yerini aldı
/// `varlik_ekrani_alim_etkisi_test` ve `varlik_donem_degisimi_test` aynı
/// gün yazılmıştı ve POZİSYON serisini miktara bölen bir düzeltmeyi
/// (`miktarDamgada`/`bolenDamgada`) kaynak metninden kilitliyordu. O
/// düzeltme yetmedi: ekran ham `addedDate` ile bölüyor, motor (`HistoryService`)
/// `addedDate`i gün/saat/5 dk'ya YUVARLAYARAK kapılıyordu — alım slotunda
/// pay iki lot, bölen bir lot sayıyordu. Bölme kaldırıldı; birim seri
/// doğrudan çekiliyor (`FiyatKaynagi.birimVarlik`). Eski testlerin geçerli
/// regresyon vakaları (boş ilk slot → 100 kat tutar, gün içi alım) burada
/// yeni sözleşmeyle yeniden yazıldı.
///
/// Motor testleri AĞSIZ koşar: `HistoryService.seriCekici` sahte seriyle
/// değiştirilir, çıktı servisin KENDİ hesabıdır (yeniden hesaplanmaz).
void main() {
  final now = DateTime.now();
  final bugun = DateTime(now.year, now.month, now.day);

  Asset lot({
    required String id,
    required String ticker,
    required double qty,
    required double fiyat,
    required DateTime tarih,
    AssetKind kind = AssetKind.buy,
    double? satis,
  }) =>
      Asset(
        id: id,
        userId: 'u1',
        name: ticker,
        ticker: ticker,
        type: AssetType.hisse,
        quantity: qty,
        purchasePrice: fiyat,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: fiyat,
        addedDate: tarih,
        kind: kind,
        sellPrice: satis,
      );

  /// Günlük fiyat: 40 gün önce 100, her gün +1. Tek sembol için.
  double fiyatGun(int gunOnce) => 140.0 - gunOnce;

  /// Sahte seri — yalnızca [semboller] için dolu, gerisi boş.
  void sahteSeri(Set<String> semboller) {
    HistoryService.seriCekici = (sym, range, interval) async {
      if (!semboller.contains(sym)) return const [];
      return [
        for (var g = 40; g >= 0; g--)
          (
            bugun.subtract(Duration(days: g)).millisecondsSinceEpoch,
            fiyatGun(g),
          ),
      ];
    };
  }

  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
  });

  Future<PortfolioHistoryBreakdown> motor(List<Asset> defter, DateTime from) =>
      HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
        assets: defter,
        from: from,
        to: now,
        tier: ResolutionTier.daily,
      );

  group('birimVarlik — sentetik 1 birimlik lot', () {
    final gercek = lot(
        id: 'x', ticker: 'THYAO', qty: 250, fiyat: 312.5, tarih: bugun);

    test('miktar 1, her pencereden ÖNCE alınmış', () {
      final b = FiyatKaynagi.birimVarlik(gercek);
      expect(b.quantity, 1);
      expect(b.isBuy, isTrue);
      expect(b.addedDate.isBefore(bugun.subtract(const Duration(days: 3650))),
          isTrue,
          reason: 'tarih kapısı hiçbir slotta miktarı sıfırlamamalı');
    });

    test('kaynağı belirleyen alanlar AYNEN taşınır', () {
      // Ağırlık çarpanı, kalibrasyon ve sembol seçimi bu alanlardan okunur;
      // biri değişirse birim seri başka bir ürünü çizer.
      final b = FiyatKaynagi.birimVarlik(gercek);
      expect(b.ticker, gercek.ticker);
      expect(b.type, gercek.type);
      expect(b.subCategory, gercek.subCategory);
      expect(b.currency, gercek.currency);
      expect(b.currentPrice, gercek.currentPrice);
      expect(b.isManualPrice, gercek.isManualPrice);
      expect(positionKey(b), positionKey(gercek));
      expect(FiyatKaynagi.seriSembolleri(b),
          FiyatKaynagi.seriSembolleri(gercek));
    });
  });

  group('MOTOR: birim seri alımdan ETKİLENMEZ', () {
    test('dönem içi alım pozisyon serisini zıplatır, birim seriyi DEĞİL',
        () async {
      const t = 'ZZBIRIM1';
      sahteSeri({t});
      final from = bugun.subtract(const Duration(days: 20));
      final eski = lot(
          id: 'l1',
          ticker: t,
          qty: 10,
          fiyat: 100,
          tarih: bugun.subtract(const Duration(days: 60)));
      // Gün ORTASINDA alım — eski düzeltmeyi kıran tam bu damgaydı.
      final yeni = lot(
          id: 'l2',
          ticker: t,
          qty: 10,
          fiyat: fiyatGun(5),
          tarih: bugun
              .subtract(const Duration(days: 5))
              .add(const Duration(hours: 14, minutes: 30)));

      final poz = (await motor([eski, yeni], from)).total;
      final birim =
          (await motor([FiyatKaynagi.birimVarlik(yeni)], from)).total;
      expect(birim, isNotEmpty);

      // Birim seri = fiyatın KENDİSİ, her slotta.
      for (final e in birim.entries) {
        final gunOnce =
            bugun.difference(DateTime.fromMillisecondsSinceEpoch(e.key)).inDays;
        expect(e.value, closeTo(fiyatGun(gunOnce), 1e-9),
            reason: 'birim seri miktar TAŞIMAZ');
      }

      // Pozisyon serisi ise alımda ~2 kat zıplar — "grafik bu değil"
      // bildiriminin kaynağı.
      final pk = poz.keys.toList()..sort();
      var enBuyukOran = 0.0;
      for (var i = 1; i < pk.length; i++) {
        final r = poz[pk[i]]! / poz[pk[i - 1]]!;
        if (r > enBuyukOran) enBuyukOran = r;
      }
      expect(enBuyukOran, greaterThan(1.9),
          reason: 'pozisyon serisi alımı taşır; grafik onu çizmemeli');
    });

    test('birleşik varlık (bugünkü toplam + ilk tarih) geçmişi ŞİŞİRİR',
        () async {
      // `Position.asDisplayAsset` ile seri çekmenin neden yanlış olduğu:
      // bugün alınan miktar dönemin tamamında varmış gibi sayılır.
      const t = 'ZZBIRIM2';
      sahteSeri({t});
      final from = bugun.subtract(const Duration(days: 20));
      final birlesik = lot(
          id: 'pos',
          ticker: t,
          qty: 20,
          fiyat: 100,
          tarih: bugun.subtract(const Duration(days: 60)));
      final dogru = [
        lot(
            id: 'l1',
            ticker: t,
            qty: 10,
            fiyat: 100,
            tarih: bugun.subtract(const Duration(days: 60))),
        lot(
            id: 'l2',
            ticker: t,
            qty: 10,
            fiyat: fiyatGun(5),
            tarih: bugun.subtract(const Duration(days: 5))),
      ];
      final a = (await motor([birlesik], from)).total;
      final b = (await motor(dogru, from)).total;
      final ilk = (a.keys.toList()..sort()).first;
      expect(a[ilk]! / b[ilk]!, closeTo(2.0, 1e-9),
          reason: 'dönem başında 10 lot vardı, birleşik varlık 20 sayar');
    });
  });

  group('KAZANÇ = piyasa etkisi (Performans ile aynı fonksiyon)', () {
    test('alım YOKSA tutar = miktar × birim fark, yüzdeyle TUTARLI',
        () async {
      const t = 'ZZKAZANC1';
      sahteSeri({t});
      final from = bugun.subtract(const Duration(days: 20));
      final l = lot(
          id: 'l1',
          ticker: t,
          qty: 10,
          fiyat: 100,
          tarih: bugun.subtract(const Duration(days: 60)));
      final poz = (await motor([l], from)).total;
      final birim = (await motor([FiyatKaynagi.birimVarlik(l)], from)).total;

      final pe = PeriodSummaryService.piyasaEtkisi(
          seri: poz, lotlar: [l], start: from, end: now)!;
      final u = PeriodSummaryService.uclar(birim,
          fromMs: from.millisecondsSinceEpoch,
          toMs: now.millisecondsSinceEpoch)!;
      expect(pe.katki, 0);
      expect(pe.piyasa, closeTo(10 * (u.last - u.first), 1e-6));
      // Yüzde (ürün) ile tutar (sahip) aynı hareketi anlatır.
      final birimPct = (u.last / u.first - 1) * 100;
      expect(pe.piyasa / pe.taban * 100, closeTo(birimPct, 1e-9));
    });

    test('dönem içi ALIM: yeni lot yalnızca alış fiyatından sonrasını kazanır',
        () async {
      // Eski formül `(son − baş) × SON miktar` idi: bugün alınan lot da
      // dönem başından beri elde sayılıyordu.
      const t = 'ZZKAZANC2';
      sahteSeri({t});
      final from = bugun.subtract(const Duration(days: 20));
      final eski = lot(
          id: 'l1',
          ticker: t,
          qty: 10,
          fiyat: 100,
          tarih: bugun.subtract(const Duration(days: 60)));
      const alisFiyati = 137.0;
      final yeni = lot(
          id: 'l2',
          ticker: t,
          qty: 10,
          fiyat: alisFiyati,
          tarih: bugun
              .subtract(const Duration(days: 3))
              .add(const Duration(hours: 11)));
      final defter = [eski, yeni];
      final poz = (await motor(defter, from)).total;
      final pe = PeriodSummaryService.piyasaEtkisi(
          seri: poz, lotlar: defter, start: from, end: now)!;

      final basFiyat = fiyatGun(20);
      final sonFiyat = fiyatGun(0);
      expect(pe.katki, closeTo(10 * alisFiyati, 1e-9));
      expect(
          pe.piyasa,
          closeTo(
              10 * (sonFiyat - basFiyat) + 10 * (sonFiyat - alisFiyati), 1e-6));
      final eskiFormul = (sonFiyat - basFiyat) * 20;
      expect(pe.piyasa, isNot(closeTo(eskiFormul, 1)),
          reason: 'yeni lot dönem başındaki fiyattan alınmadı');
    });

    test('dönem içinde AÇILAN pozisyon: alım tabanda, katkıda DEĞİL',
        () async {
      // İlk dolu slot alımı zaten içeriyor; aynı alım katkıya da girerse
      // piyasa etkisi alım tutarı kadar eksiye düşerdi (çifte sayım). Grafik
      // kartında gerçekten vardı — Özet 2026-09-16'da kapatmıştı.
      const t = 'ZZKAZANC3';
      sahteSeri({t});
      final from = bugun.subtract(const Duration(days: 20));
      final l = lot(
          id: 'l1',
          ticker: t,
          qty: 10,
          fiyat: fiyatGun(6),
          tarih: bugun
              .subtract(const Duration(days: 6))
              .add(const Duration(hours: 10)));
      final poz = (await motor([l], from)).total;
      final pe = PeriodSummaryService.piyasaEtkisi(
          seri: poz, lotlar: [l], start: from, end: now)!;
      expect(pe.katki, 0, reason: 'lot ilk ölçümün içinde');
      // İlk dolu slot alımın ERTESİ günü (günlük kova 00:00'da kapılar).
      expect(pe.piyasa, closeTo(10 * (fiyatGun(0) - fiyatGun(5)), 1e-6));
      expect(pe.piyasa, greaterThan(0), reason: 'fiyat yükseldi — kazanç');
    });

    test('canlı son değer grafiğin sağ ucudur', () {
      final seri = {1: 1000.0, 2: 1100.0};
      final pe = PeriodSummaryService.piyasaEtkisi(
        seri: seri,
        lotlar: const [],
        start: DateTime.fromMillisecondsSinceEpoch(0),
        end: DateTime.fromMillisecondsSinceEpoch(10),
        canliSon: 1150,
      )!;
      expect(pe.son, 1150);
      expect(pe.piyasa, 150);
      final olcumYok = PeriodSummaryService.piyasaEtkisi(
        seri: seri,
        lotlar: const [],
        start: DateTime.fromMillisecondsSinceEpoch(0),
        end: DateTime.fromMillisecondsSinceEpoch(10),
        canliSon: 0,
      )!;
      expect(olcumYok.son, 1100, reason: 'sıfır canlı değer ölçüm değildir');
    });

    test('BOŞ ilk slot tabana alınmaz (ölçülen: gram fiyatının 100 katı)', () {
      // Kullanıcı ekranı (22 Ayar Gram Altın, 100 gram, 1H): +₺612.621.
      final pe = PeriodSummaryService.piyasaEtkisi(
        seri: {1: 0.0, 2: 612000.0, 3: 612621.0},
        lotlar: const [],
        start: DateTime.fromMillisecondsSinceEpoch(0),
        end: DateTime.fromMillisecondsSinceEpoch(10),
      )!;
      expect(pe.piyasa, closeTo(621, 1e-9));
    });

    test('ölçüm yoksa sayı UYDURULMAZ', () {
      expect(
          PeriodSummaryService.piyasaEtkisi(
            seri: {1: 0.0, 2: 0.0},
            lotlar: const [],
            start: DateTime.fromMillisecondsSinceEpoch(0),
            end: DateTime.fromMillisecondsSinceEpoch(10),
          ),
          isNull);
    });
  });

  group('PARİTE: Σ varlık ekranı == Performans › tür filtresi', () {
    test('ürünlerin piyasa etkileri toplamı türün piyasa etkisine eşit',
        () async {
      const a = 'ZZTUR1', b = 'ZZTUR2';
      sahteSeri({a, b});
      final from = PeriodSummaryService.pencere(SummaryPeriod.birAy, now).start;
      final aLotlari = [
        lot(
            id: 'a1',
            ticker: a,
            qty: 10,
            fiyat: 90,
            tarih: bugun.subtract(const Duration(days: 90))),
        // Dönem içi ALIM — tabanı olan pozisyona ekleme.
        lot(
            id: 'a2',
            ticker: a,
            qty: 4,
            fiyat: 133,
            tarih: bugun
                .subtract(const Duration(days: 7))
                .add(const Duration(hours: 15))),
      ];
      final bLotlari = [
        lot(
            id: 'b1',
            ticker: b,
            qty: 30,
            fiyat: 80,
            tarih: bugun.subtract(const Duration(days: 90))),
        // Dönem içi SATIŞ.
        lot(
            id: 'b2',
            ticker: b,
            qty: 5,
            fiyat: 80,
            tarih: bugun.subtract(const Duration(days: 2)),
            kind: AssetKind.sell,
            satis: 139),
      ];
      final hepsi = [...aLotlari, ...bLotlari];

      double etki(List<Asset> defter, Map<int, double> seri) =>
          PeriodSummaryService.piyasaEtkisi(
                  seri: seri, lotlar: defter, start: from, end: now)!
              .piyasa;

      // Varlık ekranının GERÇEK hesabı: birim seri + lot miktarları.
      Future<double> varlikEkrani(List<Asset> defter) async {
        final birim =
            (await motor([FiyatKaynagi.birimVarlik(defter.first)], from))
                .total;
        return PeriodSummaryService.birimPiyasaEtkisi(
                birimSeri: birim, lotlar: defter, start: from, end: now)!
            .piyasa;
      }

      final tur = await motor(hepsi, from);
      final varlikA = await varlikEkrani(aLotlari);
      final varlikB = await varlikEkrani(bLotlari);
      final performans = etki(hepsi, tur.total);

      expect(varlikA + varlikB, closeTo(performans, 1e-6),
          reason: 'Σ parça == bütün — varlık ekranları türün etkisini tutar');

      // Özet sekmesi de AYNI fonksiyondan okur.
      final ozet = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: hepsi,
        breakdown: tur,
        now: now,
      );
      expect(ozet.piyasaTRY, closeTo(performans, 1e-6));
    });
  });

  group('EMÜLATÖR VAKASI: bugün AÇILAN pozisyon (2026-09-23)', () {
    // Ölçüldü: 22 Ayar Gram, 100 gr, pozisyonun TAMAMI bugün alındı
    // (maliyet ₺616.357,27), şimdi gram ₺6.126,21. Varlık ekranı GÜNLÜK
    // −₺619.300 yazıyordu: pozisyon serisinin ilk dolu slotu alımı içeriyor
    // (motor 14:32'yi 14:30 kovasına yuvarlar), ham damgalı katkı da aynı
    // alımı yazıyordu.
    final gun = DateTime(2026, 9, 23);
    int ts(int saat, int dk) =>
        gun.add(Duration(hours: saat, minutes: dk)).millisecondsSinceEpoch;
    final alim = Asset(
      id: 'g1',
      userId: 'u1',
      name: '22 Ayar Gram Altın',
      ticker: 'ALTIN_GRAM',
      type: AssetType.altin,
      quantity: 100,
      purchasePrice: 6163.5727,
      currency: 'TRY',
      notes: '',
      currentPrice: 6126.21,
      addedDate: gun.add(const Duration(hours: 14, minutes: 32)),
    );
    // Birim seri — gün başı truncgil açılışı (−%0,72'lik gün).
    final birim = {
      ts(0, 0): 6170.64,
      ts(14, 30): 6178.0,
      ts(23, 50): 6126.21,
    };

    test('kazanç ALIŞTAN ölçülür: 100 × 6.126,21 − maliyet', () {
      final r = PeriodSummaryService.birimPiyasaEtkisi(
        birimSeri: birim,
        lotlar: [alim],
        start: gun,
        end: gun.add(const Duration(hours: 23, minutes: 55)),
        canliBirim: 6126.21,
      )!;
      expect(r.basMiktar, 0, reason: 'gün başında gram yoktu');
      expect(r.katki, closeTo(616357.27, 0.01));
      expect(r.piyasa, closeTo(612621 - 616357.27, 0.01),
          reason: 'portföy satırındaki −₺3.736 ile AYNI');
    });

    test('regresyon: pozisyon serisiyle ÇİFTE sayım (ölçülen −₺619.300)', () {
      // Motorun pozisyon serisi: alım 14:30 kovasında VAR.
      final pozisyon = {ts(14, 30): 617800.0, ts(23, 50): 612621.0};
      final eski = PeriodSummaryService.piyasaEtkisi(
        seri: pozisyon,
        lotlar: [alim],
        start: gun,
        end: gun.add(const Duration(hours: 23, minutes: 55)),
      )!;
      expect(eski.piyasa, lessThan(-600000),
          reason: 'ekranda görülen hata: alım hem tabanda hem katkıda');
    });
  });

  group('MOTOR: altın tohumu ürün bazlı yoldan geçer (−%1,39 → −%0,72)', () {
    // Ölçüldü (emülatör, 2026-09-23 23:55): Yahoo gün içi altın verisi
    // gece 03:00 civarında başlıyor; 00:00–03:00 slotları TOHUM. Tohum spot
    // kalibrasyonundan (−%1,39), gerçek slotlar truncgil yüzdesinden
    // (−%0,72) geliyordu → gün başı spot'tan kuruluyordu.
    // Saat SABİT: öğleden sonra 16:40. Duvar saatine bağlı kalsaydı gece
    // yarısına yakın koşularda tohum penceresi kurulamazdı.
    final simdi = DateTime(2026, 9, 23, 16, 40);
    setUp(() {
      HistoryService.clearCache();
      HistoryService.gunIciSaat = () => simdi;
    });
    tearDown(() {
      HistoryService.gunIciSaat = DateTime.now;
      HistoryService.clearCache();
      PriceService.instance.sonBilinenFiyatlariTemizle();
    });

    test('gün başı = ürünün açılışı, gün sonu = canlı; basamak YOK',
        () async {
      final gunBasi = DateTime(simdi.year, simdi.month, simdi.day);
      final gecen = simdi.difference(gunBasi);
      // Veri günün YARISINDA başlar; öncesi tohumdur. Spot bu arada %2
      // düşer — truncgil ise −%0,72 diyor. İkisi bilerek farklı.
      final veriBasi = gunBasi.add(gecen ~/ 2);
      const adim = Duration(minutes: 5);
      final noktalar = <(int, double)>[];
      final n = simdi.difference(veriBasi).inMinutes ~/ 5;
      var t = veriBasi;
      var i = 0;
      while (!t.isAfter(simdi)) {
        noktalar
            .add((t.millisecondsSinceEpoch, 150000.0 * (1 - 0.02 * i / n)));
        t = t.add(adim);
        i++;
      }
      HistoryService.seriCekici = (sym, range, interval) async {
        if (sym == FiyatKaynagi.xauTry) return noktalar;
        if (sym == FiyatKaynagi.usdTry) {
          return [for (final p in noktalar) (p.$1, 41.0)];
        }
        return const [];
      };
      const canli = 6126.21;
      PriceService.instance
          .testIcinKotasyonYaz('ALTIN_GRAM', canli, gunlukPct: -0.72);
      expect(PriceService.instance.altinGunlukYuzdeTam, isTrue);

      final gram = Asset(
        id: 'g',
        userId: 'u1',
        name: '22 Ayar Gram Altın',
        ticker: 'ALTIN_GRAM',
        type: AssetType.altin,
        quantity: 1,
        purchasePrice: 6000,
        currency: 'TRY',
        notes: '',
        currentPrice: canli,
        addedDate: DateTime(2000),
      );
      final b = await HistoryService.instance
          .getPortfolioHistoryHourlyBreakdown([gram], 24);
      final u = PeriodSummaryService.uclar(b.total,
          fromMs: gunBasi.millisecondsSinceEpoch,
          toMs: simdi.millisecondsSinceEpoch)!;
      const acilis = canli / (1 - 0.0072);
      expect(u.firstTs, lessThan(veriBasi.millisecondsSinceEpoch),
          reason: 'test tohum slotunu gerçekten kapsamalı');
      expect(u.first, closeTo(acilis, 0.01),
          reason: 'gün başı truncgil açılışı olmalı, spot değil');
      expect(u.last, closeTo(canli, 0.01));
      expect((u.last / u.first - 1) * 100, closeTo(-0.72, 0.001));

      // Tohumdan ilk gerçek slota geçişte basamak olmamalı.
      final veriIlkTs = b.total.keys
          .where((k) => k >= veriBasi.millisecondsSinceEpoch)
          .reduce((a, c) => a < c ? a : c);
      expect(b.total[veriIlkTs], closeTo(acilis, 0.01));
    });
  });

  group('kaynak: ekranlar ortak kurala bağlı', () {
    /// Yorumlar ATILIR: karar kayıtları eski adları (`miktarDamgada`,
    /// `getPortfolioHistory(days)`) gerekçe olarak anıyor; iddia koda bakar.
    String tek(String yol) => ekranKaynagiSync(yol)
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    test('varlık ekranı BİRİM seriyi çizer, bölmez', () {
      final s = tek('lib/screens/asset_detail_screen.dart');
      expect(s.contains('FiyatKaynagi.birimVarlik(widget.asset)'), isTrue);
      expect(s.contains('miktarDamgada'), isFalse,
          reason: 'bölen kaldırıldı — motorun kapısını ekranda yeniden '
              'kurmak ayrışma üretiyordu');
      expect(s.contains('bolenDamgada'), isFalse);
    });

    test('varlık ekranı Performans\'ın motorunu ve penceresini kullanır', () {
      final s = tek('lib/screens/asset_detail_screen.dart');
      expect(s.contains('getPortfolioHistoryBreakdownAtResolution('), isTrue);
      expect(s.contains('getPortfolioHistory('), isFalse,
          reason: 'eski motor tarih kapısını gün/saate yuvarlıyor');
      expect(s.contains('PeriodSummaryService.pencere(p, now).start'), isTrue);
    });

    test('varlık ekranının tutarı piyasa etkisidir', () {
      final s = tek('lib/screens/asset_detail_screen.dart');
      expect(s.contains('PeriodSummaryService.birimPiyasaEtkisi('), isTrue);
      expect(s.contains('_pozisyonSerisi'), isFalse,
          reason: 'pozisyon serisi motorun 5 dk kapısını taşır; ilk dolu '
              'slot alımı içerip katkıyla ÇİFTE sayılıyordu (−₺619.300)');
      expect(s.contains('periodChangeTRY = (l - f)'), isFalse,
          reason: '(son − baş) × miktar, dönem içi alımı kazanç sayar');
    });

    test('grafik ilk noktayı maliyetle EZMEZ ve alım tarihinde KESMEZ', () {
      final s = tek('lib/screens/asset_detail/eylemler.dart');
      expect(s.contains('anchorUnitPrice'), isFalse);
      expect(s.contains('firstAssetMidnight'), isFalse);
    });

    test('Performans dönem kartı katkıyı taban anından sonra sayar', () {
      final s = tek('lib/screens/portfolio_performance/kartlar.dart');
      expect(s.contains('startExclusiveMs: start.millisecondsSinceEpoch +'),
          isTrue);
    });
  });
}
