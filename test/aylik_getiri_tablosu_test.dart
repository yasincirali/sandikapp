import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/aylik_getiri_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show premiumKilitliProvider;
import 'package:portfoy_takip/providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import 'package:portfoy_takip/services/aylik_getiri_tablosu.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/aylik_getiri_karti.dart';
import 'package:portfoy_takip/utils/tr_format.dart' show ayBulunmaParcasi;
import 'package:portfoy_takip/utils/tr_iyelik.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart' show KilitSatiri;

/// Aylık getiri tablosu (2026-11-11, Premium). Kilitlenen: hücre Özet'in
/// getiri yöntemi (`piyasaEtkisi.pct`) ay sınırlarında, akıştan
/// arındırılmış; eksik ay `null` ("—"), uydurma yok; yıl toplamı bileşik
/// ve eksik ayda `null`; kartın görünürlüğü, Premium kilidi ve 2× metinde
/// tek sütun.
Asset _alim(String id, double adet, double fiyat, DateTime t) => Asset(
      id: id,
      userId: 'u',
      name: 'THYAO',
      ticker: 'THYAO',
      type: AssetType.hisse,
      quantity: adet,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: t,
      kind: AssetKind.buy,
    );

int _g(int y, int m, int d) => DateTime(y, m, d).millisecondsSinceEpoch;

/// Günlük seri: ayın son günü hariç her gün önceki ayın kapanışı, son
/// günü [kapanis]. Akışsız ayda hücre tam olarak kapanış oranıdır.
void _ayEkle(Map<int, double> seri, int y, int m, double bas, double kapanis,
    {int ilkGun = 1}) {
  final son = DateTime(y, m + 1, 0).day;
  for (var d = ilkGun; d < son; d++) {
    seri[_g(y, m, d)] = bas;
  }
  seri[_g(y, m, son)] = kapanis;
}

