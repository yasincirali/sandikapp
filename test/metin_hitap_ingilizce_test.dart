import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/l10n/l10n.dart';
import 'package:portfoy_takip/l10n/sen_material_localizations.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/technical_signal.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/screens/settings_screen.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/money_format.dart';
import 'package:portfoy_takip/utils/tr_format.dart';

import 'helpers/kaynak.dart';

/// 2026-09-29 emülatör testi — metin grubu: #19 (sen hitabı), #27 (İngilizce
/// mod), #31 (çeşitli etiketler).
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('#19 — sen hitabı', () {
    // Yasal uyarı (`disclaimerText`) hukuk metnidir, bilinçli dışarıda:
    // hitabını değiştirmek hukuk kararı (bkz. rapor).
    const yasal = {'disclaimerText'};
    final sizKipi = RegExp(
        r'\b(bırakın|kullanın|edin|yapın|girin|seçin|deneyin|olun|bakın|'
        r'ekleyin|verin|yazın|dokunun|bekleyin|tıklayın|açın|kapatın|gidin|'
        r'indirin|onaylayın|silin|kaydedin|giriniz|ediniz|veriniz)\b');

    test('app_tr.arb kullanıcı metinlerinde "siz" emir kipi yok', () {
      final arb = jsonDecode(File('lib/l10n/app_tr.arb').readAsStringSync())
          as Map<String, dynamic>;
      final ihlal = <String>[
        for (final e in arb.entries)
          if (!e.key.startsWith('@') &&
              !yasal.contains(e.key) &&
              e.value is String &&
              sizKipi.hasMatch(e.value as String))
            '${e.key}: ${e.value}',
      ];
      expect(ihlal, isEmpty);
    });

    testWidgets('Material Türkçesi sen hitabıyla; ay adları Flutter\'ınki',
        (tester) async {
      late MaterialLocalizations m;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: const [
          SenMaterialLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(builder: (c) {
          m = MaterialLocalizations.of(c);
          return const SizedBox();
        }),
      ));
      expect(m.dateRangePickerHelpText, 'Aralık seç');
      expect(m.selectYearSemanticsLabel, 'Yılı seç');
      expect(m.datePickerHelpText, 'Tarih seç');
      expect(m.dateInputLabel, 'Tarih gir');
      expect(m.formatMonthYear(DateTime(2026, 3)), 'Mart 2026');
      expect(m.cancelButtonLabel, 'İptal');
    });

    test('main.dart: sen delegate\'i Global delegate\'lerden ÖNCE', () {
      final k = File('lib/main.dart').readAsStringSync();
      final sen = k.indexOf('SenMaterialLocalizationsDelegate()');
      final app = k.indexOf('...AppLocalizations.localizationsDelegates');
      expect(sen, greaterThan(0));
      expect(sen, lessThan(app),
          reason: 'Localizations bir tür için ilk uyan delegate\'i kullanır; '
              'AppLocalizations.localizationsDelegates Global Material '
              'delegate\'ini de içerir.');
    });
  });

  group('#27 — İngilizce mod', () {
    final en = AppLocalizationsEn();
    final tr = AppLocalizationsTr();

    test('çoğul: alarm ve bildirim sayısı', () {
      expect(en.activeAlertsCount(1), '1 active price alert');
      expect(en.activeAlertsCount(3), '3 active price alerts');
      expect(en.nActiveAlerts(1), '1 active price alert');
      expect(en.notificationsNewCount(1), '1 new notification');
      expect(en.notificationsNewCount(4), '4 new notifications');
      expect(tr.notificationsNewCount(4), '4 yeni bildirim');
    });

    test('baz para adı ve birim dile göre', () {
      expect(bazBirimAdi(en, BaseCurrency.usd), 'Dollar');
      expect(bazBirimAdi(tr, BaseCurrency.usd), 'Dolar');
      expect(bazBirimAdi(en, BaseCurrency.gold), 'Gram gold');
      expect(birimMetni(en, 'adet'), 'units');
      expect(birimMetni(tr, 'adet'), 'adet');
      expect(birimMetni(en, 'gr'), 'gr');
    });

    Widget uygulama(Widget child) => MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('çıkış düğmesi ve tarih seçici İngilizce', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(uygulama(Builder(
        builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
          SandikLogoutButton(onPressed: () {}),
          TextButton(
            onPressed: () =>
                pickSandikDate(c, initialDate: DateTime(2026, 3, 2)),
            child: const Text('ac'),
          ),
          Text(c.tarihDili),
        ]),
      )));
      expect(find.bySemanticsLabel('Sign out'), findsOneWidget);
      expect(find.text('en_US'), findsOneWidget);
      await tester.tap(find.text('ac'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Select'), findsOneWidget);
      expect(find.text('İptal'), findsNothing);
      semantics.dispose();
    });

    test('ortak yardımcı yerinde: Performans kartı tarihi arayüz dilinde', () {
      final k = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
      expect(k, contains("DateFormat('d MMM', context.tarihDili)"));
      expect(k, contains("DateFormat('d MMMM', context.tarihDili)"));
    });
  });

  group('#31 — çeşitli etiketler', () {
    test('hafta sonu seçilince kapanış günü Cuma; kripto 7/24', () {
      // 1 Mar 2026 Pazar, 28 Şub Cumartesi, 27 Şub Cuma.
      expect(haftaSonuKapanisGunu(DateTime(2026, 3, 1), yediGun: false),
          DateTime(2026, 2, 27));
      expect(haftaSonuKapanisGunu(DateTime(2026, 2, 28, 15), yediGun: false),
          DateTime(2026, 2, 27));
      expect(haftaSonuKapanisGunu(DateTime(2026, 3, 2), yediGun: false),
          isNull);
      expect(
          haftaSonuKapanisGunu(DateTime(2026, 3, 1), yediGun: true), isNull);
      final k = ekranKaynagiSync('lib/screens/add_asset_screen.dart');
      expect(k, contains('pricePreviewLastTradingClose'));
      expect(k, contains('priceAssignedLastTradingClose'));
    });

    test('hedef tutarı sondaki sıfırlar olmadan', () {
      expect(fmtTRYCompactSade(250000), '₺250K');
      expect(fmtTRYCompactSade(2500000), '₺2,5M');
      expect(fmtTRYCompactSade(1250000), '₺1,25M');
      expect(fmtTRYCompactSade(-2.5e9), '-₺2,5Mr');
      expect(fmtTRYCompactSade(750), '₺750');
      // Eksen biçimi DEĞİŞMEDİ (sabit ondalık, parite testleri).
      expect(fmtTRYCompact(250000), '₺250,0K');
    });

    test('"2 alım · 0 çıkarma" yazılmaz', () {
      expect(AppLocalizationsTr().lotSummary(2, 0), '2 alım');
      expect(AppLocalizationsTr().lotSummary(2, 1), '2 alım · 1 çıkarma');
      expect(AppLocalizationsEn().lotSummary(1, 0), '1 buy');
      expect(AppLocalizationsEn().lotSummary(3, 2), '3 buys · 2 removals');
    });

    test('özet ve panel sayaçları farklı şeyi saydığını söyler', () {
      // Özet: yön veren göstergelerden kaçı lehte; panel: kaç gösterge açık.
      // İkisi de "x/y gösterge" yazınca "1/2" ile "5/8" çelişki gibi okunuyordu.
      expect(trMetni('indicatorsConfidence'), contains('yön veren'));
      expect(trMetni('nOfMIndicators'), contains('açık'));
    });

    test('EMA: NÖTR sinyal "yükseliş trendi" demez', () {
      // Uzun yükseliş (EMA20 > EMA50) + son günlerde sert düşüş (fiyat
      // EMA20'nin altında): sinyal teyitsiz → nötr.
      final fiyat = [
        for (var i = 0; i < 90; i++) 100.0 + i,
        for (var i = 0; i < 4; i++) 180.0 - i * 10,
      ];
      final ind = TechnicalAnalysisService.movingAverage(fiyat, AssetType.hisse);
      expect(ind.signal, SignalType.neutral);
      expect(ind.description, isNot(contains('trendi')));
      expect(ind.description, contains('teyit yok'));

      final yukselis = [for (var i = 0; i < 90; i++) 100.0 + i];
      final al =
          TechnicalAnalysisService.movingAverage(yukselis, AssetType.hisse);
      expect(al.signal, SignalType.buy);
      expect(al.description, contains('yükseliş trendi'));
    });
  });
}
