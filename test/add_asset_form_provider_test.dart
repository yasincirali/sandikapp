import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/bulk_cart_provider.dart';
import 'package:portfoy_takip/services/tefas_service.dart';

/// Varlık ekleme formunun durum makinesi — Yahoo/TEFAS/Supabase olmadan
/// (Faz 3.10). Ekran 37 `setState` ile bu kuralları widget ağacına gömmüştü;
/// şimdi her geçiş burada kilitlenir.
class _SahteFiyat implements AddAssetPriceLookup {
  _SahteFiyat({this.hist, this.spotFiyat, this.hataVer = false});
  double? hist;
  double? spotFiyat;
  bool hataVer;
  final istekler = <String>[];

  @override
  Future<double?> historicalClose(String ticker, DateTime date) async {
    istekler.add('hist:$ticker');
    if (hataVer) throw Exception('ağ yok');
    return hist;
  }

  @override
  Future<double?> spot(String ticker) async {
    istekler.add('spot:$ticker');
    if (hataVer) throw Exception('ağ yok');
    return spotFiyat;
  }

  @override
  Future<String?> companyName(String ticker) async => null;
}

final _bugun = DateTime(2026, 9, 14);
final _dun = DateTime(2026, 9, 13);

void main() {
  ProviderContainer kur(_SahteFiyat fiyat) {
    final c = ProviderContainer(overrides: [
      addAssetPriceLookupProvider.overrideWithValue(fiyat),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  group('açılış durumu', () {
    test('varsayılan: hisse, TRY, bugün, piece', () {
      final s = AddAssetFormState.initial(now: _bugun);
      expect(s.type, AssetType.hisse);
      expect(s.currency, AssetType.hisse.defaultCurrency);
      expect(s.unitType, 'piece');
      expect(s.addedDate, _bugun);
      expect(s.isManualPrice, isFalse);
      expect(s.bist100Ticker, isNull);
    });

    test('BIST prefill alt kategoriyi kurar — seçici boş açılmasın', () {
      final s = AddAssetFormState.initial(
        prefillTicker: 'THYAO.IS',
        prefillType: AssetType.hisse,
        now: _bugun,
      );
      expect(s.isBist100, isTrue);
      expect(s.bist100Ticker, 'THYAO.IS');
    });

    test('sepet öğesi sembolsüzse fiyat manueldir', () {
      final c = BulkCartItem(
        id: '1',
        type: AssetType.diger,
        name: 'Tablo',
        ticker: '',
        quantity: 1,
        price: 100,
        currency: 'TRY',
        addedDate: _dun,
      );
      final s = AddAssetFormState.initial(cartInitial: c, now: _bugun);
      expect(s.isManualPrice, isTrue);
      expect(s.addedDate, _dun);
    });

    test('TEFAS sembolü fon nesnesine açılır', () {
      final s = AddAssetFormState.initial(
        prefillTicker: 'TEFAS:AAK',
        prefillType: AssetType.fon,
        now: _bugun,
      );
      expect(s.selectedFund?.code, 'AAK');
      expect(s.resolveTicker(''), 'TEFAS:AAK');
    });
  });

  group('geçişler', () {
    test('tür değişince alt seçimler ve metinler temizlenir', () {
      final c = kur(_SahteFiyat());
      final args = AddAssetFormArgs(
          prefillTicker: 'THYAO.IS', prefillType: AssetType.hisse);
      final n = c.read(addAssetFormProvider(args).notifier);
      final yaz = n.selectType(AssetType.altin);
      final s = c.read(addAssetFormProvider(args));
      expect(s.type, AssetType.altin);
      expect(s.subCategory, isNull);
      expect(s.bist100Ticker, isNull);
      expect(s.currency, AssetType.altin.defaultCurrency);
      expect(yaz.ticker, '');
      expect(yaz.name, '');
      expect(yaz.quantity, isNull, reason: 'miktar korunur');
    });

    test('döviz seçimi TRY karşılığı ve ad/sembol yazar; TRY manueldir', () {
      final c = kur(_SahteFiyat());
      final args = AddAssetFormArgs(prefillType: AssetType.doviz);
      final n = c.read(addAssetFormProvider(args).notifier);
      final usd = n.selectDoviz(dovizOptFor('USD'));
      expect(usd.ticker, 'USDTRY=X');
      expect(usd.name, 'ABD Doları');
      expect(c.read(addAssetFormProvider(args)).isManualPrice, isFalse);
      expect(c.read(addAssetFormProvider(args)).currency, 'TRY');

      n.selectDoviz(dovizOptFor('TRY'));
      expect(c.read(addAssetFormProvider(args)).isManualPrice, isTrue);
    });

    test('serbest sembol yazılınca BIST100 seçimi düşer', () {
      final c = kur(_SahteFiyat());
      final args = AddAssetFormArgs(
          prefillTicker: 'THYAO.IS', prefillType: AssetType.hisse);
      final n = c.read(addAssetFormProvider(args).notifier);
      n.tickerTyped('AAPL');
      final s = c.read(addAssetFormProvider(args));
      expect(s.bist100Ticker, isNull);
      expect(s.subCategory, StockSubCategory.other.label);
      expect(s.isBist100, isFalse);

      n.tickerTyped('');
      expect(c.read(addAssetFormProvider(args)).isManualPrice, isTrue);
    });

    test('fon seçimi fiyatı yalnızca alan boşsa doldurur', () {
      final c = kur(_SahteFiyat());
      final args = AddAssetFormArgs(prefillType: AssetType.fon);
      final n = c.read(addAssetFormProvider(args).notifier);
      const fon = TefasFund(
          code: 'AAK', name: 'Ak Fon', price: 12.5, fundType: '', managerName: '');
      expect(n.selectFund(fon, priceEmpty: true).price, '12,5');
      expect(n.selectFund(fon, priceEmpty: false).price, isNull);
      expect(c.read(addAssetFormProvider(args)).resolveTicker(''), 'TEFAS:AAK');
    });

    test('altın alt türü birim tipini ve adı taşır', () {
      final c = kur(_SahteFiyat());
      final args = AddAssetFormArgs(prefillType: AssetType.altin);
      final n = c.read(addAssetFormProvider(args).notifier);
      final g = GoldSubCategory.values.first;
      final yaz = n.selectGold(g);
      expect(yaz.name, g.label);
      expect(c.read(addAssetFormProvider(args)).unitType, g.unitType);
    });

    test('hızlı giriş satırı tür + döviz + miktar/fiyat kurar', () {
      final c = kur(_SahteFiyat());
      final args = AddAssetFormArgs();
      final n = c.read(addAssetFormProvider(args).notifier);
      final e = parseQuickEntry('100 dolar 32,5 liradan')!;
      final yaz = n.applyParsedEntry(e);
      final s = c.read(addAssetFormProvider(args));
      expect(s.type, AssetType.doviz);
      expect(s.subCategory, 'USD');
      expect(s.currency, 'TRY');
      expect(yaz.ticker, 'USDTRY=X');
      expect(yaz.quantity, '100');
      expect(yaz.price, '32,5');
    });
  });

  group('kayıt kimliği', () {
    test('BIST100: ad haritadan, sembol seçimden', () {
      final s = AddAssetFormState.initial(
          prefillTicker: 'THYAO.IS', prefillType: AssetType.hisse, now: _bugun);
      final k = s.resolveIdentity(nameText: '', tickerText: 'yok sayılır');
      expect(k.ticker, 'THYAO.IS');
      expect(k.name, bist100StocksMap['THYAO.IS']);
      expect(k.manual, isFalse);
    });

    test('diğer hisse: sembol büyük harfe çevrilir; manuelde sembol yok', () {
      var s = AddAssetFormState.initial(now: _bugun)
          .copyWith(subCategory: StockSubCategory.other.label);
      expect(s.resolveIdentity(nameText: 'x', tickerText: ' aapl ').ticker,
          'AAPL');
      s = s.copyWith(isManualPrice: true);
      final k = s.resolveIdentity(nameText: 'x', tickerText: 'aapl');
      expect(k.ticker, '');
      expect(k.manual, isTrue);
    });

    test('döviz TRY sembolsüz → manuel; USD → değil', () {
      final s = AddAssetFormState.initial(prefillType: AssetType.doviz, now: _bugun);
      expect(
          s.copyWith(subCategory: 'TRY').resolveIdentity(nameText: '', tickerText: '').manual,
          isTrue);
      final usd = s.copyWith(subCategory: 'USD').resolveIdentity(nameText: '', tickerText: '');
      expect(usd.manual, isFalse);
      expect(usd.name, 'ABD Doları');
    });
  });

  group('fiyat çözümü', () {
    test('bugün → yalnızca spot', () async {
      final f = _SahteFiyat(spotFiyat: 10);
      final r = await fiyatBul(lookup: f, ticker: 'X', date: _bugun, now: _bugun);
      expect(r.price, 10);
      expect(r.historical, isFalse);
      expect(r.fallbackToSpot, isFalse);
      expect(f.istekler, ['spot:X']);
    });

    test('geçmiş tarih → kapanış', () async {
      final f = _SahteFiyat(hist: 9, spotFiyat: 10);
      final r = await fiyatBul(lookup: f, ticker: 'X', date: _dun, now: _bugun);
      expect(r.price, 9);
      expect(r.historical, isTrue);
      expect(f.istekler, ['hist:X']);
    });

    test('kapanış yoksa spot\'a düşer ve bunu işaretler', () async {
      final f = _SahteFiyat(spotFiyat: 10);
      final r = await fiyatBul(lookup: f, ticker: 'X', date: _dun, now: _bugun);
      expect(r.price, 10);
      expect(r.fallbackToSpot, isTrue);
    });

    test('ağ hatası fiyatsız döner, fırlatmaz', () async {
      final f = _SahteFiyat(hataVer: true);
      final r = await fiyatBul(lookup: f, ticker: 'X', date: _dun, now: _bugun);
      expect(r.price, isNull);
    });
  });

  group('önizleme', () {
    test('kullanıcı fiyat yazdıysa önizleme temizlenir, istek atılmaz',
        () async {
      final f = _SahteFiyat(spotFiyat: 5);
      final c = kur(f);
      final args = AddAssetFormArgs(
          prefillTicker: 'THYAO.IS', prefillType: AssetType.hisse);
      final n = c.read(addAssetFormProvider(args).notifier);
      // Form tarihi gerçek saatten gelir; `now` sabitken tarihi de sabitle,
      // yoksa gün değişince "geçmiş tarih" yoluna düşüp ikinci istek atılır.
      n.setDate(_bugun);
      await n.refreshPreview(userPrice: null, tickerText: '', now: _bugun);
      expect(c.read(addAssetFormProvider(args)).previewPrice, 5);
      await n.refreshPreview(userPrice: 3, tickerText: '', now: _bugun);
      expect(c.read(addAssetFormProvider(args)).previewPrice, isNull);
      expect(f.istekler.length, 1);
    });

    test('sembol yoksa istek atılmaz', () async {
      final f = _SahteFiyat(spotFiyat: 5);
      final c = kur(f);
      final args = AddAssetFormArgs();
      final n = c.read(addAssetFormProvider(args).notifier);
      await n.refreshPreview(userPrice: null, tickerText: '  ', now: _bugun);
      expect(f.istekler, isEmpty);
      expect(c.read(addAssetFormProvider(args)).previewLoading, isFalse);
    });

    test('fiyatCoz sırasında saving açık, sonunda kapalı', () async {
      final c = kur(_SahteFiyat(spotFiyat: 7));
      final args = AddAssetFormArgs();
      final n = c.read(addAssetFormProvider(args).notifier);
      final gorulen = <bool>[];
      c.listen(addAssetFormProvider(args), (_, s) => gorulen.add(s.saving));
      final r = await n.fiyatCoz('X');
      expect(r.price, 7);
      expect(gorulen, [true, false]);
    });
  });

  test('hızlı giriş çözümleyici', () {
    expect(parseQuickEntry('')?.qty, isNull);
    expect(parseQuickEntry('dolar')?.qty, isNull, reason: 'miktarsız satır');
    final g = parseQuickEntry('10 gram altın 4.500 liradan')!;
    expect(g.type, AssetType.altin);
    expect(g.qty, 10);
    expect(g.price, 4500, reason: 'binlik noktası atılır');
    final h = parseQuickEntry('GARAN 500 adet 105 lira')!;
    expect(h.type, AssetType.hisse);
    expect(h.qty, 500);
    expect(h.price, 105);
    // Denetim F15: nokta sonrası 3+ hane eskiden binlik sayılıp atılıyordu.
    expect(parseQuickEntry('100 dolar 41.2345 liradan')!.price, 41.2345);
    expect(parseQuickEntry('0.125 gram altın')!.qty, 0.125);
    expect(parseQuickEntry('1.234,5 dolar')!.qty, 1234.5);
    expect(parseQuickEntry('10 gram altın 4.500,75 liradan')!.price, 4500.75);
  });

  test('ekran durum alanı taşımaz — Faz 3.10 ratchet', () {
    final src = File('lib/screens/add_asset_screen.dart').readAsStringSync();
    final govde = src.substring(
      src.indexOf('class _AddAssetScreenState'),
      src.indexOf('class _QuickEntrySheet'),
    );
    expect(govde.contains('setState('), isFalse,
        reason: 'form durumu addAssetFormProvider\'da; setState geri gelmesin');
    expect(govde.contains('PriceService.instance'), isFalse,
        reason: 'fiyat erişimi AddAssetPriceLookup kapısından');
  });
}
