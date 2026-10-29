import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/yuzde_alarmi.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/yuzde_alarmi_provider.dart';
import 'package:portfoy_takip/services/bildirim_izni.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart' show AlarmAdayi;
import 'package:portfoy_takip/widgets/tek_dokunus_alarm.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kayıt anında tek dokunuşla ±%2 yüzde alarmı (Ar-Ge 29 Eki 12:45 #1).
final _kurulan = <YuzdeAlarmi>[];

class _Y extends YuzdeAlarmlariNotifier {
  @override
  Future<List<YuzdeAlarmi>> build() async => const [];
  @override
  Future<YuzdeAlarmi> create(YuzdeAlarmi alarm) async {
    _kurulan.add(alarm);
    state = AsyncData([alarm, ...(state.valueOrNull ?? const [])]);
    return alarm;
  }
}

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 't@example.com',
        displayName: 'T',
        createdAt: DateTime(2026, 1, 1),
      );
}

YuzdeAlarmi _y(String s) => YuzdeAlarmi(
      id: 'y',
      userId: 'u1',
      symbol: s,
      label: s,
      esikPct: 2,
      yon: YuzdeYon.ikisi,
      createdAt: DateTime(2026, 10, 28),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _kurulan.clear();
    BildirimIzni.testOkuyucu = () async => false;
  });
  tearDown(() => BildirimIzni.testOkuyucu = null);

  test('altın/döviz önerilir; hisse/fon ve zaten yüzde alarmı olan önerilmez',
      () {
    const altin = AlarmAdayi('ALTIN_GRAM', 'Gram altın', 4200);
    expect(yuzdeAlarmiOnerilsinMi(altin, const []), isTrue);
    expect(yuzdeAlarmiOnerilsinMi(altin, [_y('ALTIN_GRAM')]), isFalse);
    expect(yuzdeAlarmiOnerilsinMi(altin, [_y('USDTRY=X')]), isTrue);
    expect(
        yuzdeAlarmiOnerilsinMi(
            const AlarmAdayi('THYAO.IS', 'THY', 300), const []),
        isFalse);
  });

  testWidgets('"Kur" sayfa açmadan ±%2 ikisi de alarmı kurar ve onaylar',
      (tester) async {
    late WidgetRef r;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        yuzdeAlarmlariProvider.overrideWith(_Y.new),
        authProvider.overrideWith(_Auth.new),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [SandikPalette.dark]),
        home: Scaffold(
          body: Consumer(builder: (_, ref, __) {
            r = ref;
            ref.watch(authProvider);
            return const SizedBox.expand();
          }),
        ),
      ),
    ));
    await tester.pump();
    final ctx = tester.element(find.byType(SizedBox).last);
    await tekDokunusYuzdeAlarmiKur(
        ctx, r, const AlarmAdayi('ALTIN_GRAM', 'Gram altın', 4200));
    await tester.pump();
    expect(_kurulan, hasLength(1));
    expect(_kurulan.single.esikPct, 2);
    expect(_kurulan.single.yon, YuzdeYon.ikisi);
    expect(find.textContaining('alarmı kuruldu'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });
}
