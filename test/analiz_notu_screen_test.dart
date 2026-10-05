import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/analiz_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/analiz_notu_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Yapay zekâ notu ekranı — sunucu kapısı ile istemci kilidi ayrışınca.
///
/// Premium açılışında `premium_ayar.kapi_acik` sunucuda, `paywall_enabled`
/// istemcide (Remote Config) açılır. İkisi bir an ayrışabilir (RC henüz
/// gelmemiş/okunamamış): istemci kilitsiz sanır, sunucu satırı gizler.
/// Başlık listeden geldiyse not vardır; ekran "açılamadı" hatası değil
/// kilit satırını göstermeli.
void main() {
  final donem = DateTime.utc(2026, 9, 28);

  Future<void> kur(WidgetTester tester, {String? baslik}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        radarKilitliProvider.overrideWithValue(false),
        varlikNotuProvider.overrideWith((ref, a) async => null),
      ],
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AnalizNotuScreen(
          ticker: 'TEFAS:TTE',
          tur: 'haftalik',
          donem: donem,
          kod: 'TTE',
          baslik: baslik,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('başlık var, satır boş → kilit satırı (hata değil)',
      (tester) async {
    await kur(tester, baslik: 'TTE bu hafta güçlü giriş aldı');
    final l10n =
        AppLocalizations.of(tester.element(find.byType(AnalizNotuScreen)))!;
    expect(find.text('TTE bu hafta güçlü giriş aldı'), findsOneWidget);
    expect(find.text(l10n.prmKilitNot), findsOneWidget);
    expect(find.text(l10n.anzOkunamadi), findsNothing);
  });

  testWidgets('başlık yok, satır boş → "okunamadı"', (tester) async {
    await kur(tester);
    final l10n =
        AppLocalizations.of(tester.element(find.byType(AnalizNotuScreen)))!;
    expect(find.text(l10n.anzOkunamadi), findsOneWidget);
    expect(find.text(l10n.prmKilitNot), findsNothing);
  });
}
