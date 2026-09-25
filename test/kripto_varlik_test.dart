// Kripto varlık türü — model, fiyat kaynağı, hızlı giriş, CSV, ızgara.
//
// Kullanıcı isteği (2026-09-25): "Kripto varlıkları da gerekli ondalık
// basamaklarla tut, try karşılıklarını da toplam gösterirken best-practice
// neyse o şekilde gösterirsin. Grafikleri, tutarları bozma."
//
// Bu dosya üç şeyi kilitler:
//   1. Miktar SİLİNMEZ: 0,0045 BTC "0,00" görünmez; tam sayı yine
//      ondalıksız; diğer türlerin kuralı değişmez.
//   2. TL tek kaynaktan: kripto TRY kotedir, ikinci çevrim yok, Yahoo'ya
//      düşmez.
//   3. Kriptosuz portföyün grafiği DEĞİŞMEZ; kripto varsa hafta sonu
//      ızgarada kalır.
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/kripto_fiyat.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/services/csv_import_service.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/price_service.dart';

Asset _kripto(double q, {String ticker = 'KRIPTO:BTC'}) => Asset(
      id: 'k',
      userId: 'u',
      name: 'Bitcoin',
      ticker: ticker,
      type: AssetType.kripto,
      quantity: q,
      purchasePrice: 3650000,
      currency: 'TRY',
      notes: '',
      currentPrice: 3950000,
    );

String _fmt(double v, int d) => v.toStringAsFixed(d);

