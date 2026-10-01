import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/sozlesme.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/sozlesme_provider.dart';
import 'package:portfoy_takip/services/bes_hesabi.dart';
import 'package:portfoy_takip/widgets/sozlesme_karti.dart';

/// BES otomatik katkı (0096; kullanıcı isteği 2026-10-01): *"tarihe göre,
/// miktar değişmediği sürece ekleyelim ve yatırma günü de; BES'in otomatik
/// yatırıldı, tutarı güncellemek ister misin deriz."*
void main() {
  Sozlesme bes({
    bool otomatik = true,
    DateTime? son,
    DateTime? bekleyen,
    int? gun = 15,
    double? aylik = 2000,
    DateTime? kapandi,
  }) =>
      Sozlesme(
        id: 'b-1',
        userId: 'u',
        tur: SozlesmeTuru.bes,
        kurum: 'Anadolu Hayat',
        baslangic: DateTime(2020, 1, 1),
        aylikKatki: aylik,
        katkiGunu: gun,
        fonDagilimi: const [FonPayi(kod: 'AH5', oran: 100)],
        dkFonKodu: 'AEK',
        kapandi: kapandi,
        otomatikKatki: otomatik,
        otomatikKatkiSon: son,
        otomatikKatkiBekleyen: bekleyen,
      );

  group('otomatikKatkiGunleri', () {
    test('imleçten sonraki her ay KENDİ günüyle; bugüne yığılmaz', () {
      final g = BesHesabi.otomatikKatkiGunleri(
        s: bes(son: DateTime(2026, 7, 20)),
        simdi: DateTime(2026, 10, 16),
        katkiTarihleri: const [],
      );
      expect(g, [
        DateTime(2026, 8, 15),
        DateTime(2026, 9, 15),
        DateTime(2026, 10, 15),
      ]);
    });

    test('katkı günü bugünse yazılır, gelmediyse yazılmaz', () {
      final s = bes(son: DateTime(2026, 9, 30));
      expect(
          BesHesabi.otomatikKatkiGunleri(
              s: s, simdi: DateTime(2026, 10, 15, 8), katkiTarihleri: const []),
          [DateTime(2026, 10, 15)]);
      expect(
          BesHesabi.otomatikKatkiGunleri(
              s: s, simdi: DateTime(2026, 10, 14), katkiTarihleri: const []),
          isEmpty);
    });

    test('imleç günü ve öncesi yazılmaz (açılış birikimi onu içerir)', () {
      expect(
          BesHesabi.otomatikKatkiGunleri(
            s: bes(son: DateTime(2026, 10, 15)),
            simdi: DateTime(2026, 10, 20),
            katkiTarihleri: const [],
          ),
          isEmpty);
    });

    test('elle katkı eklenen ay atlanır: aynı ayın katkısı iki kez yok', () {
      final g = BesHesabi.otomatikKatkiGunleri(
        s: bes(son: DateTime(2026, 8, 1)),
        simdi: DateTime(2026, 10, 20),
        katkiTarihleri: [DateTime(2026, 9, 3, 14)],
      );
      expect(g, [DateTime(2026, 8, 15), DateTime(2026, 10, 15)]);
    });

    test('yıl dönümü: Aralık → Ocak', () {
      final g = BesHesabi.otomatikKatkiGunleri(
        s: bes(son: DateTime(2026, 11, 30), gun: 28),
        simdi: DateTime(2027, 1, 28),
        katkiTarihleri: const [],
      );
      expect(g, [DateTime(2026, 12, 28), DateTime(2027, 1, 28)]);
    });

    test('kapalı, kapatılmış, plansız ya da imleçsiz sözleşmede hiçbir şey',
        () {
      final simdi = DateTime(2026, 10, 20);
      final son = DateTime(2026, 8, 1);
      for (final s in [
        bes(otomatik: false, son: son),
        bes(son: son, kapandi: DateTime(2026, 9, 1)),
        bes(son: son, gun: null),
        bes(son: son, aylik: null),
        bes(),
      ]) {
        expect(
            BesHesabi.otomatikKatkiGunleri(
                s: s, simdi: simdi, katkiTarihleri: const []),
            isEmpty);
      }
    });

    test('bozuk imleç yıllarca geriye yazmaz: en çok enFazla ay', () {
      final g = BesHesabi.otomatikKatkiGunleri(
        s: bes(son: DateTime(2010, 1, 1)),
        simdi: DateTime(2026, 10, 20),
        katkiTarihleri: const [],
      );
      expect(g, hasLength(24));
    });
  });

  group('Sozlesme 0096 alanları', () {
    test('kapalıyken 0096 sütunları gönderilmez (eski şemaya yazılabilir)',
        () {
      final m = bes(otomatik: false).toSupabase();
      expect(m.containsKey('otomatik_katki'), isFalse);
      expect(m.containsKey('otomatik_katki_son'), isFalse);
      expect(m.containsKey('otomatik_katki_bekleyen'), isFalse);
    });

    test('açıkken gider ve geri okunur', () {
      final s = bes(
          son: DateTime(2026, 10, 1), bekleyen: DateTime(2026, 10, 15));
      final m = s.toSupabase();
      expect(m['otomatik_katki'], isTrue);
      expect(m['otomatik_katki_son'], '2026-10-01');
      expect(m['otomatik_katki_bekleyen'], '2026-10-15');
      final geri = Sozlesme.fromSupabase(m);
      expect(geri.otomatikKatki, isTrue);
      expect(geri.otomatikKatkiSon, DateTime(2026, 10, 1));
      expect(geri.otomatikKatkiBekleyen, DateTime(2026, 10, 15));
    });

    test('kapatma (true → false) yine gönderilir: imleç dolu', () {
      final s = bes(son: DateTime(2026, 10, 1))
          .kopya(otomatikKatki: false, bekleyenSil: true);
      final m = s.toSupabase();
      expect(m['otomatik_katki'], isFalse);
      expect(m['otomatik_katki_bekleyen'], isNull);
    });

    test('kopya diğer alanları korur; bekleyen yalnız bekleyenSil ile silinir',
        () {
      final s = bes(
          son: DateTime(2026, 10, 1), bekleyen: DateTime(2026, 10, 15));
      expect(s.kopya(aylikKatki: 2500).otomatikKatkiBekleyen,
          DateTime(2026, 10, 15));
      expect(s.kopya(aylikKatki: 2500).aylikKatki, 2500);
      expect(s.kopya(bekleyenSil: true).otomatikKatkiBekleyen, isNull);
      expect(s.kopya(bekleyenSil: true).aylikKatki, 2000);
    });
  });

  group('notifier okumaları', () {
    Asset lot(String id, DateTime t,
            {String sub = 'katki',
            AssetKind kind = AssetKind.buy,
            double qty = 100,
            double fiyat = 10}) =>
        Asset(
          id: id,
          userId: 'u',
          name: 'x',
          ticker: sub == 'dk' ? 'TEFAS:AEK' : 'TEFAS:AH5',
          type: AssetType.bes,
          subCategory: sub,
          quantity: qty,
          purchasePrice: fiyat,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: fiyat,
          addedDate: t,
          kind: kind,
          sozlesmeId: 'b-1',
        );

    ProviderContainer kap(List<Asset> lotlar, Sozlesme s) {
      final c = ProviderContainer(overrides: [
        portfolioProvider.overrideWith(() => _Portfoy(lotlar)),
        sozlesmeProvider.overrideWith(
            () => _Sozlesmeler(SozlesmeState(sozlesmeler: {s.id: s}))),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('fon değişikliğinin alış ayağı katkı sayılmaz', () async {
      final acilis = DateTime(2026, 1, 1);
      final degisim = DateTime(2026, 9, 20, 10, 30);
      final c = kap([
        lot('acilis', acilis),
        lot('degisim-satis', degisim, kind: AssetKind.sell),
        lot('degisim-alis', degisim),
        lot('katki', DateTime(2026, 8, 15, 12)),
      ], bes(son: acilis));
      await c.read(portfolioProvider.future);
      await c.read(sozlesmeProvider.future);
      expect(c.read(sozlesmeProvider.notifier).katkiTarihleri('b-1'),
          [DateTime(2026, 8, 15, 12)],
          reason: 'Eylül fon değişikliği ayı "katkı eklendi" göstermemeli');
    });

    test('bekleyen günün katkı ve devlet katkısı lotları, tutarla', () async {
      final gun = DateTime(2026, 10, 15);
      final c = kap([
        lot('acilis', DateTime(2026, 1, 1)),
        lot('k', DateTime(2026, 10, 15), qty: 200, fiyat: 10),
        lot('d', DateTime(2026, 10, 15), sub: 'dk', qty: 40, fiyat: 10),
        lot('eski', DateTime(2026, 9, 15, 12)),
      ], bes(son: gun, bekleyen: gun));
      await c.read(portfolioProvider.future);
      await c.read(sozlesmeProvider.future);
      final l = c.read(sozlesmeProvider.notifier).otomatikKatkiLotlari('b-1')!;
      expect(l.katki.map((a) => a.id), ['k']);
      expect(l.dk?.id, 'd');
      expect(l.tutar, 2000);
    });

    test('bekleyen yoksa ya da o günün lotu silindiyse soru yok', () async {
      final c = kap([lot('acilis', DateTime(2026, 1, 1))],
          bes(son: DateTime(2026, 10, 15), bekleyen: DateTime(2026, 10, 15)));
      await c.read(portfolioProvider.future);
      await c.read(sozlesmeProvider.future);
      expect(c.read(sozlesmeProvider.notifier).otomatikKatkiLotlari('b-1'),
          isNull);
    });
  });

  group('kart', () {
    Future<void> ac(WidgetTester tester, Sozlesme s, List<Asset> lotlar,
        {double olcek = 1}) async {
      await initializeDateFormatting('tr_TR');
      tester.view.physicalSize = const Size(320 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          portfolioProvider.overrideWith(() => _Portfoy(lotlar)),
          sozlesmeProvider.overrideWith(
              () => _Sozlesmeler(SozlesmeState(sozlesmeler: {s.id: s}))),
        ],
        child: MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(olcek)),
            child: Scaffold(
              body: SingleChildScrollView(
                  child: SozlesmeKarti(varlik: lotlar.last)),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    final bugun = DateTime.now();
    final gun = DateTime(bugun.year, bugun.month, 1);
    List<Asset> lotlar() => [
          Asset(
            id: 'acilis',
            userId: 'u',
            name: 'x',
            ticker: 'TEFAS:AH5',
            type: AssetType.bes,
            subCategory: 'katki',
            quantity: 1000,
            purchasePrice: 10,
            currency: 'TRY',
            notes: '',
            isManualPrice: false,
            currentPrice: 12,
            addedDate: DateTime(bugun.year - 1, 1, 1),
            sozlesmeId: 'b-1',
          ),
          Asset(
            id: 'oto',
            userId: 'u',
            name: 'x',
            ticker: 'TEFAS:AH5',
            type: AssetType.bes,
            subCategory: 'katki',
            quantity: 200,
            purchasePrice: 10,
            currency: 'TRY',
            notes: 'Otomatik katkı',
            isManualPrice: false,
            currentPrice: 12,
            addedDate: DateTime(gun.year, gun.month, gun.day),
            sozlesmeId: 'b-1',
          ),
        ];

    testWidgets('otomatik eklenen katkı sorulur; hatırlatma çıkmaz',
        (tester) async {
      await ac(tester, bes(gun: 1, son: gun, bekleyen: gun), lotlar());
      expect(find.textContaining('katkın otomatik eklendi'), findsOneWidget);
      expect(find.textContaining('Tutarı güncellemek ister misin'),
          findsOneWidget);
      expect(find.text('Tutar doğru'), findsOneWidget);
      expect(find.text('Tutarı güncelle'), findsOneWidget);
      expect(find.text('Bu ayın katkısı henüz eklenmedi.'), findsNothing);
      expect(find.text('Katkıyı otomatik ekle'), findsOneWidget);
    });

    testWidgets('bu ayın katkısı eklendiyse düğme "Ek katkı ekle" der',
        (tester) async {
      // Emülatör testi (2026-10-01): eklendikten sonra da "Bu ayın
      // katkısını ekle" yazıyordu, aynı ay ikinci kez ekleniyordu.
      await ac(tester, bes(otomatik: false, gun: 1), lotlar());
      expect(find.text('Ek katkı ekle'), findsOneWidget);
      expect(find.text('Bu ayın katkısını ekle'), findsNothing);
      expect(find.text('Bu ayın katkısı henüz eklenmedi.'), findsNothing);
    });

    testWidgets('plan eksikse otomatik anahtarı yok', (tester) async {
      await ac(tester, bes(otomatik: false, gun: null), lotlar());
      expect(find.text('Katkıyı otomatik ekle'), findsNothing);
    });

    testWidgets('soru ve anahtar 320pt x3.0 taşmaz', (tester) async {
      await ac(tester, bes(gun: 1, son: gun, bekleyen: gun), lotlar(),
          olcek: 3);
      expect(tester.takeException(), isNull);
    });
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
