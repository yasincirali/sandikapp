import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/tur_filtre_cipleri.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BosPortfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => const PortfolioState(ownerId: 'ben');
}

class _FiyatsizKapi implements AddAssetPriceLookup {
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => null;
  @override
  Future<String?> companyName(String ticker) async => null;
}

/// Dokunma hedefi minimum boyutu — iOS HIG #37, **High severity**.
///
/// > Do: "Ensure all interactive elements meet minimum size"
/// > Don't: "Create touch targets smaller than 44pt"
/// > Flutter_Equiv: `SizedBox(width: 44, height: 44)`
///
/// Denetimde (2026-08-10) 6 ihlal bulundu: bir chevron 32×32, beş ikon
/// butonu 42×42 idi. 42 sınıra çok yakın görünse de HIG eşiği kesindir ve
/// küçük hedefler ıskalanan dokunuş üretir — finansal bir uygulamada
/// "gizle/göster" ya da "sil" gibi butonlarda bu can sıkıcıdır.
///
/// Bu test kaynak taramasıdır: dokunulabilir bir widget'ın gövdesinde
/// 44'ten küçük sabit `width`/`height` görürse kırılır.
void main() {
  test('dokunulabilir widget\'lar en az 44×44pt olmalı', () {
    final tapPattern = RegExp(
      r'(GestureDetector|InkWell|CupertinoButton|IconButton|SandikTappable)'
      r'\s*\(',
    );
    // Yalnızca sabit sayısal boyutlar; `width: someVar` denetlenmez.
    final sizePattern = RegExp(r'\b(width|height)\s*:\s*(\d+(?:\.\d+)?)');

    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();

      for (final m in tapPattern.allMatches(src)) {
        // Widget çağrısının gövdesini parantez dengesiyle bul.
        var depth = 0;
        var end = m.end - 1;
        for (var j = m.end - 1; j < src.length && j < m.end + 2000; j++) {
          if (src[j] == '(') depth++;
          if (src[j] == ')') {
            depth--;
            if (depth == 0) {
              end = j;
              break;
            }
          }
        }
        final body = src.substring(m.end - 1, end);

        // Yalnızca ÜST SEVİYE boyutlar sayılır. Aksi halde
        // `Border.all(width: 1)` gibi iç içe değerler yakalanır ve test
        // yanlış alarm verir (ilk taramada tam olarak bu oldu).
        var d = 0;
        final dims = <double>[];
        for (var k = 0; k < body.length; k++) {
          final ch = body[k];
          if (ch == '(' || ch == '[' || ch == '{') d++;
          if (ch == ')' || ch == ']' || ch == '}') d--;
          if (d <= 2) {
            final sm = sizePattern.matchAsPrefix(body, k);
            if (sm != null) dims.add(double.parse(sm.group(2)!));
          }
        }

        if (dims.isNotEmpty && dims.reduce((a, b) => a < b ? a : b) < 44) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          final smallest = dims.reduce((a, b) => a < b ? a : b);
          offenders.add('${entity.path}:$line — ${m.group(1)} '
              '(${smallest.toStringAsFixed(0)}pt)');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'iOS HIG #37 (High): dokunma hedefi en az 44×44pt olmalı. '
          'Görsel boyutu korumak istiyorsan widget\'ı büyütmek yerine '
          'şeffaf dolgu ver (Container 44×44 + ortalanmış küçük ikon).\n'
          '${offenders.join('\n')}',
    );
  });

  test('CupertinoButton dokunma hedefi Size.zero ile iptal edilmemeli', () {
    // 2026-09-14: 20 `minimumSize: Size.zero` sitesi `SandikTouch.minSize`'a
    // çekildi (2.13). Size.zero, HIG 44pt sınırını tek satırla iptal eder ve
    // yukarıdaki boyut taraması onu görmez (sayı yok). Tema dosyası sabitin
    // kendisini tanımlar, taramanın dışındadır.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('sandik.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('minimumSize: Size.zero')) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'minimumSize: SandikTouch.minSize kullan.\n'
            '${offenders.join('\n')}');
  });

  test('metin ölçekleme (Dynamic Type) ezilmemeli', () {
    // HIG #102 (High): "Scale text with Dynamic Type up to XXXL",
    // "Don't cap text size or break layout at large sizes".
    // `TextScaler.noScaling` veya `textScaleFactor: 1` kullanmak,
    // görme güçlüğü olan kullanıcının sistem ayarını yok sayar.
    final offenders = <String>[];
    final pattern = RegExp(
      r'TextScaler\.noScaling|textScaleFactor:\s*1(?:\.0)?\b',
    );

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // Yorum satırları atlanır: kuralı AÇIKLAYAN notlar yasak ifadeyi
      // bilerek anıyor ve ham metin araması onları ihlal sanıyordu.
      final src = entity
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final m in pattern.allMatches(src)) {
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        offenders.add('${entity.path}:$line — ${m.group(0)}');
      }
    }

    expect(offenders, isEmpty,
        reason: 'Sistem metin boyutu tercihi yok sayılmamalı.\n'
            '${offenders.join('\n')}');
  });

  // Varlık Ekle önayar ve tarih çipleri (Ar-Ge 2026-11-12 #7): görsel çip
  // ~32 pt idi, "lot" eki taşıyordu, seçim yalnız tondu. Kaynak taraması
  // görsel boyutu göremez; burada çizilmiş çip ölçülür.
  testWidgets('Varlık Ekle: miktar ve tarih çipleri ≥44 pt, eksiz, '
      'seçili çipte onay işareti', (tester) async {
    RemoteConfigService.testAcik = {};
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('tr_TR');
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(_BosPortfoy.new),
        addAssetPriceLookupProvider.overrideWithValue(_FiyatsizKapi()),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: const AddAssetScreen(
            prefillTicker: 'AAPL', prefillType: AssetType.hisse),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final cipler = find.byType(SandikFiltreCipi);
    final miktar = find.byWidgetPredicate((w) =>
        w is SandikFiltreCipi &&
        (w.key as ValueKey<String>?)?.value.startsWith('miktar-cipi-') ==
            true);
    expect(miktar, findsWidgets);
    expect(cipler.evaluate().length, greaterThan(miktar.evaluate().length),
        reason: 'Tarih çipleri de aynı bileşen.');
    for (final e in cipler.evaluate()) {
      final boy = tester.getSize(find.byWidget(e.widget));
      expect(boy.height, greaterThanOrEqualTo(44), reason: '${e.widget}');
      expect(boy.width, greaterThanOrEqualTo(44), reason: '${e.widget}');
    }
    // Birim eki çipte yok: "lot" yalnız miktar alanının sonunda.
    expect(
        find.descendant(of: miktar, matching: find.textContaining('lot')),
        findsNothing);

    final on = find.byKey(const ValueKey('miktar-cipi-10'));
    await tester.tap(on);
    await tester.pumpAndSettle();
    expect(tester.widget<SandikFiltreCipi>(on).secili, isTrue);
    expect(find.descendant(of: on, matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget,
        reason: 'Seçim yalnız renkle anlatılmaz.');
  });
}
