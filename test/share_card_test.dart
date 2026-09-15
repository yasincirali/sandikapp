import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/services/recap_service.dart'
    show PortfolioCharacter;
import 'package:portfoy_takip/services/share_card_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/share_card.dart';

/// Paylaşım kartı — "Özetini paylaş" artık dört satır metin değil, önizlemeli
/// görsel kart. Üç değişmez:
/// - kart SABİT boyutta ve hiçbir veri kombinasyonunda taşmaz;
/// - kartta TUTAR yok (kaynak taraması);
/// - RepaintBoundary'den gerçekten PNG üretilir.
Future<void> _pump(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.dark}) async {
  tester.view.physicalSize = const Size(400 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      extensions: [
        brightness == Brightness.dark
            ? SandikPalette.dark
            : SandikPalette.light,
      ],
    ),
    home: Scaffold(body: Center(child: child)),
  ));
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  final tam = ShareCardData(
    baslik: 'Son 1 yıl',
    degisimPct: 47.3456,
    degisimEtiketi: 'Piyasa getirim',
    karakter: PortfolioCharacter.dengeli,
    enflasyonPuan: 12.7,
    takipGunu: 365,
    percentile: 12,
  );

  group('ShareCard yerleşimi', () {
    testWidgets('tam veri — taşma yok', (tester) async {
      await _pump(tester, ShareCard(data: tam, tarih: DateTime(2026, 9, 14)));
      expect(tester.takeException(), isNull);
      expect(find.text('+%47,35'), findsOneWidget);
      expect(
          find.textContaining("Yatırımcıların %88'inden iyi"), findsOneWidget);
      expect(find.textContaining('12,7 puan önünde'), findsOneWidget);
      expect(find.text('365 gün takip'), findsOneWidget);
    });

    testWidgets('negatif ve enflasyon gerisinde', (tester) async {
      await _pump(
        tester,
        ShareCard(
          data: const ShareCardData(
            baslik: 'Son 1 ay',
            degisimPct: -3.2,
            enflasyonPuan: -5.3,
          ),
          tarih: DateTime(2026, 9, 14),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('−%3,20'), findsOneWidget);
      expect(find.textContaining('5,3 puan gerisinde'), findsOneWidget);
    });

    testWidgets('yalnızca başlık — boş alanlar çizilmez, taşma yok',
        (tester) async {
      await _pump(
          tester, ShareCard(data: const ShareCardData(baslik: 'Son 1 hafta')));
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.groups_rounded), findsNothing);
    });

    testWidgets('çok uzun başlık ve 1,6× metin ölçeği taşmaz', (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark]),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: Center(
              child: ShareCard(
                data: ShareCardData(
                  baslik: 'sandık Özetim 2026 — çok uzun bir başlık denemesi',
                  degisimPct: 1234.5,
                  karakter: PortfolioCharacter.foncu,
                  enflasyonPuan: 3,
                  takipGunu: 12,
                  percentile: 50,
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('light temada da koyu kart — alıcı temayı bilmez',
        (tester) async {
      await _pump(tester, ShareCard(data: tam), brightness: Brightness.light);
      final box = tester.widget<Container>(find.byType(Container).first);
      final deco = box.decoration! as BoxDecoration;
      expect((deco.gradient! as LinearGradient).colors.first,
          SandikPalette.dark.background);
    });

    testWidgets('boyut sabit 320×400', (tester) async {
      await _pump(tester, ShareCard(data: tam));
      expect(tester.getSize(find.byType(ShareCard)), const Size(320, 400));
    });
  });

  testWidgets('RepaintBoundary\'den PNG üretilir', (tester) async {
    final key = GlobalKey();
    await _pump(tester, RepaintBoundary(key: key, child: ShareCard(data: tam)));
    final bytes = await tester.runAsync(() => ShareCardService.renderPng(key));
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(1000));
    // PNG imzası.
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(
        key.currentContext!.findRenderObject(), isA<RenderRepaintBoundary>());
  });

  testWidgets('paylaşım sayfası: önizleme + iki yol', (tester) async {
    await _pump(
      tester,
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => showShareSheet(
            ctx,
            data: tam,
            metin: 'x',
            subject: 's',
            analyticsPeriod: 'birYil',
          ),
          child: const Text('aç'),
        ),
      ),
    );
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    expect(find.byType(ShareCard), findsOneWidget);
    expect(find.text('Görsel olarak paylaş'), findsOneWidget);
    expect(find.text('Metin olarak paylaş'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });


  // ── Gerçek sayfa yapısı: FittedBox içinde RepaintBoundary ───────────────
  //
  // `showShareSheet` kartı `FittedBox(fit: scaleDown)` içine koyuyor (dar
  // ekranda önizleme küçülsün diye). Yukarıdaki PNG testi boundary'yi
  // DOĞRUDAN pump ediyor, yani o sarmalayıcıyı hiç sınamıyordu.
  testWidgets('FittedBox küçültmesi altında PNG üretilebiliyor',
      (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: RepaintBoundary(key: key, child: ShareCard(data: tam)),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    final bytes = await tester.runAsync(() => ShareCardService.renderPng(key));
    expect(bytes, isNotNull);
    expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(tester.takeException(), isNull);
  });

  test('kartta TUTAR yok — kaynak taraması', () {
    // Yorum satırları taranmaz — kural KOD içindir.
    final src = File('lib/widgets/share_card.dart')
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    for (final yasak in ['fmtTRY', 'tryFormatter', 'BazPara', '₺', 'toTRY']) {
      expect(src.contains(yasak), isFalse, reason: '$yasak kartta olamaz');
    }
  });


  // ── Hata yutulmuyor ─────────────────────────────────────────────────────
  //
  // Sahadan "Performans → yıllık özet → paylaş hata veriyor" bildirimi
  // geldi (2026-09-16) ve elde TEK BİR İZ yoktu:
  //   · görsel yolunda `catch` vardı ama yalnızca snackbar basıyordu —
  //     `friendlyError` tanımadığı hatayı genel bir cümleye çeviriyor,
  //     yani gerçek sebep hiçbir yere yazılmıyordu;
  //   · metin yolunda `catch` HİÇ YOKTU — `Share.share` fırlatırsa
  //     kullanıcı butona basıyor ve hiçbir şey olmuyordu.
  //
  // Bu testler iki yolun da sözleşmesini kilitler: kaynakta CrashReporter
  // çağrısı VAR ve iki yol da korumalı. Davranışın kendisi (platform
  // kanalı fırlattığında ne olur) widget testinde kurulamıyor — kanal
  // sahtesi share_plus'ın iç yapısına bağımlı olurdu ve o yapı sürümle
  // değişiyor; korunması gereken şey yapının varlığı.
  group('paylaşım hataları yutulmuyor', () {
    late String src;

    setUpAll(() {
      src = File('lib/widgets/share_card.dart')
          .readAsLinesSync()
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .join('\n');
    });

    test('görsel yolu Crashlytics\'e bildiriyor', () {
      expect(src.contains("CrashReporter.report(e, st, reason: 'share image')"),
          isTrue,
          reason: 'görsel paylaşımı sessizce düşerse sahada iz kalmaz');
    });

    test('metin yolu da korumalı ve bildiriyor', () {
      expect(src.contains("CrashReporter.report(e, st, reason: 'share text')"),
          isTrue,
          reason: 'metin yolunda catch YOKTU — hata tümden görünmezdi');
    });

    test('iki yol da kullanıcıya friendlyError gösteriyor', () {
      // Ham `$e` kullanıcıya gösterilmez (CLAUDE.md hata gösterimi kuralı).
      expect('friendlyError(e)'.allMatches(src).length, greaterThanOrEqualTo(2),
          reason: 'her iki yol da kullanıcıya anlaşılır mesaj vermeli');
      expect(src.contains(r'sandikSnack(context, $e'), isFalse);
    });
  });

  test('ShareCardData.bos', () {
    expect(const ShareCardData(baslik: 'x').bos, isTrue);
    expect(const ShareCardData(baslik: 'x', takipGunu: 0).bos, isTrue);
    expect(tam.bos, isFalse);
  });
}
