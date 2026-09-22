import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/daily_summary.dart';

/// Performans → Özet sekmesi SEÇİLİ KAPSAMI anlatır (kullanıcı bulgusu
/// 2026-09-22: "loggedin olan müşteri sayfası düzgünken ortaklara ya da
/// birlikte tabına geçildiğinde değerler kâr zarar ve birikimler
/// saçmalıyor").
///
/// ## Kayma neredeydi
/// GÜNLÜK dönemde Özet, hesabı `DailySummary.from()`'a delege eder — bu
/// doğru: widget, Live Activity, üst kart ve Özet aynı rakamı göstermek
/// zorunda (`daily_summary.dart` "Değişmezler"). Ama `from()` canlı ucu ve
/// nakit akışını `state.assets` üzerinden, yani TÜM defterden okuyordu.
/// Seri (`breakdown.total`) ise seçili kapsama göre çekiliyor.
///
/// Sonuç iki ölçüm farklı kümeye bakıyordu:
///   * gün başı = ortağın portföyü, uç = herkesin toplamı → fark ortağın
///     günlük hareketi değil, aradaki kapsam farkı kadar;
///   * başka bir sahibin o gün yaptığı alım, görüntülenen kapsamın
///     hareketinden düşülüyordu (`inflowOnDay`).
///
/// [DailySummary.from] artık `kapsamLotlari` alır; `state` geriye yalnızca
/// kur çevirici olarak kalır. Parametre verilmediğinde eski davranış
/// aynen sürer — widget ve Live Activity tüm defteri anlatmaya devam eder.
Asset _lot({
  required String userId,
  required String ticker,
  required double qty,
  required double buyPrice,
  required double currentPrice,
  DateTime? addedDate,
  AssetKind kind = AssetKind.buy,
}) =>
    Asset(
      id: '$userId-$ticker-${kind.name}-$qty-$buyPrice',
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: buyPrice,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1,
      currentPrice: currentPrice,
      addedDate: addedDate ?? DateTime(2026, 1, 1),
      kind: kind,
    );

void main() {
  // Ben: 10 THYAO @100 → 120 = ₺1.200.
  // Ortak: 5 THYAO @100 → 140 = ₺700.
  final ben = [
    _lot(
        userId: 'ben',
        ticker: 'THYAO',
        qty: 10,
        buyPrice: 100,
        currentPrice: 120),
  ];
  final ortak = [
    _lot(
        userId: 'ortak',
        ticker: 'THYAO',
        qty: 5,
        buyPrice: 100,
        currentPrice: 140),
  ];
  final birlesik = [...ben, ...ortak];

  final now = DateTime(2026, 9, 22, 15, 0);
  final gun = DateTime(2026, 9, 22);

  /// Ortağın gün içi serisi: ₺650 → ₺690. Uç canlı toplama (₺700)
  /// sabitlenecek; son damga taze olduğu için EZİLİR.
  Map<int, double> ortakSerisi() => {
        DateTime(2026, 9, 22, 10).millisecondsSinceEpoch: 650.0,
        now.millisecondsSinceEpoch: 690.0,
      };

  test('kapsam verilince canlı uç o kapsamın toplamı olur', () {
    final state = PortfolioState(assets: birlesik);

    final kapsamli = DailySummary.from(
      state: state,
      series: ortakSerisi(),
      now: now,
      seansGunu: gun,
      kapsamLotlari: ortak,
    );

    expect(kapsamli.totalTRY, 700.0,
        reason: 'ortak sekmesinde toplam ortağın portföyüdür');
    expect(kapsamli.sparkline.last, 700.0,
        reason: 'eğrinin ucu yazılan rakamla aynı yere gelmeli');
    // Gün başı 650 → 700: ₺50 / %7,69.
    expect(kapsamli.changeTRY, closeTo(50.0, 0.001));
    expect(kapsamli.changePct, closeTo(50.0 / 650.0 * 100, 0.001));
  });

  test('kapsamsız çağrı ESKİ davranış — widget/Live Activity etkilenmez', () {
    final state = PortfolioState(assets: birlesik);

    final kapsamsiz = DailySummary.from(
      state: state,
      series: ortakSerisi(),
      now: now,
      seansGunu: gun,
    );

    // Tüm defter: 1.200 + 700 = 1.900.
    expect(kapsamsiz.totalTRY, 1900.0);
  });

  test('regresyon: ortak kapsamında uç tüm deftere kaymaz', () {
    final state = PortfolioState(assets: birlesik);

    final kapsamli = DailySummary.from(
      state: state,
      series: ortakSerisi(),
      now: now,
      seansGunu: gun,
      kapsamLotlari: ortak,
    );

    // Eski hata: gün başı ₺650 (ortak), uç ₺1.900 (herkes) → +₺1.250 /
    // %192 "kâr". Kullanıcının gördüğü saçma rakam tam olarak buydu.
    expect(kapsamli.changeTRY, isNot(closeTo(1250.0, 1.0)));
    expect(kapsamli.changePct!, lessThan(100.0));
  });

  test('nakit akışı da kapsamdan okunur: başkasının alımı düşülmez', () {
    // Ortak bugün ₺700'lük alım yaptı; BEN hiçbir şey yapmadım.
    final ortakBugunAldi = [
      ...ortak,
      _lot(
        userId: 'ortak',
        ticker: 'ASELS',
        qty: 10,
        buyPrice: 70,
        currentPrice: 70,
        addedDate: DateTime(2026, 9, 22, 11),
      ),
    ];
    final defter = [...ben, ...ortakBugunAldi];
    final state = PortfolioState(assets: defter);

    // BENİM serim: 1.150 → 1.200, yani ₺50 saf piyasa hareketi.
    final benimSeri = {
      DateTime(2026, 9, 22, 10).millisecondsSinceEpoch: 1150.0,
      now.millisecondsSinceEpoch: 1190.0,
    };

    final benimOzet = DailySummary.from(
      state: state,
      series: benimSeri,
      now: now,
      seansGunu: gun,
      kapsamLotlari: ben,
    );

    expect(benimOzet.totalTRY, 1200.0);
    // Ortağın ₺700'lük alımı benim hareketimden DÜŞÜLMEMELİ.
    expect(benimOzet.changeTRY, closeTo(50.0, 0.001),
        reason: 'eski davranışta −₺650 çıkıyordu (700 inflow düşülüyordu)');
  });

  test('kaynak: Özet sekmesi kapsamı geçirir', () {
    final kartlar = File('lib/screens/portfolio_performance/kartlar.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(kartlar.contains('kapsamLotlari: targetAssets'), isTrue,
        reason: 'Özet sekmesi seçili kapsamı DailySummary.from\'a vermeli');
  });
}
