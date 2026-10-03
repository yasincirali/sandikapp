import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/canli_etkinlik_tarifi.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/live_activity_service.dart';

import 'helpers/kaynak.dart';

/// Kilit ekranı uygulama KAPALIYKEN de Performans GÜNLÜK ile eş olmalı
/// (kullanıcı kararı 2026-10-03: "Canlı aktiviteler her zaman 1 dk'da bir
/// performans günlükle eş olmalı").
///
/// Sunucu (`supabase/functions/_shared/canli_etkinlik.ts`) istemcinin yazdığı
/// tarifi canlı kotasyonla ileri taşır. Buradaki parite vakası şunu söyler:
/// "fiyatlar şu olunca UYGULAMA ne gösterirdi" — beklenen metin doğrudan
/// [DailySummary.from] + [LiveActivityService.degisimMetinleri]'nden gelir.
/// Aynı vaka `supabase/tests/canli_etkinlik_parite_test.ts`'te sunucunun
/// hesabıyla karşılaştırılır; iki taraftan biri değişirse biri kırılır.
///
/// Fikstürü yeniden üretmek (hesap BİLEREK değiştiyse):
///   CANLI_PARITE_YAZ=1 flutter test test/canli_etkinlik_tarifi_test.dart
const _fikstur = 'supabase/tests/canli_etkinlik_parite.json';

final _gun = DateTime(2026, 10, 1);
final _simdi = DateTime(2026, 10, 1, 14, 32);