void main() {
  group('sembol', () {
    test('KRIPTO: öneki çözülür, biçim dışı reddedilir', () {
      expect(kriptoKodu('KRIPTO:BTC'), 'BTC');
      expect(kriptoKodu(' kripto:eth '), 'ETH');
      expect(kriptoKodu('BTC-USD'), isNull);
      expect(kriptoKodu('KRIPTO:'), isNull);
      expect(kriptoSembolu('sol'), 'KRIPTO:SOL');
    });
  });

  group('miktar ondalığı', () {
    test('gereken kadar hane, en çok 8', () {
      expect(gerekenOndalik(2), 0);
      expect(gerekenOndalik(1.5), 1);
      expect(gerekenOndalik(0.004521), 6);
      expect(gerekenOndalik(0.00000001), 8);
      expect(gerekenOndalik(0.123456789), 8);
      // Kayan nokta gürültüsü hane şişirmez.
      expect(gerekenOndalik(0.1 + 0.2), 1);
    });

    test('kripto miktarı silinmez; birim coin kodu', () {
      final a = _kripto(0.004521);
      expect(a.miktarOndalik, 6);
      expect(a.miktarMetni(0.004521, _fmt), '0.004521 BTC');
      expect(_kripto(3).miktarMetni(3, _fmt), '3 BTC');
      expect(a.unitLabel, 'BTC');
    });

    test('diğer türlerin kuralı DEĞİŞMEDİ (2 hane)', () {
      final hisse = Asset(
        id: 'h', userId: 'u', name: 'THYAO', ticker: 'THYAO.IS',
        type: AssetType.hisse, quantity: 10.123456, purchasePrice: 300,
        currency: 'TRY', notes: '',
      );
      expect(hisse.miktarOndalik, 2);
    });
  });

  group('pozisyon', () {
    test('kripto lotları sembolde birleşir; TL toplamı çevrimsiz', () {
      final lotlar = [_kripto(0.001), _kripto(0.0035)];
      expect(positionKey(lotlar[0]), positionKey(lotlar[1]));
      expect(positionKey(lotlar[0]), 'kripto|KRIPTO:BTC|TRY');
      // TRY kote: maliyet × kur = maliyet (purchaseFxRate 1).
      expect(lotlar[0].totalCostTRY, closeTo(0.001 * 3650000, 1e-6));
    });
  });

  group('fiyat kaynağı sözleşmesi', () {
    test('kripto seriye girer, USD kote değildir, tek sembol çekilir', () {
      final a = _kripto(0.01);
      expect(FiyatKaynagi.seriyeGirer(a), isTrue);
      expect(FiyatKaynagi.usdKote(a), isFalse);
      expect(FiyatKaynagi.seriSembolleri(a), ['KRIPTO:BTC']);
      expect(FiyatKaynagi.kriptoMu('KRIPTO:BTC'), isTrue);
      expect(FiyatKaynagi.kriptoMu('BTC-USD'), isFalse);
      expect(FiyatKaynagi.yediGun(a), isTrue);
    });

    test('Yahoo dönem/aralık adları sunucunun tanıdıklarına yuvarlanır', () {
      expect(PriceService.kriptoDonemi('1mo'), '1mo');
      expect(PriceService.kriptoDonemi('3y'), '5y');
      expect(PriceService.kriptoDonemi('ytd'), '1y');
      expect(PriceService.kriptoDonemi('10y'), 'max');
      expect(PriceService.kriptoAraligi('1wk'), '1wk');
      expect(PriceService.kriptoAraligi('60m'), '1h');
      expect(PriceService.kriptoAraligi('3mo'), '1d');
    });
  });

  group('sunucu satırı', () {
    test('yüzde İstanbul açılışına göre; açılış yoksa yüzde yok', () {
      final f = KriptoFiyat.fromMap({
        'kod': 'btc',
        'fiyat_try': 4000000,
        'gun_acilis_try': 3900000,
        'guncellendi': '2026-09-25T12:00:00Z',
      })!;
      expect(f.kod, 'BTC');
      expect(f.gunlukYuzde, closeTo((4000000 / 3900000 - 1) * 100, 1e-9));
      final yok = KriptoFiyat.fromMap({
        'kod': 'SOL',
        'fiyat_try': 8700,
        'gun_acilis_try': null,
        'guncellendi': '2026-09-25T12:00:00Z',
      })!;
      expect(yok.gunlukYuzde, isNull);
    });

    test('bozuk satır nesne üretmez (uydurma sıfır yok)', () {
      expect(
          KriptoFiyat.fromMap({'kod': 'BTC', 'fiyat_try': 0, 'guncellendi': 'x'}),
          isNull);
    });

    test('10 dakikadan eski satır bayat', () {
      final f = KriptoFiyat(
        kod: 'BTC',
        fiyatTry: 1,
        gunAcilisTry: null,
        guncellendi: DateTime.utc(2026, 9, 25, 12),
      );
      expect(f.bayatMi(DateTime.utc(2026, 9, 25, 12, 9)), isFalse);
      expect(f.bayatMi(DateTime.utc(2026, 9, 25, 12, 11)), isTrue);
    });
  });

  group('hızlı giriş', () {
    test('"usdt" artık dolar sanılmıyor', () {
      final e = parseQuickEntry('500 usdt')!;
      expect(e.type, AssetType.kripto);
      expect(e.subCategory, 'USDT');
    });

    test('"0,05 btc 3.900.000 tl"', () {
      final e = parseQuickEntry('0,05 btc 3.900.000 tl')!;
      expect(e.type, AssetType.kripto);
      expect(e.subCategory, 'BTC');
      expect(e.qty, 0.05);
      expect(e.price, 3900000);
    });

    test('dolar girişleri değişmedi', () {
      expect(parseQuickEntry('100 dolar')!.type, AssetType.doviz);
      expect(parseQuickEntry('100 usd')!.subCategory, 'USD');
    });
  });

  group('CSV', () {
    test('yalnızca açık işaretli semboller kripto', () {
      expect(CsvImportService.inferType('KRIPTO:BTC'), AssetType.kripto);
      expect(CsvImportService.inferType('BTC-USD'), AssetType.kripto);
      expect(CsvImportService.inferType('ETHUSDT'), AssetType.kripto);
      // Çıplak 3 harf TEFAS koduyla ayırt edilemez → fon kalır.
      expect(CsvImportService.inferType('BTC'), AssetType.fon);
    });

    test('kripto satırı KRIPTO: sembolü ve TRY ile saklanır', () {
      final n = CsvImportService.normalizeTicker('btc-usd', AssetType.kripto);
      expect(n.ticker, 'KRIPTO:BTC');
      expect(n.currency, 'TRY');
      final ciplak = CsvImportService.normalizeTicker('eth', AssetType.kripto);
      expect(ciplak.ticker, 'KRIPTO:ETH');
    });
  });

  group('gün içi ızgara', () {
    final pazar = DateTime(2026, 9, 13, 15, 30);

    test('kriptosuz: DEĞİŞMEDİ (hafta sonu elenir, Cuma\'ya çapalanır)', () {
      final eski = HistoryService.gridSlotlari(
          now: pazar, periodDays: 1, hourly: true);
      final gunler = eski
          .map((t) => DateTime.fromMillisecondsSinceEpoch(t).weekday)
          .toSet();
      expect(gunler.contains(DateTime.sunday), isFalse);
      expect(gunler.contains(DateTime.saturday), isFalse);
    });

    test('kriptolu: Pazar günü bugünün saatleri ızgarada', () {
      final slots = HistoryService.gridSlotlari(
          now: pazar, periodDays: 1, hourly: true, yediGun: true);
      final son = DateTime.fromMillisecondsSinceEpoch(slots.last);
      expect(son.weekday, DateTime.sunday);
      expect(son.hour, 15);
      expect(slots.length, 25);
    });
  });
}
