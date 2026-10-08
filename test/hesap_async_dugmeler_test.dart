import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/screens/partnership_requests_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/custom_loading_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Tek yükleniyor davranışı — hesap/ortaklık/ayarlar yüzeyi (yasin,
/// 2026-10-08: "arkasında istek giden buton kliklerini tespit edelim ve
/// hepsinde aynı loading aksiyonu alınsın").
///
/// Sözleşme: istek sürerken düğme pasif, yerinde küçük gösterge döner,
/// ikinci dokunuş ikinci istek açmaz; iş bitince düğme geri gelir.

class _AskidaOrtaklar extends PartnersNotifier {
  final ret = Completer<void>();
  int retSayisi = 0;

  @override
  Future<List<PartnerAccount>> build() async => const [];

  @override
  Future<void> rejectInvite(String inviteId) {
    retSayisi++;
    return ret.future;
  }
}

class _SabitDavetler extends PendingInvitesNotifier {
  @override
  Future<List<Map<String, dynamic>>> build() async => [
        {'id': 'd1', 'requester_name': 'Ayşe'},
      ];

  @override
  Future<void> refresh() async {}
}

Widget _uygulama(Widget home, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: home,
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('çıkış düğmesi: iş sürerken kilitli + gösterge, tek çağrı',
      (tester) async {
    final is_ = Completer<void>();
    var cagri = 0;
    await tester.pumpWidget(_uygulama(Scaffold(
      body: Center(
        child: SandikLogoutButton(onPressed: () {
          cagri++;
          return is_.future;
        }),
      ),
    )));

    expect(find.byType(CustomLoadingIndicator), findsNothing);
    await tester.tap(find.byType(SandikLogoutButton));
    await tester.pump();
    expect(cagri, 1);
    expect(find.byType(CustomLoadingIndicator), findsOneWidget,
        reason: 'Çıkış isteği sürerken gösterge görünmeli');

    // İkinci dokunuş yutulur.
    await tester.tap(find.byType(SandikLogoutButton), warnIfMissed: false);
    await tester.pump();
    expect(cagri, 1, reason: 'İkinci dokunuş ikinci onay/istek açtı');

    is_.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(CustomLoadingIndicator), findsNothing);

    // Kilit açıldı: yeni dokunuş yeniden çağırır.
    await tester.tap(find.byType(SandikLogoutButton));
    await tester.pump();
    expect(cagri, 2);
  });

  testWidgets('ortaklık isteği "Reddet": pasif + gösterge, tek istek',
      (tester) async {
    final ortaklar = _AskidaOrtaklar();
    await tester.pumpWidget(_uygulama(
      const PartnershipRequestsScreen(),
      overrides: [
        partnersProvider.overrideWith(() => ortaklar),
        pendingInvitesProvider.overrideWith(_SabitDavetler.new),
      ],
    ));
    await tester.pump();
    await tester.pump();

    final reddet = find.text('Reddet');
    expect(reddet, findsOneWidget);
    await tester.tap(reddet);
    await tester.pump();
    expect(ortaklar.retSayisi, 1);

    // Düğme pasif ve içinde gösterge var.
    final dugme = find.ancestor(
        of: find.text('Reddet'), matching: find.byType(OutlinedButton));
    expect(tester.widget<OutlinedButton>(dugme).onPressed, isNull,
        reason: 'İstek sürerken "Reddet" yeniden etkinleşti');
    expect(
        find.descendant(
            of: dugme, matching: find.byType(CustomLoadingIndicator)),
        findsOneWidget);
    // Komşu "Onayla" etkilenmez — kilit düğme başına.
    final onayla = find.ancestor(
        of: find.text('Onayla'), matching: find.byType(FilledButton));
    expect(tester.widget<FilledButton>(onayla).onPressed, isNotNull);

    await tester.tap(reddet, warnIfMissed: false);
    await tester.pump();
    expect(ortaklar.retSayisi, 1, reason: 'İkinci dokunuş ikinci istek açtı');

    ortaklar.ret.complete();
    await tester.pump();
    await tester.pump();
    // Başarı: davet listeden HEMEN düşer (pendingInvites `kaldir`).
    expect(find.text('Reddet'), findsNothing);

    // Snack zamanlayıcısı ve ForegroundPoller kapansın.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  test('ekranlar kendi meşgul bayrağını/perdesini yazmaz', () {
    final profil = ekranKaynagiSync('lib/screens/profile_screen.dart');
    expect(profil, isNot(contains('ModalBarrier(')),
        reason: 'Profil tek düğmelik isteklerde tam ekran perde kurmamalı');
    expect(profil, isNot(contains('bool _busy')));
    expect(profil, isNot(contains('bool _generating')));
    final ayarlar = ekranKaynagiSync('lib/screens/settings_screen.dart');
    expect(ayarlar, isNot(contains('bool _exporting')));
    expect(ayarlar, contains('onTapAsync: _exportData'));
    final cihaz = ekranKaynagiSync('lib/screens/kayitli_cihazlar_screen.dart');
    expect(cihaz, isNot(contains('String? _silinen')));
  });
}
