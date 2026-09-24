import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kullanıcı bulgusu (2026-09-21): "log off yapılıp başka userla login
/// olununca portföy hedefi oraya da geçiyor — cihaz bazlı değil kullanıcı
/// bazlı olmalı."
///
/// Kök neden: `portfolioGoalProvider` `perUser: true` ile TANIMLIYDI (anahtar
/// kullanıcıya göre ayrılıyordu) ama `_AuthGate` kullanıcı değişiminde
/// yalnızca sinyal tercihlerini invalidate ediyordu. Provider'ın bellekteki
/// state'i önceki kullanıcıdan kalıyor, yeni kullanıcı onun hedefini
/// görüyordu. Aynı boşluk baz para birimi, yatırımcı seviyesi, biyometrik
/// kilit ve Live Activity tercihlerinde de vardı.
///
/// İki koruma:
///   1. Kaynak taraması: `perUser: true` ya da `_userKey(` kullanan her
///      provider `kullaniciyaOzelTercihler` listesinde olmalı — yeni bir
///      kişisel tercih listeye yazılmadan eklenemez.
///   2. Davranış: A hedef koyar, B girer (liste invalidate edilir) → B
///      varsayılanı görür; A geri gelince kendi hedefini bulur.
void main() {
  final kaynak = File('lib/providers/preferences_provider.dart')
      .readAsStringSync()
      .replaceAll(RegExp(r'\s+'), ' ');

  /// Listenin gövdesi — `final kullaniciyaOzelTercihler = <...>[ ... ];`
  final listeGovdesi = RegExp(r'kullaniciyaOzelTercihler = <ProviderOrFamily>\[(.*?)\];')
      .firstMatch(kaynak)!
      .group(1)!;

  test('perUser: true ile tanımlanan her provider listede', () {
    // `final xProvider = NotifierProvider<...>( () => _XPrefNotifier(..., perUser: true))`
    final tanimlar = RegExp(
        r'final (\w+Provider) = NotifierProvider<_(?:Bool|Int)PrefNotifier, \w+>\( \(\) => _(?:Bool|Int)PrefNotifier\([^;]*?perUser: true');
    final adlar = [for (final m in tanimlar.allMatches(kaynak)) m.group(1)!];
    expect(adlar, isNotEmpty, reason: 'Tarama deseni kaynağı bulamadı.');
    for (final ad in adlar) {
      expect(listeGovdesi, contains(ad),
          reason: '$ad perUser ama kullaniciyaOzelTercihler listesinde yok.');
    }
  });

  test('_userKey kullanan her notifier sınıfının provider\'ı listede', () {
    // `_userKey(` geçen her yeri bir önceki `class X extends Notifier`
    // başlığına bağla. Fonksiyonun kendi tanımı (`String _userKey(`) tüm
    // sınıflardan önce durur ve başlığı yoktur — atlanır.
    final basliklar =
        RegExp(r'class (\w+) extends Notifier<').allMatches(kaynak).toList();
    final adaylar = <String>{};
    for (final k in RegExp(r'(?<!String )_userKey\(').allMatches(kaynak)) {
      final onceki = basliklar.where((b) => b.start < k.start);
      if (onceki.isEmpty) continue;
      adaylar.add(onceki.last.group(1)!);
    }
    // _BoolPrefNotifier / _IntPrefNotifier genel amaçlı; onların provider'ları
    // `perUser: true` ile ayırt edilir (üstteki test).
    adaylar.removeWhere((s) => s.startsWith('_'));
    expect(adaylar, isNotEmpty);
    for (final sinif in adaylar) {
      final prov = RegExp('final (\\w+Provider) = NotifierProvider<$sinif,')
          .firstMatch(kaynak);
      expect(prov, isNotNull, reason: '$sinif için provider bulunamadı.');
      expect(listeGovdesi, contains(prov!.group(1)!),
          reason: '${prov.group(1)} ($sinif) listede yok.');
    }
  });

  group('portföy hedefi kullanıcıya özel', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      setPreferencesUser(null);
    });
    tearDown(() => setPreferencesUser(null));

    /// `_AuthGate._invalidateUserPrefs` ile aynı döngü.
    void kullaniciDegisti(ProviderContainer c, String? uid) {
      setPreferencesUser(uid);
      for (final p in kullaniciyaOzelTercihler) {
        c.invalidate(p);
      }
    }

    test('B kullanıcısı A\'nın hedefini görmez; A geri gelince bulur',
        () async {
      await initPreferencesCache();
      final c = ProviderContainer();
      addTearDown(c.dispose);

      kullaniciDegisti(c, 'A');
      await c.read(portfolioGoalProvider.notifier).set(750000);
      expect(c.read(portfolioGoalProvider), 750000);

      kullaniciDegisti(c, 'B');
      expect(c.read(portfolioGoalProvider), 0,
          reason: 'B kullanıcısı A\'nın hedefini GÖRMEMELİ.');

      await c.read(portfolioGoalProvider.notifier).set(100000);

      kullaniciDegisti(c, 'A');
      expect(c.read(portfolioGoalProvider), 750000,
          reason: 'A kendi hedefini geri bulmalı.');

      // Diskte de iki ayrı anahtar var.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('portfolio_goal_try_A'), 750000);
      expect(prefs.getInt('portfolio_goal_try_B'), 100000);
    });

    // Denetim F6 (2026-09-23): yarış onayı cihaz genelindeydi; A'nın onayı
    // aynı telefondaki B için de "açık" okunuyor, B'nin getirisi onaysız
    // sunucuya gidiyordu.
    test('yarış onayı kişiye özel: A katılınca B katılmış sayılmaz',
        () async {
      await initPreferencesCache();
      final c = ProviderContainer();
      addTearDown(c.dispose);

      kullaniciDegisti(c, 'A');
      await c.read(leaderboardOptInProvider.notifier).set(true);

      kullaniciDegisti(c, 'B');
      expect(c.read(leaderboardOptInProvider), isFalse,
          reason: 'B açık rıza vermedi.');

      kullaniciDegisti(c, 'A');
      expect(c.read(leaderboardOptInProvider), isTrue);
    });

    test('invalidate edilmezse eski state kalır — listenin varlık sebebi',
        () async {
      await initPreferencesCache();
      final c = ProviderContainer();
      addTearDown(c.dispose);

      setPreferencesUser('A');
      await c.read(portfolioGoalProvider.notifier).set(5);
      // Yalnızca ön ek değişti, invalidate yok: hata yeniden üretilir.
      setPreferencesUser('B');
      expect(c.read(portfolioGoalProvider), 5,
          reason: 'Bu satır kırılırsa Riverpod davranışı değişmiş demektir; '
              'liste yine de gerekli (senkron okuma).');
      c.invalidate(portfolioGoalProvider);
      expect(c.read(portfolioGoalProvider), 0);
    });
  });
}
