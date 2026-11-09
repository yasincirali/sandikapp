import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/secili_donem_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/varlik_sayfasi.dart';
import 'package:portfoy_takip/services/period_summary_service.dart'
    show SummaryPeriod;
import 'package:portfoy_takip/widgets/donem_istatistik.dart';
import 'package:portfoy_takip/widgets/katmanli_fiyat_grafigi.dart';
import 'package:portfoy_takip/widgets/seri_son_guncelleme.dart';
import 'package:portfoy_takip/widgets/varlik_iskeleti.dart';

/// Varlık sayfası: **önce eski seri, sonra taze** (Ar-Ge raporu 2026-10-24
/// §1 YAP). Eski seri hemen SOLUK çizilir (açılış kapısı tazeyi beklemez);
/// taze seri gelince net çizilir ve sayılar/göstergeler yeni seriden
/// yeniden hesaplanır; taze çekim düşerse eski seri net kalır, altında
/// "Son güncelleme". Hareketi azalt açıkken geçiş anında.

const _thy = VarlikKimligi(
  ticker: 'THYAO.IS',
  name: 'Türk Hava Yolları',
  type: AssetType.hisse,
  currency: 'TRY',
);

class _Portfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: const [],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

class _Takip extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => const [];
}

final _son = DateTime(2026, 9, 28, 17).millisecondsSinceEpoch;

/// İki noktalı seri: 100 → [bitis]. Fiyat başlığı son noktayı yazar.
Map<int, double> _seri(int gun, double bitis) => {
      _son -
          Duration(days: gun == 1 ? 0 : gun).inMilliseconds -
          const Duration(hours: 8).inMilliseconds: 100.0,
      _son: bitis,
    };

final _olculdu = DateTime(2026, 9, 27, 14, 32);

Future<void> _kur(
  WidgetTester t, {
  required TazeSeriYukleyici taze,
  required EldekiSeriYukleyici eldeki,
  bool hareketiAzalt = false,
}) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      seciliDonemProvider.overrideWith((ref) => SummaryPeriod.birYil),
      portfolioProvider.overrideWith(_Portfoy.new),
      watchlistProvider.overrideWith(_Takip.new),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: hareketiAzalt),
          child: Scaffold(
            body: VarlikSayfasi(
              kimlik: _thy,
              tamAcilis: true,
              tazeYukleyici: taze,
              eldekiYukleyici: eldeki,
            ),
          ),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<({Map<int, double> seri, DateTime zaman})?> _eskiHemen(
        String _, int gun) async =>
    (seri: _seri(gun, 110), zaman: _olculdu);

AnimatedOpacity _grafikOpakligi(WidgetTester t) => t.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byType(KatmanliFiyatGrafigi),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );

