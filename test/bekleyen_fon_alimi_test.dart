import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/bekleyen_fon_alimi_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/tefas_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/bekleyen_fon_alimi_satiri.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fon alımında "fiyat yarın kesinleşir" (Ar-Ge 7 Kas 14:30 #1).
///
/// Kilitlenen: işaret yalnız fon + tutar kipi + bugün alımında kurulur;
/// alım gününün TEFAS fiyatı gelmeden öneri yok (uydurma sayı yasak), başka
/// günün fiyatı eşleşmez; Güncelle adet = tutar ÷ yeni fiyat, birim maliyet
/// yeni fiyat, toplam aynı; Yok say ve lot düzenleme işareti düşürür.

// Perşembe 5 Kas 2026: alım günü (hafta içi).
final _alim = DateTime(2026, 11, 5);
final _dun = DateTime(2026, 11, 4);
final _ertesi = DateTime(2026, 11, 6);

const _tutar = 10000.0;
const _dunkuFiyat = 2.5; // kayıt anında bilinen → 4000 adet
const _yeniFiyat = 2.56; // alım gününün fiyatı → 3906,25 adet

Asset _lot({double adet = 4000, double fiyat = _dunkuFiyat}) => Asset(
      id: 'lot1',
      userId: 'u1',
      name: 'Ak Portföy Fon',
      ticker: 'TEFAS:AFT',
      type: AssetType.fon,
      quantity: adet,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      kind: AssetKind.buy,
      addedDate: _alim,
    );

BekleyenFonAlimi _isaret({double? kesin, DateTime? kayitGunu}) =>
    BekleyenFonAlimi(
      lotId: 'lot1',
      kod: 'AFT',
      tutar: _tutar,
      alimGunu: _alim,
      kayitAdet: 4000,
      kayitFiyat: _dunkuFiyat,
      kayitFiyatGunu: kayitGunu ?? _dun,
      kesinFiyat: kesin,
    );

class _SahtePortfoy extends PortfolioNotifier {
  _SahtePortfoy(this.lot);
  final Asset lot;
  int guncelleme = 0;

  @override
  Future<PortfolioState> build() async => PortfolioState(assets: [lot]);

  @override
  Future<void> updateAsset(Asset asset) async {
    guncelleme++;
    state = AsyncData(PortfolioState(assets: [asset]));
  }

  /// Lot dışarıdan düzenlendi (form): aynı nesne yeni değerlerle.
  void duzenle(double adet) {
    final a = state.requireValue.assets.single..quantity = adet;
    state = AsyncData(PortfolioState(assets: [a]));
  }
}

class _YuklenmeyenPortfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() => Completer<PortfolioState>().future;
}

