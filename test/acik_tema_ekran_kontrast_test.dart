import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/screens/forgot_password_screen.dart';
import 'package:portfoy_takip/screens/legal_doc_screen.dart';
import 'package:portfoy_takip/screens/login_screen.dart';
import 'package:portfoy_takip/screens/otp_verification_screen.dart';
import 'package:portfoy_takip/screens/register_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/fiyat_grafigi.dart';
import 'package:portfoy_takip/widgets/percent_comparison_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kontrast_denetimi.dart';

/// Açık temada hiç gözle görülmemiş ekranlar (TECHNICAL_DEBT "Light mode",
/// 2026-10-08): her metin arkasındaki gerçek zemine karşı ≥ 4,5:1
/// (büyük metin 3:1). Varsayılan tema `ThemeMode.system` olduğundan açık
/// temalı telefonlar bu ekranları artık görüyor.
///
/// Aynı denetim koyu temada da koşar — düzeltmeler koyu temayı bozmasın.
class _OturumYok extends AuthNotifier {
  @override
  Future<AppUser?> build() async => null;
}

const _belge = [
  LegalBlock.h1('Kullanım Koşulları'),
  LegalBlock.meta('Sürüm 1.4 · Yürürlük 2026-10-04'),
  LegalBlock.h2('1. Taraflar'),
  LegalBlock.p('Bu metin uygulamanın gerçek davranışını anlatır.'),
  LegalBlock.h3('1.1 Tanımlar'),
  LegalBlock.p('• Madde işaretli satır'),
  LegalBlock.divider(),
  LegalBlock.tableHeader(['Veri', 'Amaç', 'Süre']),
  LegalBlock.tableRow(['E-posta', 'Giriş', 'Hesap süresince']),
  LegalBlock.tableRow(['Portföy', 'Hesaplama', 'Hesap süresince']),
];

