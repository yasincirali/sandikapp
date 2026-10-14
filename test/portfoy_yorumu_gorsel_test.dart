@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/portfoy_yorumu_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/portfoy_yorumu_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/portfoy_yorumu_karti.dart';

/// AI yorumu kartı (0151) — önce/sonra GÖRSEL önizlemesi, `build/gorsel/`
/// altına PNG. Assert etmez; `gorsel` etiketi CI'da atlanır.
///   flutter test --run-skipped test/portfoy_yorumu_gorsel_test.dart
///
/// Yorum metinleri ÖRNEKTİR (talimatın kurallarıyla elle yazıldı, model
/// çıktısı değil); sayılar demo.

const _olcumler = [
  YorumOlcumu('getiri', 'Dönem getirisi', '+%9,8'),
  YorumOlcumu('tufe', 'Son açıklanan aylarda TÜFE (Tem–Eyl)', '%7,9'),
  YorumOlcumu('reel_getiri', 'Aynı aylarda enflasyondan arındırılmış (reel) getiri', '+%1,6'),
  YorumOlcumu('kiyas_altin', 'Aynı paralar aynı günlerde gram altın yatırılsaydı getiri', '+%14,1'),
  YorumOlcumu('kiyas_altin_fark', 'Portföyün gram altın kıyasına göre farkı', '−4,3 puan'),
  YorumOlcumu('kiyas_bist100', 'Aynı paralar aynı günlerde BIST 100 yatırılsaydı getiri', '+%6,2'),
  YorumOlcumu('en_buyuk_pay', 'Dönem sonunda en büyük pay: THYAO', '%38,5'),
  YorumOlcumu('en_derin_dusus', 'Dönem içindeki en derin geri çekilme', '−%7,4'),
];

PortfoyYorumPaketi _paket(YorumTuru tur) => PortfoyYorumPaketi(
      tur: tur,
      baslangic: DateTime(2026, 7, 14),
      bitis: DateTime(2026, 10, 14),
      parmakIzi: 'v1:a',
      olcumler: _olcumler,
      donemKodu: tur == YorumTuru.secili ? '3A' : null,
    );

PortfoyYorumu _portfoyYorumu() => PortfoyYorumu(
      tur: YorumTuru.secili,
      baslangic: DateTime(2026, 7, 14),
      bitis: DateTime(2026, 10, 14),
      parmakIzi: 'v1:a',
      baslik: 'Portföyün son üç ayda +%9,8 ile enflasyonun önünde kaldı, ama paranın altında getireceğinin gerisinde.',
      maddeler: const [
        (
          metin: 'Tem–Eyl aylarında TÜFE %7,9 iken reel getirin +%1,6: alım gücün korunmuş, üstüne az da olsa eklenmiş.',
          kanit: ['tufe', 'reel_getiri'],
        ),
        (
          metin: 'Aynı paralar aynı günlerde gram altına konsaydı getiri +%14,1 olurdu; portföyün bu kıyasın −4,3 puan gerisinde. BIST 100 kıyası +%6,2 ile portföyün altında kaldı.',
          kanit: ['kiyas_altin', 'kiyas_altin_fark', 'kiyas_bist100'],
        ),
        (
          metin: 'Getirinin yükünü %38,5 payla THYAO taşıdı; dönem içindeki en derin geri çekilme −%7,4 oldu.',
          kanit: ['en_buyuk_pay', 'en_derin_dusus'],
        ),
      ],
      olcumler: _olcumler,
      olusturuldu: DateTime(2026, 10, 14, 14, 32),
    );

