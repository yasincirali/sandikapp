import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/services/tazelik_ritmi.dart';

import 'helpers/kaynak.dart';

/// Kullanıcı isteği (2026-09-24): *"En kritik sorunumuz bu altın fiyatları.
/// Anasayfa günlük, varlık günlük performans, Performans günlük'te grafik ve
/// özet kısmı her varlık tipi için birbirleriyle aynı kaynaktan tutarlı
/// değerleri göstermeli. Ve senkron şekilde yenilenmeliler."*
///
/// Koddan çıkarılan üç ayrışma, üçü de burada kilitli:
///
/// 1. **Altının gün başı iki ayrı anın verisinden kuruluyordu.** Motor
///    `ilk = canlı ÷ (1 + yüzde)` hesabında canlıyı defterden (yalnızca
///    `refreshPrices` yazar), yüzdeyi `PriceService` belleğinden (her
///    `fetchQuotes`, piyasa bandı dahil, yazar) okuyordu.
/// 2. **Fiyat turunun sahibi yoktu.** Turu yalnızca Performans ekranı, o da
///    yalnızca GÜNLÜK seçiliyken atıyordu; tur tekilleştirilmiyordu.
/// 3. **Varlık ekranı açılış anında donuyordu.** Canlı değeri açılışta
///    kurulan kopyadan (`widget.asset`) okuyor ve nabzı dinlemiyordu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String kod(String yol) => ekranKaynagiSync(yol)
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  group('1 · altın gün başı AYNI kotasyondan', () {
    tearDown(() => PriceService.instance.sonBilinenFiyatlariTemizle());

    test('gün başı kotasyon yazılırken fiyat ve yüzdeden birlikte hesaplanır',
        () {
      PriceService.instance
          .testIcinKotasyonYaz('ALTIN_GRAM', 4040, gunlukPct: 1.0);
      expect(PriceService.instance.gunlukReferansFiyat('altin_gram'),
          closeTo(4000, 1e-9));
    });

    test('defter bir tur geride kalsa da gün başı KAYMAZ', () {
      // Bant yeni kotasyonu çekti (4040, +%1) ama defter hâlâ eski turun
      // fiyatında (4020). Eski formül: 4020 ÷ 1,01 = 3980,2 — gün başı
      // günün hareketinin yarısı kadar yanlış ve seriyi hangi anda çeken
      // yüzeye göre farklı.
      PriceService.instance
          .testIcinKotasyonYaz('ALTIN_GRAM', 4040, gunlukPct: 1.0);
      final eskiYol =
          altinUrunUclari(canliBirimTRY: 4020, gunlukPct: 1.0)!;
      expect(eskiYol.ilk, isNot(closeTo(4000, 1)));

      final uc = altinUrunUclari(
        canliBirimTRY: 4020,
        gunlukPct: PriceService.instance.gunlukDegisimPct('ALTIN_GRAM'),
        referansTRY: PriceService.instance.gunlukReferansFiyat('ALTIN_GRAM'),
      )!;
      expect(uc.ilk, closeTo(4000, 1e-9),
          reason: 'gün başı yüzdeyle aynı kotasyondan gelmeli');
      expect(uc.son, 4020, reason: 'uç yine defterin canlı fiyatı');
    });

    test('yüzde yoksa referans da yok — eski çarpan yoluna düşülür', () {
      PriceService.instance.testIcinKotasyonYaz('ALTIN_GRAM', 4040);
      expect(PriceService.instance.gunlukReferansFiyat('ALTIN_GRAM'), isNull);
      expect(
          altinUrunUclari(
              canliBirimTRY: 4040, gunlukPct: null, referansTRY: 4000),
          isNull,
          reason: 'ya hep ya hiç kuralı yüzde varlığına bakar');
    });

    test('motor iki altın dalında da referansı geçirir', () {
      final src = kod('lib/services/history_service.dart');
      expect(
          'referansTRY: PriceService.instance.gunlukReferansFiyat(a.ticker)'
              .allMatches(src)
              .length,
          2,
          reason: 'tohum ve slot dalı aynı gün başını kullanmalı');
    });
  });

  group('2 · tek fiyat turu, dinleyicilerden ÖNCE', () {
    test('tur bitmeden hiçbir yüzey tazelenmez', () async {
      final sira = <String>[];
      final tur = Completer<void>();
      final coz = TazelikRitmi.nabiz.fiyatTuruBagla(() {
        sira.add('tur');
        return tur.future;
      });
      final b1 = TazelikRitmi.nabiz.dinle(() => sira.add('bugun'));
      final b2 = TazelikRitmi.nabiz.dinle(() => sira.add('varlik'));

      final at = TazelikRitmi.nabiz.atForTest();
      await Future<void>.delayed(Duration.zero);
      expect(sira, ['tur'],
          reason: 'yüzeyler eski fiyatla seri çekmemeli');
      tur.complete();
      await at;
      expect(sira, ['tur', 'bugun', 'varlik']);

      b1();
      b2();
      coz();
    });

    test('asılı tur yüzeyleri en fazla bir aralık bekletir', () {
      fakeAsync((fa) {
        var tazelendi = false;
        final coz = TazelikRitmi.nabiz
            .fiyatTuruBagla(() => Completer<void>().future); // hiç bitmez
        final b = TazelikRitmi.nabiz.dinle(() => tazelendi = true);
        unawaited(TazelikRitmi.nabiz.atForTest());
        fa.elapse(TazelikRitmi.yuzey - const Duration(seconds: 1));
        expect(tazelendi, isFalse);
        fa.elapse(const Duration(seconds: 2));
        expect(tazelendi, isTrue,
            reason: 'ağ asılı kalsa da yüzey eldeki fiyatla tazelenmeli');
        b();
        coz();
      });
    });

    test('hata veren tur sırayı kesmez', () async {
      var tazelendi = false;
      final coz = TazelikRitmi.nabiz
          .fiyatTuruBagla(() async => throw StateError('ağ yok'));
      final b = TazelikRitmi.nabiz.dinle(() => tazelendi = true);
      await TazelikRitmi.nabiz.atForTest();
      expect(tazelendi, isTrue);
      b();
      coz();
    });

    test('eski bağın çözücüsü yeni bağı düşürmez', () async {
      var hangisi = '';
      final cozEski =
          TazelikRitmi.nabiz.fiyatTuruBagla(() async => hangisi = 'eski');
      final cozYeni =
          TazelikRitmi.nabiz.fiyatTuruBagla(() async => hangisi = 'yeni');
      cozEski(); // ekran yeniden kurulurken eskisinin dispose'u geç gelir
      final b = TazelikRitmi.nabiz.dinle(() {});
      await TazelikRitmi.nabiz.atForTest();
      expect(hangisi, 'yeni');
      b();
      cozYeni();
    });

    test('turu uygulama kabuğu bağlar, Performans kendisi ATMAZ', () {
      final kabuk = kod('lib/screens/main_navigation_screen.dart');
      expect(kabuk.contains('TazelikRitmi.nabiz.fiyatTuruBagla('), isTrue);
      expect(kabuk.contains('refreshPrices(nabiz: true)'), isTrue);
      expect(kabuk.contains('_fiyatTuruBagi?.call();'), isTrue,
          reason: 'bağ dispose\'ta çözülmeli');

      final seriler = kod('lib/screens/portfolio_performance/seriler.dart');
      expect(seriler.contains('refreshPrices('), isFalse,
          reason: 'tur Performans\'ın dönem seçimine bağlı kalmamalı');
    });

    test('fiyat turu tekilleştirilir, nabız turu sunucuyu seyreltir', () {
      final p = kod('lib/providers/portfolio_provider.dart');
      expect(p.contains('final suren = _surenTur;'), isTrue);
      expect(p.contains('if (!zorla || _surenTurZorla) return suren;'), isTrue);
      expect(p.contains('TazelikRitmi.gunIciSeriOmru'), isTrue,
          reason: 'nabız turunda sunucu yazımı push döngüsüne iner');
    });
  });

  group('3 · varlık ekranı canlı', () {
    final src = kod('lib/screens/asset_detail_screen.dart');

    test('değer ve yüzde açılış kopyasından okunmaz', () {
      expect(src.contains('final asset = widget.asset;'), isFalse,
          reason: 'kopya açılış anının fiyatında donar');
      expect(src.contains('final asset = _canli.asset;'), isTrue);
      expect(src.contains('FiyatKaynagi.birimVarlik(_canli.asset)'), isTrue,
          reason: 'seri de canlı fiyatla çekilmeli');
    });

    test('ortak nabzı dinler ve dispose\'ta bırakır', () {
      expect(src.contains('TazelikRitmi.nabiz.dinle(_nabizGeldi)'), isTrue);
      expect(src.contains('_nabziBirak?.call();'), isTrue);
    });

    test('sessiz tazeleme: future ancak sonuç eldeyken değişir', () {
      expect(src.contains('_historyFuture = SynchronousFuture(seri)'), isTrue,
          reason: 'her nabızda yükleme çubuğu yanıp sönmemeli');
    });
  });

  group('4 · döviz gün başı yurt içi referanstan (karar 2026-09-24)', () {
    // Ölçüldü (tarayıcı, sahte yurt içi fiyat): bant "Dolar −%0,40",
    // Performans › Döviz −%0,05. Gün başı Yahoo'nun ilk gün içi noktası,
    // uç yurt içi kotasyondu. Kullanıcı kararı: altınla aynı kural.
    tearDown(() {
      HistoryService.gunIciSaat = DateTime.now;
      HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
      HistoryService.clearCache();
      PriceService.instance.sonBilinenFiyatlariTemizle();
    });

    Asset dolar(double canli) => Asset(
          id: 'usd',
          userId: 'u1',
          name: 'ABD Doları',
          ticker: 'USDTRY=X',
          type: AssetType.doviz,
          quantity: 1000,
          purchasePrice: 40,
          currency: 'TRY',
          notes: '',
          currentPrice: canli,
          addedDate: DateTime(2000),
        );

    /// [gun] 00:00 → [bitis] arası 5 dk'lık Yahoo serisi: 41,00 → 41,30.
    List<(int, double)> yahoo(DateTime gun, DateTime bitis) {
      final n = bitis.difference(gun).inMinutes ~/ 5;
      return [
        for (var i = 0; i <= n; i++)
          (
            gun.add(Duration(minutes: 5 * i)).millisecondsSinceEpoch,
            41.0 + 0.3 * i / n,
          ),
      ];
    }

    test('bugünün seansı: gün başı referans, uç canlı, yüzde bantla aynı',
        () async {
      final simdi = DateTime(2026, 9, 24, 16, 40);
      final gun = DateTime(2026, 9, 24);
      HistoryService.clearCache();
      HistoryService.gunIciSaat = () => simdi;
      final seri = yahoo(gun, simdi);
      HistoryService.seriCekici = (sym, range, interval) async =>
          sym == 'USDTRY=X' ? seri : const [];
      const canli = 41.25;
      PriceService.instance
          .testIcinKotasyonYaz('USDTRY=X', canli, gunlukPct: -0.40);

      final b = await HistoryService.instance
          .getPortfolioHistoryHourlyBreakdown([dolar(canli)], 24);
      final u = PeriodSummaryService.uclar(b.total,
          fromMs: gun.millisecondsSinceEpoch,
          toMs: simdi.millisecondsSinceEpoch)!;
      expect(u.first, closeTo(1000 * canli / 0.996, 0.01),
          reason: 'gün başı Yahoo\'nun ilk noktası (41.000) değil');
      expect(u.last, closeTo(1000 * canli, 0.01));
      expect((u.last / u.first - 1) * 100, closeTo(-0.40, 1e-9));
    });

    test('hafta sonu: seri Cuma\'da bitti, bugün düz ve canlı çizilir',
        () async {
      // Döviz tek başınayken motor BUGÜNÜ çizer (7/24 sayılır); Yahoo'nun
      // son noktası Cuma. Eski yolda gün başı Cuma 00:00'ın kuru (41.000)
      // oluyordu ve iki günlük hareket "bugün" yazılıyordu. Zamana yayılan
      // çarpan serinin son noktasından sonra uca sabitlenir: bugün hareket
      // uydurulmaz.
      final cuma = DateTime(2026, 9, 18);
      final simdi = DateTime(2026, 9, 20, 12);
      HistoryService.clearCache();
      HistoryService.gunIciSaat = () => simdi;
      final seri = yahoo(cuma, DateTime(2026, 9, 18, 23, 55));
      HistoryService.seriCekici = (sym, range, interval) async =>
          sym == 'USDTRY=X' ? seri : const [];
      const canli = 41.25;
      PriceService.instance
          .testIcinKotasyonYaz('USDTRY=X', canli, gunlukPct: -0.40);

      final b = await HistoryService.instance
          .getPortfolioHistoryHourlyBreakdown([dolar(canli)], 24);
      expect(b.seansGunu, DateTime(2026, 9, 20));
      expect(b.total.values.toSet(), {closeTo(1000 * canli, 1e-6)},
          reason: 'kapalı piyasada gün içi hareket yok');
    });

    test('kaynak: tohum ve slot dalı aynı yoldan', () {
      final src = kod('lib/services/history_service.dart');
      expect('dovizUrunBirimi(a, '.allMatches(src).length, 2);
    });
  });

  // Kullanıcı bildirimi (2026-09-24): "kill edildikten sonraki ilk açılışta
  // ana sayfa günlük ile Performans grafik/özet farklı". Nabız yolu turdan
  // sonra çekiyordu, açılış yolu değil — gerekçe `TazelikRitmi.turuBekle`.
  group('5 · soğuk açılış: seri, süren fiyat turu bitmeden kurulmaz', () {
    test('tur yoksa bekleme anında biter', () {
      fakeAsync((fa) {
        var bitti = false;
        unawaited(TazelikRitmi.turuBekle(null).then((_) => bitti = true));
        fa.flushMicrotasks();
        expect(bitti, isTrue);
      });
    });

    test('süren tur bitene kadar seri kurulmaz, bitince kurulur', () {
      fakeAsync((fa) {
        final tur = Completer<void>();
        var seriKuruldu = false;
        unawaited(TazelikRitmi.turuBekle(tur.future)
            .then((_) => seriKuruldu = true));
        fa.elapse(const Duration(seconds: 5));
        expect(seriKuruldu, isFalse,
            reason: 'gün başı referansı tur dolmadan yok — seri beklemeli');
        tur.complete();
        fa.flushMicrotasks();
        expect(seriKuruldu, isTrue);
      });
    });

    test('asılı ve hatalı tur seriyi en fazla bir aralık bekletir', () {
      fakeAsync((fa) {
        var asili = false;
        unawaited(TazelikRitmi.turuBekle(Completer<void>().future)
            .then((_) => asili = true));
        fa.elapse(TazelikRitmi.yuzey - const Duration(seconds: 1));
        expect(asili, isFalse);
        fa.elapse(const Duration(seconds: 2));
        expect(asili, isTrue, reason: 'nabızla aynı üst sınır');

        var hatali = false;
        unawaited(TazelikRitmi.turuBekle(Future<void>.error(StateError('ağ')))
            .then((_) => hatali = true));
        fa.flushMicrotasks();
        expect(hatali, isTrue, reason: 'turun hatası sahibinde raporlanır');
      });
    });

    testWidgets('tur + kare: defter widget\'a inene kadar beklenir',
        (tester) async {
      // Kare gelmeden bitmemeli — `widget.state` o karede güncellenir.
      var bitti = false;
      final f = TazelikRitmi.turuVeKareyiBekle(null).then((_) => bitti = true);
      // Mikro görevler akar, kare AKMAZ (`idle` kare üretmez).
      await tester.idle();
      expect(bitti, isFalse, reason: 'kare gelmeden defter eski');
      await tester.pump();
      await f;
      expect(bitti, isTrue);
    });

    test('kaynak: üç gün içi yüzey de seriden ÖNCE turu bekler', () {
      final p = kod('lib/providers/portfolio_provider.dart');
      expect(p.contains('TazelikRitmi.turuBekle(_surenTur, enFazla: enFazla)'),
          isTrue,
          reason: 'bekleme süren turun kendisine bağlı olmalı');
      expect(
          p.contains(
              'TazelikRitmi.turuVeKareyiBekle(_surenTur, enFazla: enFazla)'),
          isTrue);

      // Bugün kartı `widget.state` okur → tur + KARE; bekleme kişisel/ortak
      // dallanmasından ÖNCE — iki dal da seriyi kurar, ikisi de beklemeli.
      final kart = kod('lib/widgets/bugun_karti.dart');
      final govde = kart.substring(
          kart.indexOf('_seriYukle({bool nabiz = false}) async {'));
      final bekle = govde.indexOf('.fiyatTurunuVeKareyiBekle(');
      final dal = govde.indexOf('if (!widget.kisisel) {');
      expect(bekle, greaterThan(0));
      expect(bekle, lessThan(dal), reason: 'ortak dalı da beklemeli');
      // Bütçe dolduğunda tur hâlâ ağdaysa eski defterle seri KURULMAZ:
      // satır boş kalır, tur bitince yüklenir (emülatörde 27 sn'lik tur).
      final kapi = govde.indexOf('if (notifier.fiyatTuruSuruyor) { '
          '_turBitinceYukle(notifier); return null; }');
      expect(kapi, greaterThan(bekle));
      expect(kapi, lessThan(dal));

      // Performans: tur + KARE, ve liste son build'in kopyasından.
      final seriler = kod('lib/screens/portfolio_performance/seriler.dart');
      expect(
          seriler.contains(
              '.fiyatTurunuVeKareyiBekle(enFazla: TazelikRitmi.gunIciSeriOmru) '
              '.then((_) => HistoryService.instance'
              '.getPortfolioHistoryHourlyBreakdown( '
              '_intradayKey == key ? _intradayAssets : chartAssets, 24))'),
          isTrue,
          reason: 'memoize edilen future taze listeyi okumalı');
      expect(seriler.contains('_intradayAssets = chartAssets;'), isTrue);

      // Varlık ekranı provider\'ı doğrudan okur (`_canli`) → yalnızca tur,
      // ama `_canli` OKUNMADAN önce.
      final varlik = kod('lib/screens/asset_detail_screen.dart');
      final yukle = varlik.substring(
          varlik.indexOf('Future<Map<int, double>> _loadHistory(int days) async {'));
      final vBekle = yukle.indexOf(
          '.fiyatTurunuBekle(enFazla: TazelikRitmi.gunIciSeriOmru);');
      final vCanli = yukle.indexOf('_canli.asset');
      expect(vBekle, greaterThan(0));
      expect(vBekle, lessThan(vCanli), reason: 'defter turdan sonra okunmalı');
    });
  });
}
