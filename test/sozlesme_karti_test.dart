import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/bes_hesabi.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/sozlesme.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/sozlesme_provider.dart';
import 'package:portfoy_takip/utils/money_format.dart';
import 'package:portfoy_takip/widgets/mevduat_vade_seridi.dart';
import 'package:portfoy_takip/widgets/sozlesme_karti.dart';

/// Varlık sayfasındaki sözleşme kartı — mevduat ve BES.
void main() {
  final bugun = DateTime.now();
  final gun = DateTime(bugun.year, bugun.month, bugun.day);
  const mid = 'm-1';
  const bid = 'b-1';

  final mevduat = Sozlesme(
      id: mid,
      userId: 'u',
      tur: SozlesmeTuru.mevduat,
      kurum: 'Enpara',
      baslangic: gun.subtract(const Duration(days: 40)));
  final bes = Sozlesme(
    id: bid,
    userId: 'u',
    tur: SozlesmeTuru.bes,
    kurum: 'Anadolu Hayat Emeklilik',
    baslangic: DateTime(gun.year - 7, 1, 1),
    aylikKatki: 5000,
    katkiGunu: 1,
    fonDagilimi: const [FonPayi(kod: 'AH5', oran: 100)],
    dkFonKodu: 'AEK',
  );

  Asset lot(String sozlesme, AssetType tur, String ticker,
          {String? sub, double qty = 1000, double fiyat = 1, double guncel = 1}) =>
      Asset(
        id: '$ticker-$sub',
        userId: 'u',
        name: 'x',
        ticker: ticker,
        type: tur,
        subCategory: sub,
        quantity: qty,
        purchasePrice: fiyat,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: guncel,
        addedDate: gun.subtract(const Duration(days: 40)),
        sozlesmeId: sozlesme,
      );

  final lotlar = [
    lot(mid, AssetType.mevduat, mevduatSembolu(mid), qty: 250000, guncel: 1.03),
    lot(bid, AssetType.bes, 'TEFAS:AH5', sub: 'katki', qty: 10000, fiyat: 0.02, guncel: 0.03),
    lot(bid, AssetType.bes, 'TEFAS:AEK', sub: 'dk', qty: 2000, fiyat: 0.025, guncel: 0.03),
  ];

  // Vadesi dolmuş dönem (varsayılan) ve vade içindeki dönem.
  final dolmus = MevduatDonemi(
    id: 'd',
    sozlesmeId: mid,
    baslangic: gun.subtract(const Duration(days: 40)),
    vadeSonu: gun.subtract(const Duration(days: 8)),
    yillikFaiz: 42,
    stopaj: 17.5,
  );
  final vadeIci = MevduatDonemi(
    id: 'd',
    sozlesmeId: mid,
    baslangic: gun.subtract(const Duration(days: 8)),
    vadeSonu: gun.add(const Duration(days: 24)),
    yillikFaiz: 42,
    stopaj: 17.5,
  );

  Future<void> ac(WidgetTester tester, Asset varlik,
      {double olcek = 1, MevduatDonemi? donem, Widget? govde}) async {
    await initializeDateFormatting('tr_TR');
    tester.view.physicalSize = const Size(320 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(() => _Portfoy(lotlar)),
        sozlesmeProvider.overrideWith(() => _Sozlesmeler(SozlesmeState(
              sozlesmeler: {mid: mevduat, bid: bes},
              donemler: {
                mid: [donem ?? dolmus],
              },
            ))),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(olcek)),
          child: Scaffold(
            body: SingleChildScrollView(
                child: govde ?? SozlesmeKarti(varlik: varlik)),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('mevduat: vade doldu uyarısı ve Yenile / Çektim', (tester) async {
    await ac(tester, lotlar[0]);
    expect(find.text('Vadesi doldu'), findsOneWidget);
    expect(find.text('Yenile'), findsOneWidget);
    expect(find.text('Çektim'), findsOneWidget);
    expect(find.textContaining('Enpara'), findsOneWidget);
  });

  testWidgets(
      'mevduat vade içinde: kazanç vade sonunda, "Oranı güncelle" ve not '
      '(2026-10-02)', (tester) async {
    await ac(tester, lotlar[0], donem: vadeIci);
    expect(find.text('Vade sonunda net faiz'), findsOneWidget);
    expect(find.text('Bu dönem net'), findsNothing,
        reason: 'vade içinde ₺0 yazan "bu dönem net" gösterilmez');
    // 250.000 × %42 × 0,825 × 32 / 365
    expect(find.text('+₺7.594,52'), findsOneWidget);
    expect(find.text('Oranı güncelle'), findsOneWidget);
    expect(find.text('Yenile'), findsNothing);
    expect(find.textContaining('Faiz vade sonunda eklenir'), findsOneWidget);
  });

  testWidgets('portföy paneli: mevduat vade şeridi (grafik yerine)',
      (tester) async {
    await ac(tester, lotlar[0],
        donem: vadeIci,
        govde: MevduatVadeSeridi(
            temsilci: lotlar[0], pay: 250000, baz: const BazPara.lira()));
    expect(find.textContaining('%42 brüt faiz', findRichText: true), findsOneWidget);
    expect(find.text('Vadeye 24 gün'), findsOneWidget);
    expect(find.text('Vade sonunda net faiz'), findsOneWidget);
    expect(find.text('+₺7.594,52'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await ac(tester, lotlar[0],
        olcek: 3,
        donem: vadeIci,
        govde: MevduatVadeSeridi(
            temsilci: lotlar[0], pay: 250000, baz: const BazPara.lira()));
    expect(tester.takeException(), isNull, reason: '320pt x3.0 taşmaz');
  });

  testWidgets('BES: döküm, hak ediş ve bu ayın katkısı', (tester) async {
    await ac(tester, lotlar[1]);
    expect(find.text('Toplam birikim'), findsOneWidget);
    expect(find.text('Senin katkın'), findsOneWidget);
    expect(find.text('Devlet'), findsOneWidget);
    // Kalan süre ay hassasiyetinde (2026-10-01): eski "3 yıl sonra" tam yıl
    // farkıydı; giriş yıl−7'nin 1 Ocak'ı olduğundan %60 eşiğine çoğu gün
    // "2 yıl N ay" kalır. Beklenen metin aynı saf hesaptan kurulur.
    final kalan = BesHesabi.sonrakiBasamakSuresi(
        DateTime(gun.year - 7, 1, 1), DateTime.now())!;
    final sure = kalan.ay == 0
        ? '${kalan.yil} yıl'
        : kalan.yil == 0
            ? '${kalan.ay} ay'
            : '${kalan.yil} yıl ${kalan.ay} ay';
    expect(find.textContaining('$sure sonra %60'), findsOneWidget,
        reason: '7. yıl: %35, $sure sonra %60');
    expect(find.text('Bu ayın katkısı henüz eklenmedi.'), findsOneWidget);
    expect(find.text('Bu ayın katkısını ekle'), findsOneWidget);
  });

  for (final i in [0, 1]) {
    testWidgets('kart 320pt x3.0 taşmaz (${lotlar[i].type.label})',
        (tester) async {
      await ac(tester, lotlar[i], olcek: 3);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sözleşmesiz ya da sözleşmesi bilinmeyen lotta kart çizilmez',
      (tester) async {
    await ac(tester, lot('yok', AssetType.mevduat, mevduatSembolu('yok')));
    expect(find.byType(Card), findsNothing);
    expect(find.text('Yenile'), findsNothing);
  });
}

class _Portfoy extends PortfolioNotifier {
  _Portfoy(this.lotlar);
  final List<Asset> lotlar;
  @override
  Future<PortfolioState> build() async => PortfolioState(assets: lotlar);
}

class _Sozlesmeler extends SozlesmeNotifier {
  _Sozlesmeler(this.durum);
  final SozlesmeState durum;
  @override
  Future<SozlesmeState> build() async => durum;
}
