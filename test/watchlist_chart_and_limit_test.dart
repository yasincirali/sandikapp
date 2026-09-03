import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/widgets/watchlist_chart.dart';

/// Takip listesi grafiği + free tier limiti.
///
/// ## Grafik: neden yüzde
/// `comparison_screen` ile AYNI motor (`normalizeSeries`) kullanılıyor.
/// Ham fiyatla çizmek anlamsız olurdu: ₺12'lik hisse ile ₺4.800'lük altın
/// aynı eksende görünmez. Yüzde ayrıca takip listesinin doğasına uygun —
/// sahip olmadığın varlığın "kazancı" tanımsızdır.
///
/// ## Limit: neden paywall kapalıyken uygulanmaz
/// `paywall_enabled` şu an `false`. Limiti koşulsuz uygulamak, satın
/// alınabilir bir premium yokken kullanıcıyı 5 varlıkta durdurup ÇIKIŞSIZ
/// bırakırdı. `assetLimitProvider` de aynı kalıbı izliyor.

/// Kıyas seçici testleri için basit bir lot. Yalnızca `ticker` ayırt edici;
/// `kiyasVarliklari` varlığın içeriğine değil SAHİBİNE göre seçim yapar.
Asset _lot(String ticker) => Asset(
      id: ticker,
      userId: 'u',
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: 1,
      purchasePrice: 10,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 12,
      addedDate: DateTime(2026, 1, 1),
    );

String _yorumsuz(String src) => src.split('\n').where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    }).join('\n');

