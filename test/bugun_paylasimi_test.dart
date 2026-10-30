import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/bugun_paylasimi.dart';
import 'package:portfoy_takip/widgets/share_card.dart';

/// Bugün kartından "yalnız yüzde" paylaşımı (müşteri raporu 30 Eki 17:15 §1).
///
/// Kilitlenen: görsel ve metinde tutar yok, dağılım yalnız tür adıyla (pay
/// yazılmaz, şerit çizilmez), "Yatırım tavsiyesi değildir" ikisinde de var,
/// bağlantı öteki paylaşımlarla aynı kapıdan kendi kanal etiketiyle.
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  final l = lookupAppLocalizations(const Locale('tr'));

  const dagilim = {
    AssetType.hisse: 600.0,
    AssetType.altin: 300.0,
    AssetType.fon: 100.0,
  };

  test('metin: yüzde + tarih, uyarı, imza, bugun kanalı; tutar yok', () {
    final m = bugunPaylasimMetni(l, degisimPct: 0.8412, tarih: '30 Ekim 2026');
    final satirlar = m.split('\n');
    expect(satirlar.first, 'Portföyüm bugün +%0,84 · 30 Ekim 2026');
    expect(m, contains('Yatırım tavsiyesi değildir.'));
    expect(m, contains('sandık ile takip ediyorum'));
    expect(satirlar.last, contains('utm_source=bugun_karti'));
    expect(m.contains('₺'), isFalse);
  });

  test('eksi gün: tipografik eksi, teselli cümlesi yok', () {
    final m = bugunPaylasimMetni(l, degisimPct: -1.2, tarih: '30 Ekim 2026');
    expect(m.split('\n').first, 'Portföyüm bugün −%1,20 · 30 Ekim 2026');
    expect(m.split('\n').length, 5);
  });

  testWidgets('görsel: yüzde büyük, tür adları paysız, şerit yok, dipnotlar',
      (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
          brightness: Brightness.dark, extensions: [SandikPalette.dark]),
      home: Scaffold(
        body: Center(
          child: ShareCard(
            data: bugunPaylasimKarti(l, degisimPct: 0.8412, dagilim: dagilim),
            tarih: DateTime(2026, 10, 30),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('+%0,84'), findsOneWidget);
    expect(find.text('PORTFÖYÜM BUGÜN'), findsOneWidget);
    for (final ad in ['Hisse', 'Altın', 'Fon']) {
      expect(find.text(ad), findsOneWidget, reason: ad);
    }
    expect(find.textContaining('%60'), findsNothing);
    expect(find.bySemanticsLabel('Dağılım'), findsNothing,
        reason: 'oran şeridi çizilmez');
    expect(find.text('Yatırım tavsiyesi değildir.'), findsOneWidget);
    expect(find.text('yasincirali.github.io/sandikapp/indir'), findsOneWidget);
  });

  test('kaynakta para biçimleyici yok', () {
    final src = File('lib/widgets/bugun_paylasimi.dart')
        .readAsLinesSync()
        .where((s) => !s.trimLeft().startsWith('//'))
        .join('\n');
    for (final yasak in ['fmtTRY', 'BazPara', '₺', 'toTRY', 'changeTRY']) {
      expect(src.contains(yasak), isFalse, reason: yasak);
    }
  });
}
