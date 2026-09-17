import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/widgets/review_prompt_sheet.dart';

/// Değerlendirme isteminin sunum sözleşmesi.
///
/// Karar mantığı `review_prompt_test`'te; burada yalnızca "üç yol da
/// görünür ve dokunulabilir" sabitlenir. Mağaza kurallarının hassas
/// olduğu nokta şu: kullanıcıya kaçış yolu bırakmayan ("puan ver" tek
/// düğme) bir istem manipülatif sayılır. "Sonra" ve "Bir sorun var" bu
/// yüzden isteğe bağlı süs değil, sözleşmenin parçasıdır.
void main() {
  Future<void> pump(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      theme: ThemeData.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: ReviewPromptSheet()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Türkçe: soru + üç seçenek görünür', (tester) async {
    await pump(tester, const Locale('tr', 'TR'));
    expect(find.text("sandık'ı seviyor musun?"), findsOneWidget);
    expect(find.text('Evet, değerlendir'), findsOneWidget);
    expect(find.text('Sonra'), findsOneWidget);
    expect(find.text('Bir sorun var'), findsOneWidget);
  });

  testWidgets('İngilizce: aynı üç yol', (tester) async {
    await pump(tester, const Locale('en', 'US'));
    expect(find.text('Enjoying sandık?'), findsOneWidget);
    expect(find.text('Yes, rate it'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text("Something's off"), findsOneWidget);
  });

  testWidgets('yalvarma dili yok — "5 yıldız" / "lütfen" geçmez',
      (tester) async {
    await pump(tester, const Locale('tr', 'TR'));
    final metinler = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => (t.data ?? '').toLowerCase())
        .join(' ');
    expect(metinler.contains('yıldız'), isFalse);
    expect(metinler.contains('lütfen'), isFalse);
  });

  testWidgets('düğmeler 44pt dokunma hedefi sağlar', (tester) async {
    await pump(tester, const Locale('tr', 'TR'));
    for (final etiket in const ['Evet, değerlendir', 'Sonra', 'Bir sorun var']) {
      final boyut = tester.getSize(find.ancestor(
        of: find.text(etiket),
        matching: find.byWidgetPredicate(
            (w) => w is FilledButton || w is TextButton),
      ));
      expect(boyut.height, greaterThanOrEqualTo(44), reason: etiket);
    }
  });
}