Asset _lot(
  String id,
  String ticker,
  AssetType type,
  double qty,
  double fiyat, {
  String currency = 'TRY',
  String? sub,
  DateTime? eklendi,
  double? alis,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      // Alış fiyatı piyasayla OYNAMAZ: gün içi alımın akışı (katkı) alış
      // tutarıdır; vakalarda yalnızca güncel fiyat değişir.
      purchasePrice: alis ?? fiyat,
      currency: currency,
      notes: '',
      subCategory: sub,
      currentPrice: fiyat,
      addedDate: eklendi ?? DateTime(2026, 1, 1),
      isManualPrice: false,
    );

/// Fiyatlar [f] ile; kur [usd].
PortfolioState _durum(Map<String, double> f, {double usd = 42}) =>
    PortfolioState(
      assets: [
        _lot('a1', 'THYAO.IS', AssetType.hisse, 100, f['THYAO.IS']!),
        // Gün içi alım — açılıştan sonra: nakit akışı (katkı).
        _lot('a2', 'THYAO.IS', AssetType.hisse, 10, f['THYAO.IS']!,
            alis: 300, eklendi: DateTime(2026, 10, 1, 13, 2)),
        _lot('g1', 'ALTIN_GRAM', AssetType.altin, 10, f['ALTIN_GRAM']!,
            sub: '22 Ayar'),
        _lot('u1', 'AAPL', AssetType.hisse, 5, f['AAPL']!, currency: 'USD'),
        // Fon: gün içi oynamaz, sabit parçaya girer.
        _lot('t1', 'TEFAS:AFT', AssetType.fon, 1000, 2),
      ],
      usdTry: usd,
      eurTry: 46,
      gbpTry: 54,
    );

const _fiyat1 = {'THYAO.IS': 300.0, 'ALTIN_GRAM': 6000.0, 'AAPL': 200.0};

/// `IntradaySeriesCache`'teki seri: 14:32'de çekilmiş (5 dk önbellek).
/// HistoryService ızgarayı çekim anında keser (gelecek slot YOK), açılış
/// öncesi slotlar boştur. Vakalar 14:32'den sonraki dakikalardır; uygulama
/// o arada aynı önbellekli seriyi kullanır, canlı ucu her turda yeniden
/// koyar — sunucunun taklit ettiği tam olarak budur.
Map<int, double> _seri() {
  final out = <int, double>{};
  for (var m = 9 * 60; m <= 14 * 60 + 30; m += 5) {
    final t = _gun.add(Duration(minutes: m));
    final ms = t.millisecondsSinceEpoch;
    if (m < 10 * 60) {
      out[ms] = 0;
      continue;
    }
    final i = (m - 10 * 60) ~/ 5;
    // Hafif dalgalı bir gün; 13:00'ten sonra alım (+3.000) içeride.
    var v = 134000 + i * 50 + (i % 4 == 0 ? -400 : 120);
    if (m >= 13 * 60) v += 3000;
    out[ms] = v.toDouble();
  }
  return out;
}

DailySummary _ozet(PortfolioState s, DateTime now) =>
    DailySummary.from(state: s, series: _seri(), now: now, seansGunu: _gun);

Map<String, Object?> _uygulamaNeGosterir(PortfolioState s, DateTime now) {
  final o = _ozet(s, now);
  final m = LiveActivityService.degisimMetinleri(o);
  final eksen = LiveActivityService.eksenMetinleri(o.sparkline);
  return {
    'totalText': m.totalText,
    'changeText': m.changeText,
    'changePctText': m.changePctText,
    'isPositive': m.isPositive,
    'isFlatChange': m.isFlat,
    'sparkline': DailySummary.normalizeForSparkline(o.sparkline),
    'axisMinText': eksen?.min ?? '',
    'axisMaxText': eksen?.max ?? '',
  };
}

Map<String, Object?> _tarif() {
  final s = _durum(_fiyat1);
  final t = CanliEtkinlikTarifi.kur(
    state: s,
    ozet: _ozet(s, _simdi),
    series: _seri(),
    now: _simdi,
    seansGunu: _gun,
  );
  expect(t, isNotNull);
  return t!;
}

/// Vaka: [dk] dakika sonra fiyatlar [f], kur [usd]. Sunucuya giden
/// kotasyonlar [kotasyon] (eksik sembol = sunucu alamadı).
Map<String, Object?> _vaka(
  String ad,
  int dk,
  Map<String, double> f,
  double usd,
  Map<String, double> kotasyon,
) {
  final now = _simdi.add(Duration(minutes: dk));
  return {
    'ad': ad,
    'simdiMs': now.millisecondsSinceEpoch,
    'kotasyonlar': kotasyon,
    'beklenen': _uygulamaNeGosterir(_durum(f, usd: usd), now),
  };
}

List<Map<String, Object?>> _vakalar() => [
      _vaka(
        'yukselis, son slot taze (uc ezilir)',
        3,
        {'THYAO.IS': 306, 'ALTIN_GRAM': 6030, 'AAPL': 201},
        42.1,
        {'THYAO.IS': 306, 'ALTIN_GRAM': 6030, 'AAPL': 201, 'USDTRY=X': 42.1},
      ),
      _vaka(
        'dusus, son slot bayat (uc eklenir)',
        9,
        {'THYAO.IS': 280, 'ALTIN_GRAM': 5900, 'AAPL': 195},
        41.9,
        {'THYAO.IS': 280, 'ALTIN_GRAM': 5900, 'AAPL': 195, 'USDTRY=X': 41.9},
      ),
      _vaka(
        'altin kotasyonu alinamadi (parca sabit kalir)',
        4,
        {'THYAO.IS': 303, 'ALTIN_GRAM': 6000, 'AAPL': 200},
        42,
        {'THYAO.IS': 303, 'AAPL': 200, 'USDTRY=X': 42},
      ),
    ];

Map<String, Object?> _fiksturUret() => {
      'not': 'Uretildi: test/canli_etkinlik_tarifi_test.dart (CANLI_PARITE_YAZ=1). '
          'Elle duzenleme.',
      'tabanMs': _simdi.millisecondsSinceEpoch,
      'bugun': '2026-10-01',
      'tutarGoster': true,
      'tarif': _tarif(),
      'vakalar': _vakalar(),
    };

/// Saat dilimine bağlı mutlak damgaları tabana göre görelileştirir — fikstür
/// UTC'de üretilir, geliştirici makinesi İstanbul saatinde koşar.
Object? _goreli(Object? x, int taban) {
  const damgalar = {'yazildiMs', 'acilisMs', 'sonSlotMs', 'ms', 'simdiMs'};
  if (x is Map) {
    return {
      for (final e in x.entries)
        e.key: damgalar.contains(e.key) && e.value is num
            ? (e.value as num).toInt() - taban
            : _goreli(e.value, taban),
    };
  }
  if (x is List) return [for (final v in x) _goreli(v, taban)];
  if (x is num) return double.parse(x.toDouble().toStringAsPrecision(12));
  return x;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
  });

  group('tarif', () {
    test('Σ parça + sabit = toplam; yalnızca gün içi oynayan türler', () {
      final t = _tarif();
      final parcalar = (t['parcalar']! as List).cast<Map<String, Object?>>();
      final semboller = parcalar.map((p) => p['s']).toSet();
      expect(semboller, {'THYAO.IS', 'ALTIN_GRAM', 'AAPL'},
          reason: 'fon (TEFAS) gün içi oynamaz, sabit parçada kalır');
      final toplam = parcalar.fold<double>(
              0, (a, p) => a + (p['d']! as double)) +
          (t['sabit']! as double);
      expect(toplam, closeTo(t['toplam']! as double, 1e-6));
      expect(t['sabit'], closeTo(2000, 1e-6), reason: 'fon değeri');

      final aapl = parcalar.firstWhere((p) => p['s'] == 'AAPL');
      expect(aapl['k'], 'USDTRY=X');
      expect(aapl['kf'], 42);
      expect(aapl['d'], closeTo(5 * 200 * 42, 1e-6));
    });

    test('seri canlı uçtan ÖNCEKİ hâl; akış açılıştan sonraki alım', () {
      final t = _tarif();
      final seri = (t['seri']! as List).cast<double>();
      expect(seri.first, isNot(0), reason: 'baştaki boş slotlar atılır');
      // 10:00 … 14:30 = 55 slot.
      expect(seri.length, 55);
      expect(t['sonSlotMs'],
          DateTime(2026, 10, 1, 14, 30).millisecondsSinceEpoch);
      final akislar = (t['akislar']! as List).cast<Map<String, Object?>>();
      expect(akislar, hasLength(1));
      expect(akislar.single['f'], closeTo(3000, 1e-6));
    });

    test('çizilen seans bugün değilse tarif YOK (hafta sonu → Cuma)', () {
      final s = _durum(_fiyat1);
      final pazar = DateTime(2026, 10, 4, 12);
      final t = CanliEtkinlikTarifi.kur(
        state: s,
        ozet: DailySummary.from(
            state: s, series: _seri(), now: pazar, seansGunu: _gun),
        series: _seri(),
        now: pazar,
        seansGunu: _gun,
      );
      expect(t, isNull);
    });

    test('değişim ölçülemediyse tarif YOK (uydurma ileri taşınmaz)', () {
      final s = _durum(_fiyat1);
      final t = CanliEtkinlikTarifi.kur(
        state: s,
        ozet: DailySummary.from(
            state: s, series: const {}, now: _simdi, seansGunu: _gun),
        series: const {},
        now: _simdi,
        seansGunu: _gun,
      );
      expect(t, isNull);
    });
  });

  group('sunucu paritesi', () {
    test('fikstür, uygulamanın bugünkü hesabıyla AYNI', () {
      final uretilen = _fiksturUret();
      final dosya = File(_fikstur);
      if (Platform.environment['CANLI_PARITE_YAZ'] == '1') {
        dosya.writeAsStringSync(
            '${const JsonEncoder.withIndent('  ').convert(uretilen)}\n');
      }
      final kayitli = jsonDecode(dosya.readAsStringSync()) as Map;
      final tabanK = (kayitli['tabanMs'] as num).toInt();
      final tabanU = uretilen['tabanMs']! as int;
      expect(_goreli(kayitli['tarif'], tabanK),
          _goreli(uretilen['tarif'], tabanU),
          reason: 'tarif biçimi değişti — sunucu da güncellenmeli, '
              'sonra CANLI_PARITE_YAZ=1 ile fikstürü yeniden üret');
      expect(_goreli(kayitli['vakalar'], tabanK),
          _goreli(uretilen['vakalar'], tabanU),
          reason: 'uygulamanın günlük hesabı/metni değişti — sunucu '
              '(_shared/canli_etkinlik.ts) da aynı değişikliği almalı');
    });
  });

  test('main.dart bayrağı her senkronda servise aktarır', () {
    final src = ekranKaynagiSync('lib/main.dart');
    expect(
        src.contains('la.dakikalikGuncelleme =\n'
            '        RemoteConfigService.instance.canliEtkinlikDakikalik;'),
        isTrue);
  });
}
