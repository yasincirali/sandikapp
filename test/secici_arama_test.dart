import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/secici_arama.dart';

/// Varlık Ekle seçicilerinin süzgeci ve "Portföyündekiler" bölümü
/// (Ar-Ge 0200, 2026-11-07). Süzgeç `trKatla` ile genel aramayla aynı
/// sonucu vermeli; kodu tam yazılan ilk satırda olmalı.
typedef _F = MapEntry<String, String>;

const _fonlar = [
  _F('AAK', 'ATA PORTFÖY ÇOKLU VARLIK DEĞİŞKEN FON'),
  _F('GAU', 'GARANTİ PORTFÖY ALTIN FONU'),
  _F('IPB', 'İŞ PORTFÖY BIST BANKA ENDEKSİ HİSSE SENEDİ FONU'),
  _F('KZL', 'KUVEYT TÜRK PORTFÖY KATILIM HİSSE SENEDİ FONU'),
  _F('TTA', 'TTE ALTIN BAĞLANTILI FON'),
  _F('TTE', 'İŞ PORTFÖY BIST TEKNOLOJİ AĞIRLIKLI SINIRLAMALI HİSSE FONU'),
];

List<String> _ara(String q, [List<_F> l = _fonlar]) =>
    seciciSuz(l, q, kod: (e) => e.key, ad: (e) => e.value)
        .map((e) => e.key)
        .toList();

Asset _lot(String id, AssetType type, String ticker,
        {double qty = 1, double fiyat = 100, AssetKind kind = AssetKind.buy}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: ticker,
      ticker: ticker,
      notes: '',
      type: type,
      unitType: 'adet',
      quantity: qty,
      purchasePrice: fiyat,
      currentPrice: fiyat,
      currency: 'TRY',
      kind: kind,
      addedDate: DateTime(2026, 1, 1),
    );

String? _fonKodu(Asset a) => a.type == AssetType.fon
    ? a.ticker.replaceFirst('TEFAS:', '').toUpperCase()
    : null;

void main() {
  group('seciciSuz', () {
    test('"altın" ALTIN adlı fonları bulur (Dart toLowerCase bulamıyordu)',
        () {
      expect(_ara('altın'), ['GAU', 'TTA']);
    });

    test('"katılım" KATILIM fonunu bulur', () {
      expect(_ara('katılım'), ['KZL']);
    });

    test('"is portfoy" İŞ PORTFÖY fonlarını bulur, "turk" TÜRK\'ü bulur', () {
      expect(_ara('is portfoy'), ['IPB', 'TTE']);
      expect(_ara('turk'), ['KZL']);
    });

    test('kod tam eşleşmesi en üstte, sonra kod başı, sonra ad', () {
      // TTE: kod tam eşit; TTA: kodu "tt" ile başlamaz ama adı "TTE" içerir.
      expect(_ara('tte'), ['TTE', 'TTA']);
      expect(_ara('TT'), ['TTA', 'TTE']); // ikisi de kod başı: gelen sıra
    });

    test('boş ya da yalnız boşluk sorgu listeyi olduğu gibi döner', () {
      expect(_ara(''), _fonlar.map((e) => e.key).toList());
      expect(_ara('   '), _fonlar.map((e) => e.key).toList());
    });

    test('kodSorgusu kod alanına özgü biçimi uygular (ABD "brk.b")', () {
      const abd = [_F('AAPL', 'Apple'), _F('BRK-B', 'Berkshire Hathaway')];
      final r = seciciSuz(abd, 'brk.b',
          kod: (e) => e.key,
          ad: (e) => e.value,
          kodSorgusu: (q) => q.toUpperCase().replaceAll('.', '-'));
      expect(r.map((e) => e.key), ['BRK-B']);
    });
  });

  group('fonAltBasligi', () {
    String yil(String p) => '1 yıl $p';

    test('kurucu ve getiri: "İş Portföy · 1 yıl +%42,1"', () {
      expect(
          fonAltBasligi(
              kurucu: 'İş Portföy', getiri1y: 42.06, yilEtiketi: yil),
          'İş Portföy · 1 yıl +%42,1');
    });

    test('eksi getiri U+2212 ile', () {
      expect(fonAltBasligi(kurucu: 'Ata', getiri1y: -3.2, yilEtiketi: yil),
          'Ata · 1 yıl −%3,2');
    });

    test('getiri yoksa yalnız kurucu (uydurma sayı yok)', () {
      expect(fonAltBasligi(kurucu: 'Ata', getiri1y: null, yilEtiketi: yil),
          'Ata');
    });

    test('ikisi de yoksa null (çağıran fiyat satırına düşer)', () {
      expect(fonAltBasligi(kurucu: '  ', getiri1y: null, yilEtiketi: yil),
          isNull);
    });
  });

  group('Portföyündekiler', () {
    final assets = [
      _lot('1', AssetType.fon, 'TEFAS:TTE', qty: 10),
      _lot('2', AssetType.fon, 'TEFAS:GAU', qty: 50),
      // Tamamen satılmış fon bugün tutulmuyor: bölüme girmez.
      _lot('3', AssetType.fon, 'TEFAS:KZL', qty: 5),
      _lot('4', AssetType.fon, 'TEFAS:KZL', qty: 5, kind: AssetKind.sell),
      _lot('5', AssetType.hisse, 'THYAO.IS', qty: 100),
    ];

    test('aktif fon kodları, değere göre büyükten küçüğe', () {
      expect(portfoydekiKodlar(assets, _fonKodu), ['GAU', 'TTE']);
    });

    test('adet sınırı', () {
      expect(portfoydekiKodlar(assets, _fonKodu, adet: 1), ['GAU']);
    });

    test('bölüm yalnız boş aramada görünür', () {
      final kodlar = portfoydekiKodlar(assets, _fonKodu);
      expect(
          portfoyBolumu(_fonlar, kodlar, '', kod: (e) => e.key)
              .map((e) => e.key),
          ['GAU', 'TTE']);
      expect(portfoyBolumu(_fonlar, kodlar, 'a', kod: (e) => e.key), isEmpty);
      expect(portfoyBolumu(_fonlar, const [], '', kod: (e) => e.key), isEmpty);
    });

    test('listede olmayan kod atlanır', () {
      expect(
          portfoyBolumu(_fonlar, const ['YOK', 'IPB'], '', kod: (e) => e.key)
              .map((e) => e.key),
          ['IPB']);
    });
  });
}