void main() {
  group('işaret ne zaman kurulur', () {
    final simdi = DateTime(2026, 11, 5, 11, 0);
    bool kur({
      AssetType tur = AssetType.fon,
      bool tutarModu = true,
      bool fiyatGirildi = false,
      DateTime? islem,
      DateTime? simdiyi,
      DateTime? bilinen,
    }) =>
        fonAlimiIsaretlensinMi(
          tur: tur,
          tutarModu: tutarModu,
          fiyatGirildi: fiyatGirildi,
          islemTarihi: islem ?? simdi,
          simdi: simdiyi ?? simdi,
          bilinenFiyatGunu: bilinen ?? _dun,
        );

    test('fon + tutar kipi + bugün → evet', () => expect(kur(), isTrue));
    test('hisse/BES hayır', () {
      expect(kur(tur: AssetType.hisse), isFalse);
      expect(kur(tur: AssetType.bes), isFalse);
    });
    test('adet kipi hayır', () => expect(kur(tutarModu: false), isFalse));
    test('fiyatı kullanıcı yazdıysa hayır',
        () => expect(kur(fiyatGirildi: true), isFalse));
    test('geçmiş tarihli alım hayır',
        () => expect(kur(islem: _dun), isFalse));
    test('bilinen fiyat zaten bugünün → hayır (adet doğru)',
        () => expect(kur(bilinen: simdi), isFalse));
    // 2026-11-10: hafta sonu/tatil alımı artık işaretlenir; fiyat günü
    // sonraki BIST iş günü (`fonFiyatGunu`). Eskiden "hayır"dı.
    test('hafta sonu alımı evet, fiyat günü Pazartesi', () {
      final cumartesi = DateTime(2026, 11, 7, 11);
      expect(kur(islem: cumartesi, simdiyi: cumartesi), isTrue);
      expect(fonFiyatGunu(cumartesi), DateTime(2026, 11, 9));
      expect(fonFiyatGunu(DateTime(2026, 11, 8, 22)), DateTime(2026, 11, 9));
      // Bilinen fiyat zaten Pazartesi'nin olamaz ama olursa adet doğrudur.
      expect(
          kur(
              islem: cumartesi,
              simdiyi: cumartesi,
              bilinen: DateTime(2026, 11, 9)),
          isFalse);
    });
    test('iş günü alımı kendi gününde (kesim saati sınırı aynen)', () {
      expect(fonFiyatGunu(DateTime(2026, 11, 5, 17)), DateTime(2026, 11, 5));
    });
    test('bayram içinde girilen → bayram sonrası ilk iş günü', () {
      // 2027 Ramazan Bayramı 9–11 Mart (Salı–Perşembe) → 12 Mart Cuma.
      final bayram = DateTime(2027, 3, 10, 11);
      expect(kur(islem: bayram, simdiyi: bayram), isTrue);
      expect(fonFiyatGunu(bayram), DateTime(2027, 3, 12));
      // 2026 Kurban Bayramı 27–30 Mayıs (Çarşamba–Cumartesi) + Pazar →
      // 1 Haziran Pazartesi.
      expect(fonFiyatGunu(DateTime(2026, 5, 28, 9)), DateTime(2026, 6, 1));
      // Yılbaşı 2027 (Cuma) → 4 Ocak Pazartesi.
      expect(fonFiyatGunu(DateTime(2027, 1, 1, 12)), DateTime(2027, 1, 4));
    });
    test('takvimin kapsamadığı yılda eski davranış', () {
      final cumartesi2028 = DateTime(2028, 3, 4, 11);
      expect(fonFiyatGunu(cumartesi2028), isNull);
      expect(kur(islem: cumartesi2028, simdiyi: cumartesi2028), isFalse);
      // Hafta içi o günle eşlenir (dinî bayram bilinmez, uydurulmaz).
      final carsamba2028 = DateTime(2028, 3, 1, 11);
      expect(fonFiyatGunu(carsamba2028), DateTime(2028, 3, 1));
      expect(kur(islem: carsamba2028, simdiyi: carsamba2028, bilinen: _dun),
          isTrue);
      // 31 Ara 2027 Cuma → sonraki iş günü 2028'de; hafta sonu girişi
      // kapsanmayan yıla taşınırsa işaret yok.
      expect(fonFiyatGunu(DateTime(2028, 1, 1)), isNull);
    });
  });

  group('hangi fiyat eşleşir', () {
    test('alım gününün fiyatı eşleşir', () {
      expect(alimGunuFiyati(_isaret(), fiyat: 2.56, tarih: _alim), 2.56);
    });
    test('Cumartesi girilen alım Pazartesi fiyatıyla eşlenir', () {
      final isaret = BekleyenFonAlimi(
        lotId: 'lot1',
        kod: 'AFT',
        tutar: _tutar,
        alimGunu: fonFiyatGunu(DateTime(2026, 11, 7, 11))!,
        kayitAdet: 4000,
        kayitFiyat: _dunkuFiyat,
        kayitFiyatGunu: DateTime(2026, 11, 6),
      );
      expect(
          alimGunuFiyati(isaret, fiyat: 2.56, tarih: DateTime(2026, 11, 9, 18)),
          2.56);
      // Cuma'nın (kayıttaki) fiyatı ve Salı'nınki öneri üretmez.
      expect(alimGunuFiyati(isaret, fiyat: 2.5, tarih: DateTime(2026, 11, 6)),
          isNull);
      expect(alimGunuFiyati(isaret, fiyat: 2.6, tarih: DateTime(2026, 11, 10)),
          isNull);
    });
    test('başka günün fiyatı EŞLEŞMEZ (dün de ertesi gün de)', () {
      expect(alimGunuFiyati(_isaret(), fiyat: 2.5, tarih: _dun), isNull);
      expect(alimGunuFiyati(_isaret(), fiyat: 2.6, tarih: _ertesi), isNull);
    });
    test('fiyat ya da gün yoksa öneri yok (uydurma yok)', () {
      expect(alimGunuFiyati(_isaret(), fiyat: null, tarih: _alim), isNull);
      expect(alimGunuFiyati(_isaret(), fiyat: 2.56, tarih: null), isNull);
      expect(alimGunuFiyati(_isaret(), fiyat: 0, tarih: _alim), isNull);
    });
    test('kayıtta kullanılan fiyatın günüyle aynı gün yeni sayılmaz', () {
      expect(
          alimGunuFiyati(_isaret(kayitGunu: _alim),
              fiyat: 2.56, tarih: _alim),
          isNull);
    });
    test('geçmiş seriden yalnız alım günü', () {
      final seri = [
        (_dun.millisecondsSinceEpoch, 2.5),
        (_alim.millisecondsSinceEpoch, 2.56),
        (_ertesi.millisecondsSinceEpoch, 2.6),
      ];
      expect(gecmistenAlimGunuFiyati(_isaret(), seri), 2.56);
      expect(gecmistenAlimGunuFiyati(_isaret(), [seri.first, seri.last]),
          isNull);
    });
  });

  group('durum', () {
    test('fiyat gelmeden bekliyor', () {
      expect(fonAlimDurumu(_isaret()), isA<FonAlimBekliyor>());
    });
    test('fiyat gelince adet = tutar ÷ yeni fiyat, maliyet yeni fiyat', () {
      final d = fonAlimDurumu(_isaret(kesin: _yeniFiyat)) as FonAlimOnerisi;
      expect(d.adet, closeTo(3906.25, 1e-9));
      expect(d.birimFiyat, _yeniFiyat);
      expect(d.adet * d.birimFiyat, closeTo(_tutar, 1e-6),
          reason: 'toplam tutar aynı kalır');
    });
    test('fiyat değişmediyse öneri yok', () {
      expect(fonAlimDurumu(_isaret(kesin: _dunkuFiyat)), isNull);
    });
    test('lot silindi/düzenlendi → işaret geçersiz', () {
      expect(fonAlimiIsaretiGecersiz(_isaret(), null), isTrue);
      expect(fonAlimiIsaretiGecersiz(_isaret(), _lot(adet: 4100)), isTrue);
      expect(fonAlimiIsaretiGecersiz(_isaret(), _lot(fiyat: 2.4)), isTrue);
      expect(fonAlimiIsaretiGecersiz(_isaret(), _lot()), isFalse);
    });
    test('JSON gidiş-dönüş', () {
      final i = _isaret(kesin: _yeniFiyat);
      final g = BekleyenFonAlimi.fromJson(jsonDecode(jsonEncode(i.toJson())))!;
      expect(g.lotId, i.lotId);
      expect(g.tutar, i.tutar);
      expect(g.alimGunu, _alim);
      expect(g.kayitFiyatGunu, _dun);
      expect(g.kesinFiyat, _yeniFiyat);
      expect(BekleyenFonAlimi.fromJson({'l': 1}), isNull);
    });
  });

  test('yükleme bitmeden eklenen işaret diskteki eskiyi ezmez', () async {
    final eski = BekleyenFonAlimi(
      lotId: 'eski',
      kod: 'AFT',
      tutar: 500,
      alimGunu: _dun,
      kayitAdet: 200,
      kayitFiyat: 2.5,
    );
    SharedPreferences.setMockInitialValues({
      BekleyenFonAlimlariNotifier.anahtar: jsonEncode([eski.toJson()]),
    });
    // Portföy henüz yüklenmedi: eşitleme işaret düşürmez, yalnız yazım
    // sırası sınanır.
    final c = ProviderContainer(overrides: [
      portfolioProvider.overrideWith(_YuklenmeyenPortfoy.new),
    ]);
    addTearDown(c.dispose);
    c.read(bekleyenFonAlimlariProvider.notifier).ekle(_isaret());
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    final ham = jsonDecode(
        prefs.getString(BekleyenFonAlimlariNotifier.anahtar)!) as List;
    expect(ham.map((j) => (j as Map)['l']), containsAll(['eski', 'lot1']));
  });

  group('satır', () {
    late _SahtePortfoy portfoy;

    setUp(() {
      SharedPreferences.setMockInitialValues({
        BekleyenFonAlimlariNotifier.anahtar:
            jsonEncode([_isaret().toJson()]),
      });
      // Ağsız: geçmiş serisi boş (önbellek ileri günü gösterirse).
      TefasService.gecmisCekici = (_, __) async => const [];
    });
    tearDown(() {
      TefasService.gecmisCekici = TefasService.varsayilanGecmisCekici;
      TefasService.instance.fiyatTarihiYaz('AFT', _dunkuFiyat, null);
    });

    Future<ProviderContainer> kur(WidgetTester tester,
        {double genislik = 400, double olcek = 1}) async {
      tester.view.physicalSize = Size(genislik * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      portfoy = _SahtePortfoy(_lot());
      await tester.pumpWidget(ProviderScope(
        overrides: [portfolioProvider.overrideWith(() => portfoy)],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(olcek)),
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              extensions: const [SandikPalette.dark],
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    BekleyenFonAlimiEtiketi(lotIdleri: ['lot1'], onEk: ''),
                    FonAlimOneriSatiri(lotIdleri: ['lot1']),
                  ],
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
          tester.element(find.byType(Scaffold)));
    }

    /// Portföy tazelemesi: TEFAS önbelleği yazılır, portföy yeniden yayınlanır.
    Future<void> fiyatGelir(WidgetTester tester, double f, DateTime gun) async {
      TefasService.instance.fiyatTarihiYaz('AFT', f, gun);
      portfoy.state = AsyncData(PortfolioState(assets: [portfoy.lot]));
      await tester.pumpAndSettle();
    }

    testWidgets('fiyat gelmeden etiket, öneri yok', (tester) async {
      await kur(tester);
      expect(find.text('Fiyat yarın kesinleşir'), findsOneWidget);
      expect(find.byKey(const ValueKey('fonAlimOnerisi')), findsNothing);
    });

    testWidgets('dünkü (başka gün) fiyat öneri üretmez', (tester) async {
      await kur(tester);
      await fiyatGelir(tester, 2.51, _dun);
      expect(find.text('Fiyat yarın kesinleşir'), findsOneWidget);
      expect(find.byKey(const ValueKey('fonAlimOnerisi')), findsNothing);
    });

    testWidgets('alım gününün fiyatı gelince öneri; Güncelle adet/maliyet',
        (tester) async {
      final c = await kur(tester);
      await fiyatGelir(tester, _yeniFiyat, _alim);

      expect(find.text('Fiyat yarın kesinleşir'), findsNothing);
      expect(find.text('Yeni fiyatla adet 3.906,25 olur'), findsOneWidget);

      // HIG: Güncelle ve Yok say ≥ 44 pt.
      expect(tester.getSize(find.byType(TextButton)).height,
          greaterThanOrEqualTo(SandikTouch.min));
      expect(tester.getSize(find.byType(IconButton)).height,
          greaterThanOrEqualTo(SandikTouch.min));
      expect(find.bySemanticsLabel(RegExp('Güncellemek için dokun')),
          findsOneWidget);

      await tester.tap(find.text('Güncelle'));
      await tester.pumpAndSettle();

      expect(portfoy.guncelleme, 1);
      final lot = c.read(portfolioProvider).requireValue.assets.single;
      expect(lot.quantity, closeTo(3906.25, 1e-9));
      expect(lot.purchasePrice, _yeniFiyat);
      expect(lot.quantity * lot.purchasePrice, closeTo(_tutar, 1e-6));
      expect(c.read(bekleyenFonAlimlariProvider), isEmpty);
      expect(find.byKey(const ValueKey('fonAlimOnerisi')), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(BekleyenFonAlimlariNotifier.anahtar), isNull);
    });

    testWidgets('Yok say: işaret silinir, kayıt değişmez', (tester) async {
      final c = await kur(tester);
      await fiyatGelir(tester, _yeniFiyat, _alim);
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(c.read(bekleyenFonAlimlariProvider), isEmpty);
      expect(portfoy.guncelleme, 0);
      expect(c.read(portfolioProvider).requireValue.assets.single.quantity,
          4000);
      expect(find.byKey(const ValueKey('fonAlimOnerisi')), findsNothing);
    });

    testWidgets('lot elle düzenlenince işaret düşer', (tester) async {
      final c = await kur(tester);
      portfoy.duzenle(3906);
      await tester.pumpAndSettle();
      expect(c.read(bekleyenFonAlimlariProvider), isEmpty);
      expect(find.text('Fiyat yarın kesinleşir'), findsNothing);
    });

    for (final w in [320.0]) {
      testWidgets('${w.toInt()} pt, 3.1× yazı: öneri taşmaz', (tester) async {
        await kur(tester, genislik: w, olcek: 3.1);
        await fiyatGelir(tester, _yeniFiyat, _alim);
        expect(find.byKey(const ValueKey('fonAlimOnerisi')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