void main() {
  group('normalizeSeries — grafiğin motoru', () {
    test('dönem başı %0 kabul edilir', () {
      final n = normalizeSeries({1: 100.0, 2: 110.0, 3: 120.0});
      expect(n, isNotNull);
      expect(n!.points[1], closeTo(0.0, 1e-9),
          reason: 'ilk nokta her zaman sıfır olmalı — kıyasın referansı');
      expect(n.points[2], closeTo(10.0, 1e-9));
      expect(n.points[3], closeTo(20.0, 1e-9));
      expect(n.totalReturnPct, closeTo(20.0, 1e-9));
    });

    test('farklı fiyat ÖLÇEKLERİ aynı eksende kıyaslanabilir', () {
      // Grafiğin varlık sebebi: ₺12 hisse ile ₺4.800 altın aynı yüzdeyi
      // yaparsa çizgileri ÜST ÜSTE gelmeli.
      final ucuz = normalizeSeries({1: 12.0, 2: 13.2})!;
      final pahali = normalizeSeries({1: 4800.0, 2: 5280.0})!;
      expect(ucuz.totalReturnPct, closeTo(pahali.totalReturnPct, 1e-9),
          reason: 'ikisi de %10 kazandı — grafikte aynı yükseklikte olmalı');
    });

    test('düşen seri negatif yüzde verir', () {
      final n = normalizeSeries({1: 200.0, 2: 150.0})!;
      expect(n.totalReturnPct, closeTo(-25.0, 1e-9));
    });

    test('tek nokta çizilemez — null döner', () {
      expect(normalizeSeries({1: 100.0}), isNull);
      expect(normalizeSeries(const {}), isNull);
    });

    test('ilk fiyat sıfırsa null — sonsuz yüzde üretmez', () {
      // Sıfıra bölme grafiği okunamaz hale getirirdi.
      expect(normalizeSeries({1: 0.0, 2: 100.0}), isNull);
      expect(normalizeSeries({1: -5.0, 2: 100.0}), isNull);
    });
  });

  group('grafik kaynak kuralları', () {
    late String provider;
    late String chart;

    setUpAll(() async {
      provider = _yorumsuz(
          await File('lib/providers/watchlist_provider.dart').readAsString());
      // Grafiğin gövdesi Karşılaştır ekranıyla PAYLAŞILAN widget'a taşındı;
      // kaynak denetimleri artık orayı okur (bkz. chart_interaction_parity).
      chart = _yorumsuz(await File('lib/widgets/percent_comparison_chart.dart')
          .readAsString());
    });

    test('karşılaştırma ekranıyla AYNI motoru kullanır', () {
      expect(provider.contains('normalizeSeries'), isTrue,
          reason: 'ikinci bir normalize implementasyonu yazmak, iki ekranın '
              'aynı veriyi farklı göstermesine yol açardı');
    });

    test('portföy serisi grafiğe KIYAS olarak eklenir', () {
      expect(provider.contains('getPortfolioHistory'), isTrue);
      expect(provider.contains('portfolioSeriesKey'), isTrue,
          reason: 'portföy sabit bir anahtarla gelir; grafik onu ayrı çizer');
    });

    test('ortaklar portföy serisine dahil', () {
      // Kullanıcı "benim ve ortaklarımla birlikte olan portföyüm" istedi.
      expect(provider.contains('allPartnerAssetsProvider'), isTrue);
      expect(provider.contains('activePartnersProvider'), isTrue,
          reason: 'yalnızca AKTİF ortaklar sayılmalı');
    });

    test('kıyas çizgisinin adı SEÇİME göre değişir', () async {
      // Bir ortak seçiliyken "Portföyüm" yazmak YANLIŞ bilgi olurdu.
      final ekran = _yorumsuz(
          await File('lib/screens/watchlist_screen.dart').readAsString());
      expect(ekran.contains('String _portfolioLabel('), isTrue);
      expect(ekran.contains("if (view == null) return 'Birlikte'"), isTrue);
      expect(ekran.contains("if (view == '') return 'Portföyüm'"), isTrue);
      // Grafik sabit metin YAZMAMALI — etiketi dışarıdan almalı.
      expect(chart.contains("'Portföyüm'"), isFalse,
          reason: 'etiket seçime bağlı; grafikte sabitlenirse ortak '
              'seçildiğinde yanlış ad görünür');
      // Ortak grafik etiketi bir geri çağrıyla dışarıdan alır; `WatchlistChart`
      // de ona `portfolioLabel`'ı geçirir.
      expect(chart.contains('labelOf'), isTrue,
          reason: 'etiket dışarıdan gelmeli');
      final sarmalayici = _yorumsuz(
          await File('lib/widgets/watchlist_chart.dart').readAsString());
      expect(sarmalayici.contains('portfolioLabel'), isTrue);
    });

    test('seçici ortak YOKKA çizilmez', () async {
      // Tek seçenekli seçici karar verecek bir şey sunmaz, yer kaplar.
      final ekran = _yorumsuz(
          await File('lib/screens/watchlist_screen.dart').readAsString());
      expect(ekran.contains('if (partners.isNotEmpty)'), isTrue);
    });

    test('portföy çizgisi görsel olarak AYIRT EDİLİR', () {
      // Renk tek başına yeterli değil; kalınlık da farklı olmalı.
      expect(chart.contains('vurgulu ? 3 : 1.8'), isTrue,
          reason: 'kıyas çizgisi kalınlıktan da okunmalı');
    });

    test('sıfır çizgisi (dönem başı) çizilir', () {
      expect(chart.contains('HorizontalLine'), isTrue,
          reason: 'yüzdelerin neye göre okunacağı görünür olmalı');
    });
  });

  group('portföy çizgisi kesintisiz — simülasyon modu', () {
    // ## Bug (üretimde görüldü): portföy çizgisi kesik çiziliyordu
    //
    // Gerçek geçmiş modunda `getPortfolioHistory`, bir lot'un `addedDate`'inden
    // önceki slotlara 0 yazar. Ölçüldü: 30 günlük dönem + 10 gün önce alınan
    // varlık → 31 noktanın 20'si sıfır, `normalizeSeries` NULL döndü.
    // Aradaki bir sıfır ise seriyi −%100'e çakıp geri çıkarıyordu.
    //
    // ## Çözüm: `simulate: true`
    // Alım tarihleri yok sayılır, bugünkü net pozisyon dönemin tamamına
    // yayılır (performans ekranındaki "simülasyon" sekmesiyle AYNI bayrak).
    // Ölçüldü: aynı senaryoda 31 nokta, 0 sıfır, seri geçerli.
    //
    // Asıl gerekçe KIYAS ADALETİ: izlenen varlıklar dönemin tamamı boyunca
    // çiziliyor. Portföyü yalnızca sahip olunan günlerde çizmek iki tarafı
    // farklı pencerelerde ölçmek olurdu.
    //
    // Bunun bir yorumu var ve kullanıcıya AÇIKÇA söyleniyor (grafik altı not).

    test('sağlayıcı SİMÜLASYON modunu kullanır', () async {
      final provider = _yorumsuz(
          await File('lib/providers/watchlist_provider.dart').readAsString());
      expect(provider.contains('simulate: true'), isTrue,
          reason: 'gerçek geçmiş modu alım öncesi slotlara 0 yazar ve '
              'kıyas çizgisini bozar');
    });

    test('senaryo olduğu kullanıcıya YAZIYLA söylenir', () async {
      // Kullanıcı bu çizgiyi "gerçekleşmiş getirim" sanmamalı.
      final ekran = _yorumsuz(
          await File('lib/screens/watchlist_screen.dart').readAsString());
      expect(ekran.contains('senaryosudur'), isTrue,
          reason: 'simülasyon olduğu belirtilmezse yanıltıcı olur');
      expect(ekran.contains('gerçekleşmiş getirin değildir'), isTrue);
    });

    test('baştaki sıfırlar ATILIR', () {
      final r = portfoyunVarOlduguSlotlar({
        1: 0.0,
        2: 0.0,
        3: 0.0,
        4: 1000.0,
        5: 1100.0,
      });
      expect(r.keys.toList(), [4, 5],
          reason: 'portföyün var olmadığı slotlar seriye girmemeli');
    });

    test('düzeltme sonrası seri ÇİZİLEBİLİR', () {
      // Bug'ın asıl belirtisi: normalize null dönüyordu.
      final ham = {1: 0.0, 2: 0.0, 3: 1000.0, 4: 1200.0};
      expect(normalizeSeries(ham), isNull,
          reason: 'ham seride ilk değer 0 → çizilemez (bug)');

      final n = normalizeSeries(portfoyunVarOlduguSlotlar(ham));
      expect(n, isNotNull, reason: 'temizlenmiş seri çizilebilmeli');
      expect(n!.totalReturnPct, closeTo(20.0, 1e-9),
          reason: 'kıyas portföyün gerçekten var olduğu ilk andan başlar');
    });

    test('ORTADAKİ sıfır KORUNUR — gerçek bir olay olabilir', () {
      // Tüm varlıklar satıldıysa portföy gerçekten 0'dır. Bunu atmak
      // grafiği yalan söyletirdi.
      final r = portfoyunVarOlduguSlotlar({
        1: 1000.0,
        2: 0.0,
        3: 1200.0,
      });
      expect(r.keys.toList(), [1, 2, 3]);
      expect(r[2], 0.0, reason: 'ortadaki sıfır gerçek veridir');
    });

    test('sıfırla başlayıp ortada da sıfır olan seri', () {
      // Baştakiler atılır, ortadaki kalır.
      final r = portfoyunVarOlduguSlotlar({
        1: 0.0,
        2: 500.0,
        3: 0.0,
        4: 800.0,
      });
      expect(r.keys.toList(), [2, 3, 4]);
    });

    test('hiç pozitif değer yoksa BOŞ döner', () {
      // Portföy dönem boyunca hiç var olmamış — çizilecek bir şey yok.
      final r = portfoyunVarOlduguSlotlar({1: 0.0, 2: 0.0});
      expect(r, isEmpty);
      expect(normalizeSeries(r), isNull);
    });

    test('sıfır içermeyen seri DEĞİŞMEZ', () {
      final girdi = {1: 100.0, 2: 110.0, 3: 105.0};
      expect(portfoyunVarOlduguSlotlar(girdi), girdi);
    });

    test('boş seri çökmez', () {
      expect(portfoyunVarOlduguSlotlar(const {}), isEmpty);
    });

    test('güvenlik ağı da UYGULANIR', () async {
      // Simülasyon normalde sıfır üretmez, ama bir sembolün fiyat geçmişi
      // hiç gelmezse `_flatFallback` 0 verebilir. İki koruma birlikte çalışır.
      final provider = _yorumsuz(
          await File('lib/providers/watchlist_provider.dart').readAsString());
      expect(
          provider.contains('normalizeSeries(portfoyunVarOlduguSlotlar(raw))'),
          isTrue,
          reason: 'ham seri doğrudan normalize edilirse tek bir bozuk sembol '
              'tüm kıyas çizgisini düşürür');
    });
  });

  group('Y ekseni — etiketler çakışmaz', () {
    // ## Bug (üretimde görüldü): "+15%" ile "+16%" üst üste bindi
    //
    // `fl_chart`'a `interval` verilmezse aralığı kendisi seçiyor ve dar
    // bantlarda etiketleri birbirine değecek kadar sıkıştırabiliyor. Ayrıca
    // ham `span/n` adımı yuvarlak olmadığı için okunması zor değerler
    // çıkıyordu.
    //
    // Çözüm `portfolio_performance_screen`'deki desenin aynısı: adımı
    // 1/2/2,5/5/10 tabanına yuvarla, sınırları o adımın katına oturt.

    /// Verilen eksende üretilecek etiket metinleri.
    List<String> etiketler(
        ({double min, double max, double interval, int ondalik}) e) {
      final out = <String>[];
      for (var v = e.min; v <= e.max + 1e-9; v += e.interval) {
        final r = (v / e.interval).round() * e.interval;
        out.add('${r >= 0 ? '+' : ''}${r.toStringAsFixed(e.ondalik)}%');
      }
      return out;
    }

    test('görseldeki durum artık çakışmıyor', () {
      // Ekran görüntüsündeki bant: yaklaşık −1% .. +16%, pay eklenmiş hâli.
      final e = yuzdeEkseni(-3.31, 18.51);
      final ets = etiketler(e);
      expect(ets.toSet().length, ets.length,
          reason: 'her etiket benzersiz olmalı: $ets');
      expect(e.interval, 10.0, reason: 'adım yuvarlak olmalı');
    });

    test('etiketler HER bantta benzersiz', () {
      const bantlar = [
        (-3.31, 18.51),
        (-0.5, 16.2),
        (0.0, 0.8),
        (-0.05, 0.05),
        (-40.0, 120.0),
        (2.0, 2.4),
      ];
      for (final (alt, ust) in bantlar) {
        final ets = etiketler(yuzdeEkseni(alt, ust));
        expect(ets.toSet().length, ets.length,
            reason: 'bant $alt..$ust için çakışma: $ets');
      }
    });

    test('veri HER ZAMAN eksenin içinde kalır', () {
      // En kritik değişmez: sınır veriyi kesiyorsa çizgi kırpılır ve
      // grafik yalan söyler. (`nice_axis_test` ile aynı kural.)
      const bantlar = [
        (-3.31, 18.51),
        (0.0, 0.8),
        (-40.0, 120.0),
        (-0.05, 0.05),
      ];
      for (final (alt, ust) in bantlar) {
        final e = yuzdeEkseni(alt, ust);
        expect(e.min, lessThanOrEqualTo(alt + 1e-9),
            reason: 'alt sınır veriyi kesiyor: $alt..$ust');
        expect(e.max, greaterThanOrEqualTo(ust - 1e-9),
            reason: 'üst sınır veriyi kesiyor: $alt..$ust');
      }
    });

    test('adım 1/2/2,5/5/10 tabanına oturur', () {
      for (final (alt, ust) in const [
        (-3.31, 18.51),
        (0.0, 100.0),
        (0.0, 3.0),
      ]) {
        final adim = yuzdeEkseni(alt, ust).interval;
        // Adımı 10'un kuvvetine böl; 1/2/2,5/5/10'dan biri çıkmalı.
        final us =
            math.pow(10, (math.log(adim) / math.ln10).floor()).toDouble();
        final oran = adim / us;
        expect([1.0, 2.0, 2.5, 5.0, 10.0].any((x) => (x - oran).abs() < 1e-9),
            isTrue,
            reason: 'adım yuvarlak değil: $adim (oran $oran)');
      }
    });

    test('dar bantta ONDALIK gösterilir', () {
      // Adım 1'den küçükken tam sayı etiketi tekrar ederdi ("+0%, +0%").
      final e = yuzdeEkseni(0.0, 0.8);
      expect(e.ondalik, greaterThan(0),
          reason: 'adım ${e.interval} için tam sayı etiket yetersiz');
    });

    test('geniş bantta ondalık YOK — gürültü olurdu', () {
      expect(yuzdeEkseni(-40.0, 120.0).ondalik, 0);
    });

    test('düz seri (min == max) çökmez', () {
      final e = yuzdeEkseni(5.0, 5.0);
      expect(e.max, greaterThan(e.min));
      expect(e.interval, greaterThan(0));
    });

    test('grafik bu ekseni KULLANIR', () async {
      // Fonksiyon doğru olsa da bağlanmazsa bug sürerdi.
      final chart = _yorumsuz(
          await File('lib/widgets/percent_comparison_chart.dart')
              .readAsString());
      expect(chart.contains('yuzdeEkseni('), isTrue);
      expect(chart.contains('interval: eksen.interval'), isTrue,
          reason: 'adım fl_chart\'a açıkça verilmezse kendi seçer');
      expect(chart.contains('horizontalInterval: eksen.interval'), isTrue,
          reason: 'ızgara çizgileri etiketlerle aynı adımda olmalı');
    });
  });

  group('çizgiye dokunma — odak', () {
    test('odak yokken dokunulan seri odağa gelir', () {
      expect(yeniOdak(mevcut: null, dokunulan: 'GARAN'), 'GARAN');
    });

    test('AYNI seriye tekrar dokunmak odağı KALDIRIR', () {
      // Çıkış yolu: kullanıcı odaktan çıkmak için başka yer aramamalı.
      // Donut grafikteki `_touchedIndex` deseninin aynısı.
      expect(yeniOdak(mevcut: 'GARAN', dokunulan: 'GARAN'), isNull);
    });

    test('BAŞKA seriye dokunmak odağı taşır', () {
      expect(yeniOdak(mevcut: 'GARAN', dokunulan: 'ALARK'), 'ALARK');
    });

    test('portföy çizgisine de odaklanılabilir', () {
      const k = WatchlistChart.portfolioSeriesKey;
      expect(yeniOdak(mevcut: null, dokunulan: k), k);
      expect(yeniOdak(mevcut: k, dokunulan: k), isNull);
    });

    test('odak FİLTRE DEĞİL — diğer seriler grafikte kalır', () async {
      // En kritik kural: odaklanmak diğer çizgileri KALDIRMAZ, soluklaştırır.
      // Kaldırmak kıyası yok ederdi — "bu varlık iyi mi gidiyor" sorusunun
      // cevabı ancak diğerleri görünürken vardır.
      final chart = _yorumsuz(
          await File('lib/widgets/percent_comparison_chart.dart')
              .readAsString());
      expect(chart.contains('withValues(alpha: 0.18)'), isTrue,
          reason: 'odak dışı seriler soluklaşmalı');
      // Seri listesini odağa göre süzen bir kod OLMAMALI.
      expect(chart.contains('where((k) => k == focused'), isFalse);
      expect(chart.contains('if (focused != null && key != focused) continue'),
          isFalse,
          reason: 'odak dışı seri atlanırsa kıyas kaybolur');
    });

    test('odaktaki seri KALINLAŞIR — renk tek işaret değil', () async {
      final chart = _yorumsuz(
          await File('lib/widgets/percent_comparison_chart.dart')
              .readAsString());
      expect(chart.contains('buOdakta ?'), isTrue,
          reason: 'soluklaşmaya ek olarak kalınlık da değişmeli');
    });

    test('bayat odak temizlenir', () async {
      // Varlık takipten çıkarılmış ya da yeni dönemde serisi gelmemiş
      // olabilir. Bayat anahtar tutulursa TÜM seriler soluk kalır.
      final ekran = _yorumsuz(
          await File('lib/screens/watchlist_screen.dart').readAsString());
      expect(ekran.contains('series.containsKey(focused)'), isTrue,
          reason: 'odak yalnızca var olan bir seriye işaret edebilir');
    });
  });

  group('kıyas seçici — kimin portföyü', () {
    // `ModernTabSelector` sözleşmesi: '' = Ben, uuid = o ortak,
    // null = Birlikte. Uygulamanın geri kalanıyla aynı; ayrı bir sözleşme
    // uydurmak kullanıcıya iki farklı seçici dili öğretirdi.
    final benim = [_lot('BEN1'), _lot('BEN2')];
    final ortakA = [_lot('A1')];
    final ortakB = [_lot('B1'), _lot('B2')];
    final harita = {'a': ortakA, 'b': ortakB};

    test('Ben — yalnızca kendi varlıkların', () {
      final r = kiyasVarliklari(
        view: '',
        myAssets: benim,
        partnerAssets: harita,
        activePartnerIds: {'a', 'b'},
      );
      expect(r.map((e) => e.ticker), ['BEN1', 'BEN2'],
          reason: 'ortak varlıkları kendi kıyasıma karışmamalı');
    });

    test('Tek ortak — yalnızca o ortağın varlıkları', () {
      final r = kiyasVarliklari(
        view: 'b',
        myAssets: benim,
        partnerAssets: harita,
        activePartnerIds: {'a', 'b'},
      );
      expect(r.map((e) => e.ticker), ['B1', 'B2'],
          reason: 'ortak seçiliyken benim varlıklarım girmemeli');
    });

    test('Birlikte — ben + tüm aktif ortaklar', () {
      final r = kiyasVarliklari(
        view: null,
        myAssets: benim,
        partnerAssets: harita,
        activePartnerIds: {'a', 'b'},
      );
      expect(r.length, 5, reason: '2 benim + 1 A + 2 B');
      expect(
          r.map((e) => e.ticker).toSet(), {'BEN1', 'BEN2', 'A1', 'B1', 'B2'});
    });

    test('PASİF ortaklık Birlikte hesabına GİRMEZ', () {
      // Harita pasifleşmiş ortağın verisini hâlâ taşıyor olabilir;
      // `activePartnerIds` tek doğruluk kaynağıdır.
      final r = kiyasVarliklari(
        view: null,
        myAssets: benim,
        partnerAssets: harita,
        activePartnerIds: {'a'}, // b pasifleşti
      );
      expect(r.map((e) => e.ticker).toSet(), {'BEN1', 'BEN2', 'A1'},
          reason: 'pasif ortağın (b) verisi kıyas çizgisine sızmamalı');
      // Not: `startsWith('B')` ile bakmak YANLIŞ olurdu — 'BEN1' de B ile
      // başlıyor. Ortak B'nin lot'ları tam adlarıyla aranır.
      expect(r.any((e) => e.ticker == 'B1' || e.ticker == 'B2'), isFalse);
    });

    test('pasif ortak DOĞRUDAN seçilse bile boş döner', () {
      final r = kiyasVarliklari(
        view: 'b',
        myAssets: benim,
        partnerAssets: harita,
        activePartnerIds: {'a'},
      );
      expect(r, isEmpty,
          reason: 'seçici pasif ortağı listelemez ama state bayat kalabilir');
    });

    test('bilinmeyen ortak id — boş, çökmez', () {
      final r = kiyasVarliklari(
        view: 'yok',
        myAssets: benim,
        partnerAssets: harita,
        activePartnerIds: {'a', 'b'},
      );
      expect(r, isEmpty);
    });

    test('ortak yokken Birlikte == Ben', () {
      final birlikte = kiyasVarliklari(
        view: null,
        myAssets: benim,
        partnerAssets: const {},
        activePartnerIds: const {},
      );
      expect(birlikte.map((e) => e.ticker), ['BEN1', 'BEN2']);
    });
  });

  group('takip listesi limiti', () {
    late String prefs;
    late String provider;

    setUpAll(() async {
      prefs = _yorumsuz(
          await File('lib/providers/preferences_provider.dart').readAsString());
      provider = _yorumsuz(
          await File('lib/providers/watchlist_provider.dart').readAsString());
    });

    test('paywall KAPALIYKEN limit uygulanmaz', () {
      // En kritik kural: `paywall_enabled=false` iken kullanıcı 5 varlıkta
      // durdurulup çıkışsız bırakılmamalı — satın alınacak bir şey yok.
      final i = prefs.indexOf('watchlistLimitProvider');
      expect(i, greaterThan(0), reason: 'limit provider\'ı tanımlı olmalı');
      final govde = prefs.substring(i, i + 500);
      expect(govde.contains('paywallVisibleProvider'), isTrue);
      expect(govde.contains('if (!paywallOn) return 1 << 30'), isTrue,
          reason: 'paywall kapalıyken sınırsız — assetLimitProvider ile '
              'aynı kalıp');
    });

    test('premium kullanıcıda limit yok', () {
      final i = prefs.indexOf('watchlistLimitProvider');
      final govde = prefs.substring(i, i + 500);
      expect(govde.contains('effectivePremiumProvider'), isTrue);
      expect(govde.contains('if (premium) return 1 << 30'), isTrue);
    });

    test('limit Remote Config\'ten okunur — sabit kodlanmaz', () {
      final i = prefs.indexOf('watchlistLimitProvider');
      final govde = prefs.substring(i, i + 500);
      expect(govde.contains('freeWatchlistLimit'), isTrue,
          reason: 'limit yayın sonrası ayarlanabilmeli');
      // Varsayılan 5 — kullanıcının istediği değer.
      expect(
          _yorumsuz(File('lib/services/remote_config_service.dart')
                  .readAsStringSync())
              .contains("'free_watchlist_limit': 5"),
          isTrue);
    });

    test('limit PROVIDER\'da uygulanır — UI\'da değil', () {
      // Tek giriş noktası varsayımı kırılgandır (derin bağlantı, ileride
      // "portföyden takibe al" akışı). Kural notifier'da durursa baypas
      // edilemez; `portfolio_provider` de aynı gerekçeyle böyle yapıyor.
      final i = provider.indexOf('Future<void> add(');
      expect(i, greaterThan(0));
      final govde = provider.substring(i, i + 900);
      expect(govde.contains('watchlistLimitProvider'), isTrue,
          reason: 'limit ekleme metodunun İÇİNDE kontrol edilmeli');
      expect(govde.contains('WatchlistLimitException'), isTrue);
    });

    // NOT: Aşağıdaki testler kaynak metnine DEĞİL davranışa bakar.
    //
    // İlk sürümde bu kural `govde.contains('zatenVar')` ile denetleniyordu.
    // Sabotajla ölçüldüğünde YETERSİZ çıktı: `final zatenVar = false;`
    // yazıldığında (yani kural tamamen bozulduğunda) test hâlâ geçiyordu —
    // değişken adı duruyordu ama hiçbir şey yapmıyordu. Karar saf bir
    // fonksiyona (`watchlistLimitiAsiliyorMu`) çıkarıldı ve gerçek girdi
    // kombinasyonlarıyla sınanıyor.

    test('limit dolu değilken ekleme geçer', () {
      expect(
          watchlistLimitiAsiliyorMu(
              mevcutSayi: 3, zatenTakipte: false, limit: 5),
          isFalse);
    });

    test('limit dolduğunda YENİ varlık engellenir', () {
      expect(
          watchlistLimitiAsiliyorMu(
              mevcutSayi: 5, zatenTakipte: false, limit: 5),
          isTrue);
    });

    test('zaten takipteki varlık kotayı ARTIRMAZ', () {
      // Limit dolu olsa BİLE, var olan kaydı yeniden eklemek engellenmemeli:
      // sunucudaki unique index onu zaten reddediyor, kullanıcıya "limit
      // doldu" demek yanlış sebep göstermek olurdu.
      expect(
          watchlistLimitiAsiliyorMu(
              mevcutSayi: 5, zatenTakipte: true, limit: 5),
          isFalse,
          reason: 'aynı varlığı yeniden eklemek limite takılmamalı');
    });

    test('paywall kapalı / premium (sonsuz limit) asla engellemez', () {
      expect(
          watchlistLimitiAsiliyorMu(
              mevcutSayi: 9999, zatenTakipte: false, limit: 1 << 30),
          isFalse,
          reason: 'satın alınacak premium yokken kullanıcı durdurulmamalı');
    });

    test('limitin üstüne çıkılmışsa da engellenir', () {
      // Sunucudan limitin üstünde kayıt gelebilir (limit sonradan düşürüldü).
      // Bu durumda YENİ ekleme yine engellenmeli.
      expect(
          watchlistLimitiAsiliyorMu(
              mevcutSayi: 7, zatenTakipte: false, limit: 5),
          isTrue);
    });

    test('limit hatası ağ hatasından AYRI tiptedir', () {
      // Genel `Exception` fırlatmak, ekleme ekranında "bağlantını kontrol et"
      // gibi YANLIŞ bir mesaj gösterilmesine yol açardı.
      expect(provider.contains('class WatchlistLimitException'), isTrue);
      expect(provider.contains('final int limit'), isTrue,
          reason: 'mesajda limitin kaç olduğu yazılabilmeli');
    });

    test('ekleme ekranı limit hatasında ÇIKIŞ YOLU sunar', () async {
      final ekle = _yorumsuz(
          await File('lib/screens/add_watchlist_screen.dart').readAsString());
      expect(ekle.contains('on WatchlistLimitException'), isTrue,
          reason: 'limit hatası ayrı yakalanmalı');
      expect(ekle.contains('PaywallScreen.show'), isTrue,
          reason: 'kullanıcıya ne yapabileceği söylenmeli — '
              '"eklenemedi" deyip bırakmak çıkışsız bırakır');
    });
  });
}