PortfoyYorumu _varlikYorumu() => PortfoyYorumu(
      tur: YorumTuru.secili,
      baslangic: DateTime(2026, 7, 14),
      bitis: DateTime(2026, 10, 14),
      parmakIzi: varlikParmakIzi('hisse|THYAO|TRY', 100),
      baslik: 'THYAO son üç ayda +%11,4 değer kazandı ve dönem zirvesinin −%4,8 altında duruyor.',
      maddeler: const [
        (
          metin: 'Aynı dönemde BIST 100 +%6,0, dolar +%3,1 değişti; hisse ikisinin de önünde, gram altının (+%14,9) ise gerisinde kaldı.',
          kanit: ['degisim', 'kiyas_bist100', 'kiyas_dolar', 'kiyas_altin'],
        ),
        (
          metin: 'Yol düz değildi: yıllıklandırılmış oynaklık %31,2, en derin geri çekilme −%9,4.',
          kanit: ['oynaklik', 'en_derin_dusus'],
        ),
        (
          metin: 'Portföyündeki payı %23,5; ilk alımdan bu yana 412 günde pozisyonun +%48,2 getirdi.',
          kanit: ['portfoy_payi', 'elde_tutma', 'pozisyon_getirisi'],
        ),
      ],
      olcumler: const [
        YorumOlcumu('degisim', 'Dönem içinde fiyat değişimi', '+%11,4'),
        YorumOlcumu('kiyas_bist100', 'Aynı dönemde BIST 100 değişimi', '+%6,0'),
        YorumOlcumu('kiyas_dolar', 'Aynı dönemde Amerikan doları değişimi', '+%3,1'),
        YorumOlcumu('kiyas_altin', 'Aynı dönemde gram altın değişimi', '+%14,9'),
        YorumOlcumu('oynaklik', 'Yıllıklandırılmış oynaklık', '%31,2'),
        YorumOlcumu('en_derin_dusus', 'Dönem içindeki en derin geri çekilme', '−%9,4'),
        YorumOlcumu('portfoy_payi', 'Portföy içindeki payı', '%23,5'),
        YorumOlcumu('elde_tutma', 'İlk alımdan bu yana geçen süre', '412 gün'),
        YorumOlcumu('pozisyon_getirisi', 'İlk alımdan bu yana pozisyonun getirisi', '+%48,2'),
      ],
      olusturuldu: DateTime(2026, 10, 14, 14, 40),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    final dm = FontLoader(kSandikFontFamily);
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      dm.addFont(rootBundle.load('assets/fonts/DMSans-$w.ttf'));
    }
    await dm.load();
    final ikon = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await ikon.load();
  });

  Future<void> ciz(WidgetTester tester, String ad, Widget kart,
      {PortfoyYorumDurumu? durum, PortfoyYorumu? varlik, double boy = 900}) async {
    tester.view.physicalSize = Size(390 * 2, boy * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        premiumKilitliProvider.overrideWithValue(false),
        portfoyYorumRizaProvider.overrideWith((ref) async => true),
        portfoyYorumuProvider.overrideWith((ref, tur) async =>
            PortfoyYorumDurumu(paket: _paket(tur), kayit: null)),
        portfoySeciliYorumProvider.overrideWith((ref, p) async => durum),
        varlikYorumKaydiProvider.overrideWith((ref, a) async => varlik),
      ],
      child: RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('tr'),
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          home: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(SandikSpace.md),
                child: kart,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 2.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/gorsel').createSync(recursive: true);
      File('build/gorsel/$ad.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('önce: yalnız geçen hafta / geçen ay', (tester) async {
    await ciz(tester, 'yorum_once', const PortfoyYorumuKarti(), boy: 520);
  });

  testWidgets('sonra: Performans seçili dönem, düğme', (tester) async {
    await ciz(tester, 'yorum_sonra_dugme',
        const PortfoyYorumuKarti(secili: SummaryPeriod.ucAy),
        durum: PortfoyYorumDurumu(paket: _paket(YorumTuru.secili), kayit: null),
        boy: 560);
  });

  testWidgets('sonra: Performans seçili dönem, ekonomist yorumu', (tester) async {
    await ciz(tester, 'yorum_sonra_portfoy',
        const PortfoyYorumuKarti(secili: SummaryPeriod.ucAy),
        durum: PortfoyYorumDurumu(paket: _paket(YorumTuru.secili), kayit: _portfoyYorumu()),
        boy: 1200);
  });

  testWidgets('sonra: varlık detayı yorumu', (tester) async {
    await ciz(
        tester,
        'yorum_sonra_varlik',
        VarlikYorumuKarti(
          period: SummaryPeriod.ucAy,
          positionKey: 'hisse|THYAO|TRY',
          miktar: 100,
          veriHazir: true,
          paketKur: () async => null,
        ),
        varlik: _varlikYorumu(),
        boy: 1200);
  });

  testWidgets('sonra: GÜNLÜK seçiliyken', (tester) async {
    await ciz(tester, 'yorum_sonra_gunluk',
        const PortfoyYorumuKarti(secili: SummaryPeriod.gunluk),
        boy: 480);
  });
}
