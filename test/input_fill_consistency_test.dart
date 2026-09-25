import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Giriş alanı dolgusu tek kaynaktan gelir (kullanıcı kararı 2026-09-25:
/// "uygulama içi tüm inputfield'larda uygulanmalı").
///
/// Kural `context.inputFill`'de yazılı: dark'ta dolgu yok + hairline çerçeve,
/// light'ta `surface2`. Tema varsayılanı (`inputDecorationTheme`) ve
/// `context.inputDecoration` aynı kuralı izler. Bir ekran kendi
/// `fillColor:`'unu (`overlay`, `surface1`…) verirse o alan bulunduğu
/// zeminde yine "içi farklı renk" görünür — dört kez şikâyet edildi.
///
/// İkinci desen: kendi `Container`'ı dolgu+çerçeve çizen bir kutunun
/// içindeki `TextField` (kenarlığı `InputBorder.none`) `filled: false`
/// demezse tema dolgusu kutunun içinde ikinci bir dikdörtgen çizer.
///
/// Üçüncü desen: Material teması OKUNMAYAN alan kutuları —
/// `CupertinoTextField`'ın `BoxDecoration`'ı, `DropdownButton`'u saran kutu,
/// alan gibi görünen seçici (`_selectorContainer`). Bunlar dolguyu elle
/// yazar; tek meşru değer `inputFill`. 2026-09-25 taramasında iki tanesi
/// (`alarm_kur_sheet` dropdown'u `surface2`, Varlık Ekle seçicisi
/// `surface1`) kuralın dışında kalmıştı.
///
/// Kaynak taraması "yazılmış mı"yı, davranış testleri (alttaki grup)
/// "gerçek temayla çizilince gerçekten o renk mi"yi yanıtlar.
void main() {
  // Üç tarama aynı dosyaları okur — bir kez oku.
  late final Map<String, List<String>> kaynaklar = {
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) {
      final p = f.path.replaceAll(r'\', '/');
      // Tema tanımı (`lib/theme/`, `main.dart` → `buildTheme`) kuralın
      // kaynağıdır; tarama tüketicileri denetler.
      return !p.contains('lib/theme/') &&
          !p.endsWith('lib/main.dart') &&
          !p.contains('/generated/');
    }))
      f.path: f.readAsLinesSync(),
  };

  test('ekranlar fillColor yazmaz — dolgu temadan', () {
    final ihlal = <String>[];
    for (final MapEntry(key: yol, value: satirlar) in kaynaklar.entries) {
      for (var i = 0; i < satirlar.length; i++) {
        final s = satirlar[i].trim();
        if (s.startsWith('//')) continue;
        // Satır başında değil HER yerde: `.copyWith(fillColor: …)` ya da
        // tek satırlık `InputDecoration(filled: true, fillColor: …)` da
        // aynı kaçak. Dolgu temadan gelir; ekranda hiç yazılmaz.
        if (RegExp(r'\bfillColor\s*:').hasMatch(s)) {
          ihlal.add('$yol:${i + 1}  $s');
        }
      }
    }
    expect(ihlal, isEmpty,
        reason: 'Giriş alanı dolgusu temadan (`sandikGirisTemasi`) gelmeli; '
            '`fillColor` satırını sil.\n${ihlal.join('\n')}');
  });

  test('kenarlıksız (kutu içi) TextField tema dolgusunu kapatır', () {
    final ihlal = <String>[];
    for (final MapEntry(key: yol, value: satirlar) in kaynaklar.entries) {
      for (var i = 0; i < satirlar.length; i++) {
        if (!satirlar[i].contains('border: InputBorder.none')) continue;
        final bas = (i - 12).clamp(0, satirlar.length);
        final son = (i + 12).clamp(0, satirlar.length);
        final blok = satirlar.sublist(bas, son).join('\n');
        if (!blok.contains('filled: false')) {
          ihlal.add('$yol:${i + 1}');
        }
      }
    }
    expect(ihlal, isEmpty,
        reason: 'Kenarlığı kapatılmış alan bir kutunun içinde demektir; '
            '`filled: false` eklenmezse tema dolgusu kutunun içinde ikinci '
            'bir renk çizer.\n${ihlal.join('\n')}');
  });

  test('temayı okumayan alan kutuları (Cupertino, dropdown) inputFill kullanır',
      () {
    final ihlal = <String>[];
    for (final MapEntry(key: yol, value: satirlar) in kaynaklar.entries) {
      for (var i = 0; i < satirlar.length; i++) {
        final s = satirlar[i];
        // CupertinoTextField: `decoration: BoxDecoration(...)` alanın
        // ARDINDAN gelir → ileriye bak.
        if (s.contains('CupertinoTextField(')) {
          final son = (i + 25).clamp(0, satirlar.length);
          final blok = satirlar.sublist(i, son).join('\n');
          if (blok.contains('BoxDecoration(') && !blok.contains('inputFill')) {
            ihlal.add('$yol:${i + 1}  CupertinoTextField');
          }
        }
        // DropdownButton'u saran kutu alanın ÖNÜNDE durur → geriye bak.
        if (RegExp(r'\bDropdownButton(<[^>]*>)?\(').hasMatch(s)) {
          final bas = (i - 12).clamp(0, satirlar.length);
          final blok = satirlar.sublist(bas, i).join('\n');
          if (blok.contains('BoxDecoration(') && !blok.contains('inputFill')) {
            ihlal.add('$yol:${i + 1}  DropdownButton kutusu');
          }
        }
      }
    }
    expect(ihlal, isEmpty,
        reason: 'Material teması bu alanlara ulaşmaz; kutunun dolgusu elle '
            '`context.inputFill` olmalı.\n${ihlal.join('\n')}');
  });

  group('gerçek temayla çizilen alan', () {
    // Sahte `ThemeData` değil, uygulamanın kendi teması: varsayılan
    // değişirse test onu görür.
    Future<void> pumpAlan(
      WidgetTester tester,
      Brightness b,
      Widget Function(BuildContext) alan,
    ) async {
      final p = b == Brightness.light ? SandikPalette.light : SandikPalette.dark;
      await tester.pumpWidget(MaterialApp(
        theme: SandikApp.buildTheme(p, b),
        home: Scaffold(body: Builder(builder: alan)),
      ));
    }

    InputDecoration dekor(WidgetTester tester) =>
        tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;

    Color kenar(InputBorder? b) => (b! as OutlineInputBorder).borderSide.color;

    for (final b in Brightness.values) {
      final p = b == Brightness.light ? SandikPalette.light : SandikPalette.dark;
      final beklenenDolgu =
          b == Brightness.light ? p.surface2 : const Color(0x00000000);

      testWidgets('${b.name}: dekorasyonsuz TextField = inputFill + hairline',
          (tester) async {
        late BuildContext ctx;
        await pumpAlan(tester, b, (c) {
          ctx = c;
          return const TextField();
        });
        final d = dekor(tester);
        expect(ctx.inputFill, beklenenDolgu);
        expect(d.filled, isTrue);
        expect(d.fillColor, ctx.inputFill);
        expect(kenar(d.enabledBorder), p.hairline);
        expect(kenar(d.focusedBorder), p.amberFill);
      });

      testWidgets('${b.name}: context.inputDecoration temayla aynı',
          (tester) async {
        late BuildContext ctx;
        await pumpAlan(tester, b, (c) {
          ctx = c;
          return TextField(decoration: c.inputDecoration('ara'));
        });
        final d = dekor(tester);
        expect(d.fillColor, ctx.inputFill);
        expect(kenar(d.enabledBorder), p.hairline);
        expect(kenar(d.disabledBorder), kenar(Theme.of(ctx)
            .inputDecorationTheme
            .disabledBorder));
      });

      testWidgets('${b.name}: kilitli alan temanın hairline\'ını çizer',
          (tester) async {
        await pumpAlan(tester, b, (_) => const TextField(enabled: false));
        final d = dekor(tester);
        // Material'ın onSurface %12 varsayılanı değil, paletin hairline'ı.
        // Yarım hairline dark'ta alanı yok ediyordu (gerekçe
        // `sandikGirisTemasi`); kilidi metin anlatır.
        expect(kenar(d.disabledBorder), p.hairline);
      });
    }
  });

  group('Varlık Ekle → Altın alt sayfası (gerçek tema)', () {
    setUpAll(() => initializeDateFormatting('tr_TR'));
    setUp(() => SharedPreferences.setMockInitialValues({}));

    for (final b in Brightness.values) {
      testWidgets('${b.name}: seçici inputFill, kutu içi arama filled=false',
          (tester) async {
        final p =
            b == Brightness.light ? SandikPalette.light : SandikPalette.dark;
        tester.view.physicalSize = const Size(375 * 3, 812 * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          overrides: [
            portfolioProvider.overrideWith(() => _BosPortfoy()),
            addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
          ],
          child: MaterialApp(
            theme: SandikApp.buildTheme(p, b),
            home: const AddAssetScreen(prefillType: AssetType.altin),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final tetik = find.text('Altın türü seçmek için dokun...');
        final ctx = tester.element(tetik);
        // Seçici kutusu: alan gibi görünür → alanlarla aynı dolgu/kenar.
        final kutu = tester.widget<Container>(find
            .ancestor(of: tetik, matching: find.byType(Container))
            .first);
        final bd = kutu.decoration! as BoxDecoration;
        expect(bd.color, ctx.inputFill);
        expect((bd.border! as Border).top.color, p.hairline);

        await tester.tap(tetik);
        await tester.pumpAndSettle();
        expect(find.text('Altın Türleri'), findsOneWidget);

        // Alt sayfadaki arama: dolgu dıştaki kutuda, alanın kendisinde değil.
        final arama = find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(InputDecorator));
        final d = tester.widget<InputDecorator>(arama.last).decoration;
        expect(d.filled, isFalse);

        // Seçim yapılınca kutu varlık rengiyle parlar. Dolgu dark'ta
        // şeffaf olduğundan normal gölge kutunun İÇİNİ boyardı; yalnız
        // dışarıda (`BlurStyle.outer`) kalmalı.
        await tester.enterText(arama.last, 'gremse');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Gremse Altın'));
        await tester.pumpAndSettle();
        final secili = find
            .ancestor(
                of: find.text('Gremse Altın'), matching: find.byType(Container))
            .evaluate()
            .map((e) => (e.widget as Container).decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.boxShadow != null);
        expect(secili.color, ctx.inputFill);
        expect(secili.boxShadow!.map((s) => s.blurStyle),
            everyElement(BlurStyle.outer));
      });
    }
  });
}

class _BosPortfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: const <Asset>[], usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

class _NoLookup implements AddAssetPriceLookup {
  const _NoLookup();
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => null;
  @override
  Future<String?> companyName(String ticker) async => null;
}
