// Profil tek seferde çizilir (yasin 2026-11-15): "Profil ekranında
// açıldığında kademeli açılıp sonradan çizilen komponentler var; sayfada
// gösterilecek alanlar varsa hepsi aynı anda tekte çizilmeli."
//
// Kapı (`profilHazirProvider`) geç gelen her satırın kaynağı çözülmeden
// açılmamalı; hata da çözülmüş sayılır (satır kendi hâlini çizer, sayfa
// takılı kalmaz). Kaynaklar açılışta ısıtılır (`_AuthGate._warmUpData`).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/halka_arz_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/profile_screen.dart';
import 'package:portfoy_takip/screens/recap_screen.dart';
import 'package:portfoy_takip/widgets/percentile_strip.dart';

class _Ortak extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

final _davetler = Completer<List<Map<String, dynamic>>>();

class _Davet extends PendingInvitesNotifier {
  @override
  Future<List<Map<String, dynamic>>> build() => _davetler.future;
}

void main() {
  test('bekleyen istekler gelmeden kapı açılmaz; gelince açılır', () async {
    final c = ProviderContainer(overrides: [
      partnersProvider.overrideWith(_Ortak.new),
      pendingInvitesProvider.overrideWith(_Davet.new),
      paywallVisibleProvider.overrideWithValue(true),
      premiumHaklariProvider.overrideWith((_) async => const []),
      halkaArzEtkinProvider.overrideWithValue(false),
      yuzdelikDilimProvider.overrideWith((_) async => null),
      yillikOzetAfisiProvider.overrideWith((_) async => null),
    ]);
    addTearDown(c.dispose);
    c.listen(profilHazirProvider, (_, __) {}, fireImmediately: true);

    expect(c.read(profilHazirProvider), isFalse,
        reason: 'ilk karede hiçbir kaynak çözülmemişken sayfa çizilmez');
    await Future<void>.delayed(Duration.zero);
    expect(c.read(profilHazirProvider), isFalse,
        reason: 'bekleyen istekler satırı sonradan girerdi');

    _davetler.completeError(StateError('ağ yok'));
    await expectLater(c.read(pendingInvitesProvider.future), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(profilHazirProvider), isTrue,
        reason: 'hata da çözülmüş sayılır; sayfa takılı kalmaz');
  });
}