Future<void> _kur(WidgetTester tester, Brightness b, Widget ekran) async {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final p = b == Brightness.light ? SandikPalette.light : SandikPalette.dark;
  await tester.pumpWidget(ProviderScope(
    key: ValueKey(b),
    overrides: [authProvider.overrideWith(_OturumYok.new)],
    child: MaterialApp(
      locale: const Locale('tr', 'TR'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: SandikApp.buildTheme(p, b),
      home: ekran,
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _denetle(WidgetTester tester, Brightness b, {Set<String> haric = const {}}) {
  final p = b == Brightness.light ? SandikPalette.light : SandikPalette.dark;
  expect(olculenMetinSayisi(tester), greaterThan(2),
      reason: 'Denetim boş geçti — ekran metin çizmedi.');
  final bulgular =
      kontrastDenetle(tester, varsayilanZemin: p.background, haric: haric);
  expect(bulgular, isEmpty, reason: bulgular.join('\n'));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    // Gerçek yazı tipi: test yazı tipi (Ahem) her glifi kare çizer ve
    // giriş ekranının "Beni hatırla" satırını taşırır — konumuz değil.
    final dm = FontLoader(kSandikFontFamily);
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      dm.addFont(rootBundle.load('assets/fonts/DMSans-$w.ttf'));
    }
    await dm.load();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final ekranlar = <String, Widget Function()>{
    'yasal belge': () => const LegalDocScreen(
        title: 'Kullanım Koşulları',
        blocks: _belge,
        icon: Icons.gavel_rounded),
    'yasal belge — zorunlu okuma': () => const LegalDocScreen(
        title: 'Kullanım Koşulları',
        blocks: _belge,
        icon: Icons.gavel_rounded,
        zorunluOkuma: true),
    'giriş': () => const LoginScreen(),
    'kayıt': () => const RegisterScreen(),
    'kod doğrulama': () =>
        const OtpVerificationScreen(email: 'deneme@example.com'),
    'şifremi unuttum': () => const ForgotPasswordScreen(),
  };

  // Bilinçli istisnalar — WCAG 1.4.3 pasif (devre dışı) bileşeni kapsam
  // dışı tutar. Boş formda "Kayıt Ol" pasiftir: amber %45 dolgu, koyu
  // temada 2,25:1. Form dolunca %92 dolguya geçer ve eşiği geçer.
  const haric = {
    'kayıt': {'Kayıt Ol'},
  };

  for (final b in Brightness.values) {
    group(b == Brightness.light ? 'açık tema' : 'koyu tema', () {
      for (final e in ekranlar.entries) {
        testWidgets('${e.key}: metinler zeminine karşı AA', (tester) async {
          await _kur(tester, b, e.value());
          _denetle(tester, b, haric: haric[e.key] ?? const {});
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(minutes: 1));
        });
      }
    });
  }

  // ── Grafikler: crosshair hapı ───────────────────────────────────────────
  //
  // Hap (fiyat/tarih + ayrıntı satırları) eskiden iki modda da sabit koyu
  // zemindi; ayrıntı satırlarının renkleri ise temadan geliyordu. Açık
  // temada koyu `loss`/`text58` koyu hap üstünde okunmuyordu.
  final bas = DateTime(2026, 9, 1).millisecondsSinceEpoch;
  Map<int, double> seri(double egim) => {
        for (var g = 0; g <= 30; g++)
          bas + g * Duration.millisecondsPerDay: 100 + egim * g,
      };
  NormalizedSeries norm(double egim) => normalizeSeries(seri(egim))!;

  Future<TestGesture> crosshairAc(WidgetTester tester, Finder grafik) async {
    final kutu = tester.getRect(grafik);
    final g = await tester.startGesture(
        Offset(kutu.left + kutu.width * 0.6, kutu.center.dy));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    return g;
  }

  for (final b in Brightness.values) {
    final ad = b == Brightness.light ? 'açık tema' : 'koyu tema';
    testWidgets('$ad karşılaştırma grafiği: crosshair hapı AA',
        (tester) async {
      await _kur(
        tester,
        b,
        Builder(builder: (context) {
          final p = context.c;
          // Karşılaştır ekranının seri paleti (`_seriesColors`) — koyu
          // zemin için seçilmiş, açık temada beyaz üstünde 2:1'e iner.
          final renkler = [
            p.amberFill,
            p.info,
            p.gold,
            const Color(0xFF9B8AFB),
            const Color(0xFF4DD0C7),
          ];
          const anahtarlar = ['A', 'B', 'C', 'D', 'E'];
          return Scaffold(
            body: Center(
              child: PercentComparisonChart(
                series: {
                  for (var i = 0; i < anahtarlar.length; i++)
                    anahtarlar[i]: norm(i - 2.0),
                },
                order: anahtarlar,
                periodDays: 30,
                colorOf: (k) => renkler[anahtarlar.indexOf(k)],
                labelOf: (k) => 'Seri $k',
              ),
            ),
          );
        }),
      );
      final g = await crosshairAc(tester, find.byType(PercentComparisonChart));
      expect(find.textContaining('Seri E'), findsWidgets,
          reason: 'crosshair hapı açılmadı');
      _denetle(tester, b);
      await g.up();
      await tester.pump();
    });

    testWidgets('$ad fiyat grafiği: crosshair hapı AA', (tester) async {
      await _kur(
        tester,
        b,
        Scaffold(
          body: Center(
            child: FiyatGrafigi(
              seri: seri(-1.5),
              periodDays: 30,
              bicim: NumberFormat('#,##0.00', 'tr_TR'),
              semanticLabel: 'fiyat',
            ),
          ),
        ),
      );
      final g = await crosshairAc(tester, find.byType(FiyatGrafigi));
      expect(find.textContaining('%'), findsWidgets,
          reason: 'crosshair hapı açılmadı');
      _denetle(tester, b);
      await g.up();
      await tester.pump();
    });
  }
}
