import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';

/// Ortak yoklaması (Ar-Ge 2026-11-07 16:06#2): ortak listesi boşken 60 sn
/// zamanlayıcısı kurulmaz; ortak gelince başlar, son ortak gidince durur.
/// Hesapların çoğunda ortak yok; boş listeye dakikada iki sorgu atılıyordu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ortak = PartnerAccount(
    user: AppUser(
      id: 'ortak-1',
      email: 'o@example.com',
      displayName: 'Ortak',
      createdAt: DateTime(2026, 1, 1),
    ),
    isActive: true,
  );

  group('yoklamaGerekir (saf karar)', () {
    test('boş listede yoklama yok', () {
      expect(
          PartnersNotifier.yoklamaGerekir(onPlanda: true, ortaklar: const []),
          isFalse);
    });
    test('ortak varken ön planda yoklama var', () {
      expect(PartnersNotifier.yoklamaGerekir(onPlanda: true, ortaklar: [ortak]),
          isTrue);
    });
    test('arka planda ortak olsa da yoklama yok', () {
      expect(
          PartnersNotifier.yoklamaGerekir(onPlanda: false, ortaklar: [ortak]),
          isFalse);
    });
  });

  group('PartnersNotifier zamanlayıcısı', () {
    late List<PartnerAccount> sunucu;

    ProviderContainer kur() {
      final c = ProviderContainer(overrides: [
        authProvider.overrideWith(_Auth.new),
        partnersProvider.overrideWith(() => _SahtePartners(() => sunucu)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('ortak listesi boşken zamanlayıcı kurulmaz', () async {
      sunucu = const [];
      final c = kur();
      await c.read(authProvider.future);
      expect(await c.read(partnersProvider.future), isEmpty);
      expect(c.read(partnersProvider.notifier).yoklamaAcik, isFalse);
    });

    test('ortak varken zamanlayıcı kurulur', () async {
      sunucu = [ortak];
      final c = kur();
      await c.read(authProvider.future);
      expect(await c.read(partnersProvider.future), hasLength(1));
      expect(c.read(partnersProvider.notifier).yoklamaAcik, isTrue);
    });

    test('ortak gelince (refresh) başlar, son ortak gidince durur', () async {
      sunucu = const [];
      final c = kur();
      await c.read(authProvider.future);
      await c.read(partnersProvider.future);
      final n = c.read(partnersProvider.notifier);
      expect(n.yoklamaAcik, isFalse);

      sunucu = [ortak];
      await n.refresh();
      expect(n.yoklamaAcik, isTrue);

      sunucu = const [];
      await n.refresh();
      expect(n.yoklamaAcik, isFalse);
    });

    test('arka plana geçince durur, öne dönünce ortak varsa başlar', () async {
      sunucu = [ortak];
      final c = kur();
      await c.read(authProvider.future);
      await c.read(partnersProvider.future);
      final n = c.read(partnersProvider.notifier);

      n.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(n.yoklamaAcik, isFalse);
      n.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(n.yoklamaAcik, isTrue);
    });

    test('dispose zamanlayıcıyı kapatır', () async {
      sunucu = [ortak];
      final c = ProviderContainer(overrides: [
        authProvider.overrideWith(_Auth.new),
        partnersProvider.overrideWith(() => _SahtePartners(() => sunucu)),
      ]);
      await c.read(authProvider.future);
      await c.read(partnersProvider.future);
      final n = c.read(partnersProvider.notifier);
      expect(n.yoklamaAcik, isTrue);
      c.dispose();
      expect(n.yoklamaAcik, isFalse);
    });
  });
}

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'ben',
        email: 'ben@example.com',
        displayName: 'Ben',
        createdAt: DateTime(2026, 1, 1),
      );
}

/// Supabase'siz: yalnız yükleyici ezilir, zamanlayıcı kararı gerçek kod.
class _SahtePartners extends PartnersNotifier {
  _SahtePartners(this._kaynak);
  final List<PartnerAccount> Function() _kaynak;

  @override
  Future<List<PartnerAccount>> ortaklariYukle(String userId) async =>
      _kaynak();
}