void main() {
  group('aylikGetiriTablosu (saf)', () {
    test('akışsız aylar: hücre = ayın getirisi; yıl toplamı bileşik', () {
      final seri = <int, double>{};
      _ayEkle(seri, 2025, 1, 10000, 11000); // +%10
      _ayEkle(seri, 2025, 2, 11000, 9900); // −%10
      final t = aylikGetiriTablosu(
        seri: seri,
        lotlar: [_alim('a', 100, 100, DateTime(2025, 1, 1))],
        simdi: DateTime(2025, 2, 28, 18),
      )!;
      expect(t.aylar[2025]![0], closeTo(10, 1e-9));
      expect(t.aylar[2025]![1], closeTo(-10, 1e-9));
      // 1,1 × 0,9 − 1 = −%1 (toplam değil, bileşik).
      expect(t.yilToplami[2025], closeTo(-1, 1e-9));
      expect(t.olculenAySayisi, 2);
      // İlk alımdan önceki ay ve gelecek aylar aralık dışı (boş).
      expect(t.aralikta(2024, 12), isFalse);
      expect(t.aralikta(2025, 3), isFalse);
    });

    test('para girişi olan ay arındırılmış: Özet yöntemiyle aynı sayı', () {
      final seri = <int, double>{};
      _ayEkle(seri, 2025, 1, 10000, 10000);
      _ayEkle(seri, 2025, 2, 10000, 9900);
      // Mart 15'te 9.900 TL'lik alım; 16'dan itibaren değer iki katı,
      // ay sonu iki parça birden %5 yükseliyor.
      for (var d = 1; d <= 15; d++) {
        seri[_g(2025, 3, d)] = 9900;
      }
      for (var d = 16; d < 31; d++) {
        seri[_g(2025, 3, d)] = 19800;
      }
      seri[_g(2025, 3, 31)] = 20790;
      final lotlar = [
        _alim('a', 100, 100, DateTime(2025, 1, 1)),
        _alim('b', 100, 99, DateTime(2025, 3, 15, 10)),
      ];
      final t = aylikGetiriTablosu(
          seri: seri, lotlar: lotlar, simdi: DateTime(2025, 3, 31, 20))!;
      final mart = t.aylar[2025]![2]!;
      // Ham değer değişimi %110; eklenen para getiri sayılmaz.
      expect(mart, lessThan(10));
      expect(mart, greaterThan(4));
      // Yöntem Özet'inki: önceki ayın son ölçümü → ayın son ölçümü,
      // `piyasaEtkisi.pct`.
      final beklenen = PeriodSummaryService.piyasaEtkisi(
        seri: {
          for (final e in seri.entries)
            if (e.key >= _g(2025, 2, 28)) e.key: e.value
        },
        lotlar: lotlar,
        start: DateTime(2025, 2, 28),
        end: DateTime(2025, 3, 31, 23, 59, 59),
      )!
          .pct!;
      expect(mart, closeTo(beklenen, 1e-9));
    });

    test('ölçümsüz ay null; yıl toplamı uydurulmaz; sonraki ay kendi '
        'ilk ölçümünden başlar', () {
      final seri = <int, double>{};
      _ayEkle(seri, 2025, 1, 10000, 11000);
      // Şubat'ta hiç ölçüm yok.
      _ayEkle(seri, 2025, 3, 12000, 13200); // kendi içinde +%10
      final t = aylikGetiriTablosu(
        seri: seri,
        lotlar: [_alim('a', 100, 100, DateTime(2025, 1, 1))],
        simdi: DateTime(2025, 3, 31, 20),
      )!;
      expect(t.aylar[2025]![1], isNull);
      expect(t.aralikta(2025, 2), isTrue); // aralıkta → ekranda "—"
      // Ocak'ın kapanışı (11.000) Mart'ın tabanı OLMAZ: Şubat ölçülmedi.
      expect(t.aylar[2025]![2], closeTo(10, 1e-9));
      expect(t.yilToplami[2025], isNull);
    });

    test('içinde bulunulan ay bugüne kadar ölçülür', () {
      final seri = <int, double>{};
      _ayEkle(seri, 2025, 1, 10000, 10000);
      for (var d = 1; d <= 10; d++) {
        seri[_g(2025, 2, d)] = d == 10 ? 10500 : 10000;
      }
      final t = aylikGetiriTablosu(
        seri: seri,
        lotlar: [_alim('a', 100, 100, DateTime(2025, 1, 1))],
        simdi: DateTime(2025, 2, 10, 12),
      )!;
      expect(t.buAy, DateTime(2025, 2));
      expect(t.aylar[2025]![1], closeTo(5, 1e-9));
    });

    test('alım yoksa tablo yok', () {
      expect(
          aylikGetiriTablosu(
              seri: const {}, lotlar: const [], simdi: DateTime(2025)),
          isNull);
    });

    test('uzun seri: günlük başladığı yerden sonrası günlük', () {
      final m = uzunSeriyiBirlestir(
        haftalik: {1: 1, 5: 5, 9: 9},
        gunluk: {6: 6, 7: 7, 8: 8},
      );
      expect(m, {1: 1, 5: 5, 6: 6, 7: 7, 8: 8});
    });
  });

  group('AylikGetiriKarti', () {
    // Ocak–Ekim ölçülü, Kasım "bu ay".
    AylikGetiriTablosu tablo({int ay = 11}) => AylikGetiriTablosu(
          aylar: {
            2025: [
              for (var m = 1; m <= 12; m++)
                m <= ay ? (m.isEven ? -1.5 : 2.25) : null
            ],
          },
          yilToplami: {2025: 4.2},
          ilkAy: DateTime(2025, 1),
          buAy: DateTime(2025, ay),
          olculenAySayisi: ay,
        );
    final istek = AylikGetiriIstegi(
      anahtar: 't',
      seriLotlari: [_alim('a', 1, 1, DateTime(2025, 1, 1))],
      hesapLotlari: [_alim('a', 1, 1, DateTime(2025, 1, 1))],
    );

    Future<void> pump(
      WidgetTester tester, {
      bool gorunur = true,
      bool kilitli = false,
      AylikGetiriTablosu? t,
      double olcek = 1,
      double genislik = 390,
      AylikGetiriIstegi? ist,
      Future<AylikGetiriTablosu?> Function()? saglayici,
    }) async {
      tester.view.physicalSize = Size(genislik * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          premiumOzellikleriGorunurProvider.overrideWithValue(gorunur),
          premiumKilitliProvider.overrideWithValue(kilitli),
          aylikGetiriProvider.overrideWith(
              (ref, _) => saglayici != null ? saglayici() : Future.value(t ?? tablo())),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [SandikPalette.light]),
          home: MediaQuery(
            data: MediaQueryData(
                size: Size(genislik, 2400),
                textScaler: TextScaler.linear(olcek)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: AylikGetiriKarti(
                    istek: ist ?? istek, simdi: DateTime(2025, 11, 11)),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('dar ekranda kart görünür: iki satır, ok + yüzde, yıl', (
        tester) async {
      await pump(tester);
      expect(find.text('Aylık getiri'), findsOneWidget);
      expect(find.text('Oca'), findsOneWidget);
      expect(find.text('Tem'), findsOneWidget);
      expect(find.text('bu ay'), findsOneWidget);
      expect(find.text('▲ %2,3'), findsWidgets);
      expect(find.text('▼ %1,5'), findsWidgets);
      expect(find.text('▲ %4,2'), findsOneWidget); // yıl toplamı
      // Oca ile Tem aynı sütunda (Tem ikinci satırın başı).
      expect(tester.getTopLeft(find.text('Tem')).dy,
          greaterThan(tester.getTopLeft(find.text('Oca')).dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('yazı ×2: tek sütun liste, taşma yok', (tester) async {
      await pump(tester, olcek: 2, genislik: 320);
      // Liste yerleşiminde ay adı tam yazılır, her ay bir satır.
      expect(find.text('Ocak'), findsOneWidget);
      expect(find.text('Şubat'), findsOneWidget);
      expect(
          tester.getTopLeft(find.text('Şubat')).dy,
          greaterThan(tester.getTopLeft(find.text('Ocak')).dy));
      expect(tester.getTopLeft(find.text('Şubat')).dx,
          tester.getTopLeft(find.text('Ocak')).dx);
      expect(tester.takeException(), isNull);
    });

    testWidgets('kilitli: Premium kilit satırı, kaynak aylik_getiri', (
        tester) async {
      await pump(tester, kilitli: true);
      final kilit = tester.widget<KilitSatiri>(find.byType(KilitSatiri));
      expect(kilit.kaynak, 'aylik_getiri');
      expect(kilit.ozellik, 'aylik_getiri');
      expect(find.text('Oca'), findsNothing);
    });

    testWidgets('aralık ≥ 6 ama seri delikli (ölçülen < 6): kart yok', (tester) async {
      await pump(tester, t: tablo(ay: 5));
      expect(find.text('Aylık getiri'), findsNothing);
    });

    AylikGetiriIstegi kisaIstek(DateTime ilk) => AylikGetiriIstegi(
          anahtar: 'kisa',
          seriLotlari: [_alim('a', 1, 1, ilk)],
          hesapLotlari: [_alim('a', 1, 1, ilk)],
        );

    testWidgets('kısa geçmiş: 6 bölmeli ilerleme + hazır olacağı ay; seri '
        'çekilmez', (tester) async {
      var cagrildi = false;
      await pump(tester,
          ist: kisaIstek(DateTime(2025, 9, 3)),
          saglayici: () async {
            cagrildi = true;
            return tablo();
          });
      expect(find.text('Aylık getiri'), findsOneWidget);
      // Eylül, Ekim, Kasım = 3 ay; 6. ay Şubat 2026.
      expect(
          find.text('Tablo 6 ay dolunca burada açılır. Şu an 3 ay ölçüldü, '
              "Şubat 2026'da hazır."),
          findsOneWidget);
      expect(find.bySemanticsLabel("6 aydan 3'ü ölçüldü"), findsOneWidget);
      expect(cagrildi, isFalse);
      expect(find.text('Oca'), findsNothing);
    });

    testWidgets("kısa geçmiş, aynı yıl: yılsız \"Aralık'ta\"", (tester) async {
      // Temmuz–Kasım 2025 = 5 ay; 6. ay Aralık 2025, bugünle aynı yıl.
      await pump(tester, ist: kisaIstek(DateTime(2025, 7, 1)));
      expect(
          find.text('Tablo 6 ay dolunca burada açılır. Şu an 5 ay ölçüldü, '
              "Aralık'ta hazır."),
          findsOneWidget);
    });

    testWidgets('kısa geçmiş: yazı ×3,1 ve 320 pt taşma yok', (tester) async {
      await pump(tester,
          ist: kisaIstek(DateTime(2025, 9, 3)), olcek: 3.1, genislik: 320);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ilk alım gelecekte (0 ay): kart yok', (tester) async {
      await pump(tester, ist: kisaIstek(DateTime(2026, 1, 3)));
      expect(find.text('Aylık getiri'), findsNothing);
    });

    testWidgets('seri hatası: kart kalır, tek satır; ham hata yok', (
        tester) async {
      await pump(tester,
          saglayici: () => Future.error(StateError('ag koptu xyz')));
      expect(find.text('Aylık getiri'), findsOneWidget);
      expect(find.text('Tablo hesaplanamadı, yenileyince tekrar denenir.'),
          findsOneWidget);
      expect(find.textContaining('xyz'), findsNothing);
    });

    testWidgets('Premium özellikleri görünmüyorsa kart yok', (tester) async {
      await pump(tester, gorunur: false);
      expect(find.text('Aylık getiri'), findsNothing);
    });
  });

  group('Türkçe ek yardımcıları (ilerleme / özet cümlesi)', () {
    test('sayının iyelik eki', () {
      expect(trSayiIyelikEki(3), 'ü');
      expect(trSayiIyelikEki(1), 'i');
      expect(trSayiIyelikEki(2), 'si');
      expect(trSayiIyelikEki(6), 'sı');
      expect(trSayiIyelikEki(9), 'u');
      expect(trSayiIyelikEki(20), 'si');
      expect(trSayiIyelikEki(30), 'u');
    });
    test('sayının iyelik + belirtme eki', () {
      expect(trSayiIyelikBelirtmeEki(14), 'ünü');
      expect(trSayiIyelikBelirtmeEki(20), 'sini');
      expect(trSayiIyelikBelirtmeEki(6), 'sını');
      expect(trSayiIyelikBelirtmeEki(9), 'unu');
      expect(trSayiIyelikBelirtmeEki(1), 'ini');
    });
    test('ayın bulunma hâli', () {
      final b = DateTime(2026, 1, 5);
      expect(ayBulunmaParcasi(DateTime(2026, 2), bugun: b), "Şubat'ta");
      expect(ayBulunmaParcasi(DateTime(2026, 4), bugun: b), "Nisan'da");
      expect(ayBulunmaParcasi(DateTime(2026, 9), bugun: b), "Eylül'de");
      expect(ayBulunmaParcasi(DateTime(2027, 3), bugun: b), "Mart 2027'de");
      expect(ayBulunmaParcasi(DateTime(2025, 12), bugun: b),
          "Aralık 2025'te");
      expect(ayBulunmaParcasi(DateTime(2027, 3), dil: 'en_US', bugun: b),
          'March 2027');
    });
  });
}
