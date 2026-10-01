import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/kiyas_provider.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/kiyas_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/kiyas_karti.dart';
import 'package:portfoy_takip/widgets/sandik_skeleton.dart';

/// "Başka yere koysaydın" kartı. Seriler provider override'ıyla verilir —
/// testte ağ yok.
void main() {
  const gun = 24 * 60 * 60 * 1000;
  final t0 = DateTime(2026, 9, 1).millisecondsSinceEpoch;
  final t1 = t0 + 10 * gun;

  KiyasGirdisi girdi({double? getiri = 20, bool temettu = false}) =>
      KiyasGirdisi(
        period: SummaryPeriod.birAy,
        start: DateTime.fromMillisecondsSinceEpoch(t0),
        end: DateTime.fromMillisecondsSinceEpoch(t1),
        basTRY: 1000,
        basTs: t0,
        sonTRY: 1200,
        sonTs: t1,
        akislar: const [],
        getiriPct: getiri,
        temettuVar: temettu,
      );

  setUpAll(() => initializeDateFormatting('tr_TR'));

  Future<void> kur(
    WidgetTester t,
    KiyasGirdisi g, {
    Future<Map<KiyasVarligi, Map<int, double>>> Function()? seriler,
    bool settle = true,
  }) async {
    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        kiyasSerileriProvider.overrideWith((ref, period) =>
            seriler?.call() ??
            Future.value({
              // Dolar serisi YOK → satır çizilmemeli.
              KiyasVarligi.altin: {t0: 100.0, t1: 130.0}, // %30 → 10 puan geride
              KiyasVarligi.bist100: {t0: 100.0, t1: 110.0}, // %10 → 10 puan önde
            })),
      ],
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(SandikSpace.smd),
            child: KiyasKarti(girdi: g),
          ),
        ),
      ),
    ));
    if (settle) {
      await t.pumpAndSettle();
    } else {
      await t.pump();
    }
  }

  Color? renk(WidgetTester t, String metin) =>
      t.widget<Text>(find.text(metin)).style?.color;

  testWidgets('satırlar: senin + hesaplanabilen kıyaslar; eksik seri gizli',
      (t) async {
    await kur(t, girdi());
    expect(find.text('Başka yere koysaydın'), findsOneWidget);
    expect(find.text('Senin portföyün'), findsOneWidget);
    expect(find.text('Gram altın'), findsOneWidget);
    expect(find.text('BIST 100'), findsOneWidget);
    expect(find.text('Dolar'), findsNothing,
        reason: 'Serisi olmayan kıyasın satırı çizilmez — "₺0" uydurulmaz.');
    expect(find.text('Aynı paraları aynı günlerde buraya yatırsaydın.'),
        findsOneWidget);
    // Getiriler yönlü yüzde, son değerler ₺.
    expect(find.text('+%20,00'), findsOneWidget);
    expect(find.text('+%30,00'), findsOneWidget);
    expect(find.text('+%10,00'), findsOneWidget);
    expect(find.text(fmtTRY(1300)), findsOneWidget);
  });

  testWidgets('fark: ok + kelime + renk (renk tek başına değil)', (t) async {
    await kur(t, girdi());
    final c = t.element(find.byType(KiyasKarti)).c;

    const geride = '▼ 10,0 puan gerisindesin';
    const onde = '▲ 10,0 puan önündesin';
    expect(find.text(geride), findsOneWidget);
    expect(find.text(onde), findsOneWidget);
    expect(renk(t, geride), c.loss);
    expect(renk(t, onde), c.gain);
  });

  testWidgets('sıfıra yuvarlanan fark "Başa baş", yönsüz renk', (t) async {
    await kur(t, girdi(getiri: 10.02));
    final c = t.element(find.byType(KiyasKarti)).c;
    expect(find.text('Başa baş'), findsOneWidget);
    expect(renk(t, 'Başa baş'), c.text36);
  });

  testWidgets('temettülü dönemde dipnot çizilir', (t) async {
    await kur(t, girdi(temettu: true));
    expect(find.textContaining('temettüler iki tarafta da cebine giren'),
        findsOneWidget);
  });

  testWidgets('yükleniyor: iskelet', (t) async {
    final bekle = Completer<Map<KiyasVarligi, Map<int, double>>>();
    await kur(t, girdi(), seriler: () => bekle.future, settle: false);
    expect(find.text('Başka yere koysaydın'), findsOneWidget);
    expect(find.byType(SandikSkeleton), findsWidgets);
    expect(find.text('Senin portföyün'), findsNothing);
  });

  testWidgets('hiçbir kıyas hesaplanamazsa boş hâl', (t) async {
    await kur(t, girdi(), seriler: () async => const {});
    expect(find.text('Kıyas için fiyat verisi şu an alınamadı.'),
        findsOneWidget);
    expect(find.text('Senin portföyün'), findsNothing);
  });

  testWidgets('kullanıcının getirisi yoksa kart hiç çizilmez', (t) async {
    await kur(t, girdi(getiri: null));
    expect(find.text('Başka yere koysaydın'), findsNothing);
  });
}

