import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/eurobond.dart';
import 'package:portfoy_takip/services/eurobond_ozeti.dart';
import 'package:portfoy_takip/widgets/eurobond_karti.dart';

/// Varlık ekranının "Tahvil bilgileri" kartı (2026-10-08). Sayılar
/// `eurobondOzeti`'nde; kaynağı olmayan satır ÇİZİLMEZ (uydurma sayı yasağı).

final _tr28 = EurobondSozlesmesi(
  isin: 'US900123DF45',
  ad: 'Türkiye %9,875 2028',
  paraBirimi: 'USD',
  kuponOrani: 0.09875,
  vade: DateTime.utc(2028, 1, 15),
  ihracTarihi: DateTime.utc(2018, 1, 15),
  ihracci: EurobondIhracci.hazine,
);

final _kurumsal = EurobondSozlesmesi(
  isin: 'XS1234567896',
  ad: 'Banka 2027',
  paraBirimi: 'USD',
  kuponOrani: 0.06,
  vade: DateTime.utc(2027, 4, 1),
  ihracTarihi: DateTime.utc(2025, 4, 1), // 2 yıllık ihraç → %3
  ihracci: EurobondIhracci.ozelSektor,
);

final _gun = DateTime(2026, 4, 15);

EurobondFiyati _fiyat({double? temiz, double? alis, double? satis}) =>
    EurobondFiyati(
      isin: 'US900123DF45',
      temizFiyat: temiz,
      bankaAlis: alis,
      bankaSatis: satis,
      guncellendi: DateTime(2026, 4, 15, 14, 20),
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('eurobondOzeti', () {
    test('tam veri: kirli, getiri, kupon, kalan gün, banka', () {
      final o = eurobondOzeti(
        sozlesme: _tr28,
        fiyat: _fiyat(temiz: 104.125, alis: 105.9, satis: 107.4),
        nominal: 10000,
        simdi: _gun,
      );
      expect(o.islemisFaiz, closeTo(2.46875, 1e-9));
      expect(o.kirliFiyat, closeTo(106.59375, 1e-9));
      expect(o.vadeyeGetiri, isNotNull);
      expect(o.sonrakiKupon, DateTime.utc(2026, 7, 15));
      expect(o.sonrakiKuponTutari, closeTo(493.75, 1e-9));
      expect(o.kalanGun, DateTime.utc(2028, 1, 15)
          .difference(DateTime.utc(2026, 4, 15))
          .inDays);
      expect(o.bankaMakasi, closeTo(1.5, 1e-9));
      expect(o.bankayaSatisTutari, closeTo(10590, 1e-9));
      expect(o.bankaGuncellendi, isNotNull);
    });

    test('fiyat yoksa temiz/kirli/getiri/banka null — uydurulmaz', () {
      final o = eurobondOzeti(
          sozlesme: _tr28, fiyat: null, nominal: 0, simdi: _gun);
      expect(o.temizFiyat, isNull);
      expect(o.kirliFiyat, isNull);
      expect(o.vadeyeGetiri, isNull);
      expect(o.sonrakiKuponTutari, isNull, reason: 'nominal bilinmiyor');
      expect(o.bankaVar, isFalse);
      expect(o.bankaGuncellendi, isNull);
      // Sözleşmeden gelenler yine bilinir.
      expect(o.islemisFaiz, greaterThan(0));
      expect(o.sonrakiKupon, isNotNull);
    });

    test('vadesi geçmiş: kupon ve kalan gün yok', () {
      final o = eurobondOzeti(
          sozlesme: _tr28,
          fiyat: null,
          nominal: 1000,
          simdi: DateTime(2028, 2, 1));
      expect(o.sonrakiKupon, isNull);
      expect(o.sonrakiKuponTutari, isNull);
      expect(o.kalanGun, isNull);
      expect(o.islemisFaiz, 0);
    });
  });

  Future<void> ciz(WidgetTester tester, EurobondOzeti o) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.light(),
      home: Scaffold(
        body: SingleChildScrollView(child: EurobondKarti(ozet: o)),
      ),
    ));
  }

  testWidgets('kart: satırlar, stopaj, Ziraat kotasyonu', (tester) async {
    await ciz(
        tester,
        eurobondOzeti(
          sozlesme: _tr28,
          fiyat: _fiyat(temiz: 104.125, alis: 105.9, satis: 107.4),
          nominal: 10000,
          simdi: _gun,
        ));
    expect(find.text('TAHVİL BİLGİLERİ'), findsOneWidget);
    expect(find.text('104,125'), findsOneWidget); // temiz
    expect(find.text('%2,469'), findsOneWidget); // işlemiş faiz
    expect(find.text('106,594'), findsOneWidget); // kirli
    expect(find.text('Vadeye getiri'), findsOneWidget);
    expect(find.text('%9,875 · yılda 2 kez'), findsOneWidget);
    expect(find.text('15 Tem 2026 · 493,75 USD · Stopaj %0'), findsOneWidget);
    expect(find.textContaining('gün kaldı'), findsOneWidget);
    expect(find.text('Hazine'), findsOneWidget);

    expect(find.text('BANKAYA SATARSAN'), findsOneWidget);
    expect(find.textContaining('Ziraat Bankası'), findsOneWidget);
    expect(find.text('105,900'), findsOneWidget);
    expect(find.text('107,400'), findsOneWidget);
    expect(find.text('1,500'), findsOneWidget);
    expect(find.text('10.590,00 USD'), findsOneWidget);
  });

  testWidgets('kart: fiyatsız tahvilde fiyat ve banka satırları yok',
      (tester) async {
    await ciz(
        tester,
        eurobondOzeti(
            sozlesme: _kurumsal, fiyat: null, nominal: 5000, simdi: _gun));
    expect(find.text('Temiz fiyat'), findsNothing);
    expect(find.text('Kirli fiyat'), findsNothing);
    expect(find.text('Vadeye getiri'), findsNothing);
    expect(find.text('BANKAYA SATARSAN'), findsNothing);
    expect(find.text('İşlemiş faiz'), findsOneWidget);
    expect(find.text('Özel sektör'), findsOneWidget);
    expect(find.textContaining('Stopaj %3'), findsOneWidget);
  });
}
