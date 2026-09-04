import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/chart_axis.dart';
import 'package:portfoy_takip/utils/series_downsample.dart';
import 'package:portfoy_takip/widgets/watchlist_chart.dart';

/// **Takip listesinin GÜNLÜK ekseni, performans ekranının GÜNLÜK ekseniyle
/// AYNI olmalı.**
///
/// ## Ne oluyordu
/// Üç ayrı yerde ayrışıyorlardı:
///
/// 1. **Pencere.** `clipToPeriod` sembol serilerini bugünün 00:00'ına
///    kırpıyordu, ama `ortakPencereyeHizala` pencereyi hemen ardından yeniden
///    "son nokta − 24 saat"e açıyordu. Kırpma böylece GERİ ALINIYOR, her seri
///    pencerenin soluna kendi ilk değeriyle dolduruluyordu. Ölçüldü: saat
///    14:30'da eksen "dün 14:30 → bugün 14:30" ve ilk **%39,6'sı** gece
///    yarısından önceye düşen düz, sahte bir çizgiydi. Performans ekranı aynı
///    günü 00:00'dan çizer.
///
/// 2. **Eksenin sağ ucu.** Takip grafiği ekseni SON VERİ NOKTASINDA bitiriyordu;
///    performans ekranı günü tam gösterir (en az 00:00 → 24:00). Sabah
///    09:00'da takip grafiği 9 saatlik, performans ekranı 24 saatlik ölçek
///    çiziyordu — aynı hareket iki ekranda iki farklı eğimde görünüyordu.
///
/// 3. **Tick yerleşimi.** Takip grafiği ham `span / 4` kullanıyordu, yani
///    tick'ler eksenin başladığı rastgele ana kilitleniyordu: "14:30 · 20:30 ·
///    02:30 · 08:30". Performans ekranı 4 saatlik yuvarlak adım kullanır:
///    "04:00 · 08:00 · 12:00 · 16:00 · 20:00".
///
/// Bu testler kuralın TEK KAYNAKTAN (`chart_axis.dart`) geldiğini ve iki
/// ekranın da o kaynağı çağırdığını sabitler.
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  int ms(DateTime d) => d.millisecondsSinceEpoch;

  group('GÜNLÜK penceresi — takvim günü', () {
    /// Üretim vakası: 7/24 tikleyen döviz + seans saatli hisse + portföy.
    Map<String, Map<int, double>> gunOrtasi() {
      final son = DateTime(2026, 9, 4, 14, 30);
      return {
        // Dün öğleden sonra da veri taşıyor — Yahoo `1d` range'i böyle döner.
        'USDTRY=X': {
          for (var i = 0; i <= 576; i++)
            ms(son.subtract(Duration(minutes: 5 * i))): 40.0 + i * 0.001,
        },
        'ALE': {
          for (var i = 0; i <= 54; i++)
            ms(DateTime(2026, 9, 4, 10).add(Duration(minutes: 5 * i))):
                10.0 + i * 0.01,
        },
        '__portfoy__': {
          for (var i = 0; i <= 174; i++)
            ms(DateTime(2026, 9, 4).add(Duration(minutes: 5 * i))): 1000.0 + i,
        },
      };
    }

    test('pencere GECE YARISINDAN başlar — dünün saatleri girmez', () {
      final h = ortakPencereyeHizala(gunOrtasi(), 1);
      final bas = DateTime.fromMillisecondsSinceEpoch(
          h.values.expand((s) => s.keys).reduce((a, b) => a < b ? a : b));

      expect(bas, DateTime(2026, 9, 4),
          reason: 'pencere $bas den başlıyor — kayan 24 saate dönülmüş. '
              'Ölçülen zarar: eksenin %39,6\'sı dünün saatlerini gösteren '
              'düz, sahte bir çizgiydi');
    });

    test('hiçbir seri dünden nokta TAŞIMAZ', () {
      final h = ortakPencereyeHizala(gunOrtasi(), 1);
      final geceYarisi = ms(DateTime(2026, 9, 4));

      for (final e in h.entries) {
        for (final k in e.value.keys) {
          expect(k, greaterThanOrEqualTo(geceYarisi),
              reason: '${e.key} serisi gece yarısından önce nokta taşıyor: '
                  '${DateTime.fromMillisecondsSinceEpoch(k)}');
        }
      }
    });

    test('doldurma yüzde TABANINI kaydırmaz', () {
      // Pencere gece yarısına çekilince tabanın da günün açılışı olması
      // gerekir; dünün fiyatına göre normalize edilirse "bugün ne oldu"
      // sorusuna dünden bugüne cevabı verilirdi.
      final h = ortakPencereyeHizala(gunOrtasi(), 1);
      final usd = h['USDTRY=X']!;
      final ilk = (usd.keys.toList()..sort()).first;

      // Fixture'da 00:00 slotu i = 174 (14:30'dan 870 dk geri).
      expect(usd[ilk], closeTo(40.0 + 174 * 0.001, 1e-9),
          reason: 'taban ${usd[ilk]} — günün açılışı değil');
    });

    test('UZUN dönemler kayan pencere olarak KALIR', () {
      // Yalnızca GÜNLÜK takvim günüdür. "1H" gece yarısına çekilirse hafta
      // altı buçuk güne iner.
      final son = DateTime(2026, 9, 4, 14, 30);
      final h = ortakPencereyeHizala({
        'A': {
          for (var i = 0; i <= 14; i++)
            ms(son.subtract(Duration(hours: 12 * i))): 100.0 + i,
        },
      }, 7);
      final bas = DateTime.fromMillisecondsSinceEpoch(
          (h['A']!.keys.toList()..sort()).first);

      expect(bas, DateTime(2026, 8, 28, 14, 30),
          reason: 'haftalık pencere de gece yarısına çekilmiş — '
              'dönem 6,4 güne iniyor');
    });
  });

  group('X ekseni — performans ekranıyla AYNI kural', () {
    const dk = 60 * 1000;

    test('GÜNLÜK ekseni TAM GÜNÜ kaplar — veride nerede bitildiğine bakmaz',
        () {
      // Sabah 09:15: seri 9,25 saatlik. Eksen yine de 24 saat olmalı, yoksa
      // aynı hareket sabah dik, akşam yayvan görünür ve performans ekranıyla
      // ölçek tutmaz.
      final geceYarisi = DateTime(2026, 9, 4);
      final e = zamanEkseni(
        ilkMs: ms(geceYarisi).toDouble(),
        sonMs: ms(DateTime(2026, 9, 4, 9, 15)).toDouble(),
        periodDays: 1,
      );

      expect(e.min, ms(geceYarisi).toDouble());
      expect(e.max - e.min, 1440.0 * dk,
          reason: 'eksen ${(e.max - e.min) / (60 * dk)} saat — '
              'GÜNLÜK bir takvim günüdür');
      expect(e.gunIci, isTrue);
    });

    test('eksen son veri noktasında BİTMEZ', () {
      final e = zamanEkseni(
        ilkMs: ms(DateTime(2026, 9, 4)).toDouble(),
        sonMs: ms(DateTime(2026, 9, 4, 9, 15)).toDouble(),
        periodDays: 1,
      );
      expect(e.max, greaterThan(ms(DateTime(2026, 9, 4, 9, 15)).toDouble()),
          reason: 'eksen veri aralığına oturtulmuş — son nokta sağ kenara '
              'yapışır ve gün ilerledikçe ölçek değişir');
    });

    test('akşam geç saatte eksen performans ekranıyla AYNI ORANDA büyür', () {
      // Kural: son nokta viewport'un ~%82'sinde. 21:00 → 1260 / 0,82 = 1537 dk.
      final e = zamanEkseni(
        ilkMs: ms(DateTime(2026, 9, 4)).toDouble(),
        sonMs: ms(DateTime(2026, 9, 4, 21)).toDouble(),
        periodDays: 1,
      );
      expect((e.max - e.min) / dk, closeTo(1260 / 0.82, 0.5));
      expect(gunIciEksenSonuDk(1260), closeTo(1260 / 0.82, 1e-9));
    });

    test('tick ler YUVARLAK saatlere oturur', () {
      // fl_chart tick'leri `baselineX`'in katlarına koyar. Taban verilmezse
      // 1970-01-01 UTC alınır ve UTC+3'te etiketler 03:00 · 07:00 · 11:00
      // diye kayar.
      final geceYarisi = DateTime(2026, 9, 4);
      final e = zamanEkseni(
        ilkMs: ms(geceYarisi).toDouble(),
        sonMs: ms(DateTime(2026, 9, 4, 14, 30)).toDouble(),
        periodDays: 1,
      );

      expect(e.baseline, e.min, reason: 'taban gün başında olmalı');
      expect(e.interval, gunIciEksenAdimiDk * dk,
          reason: 'adım performans ekranındaki 4 saat olmalı');

      final saatler = <int>[];
      for (var t = e.min; t < e.max; t += e.interval) {
        final d = DateTime.fromMillisecondsSinceEpoch(t.round());
        expect(d.minute, 0, reason: '$d yuvarlak saatte değil');
        saatler.add(d.hour);
      }
      expect(saatler, [0, 4, 8, 12, 16, 20]);
    });

    test('UZUN dönemde adım yuvarlak ve GÜN SINIRINA oturur', () {
      // Performans ekranı `yuvarlakAdim(span / 5)` kullanır: 30 gün → 10 gün.
      // Ham `span / 4` (eski takip kuralı) 7,5 günlük, gün ortasına düşen
      // tick'ler üretiyordu.
      final son = DateTime(2026, 9, 4, 14, 30);
      final e = zamanEkseni(
        ilkMs: ms(son.subtract(const Duration(days: 30))).toDouble(),
        sonMs: ms(son).toDouble(),
        periodDays: 30,
      );

      expect(e.interval, 10 * 24 * 60 * dk.toDouble());
      expect(e.gunIci, isFalse);
      final taban = DateTime.fromMillisecondsSinceEpoch(e.baseline.round());
      expect(taban, DateTime(2026, 8, 5),
          reason: 'taban $taban — gün sınırında değil, "5 Ağu" etiketi '
              'günün ortasına denk gelir');
    });

    test('yuvarlakAdim performans ekranının ürettiği değerleri KORUR', () {
      // `_niceRoundNumber` kaldırılıp buraya taşındı; taşıma sırasında
      // davranış değişmemeli — Y ekseni de bu fonksiyonu kullanıyor.
      expect(yuvarlakAdim(1.4), 2);
      expect(yuvarlakAdim(6), 10);
      expect(yuvarlakAdim(2.1), 2.5);
      expect(yuvarlakAdim(36), 50);
      expect(yuvarlakAdim(73), 100);
      expect(yuvarlakAdim(0), 1);
      expect(yuvarlakAdim(-3), 1);
    });

    test('gece yarısını AŞAN tick "23:00" değil "00:00" yazar', () {
      // Performans ekranı etiketi dakikadan elle kuruyor ve saati
      // `clamp(0, 23)` ile sıkıştırıyordu: eksen günü aştığında (19:41'den
      // sonra) gece yarısı tick'i var olmayan bir saati işaretliyordu.
      final t = DateTime(2026, 9, 4).add(const Duration(minutes: 1440));
      expect(zamanEtiketi(t, spanGun: 1, gunIci: true), '00:00');
    });

    test('etiket biçimi dönemle birlikte değişir', () {
      final t = DateTime(2026, 9, 4, 14, 30);
      expect(zamanEtiketi(t, spanGun: 1, gunIci: true), '14:30');
      expect(zamanEtiketi(t, spanGun: 30, gunIci: false), contains('Eyl'));
      expect(zamanEtiketi(t, spanGun: 30, gunIci: false), isNot(contains(':')),
          reason: 'uzun dönemde saat gösterilmez');
      expect(zamanEtiketi(DateTime(2024, 3, 1), spanGun: 500, gunIci: false),
          contains('24'),
          reason: '400 günü aşan pencerede yıl gösterilir');
    });

    test('kenar payı performans ekranıyla aynı (%6)', () {
      // Sabit eşik zoom'da ya çok geniş ya etkisiz kalıyordu; oran olmalı.
      expect(eksenKenarinda(0, 0, 100), isTrue);
      expect(eksenKenarinda(5, 0, 100), isTrue);
      expect(eksenKenarinda(7, 0, 100), isFalse);
      expect(eksenKenarinda(95, 0, 100), isTrue);
      expect(eksenKenarinda(50, 0, 100), isFalse);
    });
  });

  group('nokta yoğunluğu — çizgi kendi üstüne binmez', () {
    test('hedef GENİŞLİKTEN hesaplanır, sabit değil', () async {
      // Sabit 160 nokta, ~300px'lik telefon çizim alanında nokta başına
      // 1,9px demekti; 5 dakikalık gün içi seri (288 nokta) neredeyse hiç
      // seyrelmiyordu.
      final src =
          await File('lib/widgets/percent_comparison_chart.dart').readAsString();

      expect(src.contains('_hedefNokta = 160'), isFalse,
          reason: 'sabit nokta hedefi geri gelmiş');
      expect(src.contains('_pikselBasinaNokta'), isTrue,
          reason: 'hedef piksel mesafesinden türetilmeli');
      expect(src.contains('LayoutBuilder'), isTrue,
          reason: 'gerçek çizim genişliği olmadan piksel kuralı uygulanamaz');
    });

    test('gün içi seri okunur yoğunluğa iner', () {
      // 288 nokta (5 dk × 24 sa) → ~300px çizim alanı, 3px kuralı ile 100.
      final gun = [
        for (var i = 0; i < 288; i++)
          FlSpot(i.toDouble(), (i % 11).toDouble())
      ];
      final k = seyreltSpots(gun, 100);

      expect(k.length, lessThanOrEqualTo(110));
      expect(k.length, greaterThan(60),
          reason: 'fazla seyreltmek hareketi siler');
      // Ortalama nokta aralığı en az 2,5px olmalı.
      expect(300 / k.length, greaterThanOrEqualTo(2.5),
          reason: 'nokta başına ${(300 / k.length).toStringAsFixed(1)}px — '
              'çizgi kendi kalınlığının içinde kalır');
    });
  });

  group('ÇİZİLEN EKSEN — uçtan uca', () {
    // Cebir doğru olsa da widget onu kullanmıyorsa kullanıcıya ulaşmaz.
    // Bu test grafiği gerçekten kurar ve ALT EKSENDE YAZAN metinleri okur.

    Widget host(Widget child) => MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: Scaffold(
            body: Center(child: SizedBox(width: 360, child: child)),
          ),
        );

    testWidgets('GÜNLÜK alt ekseni 4 saatlik YUVARLAK etiketler yazar',
        (tester) async {
      // Seri 00:00 → 14:30 (5 dakikalık). Eksen günün sonuna kadar uzadığı
      // için verinin bittiği yerden SONRAKİ saatler de etiketlenmeli —
      // performans ekranının GÜNLÜK sekmesinde olduğu gibi.
      final gun = DateTime(2026, 9, 4);
      final ham = <int, double>{
        for (var i = 0; i <= 174; i++)
          ms(gun.add(Duration(minutes: 5 * i))): 100.0 + i * 0.01,
      };

      await tester.pumpWidget(host(WatchlistChart(
        series: {'ALE': normalizeSeries(ham)!},
        portfolioLabel: 'Portföyüm',
        periodDays: 1,
      )));
      await tester.pumpAndSettle();

      final saatler = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => RegExp(r'^\d{2}:\d{2}$').hasMatch(s))
          .toSet();

      expect(saatler, {'04:00', '08:00', '12:00', '16:00', '20:00'},
          reason: 'alt eksende $saatler yazıyor — yuvarlak saatlere '
              'oturmuyor ya da eksen veri bittiği yerde kesiliyor');

      // **Etiket metni tek başına yetmez.** Bu test UTC'de koşuyor; orada
      // yerel gece yarısı epoch'un 4 saatlik katlarına zaten denk geldiği
      // için `baselineX` verilmese de etiketler yuvarlak çıkar. UTC+3'te
      // (kullanıcının makinesi) aynı eksik "03:00 · 07:00 · 11:00" demek.
      // Bu yüzden tabanın grafiğe GERÇEKTEN geçtiği ayrıca doğrulanır.
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(data.baselineX, data.minX,
          reason: 'tick tabanı grafiğe geçmemiş — fl_chart 1970-01-01 UTC yi '
              'taban alır ve saat dilimi kayması olan yerlerde etiketler '
              'kayar');
      expect(data.maxX - data.minX,
          const Duration(days: 1).inMilliseconds.toDouble(),
          reason: 'çizilen eksen tam günü kaplamıyor');
    });

    testWidgets('UZUN dönemde eksen saat DEĞİL tarih yazar', (tester) async {
      final son = DateTime(2026, 9, 4, 14, 30);
      final ham = <int, double>{
        for (var i = 0; i <= 30; i++)
          ms(son.subtract(Duration(days: 30 - i))): 100.0 + i,
      };

      await tester.pumpWidget(host(WatchlistChart(
        series: {'ALE': normalizeSeries(ham)!},
        portfolioLabel: 'Portföyüm',
        periodDays: 30,
      )));
      await tester.pumpAndSettle();

      final etiketler = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => s.contains('Ağu') || s.contains('Eyl'))
          .toSet();

      expect(etiketler, isNotEmpty,
          reason: 'uzun dönemde tarih etiketi çizilmiyor');
      for (final e in etiketler) {
        expect(e, isNot(contains(':')),
            reason: '"$e" saat taşıyor — uzun dönemde saat gösterilmemeli');
      }
    });
  });

  group('TEK KAYNAK — iki ekran da chart_axis i çağırır', () {
    test('takip grafiği ham span/4 kullanmaz', () async {
      final src =
          await File('lib/widgets/percent_comparison_chart.dart').readAsString();

      // Yorumda "span / 4" geçtiği için (kaldırılan kural belgeleniyor)
      // aranan şey KULLANIM: bottomTitles'a giden interval.
      expect(src.contains('interval: span'), isFalse,
          reason: 'ham bölme geri gelmiş — tick ler eksenin başladığı '
              'rastgele ana kilitlenir');
      expect(src.contains('interval: ciz.eksenX.interval'), isTrue,
          reason: 'alt eksen adımı ortak kaynaktan gelmeli');
      expect(src.contains('zamanEkseni('), isTrue);
      expect(src.contains('baselineX:'), isTrue,
          reason: 'taban verilmezse tick ler UTC epoch a hizalanır');
      expect(src.contains('zamanEtiketi('), isTrue);
    });

    test('performans ekranı kendi kopyasını taşımaz', () async {
      final src = await File('lib/screens/portfolio_performance_screen.dart')
          .readAsString();

      expect(src.contains('_niceRoundNumber'), isFalse,
          reason: 'nice-number kopyası geri gelmiş');
      expect(src.contains('gunIciEksenSonuDk('), isTrue,
          reason: 'gün içi pencere kuralı ortak olmalı');
      expect(src.contains('gunIciEksenAdimiDk'), isTrue);
      expect(src.contains('zamanEtiketi('), isTrue);
      expect(src.contains('/ 0.82'), isFalse,
          reason: 'pencere formülünün ikinci kopyası kalmış');
    });

    test('takip grafiği dönemi ÇAĞIRANDAN alır', () async {
      // Dönem veriden çıkarılamaz: GÜNLÜK ekseni son noktanın ötesine uzar.
      final chart =
          await File('lib/widgets/watchlist_chart.dart').readAsString();
      final ekran = await File('lib/screens/watchlist_screen.dart')
          .readAsString();

      expect(chart.contains('periodDays: periodDays'), isTrue);
      expect(ekran.contains('periodDays:'), isTrue,
          reason: 'ekran seçili dönemi grafiğe geçirmiyor');
    });
  });
}
