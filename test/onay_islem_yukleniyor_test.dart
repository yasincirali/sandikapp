import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/friendly_error.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart';
import 'package:portfoy_takip/widgets/custom_loading_indicator.dart';

/// Tek yükleniyor davranışı (2026-10-08): istek atan düğme iş sürerken
/// göstergeli ve kilitli, ikinci dokunuş ikinci istek atmaz; diyalog/sayfa
/// ancak iş başarıyla bitince kapanır.
///
/// Kapsam: `showSandikConfirm(islem:)` (varlık silme, mevduat çekme,
/// bildirim toplu eylemleri) ve `AlarmKurSheet(kur:)`.
Widget _uygulama(Widget Function(BuildContext) govde) => MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: Builder(builder: (context) => Scaffold(body: govde(context))),
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('showSandikConfirm(islem:)', () {
    late Completer<void> is_;
    late int cagri;
    late List<bool> sonuclar;

    Future<void> ac(WidgetTester t) async {
      is_ = Completer<void>();
      cagri = 0;
      sonuclar = [];
      await t.pumpWidget(_uygulama((context) => TextButton(
            onPressed: () async {
              sonuclar.add(await showSandikConfirm(
                context: context,
                title: 'Varlığı sil',
                message: 'Emin misin?',
                confirmLabel: 'Sil',
                destructive: true,
                islem: () {
                  cagri++;
                  return is_.future;
                },
              ));
            },
            child: const Text('aç'),
          )));
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
    }

    testWidgets('iş sürerken gösterge, çift dokunuş tek çağrı, sonra kapanır',
        (t) async {
      await ac(t);
      expect(find.byType(CustomLoadingIndicator), findsNothing);

      await t.tap(find.text('Sil'));
      await t.pump();
      await t.tap(find.text('Sil'), warnIfMissed: false);
      await t.pump();
      expect(cagri, 1, reason: 'ikinci dokunuş ikinci isteği atmaz');
      expect(find.byType(CustomLoadingIndicator), findsOneWidget);
      expect(find.text('Varlığı sil'), findsOneWidget,
          reason: 'diyalog iş bitene kadar açık');

      // Meşgulken vazgeç ve bariyer diyaloğu kapatmaz.
      await t.tap(find.text('Vazgeç'), warnIfMissed: false);
      await t.tapAt(const Offset(5, 5));
      await t.pump();
      expect(find.text('Varlığı sil'), findsOneWidget);

      is_.complete();
      await t.pumpAndSettle();
      expect(find.text('Varlığı sil'), findsNothing);
      expect(sonuclar, [true]);
    });

    testWidgets('iş fırlatırsa diyalog açık kalır, hata gösterilir',
        (t) async {
      await ac(t);
      await t.tap(find.text('Sil'));
      await t.pump();
      is_.completeError(Exception('ağ'));
      await t.pumpAndSettle();
      expect(find.text('Varlığı sil'), findsOneWidget);
      expect(find.text('Hata'), findsOneWidget);
      expect(sonuclar, isEmpty);
    });

    testWidgets('islem verilmezse eski davranış: hemen true', (t) async {
      final sonuc = <bool>[];
      await t.pumpWidget(_uygulama((context) => TextButton(
            onPressed: () async => sonuc.add(await showSandikConfirm(
                context: context, title: 'Başlık', message: 'm')),
            child: const Text('aç'),
          )));
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
      await t.tap(find.text('Onayla'));
      await t.pumpAndSettle();
      expect(sonuc, [true]);
      expect(find.byType(CustomLoadingIndicator), findsNothing);
    });
  });

  group('AlarmKurSheet(kur:)', () {
    const aday = AlarmAdayi('TUPRS.IS', 'TUPRS', 383.25);

    testWidgets('kayıt düğmede koşar, çift dokunuş tek çağrı, başarıda kapanır',
        (t) async {
      final is_ = Completer<void>();
      var cagri = 0;
      final sonuclar = <AlarmKurulumu?>[];
      await t.pumpWidget(_uygulama((context) => TextButton(
            onPressed: () async {
              sonuclar.add(await showModalBottomSheet<AlarmKurulumu>(
                context: context,
                isScrollControlled: true,
                builder: (_) => AlarmKurSheet(
                  adaylar: const [aday],
                  sabit: true,
                  kur: (_) {
                    cagri++;
                    return is_.future;
                  },
                ),
              ));
            },
            child: const Text('aç'),
          )));
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '400');
      await t.pump();

      await t.tap(find.byType(FilledButton));
      await t.pump();
      await t.tap(find.byType(FilledButton), warnIfMissed: false);
      await t.pump();
      expect(cagri, 1);
      expect(find.byType(CustomLoadingIndicator), findsOneWidget);
      final dugme = t.widget<FilledButton>(find.byType(FilledButton));
      expect(dugme.onPressed, isNull, reason: 'meşgulken pasif');
      expect(find.byType(AlarmKurSheet), findsOneWidget);

      is_.complete();
      await t.pumpAndSettle();
      expect(find.byType(AlarmKurSheet), findsNothing);
      expect(sonuclar.single?.hedef, 400);
    });

    testWidgets('kayıt fırlatırsa sayfa açık kalır, hata alanın altında',
        (t) async {
      await t.pumpWidget(_uygulama((context) => TextButton(
            onPressed: () => showModalBottomSheet<AlarmKurulumu>(
              context: context,
              isScrollControlled: true,
              builder: (_) => AlarmKurSheet(
                adaylar: const [aday],
                sabit: true,
                kur: (_) async => throw Exception('ağ'),
              ),
            ),
            child: const Text('aç'),
          )));
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '400');
      await t.tap(find.byType(FilledButton));
      await t.pumpAndSettle();
      expect(find.byType(AlarmKurSheet), findsOneWidget);
      expect(find.byType(CustomLoadingIndicator), findsNothing);
      expect(find.textContaining('kurulamadı'), findsOneWidget);
    });
  });
}