Future<void> _gecis(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  testWidgets('eski seri hemen SOLUK; taze gelince net ve sayılar yeni seriden',
      (t) async {
    final bekleyen =
        <int, Completer<({Map<int, double> seri, DateTime? bayatZaman})>>{};
    await _kur(
      t,
      eldeki: _eskiHemen,
      taze: (_, gun) => (bekleyen[gun] = Completer()).future,
    );
    await _gecis(t);

    // Taze hiçbir dönem gelmedi; sayfa yine de açıldı (iskelet yok).
    expect(find.byType(VarlikIskeleti), findsNothing,
        reason: 'eski seri varken açılış kapısı tazeyi beklememeli');
    expect(find.textContaining('110,00'), findsWidgets);
    expect(_grafikOpakligi(t).opacity, lessThan(1.0),
        reason: 'eski seri soluk çizilir');
    expect(find.byType(SeriSonGuncelleme), findsNothing,
        reason: 'taze yolda: satır değil, solukluk');
    final eskiIst =
        t.widget<DonemIstatistikIzgarasi>(find.byType(DonemIstatistikIzgarasi));
    expect(eskiIst.ist.son, 110);

    for (final e in bekleyen.entries) {
      e.value.complete((seri: _seri(e.key, 120), bayatZaman: null));
    }
    await _gecis(t);

    expect(_grafikOpakligi(t).opacity, 1.0);
    expect(find.textContaining('120,00'), findsWidgets);
    expect(find.textContaining('110,00'), findsNothing);
    // Grafik katmanları (MA/EMA, mum, özel gösterge) `seri`'den çizer:
    // yeni seri grafiğe geçti → göstergeler yeni seriden hesaplanır.
    final grafik =
        t.widget<KatmanliFiyatGrafigi>(find.byType(KatmanliFiyatGrafigi));
    expect(grafik.seri, _seri(365, 120));
    final yeniIst =
        t.widget<DonemIstatistikIzgarasi>(find.byType(DonemIstatistikIzgarasi));
    expect(yeniIst.ist.son, 120, reason: 'istatistik eski seriden kalmamalı');
    expect(find.byType(SeriSonGuncelleme), findsNothing);
  });

  testWidgets('taze çekim düşerse eski seri NET kalır, "Son güncelleme" ile',
      (t) async {
    await _kur(
      t,
      eldeki: _eskiHemen,
      // Ağ düştü: HistoryService son iyi kopyayı döner ve bunu söyler.
      taze: (_, gun) async => (seri: _seri(gun, 110), bayatZaman: _olculdu),
    );
    await _gecis(t);
    expect(_grafikOpakligi(t).opacity, 1.0,
        reason: 'ekran sonsuza dek soluk durmamalı');
    expect(find.byType(SeriSonGuncelleme), findsOneWidget);
    expect(find.textContaining('Son güncelleme'), findsOneWidget);
    expect(find.textContaining('27 Eyl 2026'), findsOneWidget);
  });

  testWidgets('taze çekim BOŞ dönerse eski seri silinmez', (t) async {
    await _kur(
      t,
      eldeki: _eskiHemen,
      taze: (_, gun) async => (seri: const <int, double>{}, bayatZaman: null),
    );
    await _gecis(t);
    expect(find.textContaining('110,00'), findsWidgets);
    expect(find.byType(SeriSonGuncelleme), findsOneWidget);
  });

  testWidgets('taze önce gelirse eski kopya yok sayılır', (t) async {
    final eski = Completer<({Map<int, double> seri, DateTime zaman})?>();
    await _kur(
      t,
      eldeki: (_, __) => eski.future,
      taze: (_, gun) async => (seri: _seri(gun, 120), bayatZaman: null),
    );
    eski.complete((seri: _seri(365, 110), zaman: _olculdu));
    await _gecis(t);
    expect(find.textContaining('120,00'), findsWidgets);
    expect(find.textContaining('110,00'), findsNothing);
    expect(_grafikOpakligi(t).opacity, 1.0);
  });

  testWidgets('eski kopya yoksa (çok eski / hiç) iskelet eskisi gibi',
      (t) async {
    final bekleyen =
        <Completer<({Map<int, double> seri, DateTime? bayatZaman})>>[];
    await _kur(
      t,
      eldeki: (_, __) async => null,
      taze: (_, __) {
        final c = Completer<({Map<int, double> seri, DateTime? bayatZaman})>();
        bekleyen.add(c);
        return c.future;
      },
    );
    expect(find.byType(VarlikIskeleti), findsOneWidget);
    for (final c in bekleyen) {
      c.complete((seri: const <int, double>{}, bayatZaman: null));
    }
    await t.pump();
  });

  testWidgets('hareketi azalt: soluktan nete geçiş ANINDA', (t) async {
    await _kur(
      t,
      hareketiAzalt: true,
      eldeki: _eskiHemen,
      taze: (_, __) =>
          Completer<({Map<int, double> seri, DateTime? bayatZaman})>().future,
    );
    await _gecis(t);
    expect(_grafikOpakligi(t).duration, Duration.zero);
  });
}
