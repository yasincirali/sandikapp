import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart';

/// Güncel fiyata EŞİT hedefle alarm kurulmaz (emülatör testi #24,
/// 2026-09-29: TUPRS 383,25'e 383,25 hedef kabul edildi).
///
/// Yön güncel fiyattan türetildiği için "zaten geçilmiş" hedef kurulamaz;
/// eşit hedef ise sunucuda ilk kontrolde (`price >= target`) tetiklenir.
/// Kural istemcide, basmadan ÖNCE görünür; "Alarmı kur" kaydı durdurur.
const _tuprs = AlarmAdayi('TUPRS.IS', 'TUPRS', 383.25);

Future<List<AlarmKurulumu?>> _ac(WidgetTester tester) async {
  final sonuclar = <AlarmKurulumu?>[];
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      extensions: const [SandikPalette.dark],
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            sonuclar.add(await showModalBottomSheet<AlarmKurulumu>(
              context: context,
              isScrollControlled: true,
              builder: (_) =>
                  const AlarmKurSheet(adaylar: [_tuprs], sabit: true),
            ));
          },
          child: const Text('aç'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('aç'));
  await tester.pumpAndSettle();
  return sonuclar;
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('alarmHedefiGuncelFiyatta', () {
    test('ekrandaki hassasiyette eşit → true', () {
      expect(alarmHedefiGuncelFiyatta(383.25, 383.25), isTrue);
      // Ham çift son hanede farklı ama kullanıcı ikisini de "383,25" görür.
      expect(alarmHedefiGuncelFiyatta(383.25, 383.2500001), isTrue);
    });

    test('bir kuruş fark yeter', () {
      expect(alarmHedefiGuncelFiyatta(383.26, 383.25), isFalse);
      expect(alarmHedefiGuncelFiyatta(383.24, 383.25), isFalse);
    });

    test('1 ₺ altı: gösterilen anlamlı hanelerle karşılaştırılır', () {
      expect(alarmHedefiGuncelFiyatta(0.0004123, 0.0004123), isTrue);
      expect(alarmHedefiGuncelFiyatta(0.0004124, 0.0004123), isFalse);
    });

    test('güncel fiyat bilinmiyorsa (0) karar verilmez', () {
      expect(alarmHedefiGuncelFiyatta(0, 0), isFalse);
      expect(alarmHedefiGuncelFiyatta(10, 0), isFalse);
    });
  });

  testWidgets('eşit hedef: uyarı yazar, "Alarmı kur" kaydetmez', (tester) async {
    final sonuclar = await _ac(tester);
    await tester.enterText(find.byType(TextField), '383,25');
    await tester.pump();
    expect(find.textContaining('güncel fiyata eşit'), findsOneWidget,
        reason: 'kural basmadan önce görünür');
    expect(find.textContaining('haber vereceğiz'), findsNothing,
        reason: 'eşit hedefte "çıkınca haber vereceğiz" yalan olurdu');

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.byType(AlarmKurSheet), findsOneWidget, reason: 'sayfa kapanmaz');
    expect(sonuclar, isEmpty);
  });

  testWidgets('farklı hedef: yön cümlesi, kayıt geçer', (tester) async {
    final sonuclar = await _ac(tester);
    await tester.enterText(find.byType(TextField), '390');
    await tester.pump();
    expect(find.textContaining('güncel fiyata eşit'), findsNothing);
    expect(find.textContaining('çıkınca haber vereceğiz'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(sonuclar.single?.hedef, 390);
    expect(sonuclar.single?.yon, 'above');
  });
}
