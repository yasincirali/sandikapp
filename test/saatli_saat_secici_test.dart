import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/saatli_bildirim.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/quiet_hours_provider.dart';
import 'package:portfoy_takip/providers/saatli_bildirim_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/saatli_bildirim.dart';

import 'helpers/yazi_olcegi.dart';

/// Saatli bildirim › saat seçimi (2026-11-26 yeniden tasarım): başlıkta
/// varlığın kimliği, "3/5" sayaç, kaldırılabilir 44 pt çipler, çark + ekle
/// tek kartta, beş saat doluyken çark yerine "birini kaldır", sessiz saat
/// uyarısı, büyük yazıda taşma yok. Kayıt ve düzenleme aynı sayfa.
List<List<int>> _kaydedilen = [];
QuietHours _sessiz = const QuietHours();

class _Saatli extends SaatliBildirimlerNotifier {
  @override
  Future<List<SaatliBildirim>> build() async => const [];

  @override
  Future<SaatliBildirim> kaydet({
    required String userId,
    required String symbol,
    required String label,
    required List<int> saatler,
  }) async {
    _kaydedilen.add([...saatler]);
    return SaatliBildirim(
        id: 'x',
        userId: userId,
        symbol: symbol,
        label: label,
        saatler: saatler,
        createdAt: DateTime(2026, 11, 26));
  }
}

class _Sessiz extends QuietHoursNotifier {
  @override
  Future<QuietHours> build() async => _sessiz;
}

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u',
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

SaatliBildirim _mevcut(List<int> saatler) => SaatliBildirim(
      id: 's1',
      userId: 'u',
      symbol: 'THYAO.IS',
      label: 'Türk Hava Yolları',
      saatler: saatler,
      createdAt: DateTime(2026, 11, 20),
    );

Future<void> _pump(WidgetTester tester,
    {SaatliBildirim? mevcut, double genislik = 390}) async {
  tester.view.physicalSize = Size(genislik * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_Auth.new),
      saatliBildirimlerProvider.overrideWith(_Saatli.new),
      quietHoursProvider.overrideWith(_Sessiz.new),
    ],
    child: MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
      home: Scaffold(
        body: SaatSecimSayfasi(
          sembol: 'THYAO.IS',
          ad: 'Türk Hava Yolları',
          mevcut: mevcut,
        ),
      ),
    ),
  ));
  // Uygulamada oturum sayfa açılmadan çözülmüş olur.
  await ProviderScope.containerOf(tester.element(find.byType(SaatSecimSayfasi)))
      .read(authProvider.future);
  await tester.pumpAndSettle();
}

Finder _cip(int dk) => find.byKey(ValueKey('saatliCip_$dk'));
String _sayac(WidgetTester t) =>
    t.widget<Text>(find.byKey(const ValueKey('saatliSayac'))).data!;

void main() {
  setUp(() {
    _kaydedilen = [];
    _sessiz = const QuietHours();
  });

  test('ilkBosSaat: listedekini atlar, gün sonunda başa sarar', () {
    expect(SaatliBildirim.ilkBosSaat(const [], 540), 540);
    expect(SaatliBildirim.ilkBosSaat(const [540, 555], 540), 570);
    expect(SaatliBildirim.ilkBosSaat(const [1425], 1425), 0);
  });

  testWidgets('başlık varlığın kimliği: ad + "sembol · tür"', (tester) async {
    await _pump(tester);
    expect(find.text('Türk Hava Yolları'), findsOneWidget);
    expect(find.text('THYAO · Hisse'), findsOneWidget);
  });

  testWidgets('yeni kayıt: saat yok cümlesi, Kaydet pasif, sayaç 0/5',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('saatliSaatYok')), findsOneWidget);
    expect(_sayac(tester), '0/${SaatliBildirim.enFazlaSaat}');
    await tester.tap(find.byKey(const ValueKey('saatliKaydet')));
    await tester.pumpAndSettle();
    expect(_kaydedilen, isEmpty);
  });

  testWidgets(
      'düzenleme: çark ilk boş adımda açılır, ekle → çip; çipe dokun → kalkar; '
      'Kaydet seçili saatleri yazar', (tester) async {
    await _pump(tester, mevcut: _mevcut(const [540, 780, 1080]));
    expect(_sayac(tester), '3/5');
    // 09:00 listede: çark 09:15'te, düğme etkin (pasif "listede" değil).
    expect(find.text('Saat ekle'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('saatliSaatEkle')));
    await tester.pumpAndSettle();
    expect(_cip(555), findsOneWidget);
    expect(_sayac(tester), '4/5');
    // Aynı saat ikinci kez eklenmez; düğme nedenini söyler.
    expect(find.text('09:15 listede'), findsOneWidget);
    expect(
        tester
            .widget<ButtonStyleButton>(
                find.byKey(const ValueKey('saatliSaatEkle')))
            .onPressed,
        isNull);

    await tester.tap(_cip(780));
    await tester.pumpAndSettle();
    expect(_cip(780), findsNothing);
    expect(_sayac(tester), '3/5');

    await tester.ensureVisible(find.byKey(const ValueKey('saatliKaydet')));
    await tester.tap(find.byKey(const ValueKey('saatliKaydet')));
    await tester.pump();
    expect(_kaydedilen, [
      [540, 555, 1080]
    ]);
    await tester.pumpAndSettle();
  });

  testWidgets('beş saat doluyken çark yerine "birini kaldır"', (tester) async {
    await _pump(tester, mevcut: _mevcut(const [480, 540, 720, 1020, 1200]));
    expect(find.byType(CupertinoDatePicker), findsNothing);
    expect(find.byKey(const ValueKey('saatliDolu')), findsOneWidget);
    await tester.tap(_cip(720));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
  });

  testWidgets('çip ≥44 pt, ekran okuyucu "… saatini kaldır" der',
      (tester) async {
    final h = tester.ensureSemantics();
    await _pump(tester, mevcut: _mevcut(const [540]));
    expect(tester.getSize(_cip(540)).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('09:00 saatini kaldır'), findsOneWidget);
    // Sayaç sesli okunurken tam cümle.
    expect(find.bySemanticsLabel(RegExp('1 saat, Varlık başına en fazla 5')),
        findsOneWidget);
    h.dispose();
  });

  testWidgets('sessiz saatlere denk gelen saatte uyarı kalır', (tester) async {
    _sessiz = const QuietHours(start: 22, end: 8);
    await _pump(tester, mevcut: _mevcut(const [420]));
    expect(find.byKey(const ValueKey('saatliSessizUyari')), findsOneWidget);
  });

  testWidgets('silme yalnız var olan kayıtta', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('saatliSil')), findsNothing);
    await _pump(tester, mevcut: _mevcut(const [540]));
    expect(find.byKey(const ValueKey('saatliSil')), findsOneWidget);
  });

  group('taşma', () {
    yaziOlcegiEkseni(() {
      testWidgets('320 pt, beş saat + çark', (tester) async {
        yaziOlceginiUygula(tester);
        _sessiz = const QuietHours(start: 22, end: 8);
        await _pump(tester,
            genislik: 320, mevcut: _mevcut(const [420, 540, 720, 1020]));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const ValueKey('saatliKaydet')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });
  });
}
