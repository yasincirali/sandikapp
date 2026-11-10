import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/services/veri_kalitesi.dart';
import 'package:portfoy_takip/widgets/veri_kalitesi_seridi.dart';

/// Fiyatı gelmeyen fon "bilgi eksik" sayılır (müşteri 2026-11-10).
///
/// Sabitlenenler: eşik BIST iş günüyle (hafta sonu ve resmî tatil
/// sayılmaz, arife sayılır), 7 iş günü uyarı değil, 8 uyarı; satırdaki gün
/// takvim günü; gün bilinmiyorsa işaret yok (uydurma yok); yalnız bugünkü
/// mülkiyet; elle fiyatlı fon bu türe girmez (o [VeriEksigiTuru.eskiFiyat]).
final _simdi = DateTime(2026, 11, 10, 14); // Salı

Asset _fon(
  String id, {
  String kod = 'AFT',
  AssetKind kind = AssetKind.buy,
  bool elle = false,
  double q = 10,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: '$kod fonu',
      ticker: kod,
      type: AssetType.fon,
      quantity: q,
      purchasePrice: 1,
      sellPrice: kind == AssetKind.sell ? 1.2 : null,
      currency: 'TRY',
      notes: '',
      isManualPrice: elle,
      currentPrice: 1.1,
      addedDate: DateTime(2026, 1, 5),
      kind: kind,
    );

List<VeriEksigi> _eksikler(List<Asset> lotlar, Map<String, DateTime?> gunler) =>
    veriEksikleri(aggregatePositions(aktifLotlar(lotlar)),
        simdi: _simdi, fonFiyatTarihi: (k) => gunler[k]);

void main() {
  group('bistIsGunuFarki', () {
    test('Cuma fiyatı Pazartesi 1 iş günü', () {
      expect(
          bistIsGunuFarki(DateTime(2026, 11, 6), DateTime(2026, 11, 9, 9)), 1);
    });

    test('6 iş günü (2 Kas → 10 Kas)', () {
      expect(bistIsGunuFarki(DateTime(2026, 11, 2), _simdi), 6);
    });

    test('29 Ekim tatili sayılmaz: 28 Eki → 10 Kas 8 iş günü', () {
      expect(bistIsGunuFarki(DateTime(2026, 10, 28), _simdi), 8);
    });

    test('Kurban Bayramı atlanır, arife sayılır: 12 takvim günü 5 iş günü', () {
      // 22 May Cuma → 3 Haz Çarşamba: 25 May, 26 May (arife), 1-3 Haz.
      expect(bistIsGunuFarki(DateTime(2026, 5, 22), DateTime(2026, 6, 3)), 5);
    });
  });

  group('veriEksikleri: fiyatGelmiyor', () {
    test('6 iş günü → işaret yok', () {
      expect(_eksikler([_fon('a')], {'AFT': DateTime(2026, 11, 2)}), isEmpty);
    });

    test('tam 7 iş günü → işaret yok (eşik "7 günden eski")', () {
      expect(_eksikler([_fon('a')], {'AFT': DateTime(2026, 10, 30)}), isEmpty);
    });

    test('8 iş günü → işaret, gün takvim günü', () {
      final e = _eksikler([_fon('a')], {'AFT': DateTime(2026, 10, 28)});
      expect(e, hasLength(1));
      expect(e.single.tur, VeriEksigiTuru.fiyatGelmiyor);
      expect(e.single.gun, 13);
      expect(eksikPozisyonSayisi(e), 1);
    });

    test('bayram uzun görünse de iş günü azsa işaret yok', () {
      final e = veriEksikleri(aggregatePositions([_fon('a')]),
          simdi: DateTime(2026, 6, 3, 10),
          fonFiyatTarihi: (_) => DateTime(2026, 5, 22));
      expect(e, isEmpty);
    });

    test('gün bilinmiyor → işaret yok', () {
      expect(_eksikler([_fon('a')], {'AFT': null}), isEmpty);
      expect(veriEksikleri(aggregatePositions([_fon('a')]), simdi: _simdi),
          isEmpty);
    });

    test('tamamı satılmış fon sorulmaz (aktifLotlar)', () {
      final e = _eksikler([
        _fon('al', q: 10),
        _fon('sat', kind: AssetKind.sell, q: 10),
      ], {
        'AFT': DateTime(2026, 9, 1)
      });
      expect(e, isEmpty);
    });

    test('elle fiyatlı fon bu türe girmez', () {
      final e =
          _eksikler([_fon('a', elle: true)], {'AFT': DateTime(2026, 9, 1)});
      expect(e.where((x) => x.tur == VeriEksigiTuru.fiyatGelmiyor), isEmpty);
    });
  });

  testWidgets('bilgi sayfası: neden ve iki yol, Anladım akışı sürdürür',
      (tester) async {
    final eksik =
        _eksikler([_fon('a')], {'AFT': DateTime(2026, 10, 28)}).single;
    bool? sonuc;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                sonuc = await showFiyatGelmiyorSayfasi(context, eksik),
            child: const Text('aç'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    expect(find.text('AFT fonu fiyatı gelmiyor'), findsOneWidget);
    expect(
        find.text('Fon kapanmış ya da başka fonla birleşmiş olabilir. '
            'Elle fiyat girebilir ya da satış kaydedebilirsin.'),
        findsOneWidget);
    await tester.tap(find.text('Anladım'));
    await tester.pumpAndSettle();
    expect(sonuc, isTrue);
  });
}
