@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/zirve_portfoyler_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Zirve "Neden henüz havuzda değilsin?" kartı (0143) — önce/sonra görseli.
/// `build/gorsel/` altına PNG; assert etmez, `gorsel` etiketi CI'da atlanır.
///   GORSEL_AD=sonra flutter test --run-skipped test/zirve_katilim_gorsel_test.dart

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
      id: 'u1', email: 'a@b.c', displayName: 'Test', createdAt: DateTime(2026));
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: const <Asset>[], usdTry: 42, eurTry: 46, gbpTry: 54);
}

void main() {
  setUpAll(() async {
    DbLogger.silentInTests = true;
    final dm = FontLoader(kSandikFontFamily);
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      dm.addFont(rootBundle.load('assets/fonts/DMSans-$w.ttf'));
    }
    await dm.load();
    final ikon = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await ikon.load();
  });

  final ad = Platform.environment['GORSEL_AD'] ?? 'sonra';
  // Yeni hesap + eski tarihli varlık (yasin'in üç test hesabının durumu).
  final simdi = DateTime.now().toUtc();
  final ZirveKatilimDurumu durum = (
    hesapHazir: simdi.add(const Duration(days: 6, hours: 19)),
    varlikHazir: DateTime.utc(2025, 12, 1),
    olcumHazir: DateTime.utc(2025, 12, 26),
    varlikSayisi: 4,
    olculdu: true,
    havuzda: false,
  );
  for (final b in [Brightness.dark, Brightness.light]) {
    for (final olcek in [1.0, 2.0]) {
      testWidgets('zirve katılım — ${b.name} ${olcek}x', (tester) async {
        tester.view.physicalSize = const Size(390 * 2, 844 * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);
        const k = Key('kok');
        await tester.pumpWidget(ProviderScope(
          overrides: [
            authProvider.overrideWith(_FakeAuth.new),
            portfolioProvider.overrideWith(_FakePortfolio.new),
          ],
          child: RepaintBoundary(
            key: k,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: SandikApp.buildTheme(
                  b == Brightness.dark ? SandikPalette.dark : SandikPalette.light,
                  b),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(olcek)),
                child: child!,
              ),
              home: Scaffold(
                body: SafeArea(
                  child: ZirveGovdesi(
                    donem: ZirveDonem.ay,
                    onDonem: (_) {},
                    rizaYukleyici: () async => true,
                    durumYukleyici: (_) async => durum, // GORSEL_DURUM
                  ),
                ),
              ),
            ),
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.runAsync(() async {
          final r = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
          final img = await r.toImage(pixelRatio: 1.0);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          Directory('build/gorsel').createSync(recursive: true);
          File('build/gorsel/zirve_katilim_${ad}_${b.name}_${olcek}x.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
