import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/hesap_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/hesap_gecisi.dart';
import 'package:portfoy_takip/services/hesap_kasasi.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/services/secure_session_storage.dart'
    show SessionVault;
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/hesap_secici.dart';
import 'package:portfoy_takip/widgets/uygulama_kabugu.dart';

/// Çoklu hesap (bayrak `coklu_hesap`, 2026-10-10).
///
/// En önemli test "veri sızıntısı bekçisi": hesap değişince önceki hesabın
/// sağlayıcı durumu yeni hesaba ULAŞMAMALI. Kullanıcı sorusu (2026-10-09)
/// "müşterilerin cihazdaki verileri birbirine karışacak mı" idi; cevap
/// `UygulamaKabugu`'nun kapsamı baştan kurmasına dayanıyor — bu test o
/// sözü kilitler.
class _BellekKasa implements SessionVault {
  final Map<String, String> m = {};
  @override
  Future<String?> read(String key) async => m[key];
  @override
  Future<void> write(String key, String value) async => m[key] = value;
  @override
  Future<void> delete(String key) async => m.remove(key);
}

KayitliHesap _h(String uid, {int gunOnce = 0, bool dustu = false}) =>
    KayitliHesap(
      uid: uid,
      eposta: '$uid@example.com',
      ad: uid,
      sonKullanim: DateTime(2026, 10, 10).subtract(Duration(days: gunOnce)),
      oturumDustu: dustu,
    );

final _ben = AppUser(
  id: 'yasin',
  email: 'yasin@example.com',
  displayName: 'yasin',
  createdAt: DateTime(2026, 1, 1),
);

class _SabitAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _ben;
}

final _sayac = StateProvider<int>((ref) => 0);

void main() {
  group('HesapKasasi', () {
    late _BellekKasa ham;
    late HesapKasasi kasa;
    setUp(() {
      ham = _BellekKasa();
      kasa = HesapKasasi(kasa: ham, onEk: 'test');
    });

    test('son kullanılan en üstte; güncelleme kopya üretmez', () async {
      await kasa.kaydet(_h('a', gunOnce: 3));
      await kasa.kaydet(_h('b', gunOnce: 1));
      await kasa.kaydet(_h('a'));
      final l = await kasa.liste();
      expect(l.map((h) => h.uid), ['a', 'b']);
    });

    test('sınır dolunca yeni hesap yazılmaz, var olan güncellenir', () async {
      for (var i = 0; i < HesapKasasi.enCok; i++) {
        expect(await kasa.kaydet(_h('h$i', gunOnce: i)), isTrue);
      }
      expect(await kasa.kaydet(_h('fazla')), isFalse);
      expect(await kasa.kaydet(_h('h0', gunOnce: 9)), isTrue);
      expect((await kasa.liste()).length, HesapKasasi.enCok);
    });

    test('oturum yalnız listedeki hesap için tazelenir', () async {
      await kasa.oturumuTazele('yabanci', '{"refresh_token":"x"}');
      expect(await kasa.oturum('yabanci'), isNull,
          reason: 'kasa, eklenmemiş hesabın oturumunu tutmamalı');
      await kasa.kaydet(_h('a'), oturumJson: '{"refresh_token":"1"}');
      await kasa.oturumuTazele('a', '{"refresh_token":"2"}');
      expect(await kasa.oturum('a'), '{"refresh_token":"2"}');
    });

    test('düşen oturum silinir, hesap listede kalır', () async {
      await kasa.kaydet(_h('a'), oturumJson: '{}');
      await kasa.isaretle('a', oturumDustu: true);
      expect(await kasa.oturum('a'), isNull);
      expect((await kasa.liste()).single.oturumDustu, isTrue);
    });

    test('sil ve hepsiniSil anahtar bırakmaz', () async {
      await kasa.kaydet(_h('a'), oturumJson: '{}');
      await kasa.kaydet(_h('b'), oturumJson: '{}');
      await kasa.sil('a');
      expect((await kasa.liste()).map((h) => h.uid), ['b']);
      await kasa.hepsiniSil();
      expect(ham.m, isEmpty);
    });

    test('bozuk kayıt listeyi düşürmez', () async {
      ham.m['test_hesaplar_v1'] = '[{"uid":""},{"uid":"a","ad":"A"},5]';
      expect((await kasa.liste()).map((h) => h.uid), ['a']);
    });
  });

  group('saf kurallar', () {
    test('siradakiHesap: düşmemiş, en son kullanılan', () {
      final l = [_h('a', gunOnce: 1), _h('b', dustu: true), _h('c', gunOnce: 3)];
      expect(siradakiHesap(l, 'x')?.uid, 'a');
      expect(siradakiHesap(l, 'a')?.uid, 'c');
      expect(siradakiHesap([_h('a')], 'a'), isNull);
    });

    test('eklenebilir: aktif hesap listede yoksa o da sayılır', () {
      final dort = [for (var i = 0; i < 4; i++) _h('h$i')];
      expect(eklenebilir(dort, 'h0'), isTrue);
      expect(eklenebilir(dort, 'yeni'), isFalse);
      expect(eklenebilir([...dort, _h('h4')], 'h0'), isFalse);
    });

    test('baş harf Türkçe büyür', () {
      expect(_h('x').kopya(ad: 'ilker').basHarf, 'İ');
      expect(_h('x').kopya(ad: 'ışık').basHarf, 'I');
      expect(_h('x').kopya(ad: '').basHarf, 'X');
    });

    test('göreli zaman', () {
      final s = DateTime(2026, 10, 10, 14);
      expect(goreliZaman(s, s), 'az önce');
      expect(goreliZaman(s.subtract(const Duration(minutes: 5)), s), '5 dk önce');
      expect(goreliZaman(DateTime(2026, 10, 9, 23), s), 'dün');
      expect(goreliZaman(DateTime(2026, 10, 6), s), '4 gün önce');
      expect(goreliZaman(DateTime(2026, 9, 20), s), '2 hafta önce');
    });
  });

  group('görünürlük', () {
    tearDown(() => RemoteConfigService.testAcik = {});

    ProviderContainer kur(List<KayitliHesap> l,
        {bool paywall = false, bool admin = false}) {
      final c = ProviderContainer(overrides: [
        kayitliHesaplarProvider.overrideWithValue(l),
        paywallVisibleProvider.overrideWithValue(paywall),
        isPushAdminProvider.overrideWith((ref) async => admin),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('bayrak kapalıyken hiçbir koşulda görünmez (canlı birebir)', () {
      expect(kur([_h('a'), _h('b')], paywall: true).read(cokluHesapGorunurProvider),
          isFalse);
    });

    test('bayrak açık: paywall kapalı + tek hesap → yalnız admin görür', () async {
      RemoteConfigService.testAcik = {'coklu_hesap'};
      expect(kur([]).read(cokluHesapGorunurProvider), isFalse);
      expect(kur([], paywall: true).read(cokluHesapGorunurProvider), isTrue);
      final adminC = kur([], admin: true);
      await adminC.read(isPushAdminProvider.future);
      expect(adminC.read(cokluHesapGorunurProvider), isTrue);
    });

    test('cihazda 2+ hesap varsa her zaman görünür (geri dönüş yolu)', () {
      RemoteConfigService.testAcik = {'coklu_hesap'};
      expect(kur([_h('a'), _h('b')]).read(cokluHesapGorunurProvider), isTrue);
    });
  });

  group('UygulamaKabugu — veri sızıntısı bekçisi', () {
    testWidgets('nesil artınca önceki hesabın sağlayıcı durumu kalmaz',
        (tester) async {
      await tester.pumpWidget(UygulamaKabugu(
        uygulama: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => ref.read(_sayac.notifier).state++,
              child: Text('sayaç ${ref.watch(_sayac)}'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('sayaç 0'));
      await tester.tap(find.text('sayaç 0'));
      await tester.pump();
      expect(find.text('sayaç 2'), findsOneWidget);

      HesapGecisi.instance.perde.value = const HesapGecisPerdesi(
          basHarf: 'A', ad: 'ayse', alt: 'Hesaba geçiliyor');
      HesapGecisi.instance.nesil.value++;
      await tester.pump(); // boş kare: eski ağaç söner
      expect(find.textContaining('sayaç'), findsNothing,
          reason: 'eski ve yeni ağaç aynı karede yaşamamalı (GlobalKey)');
      expect(find.text('ayse'), findsOneWidget);
      await tester.pump(); // yeni kapsam
      await tester.pump(SandikMotion.modal);
      expect(find.text('sayaç 0'), findsOneWidget,
          reason: 'yeni hesap önceki hesabın durumunu görmemeli');
      expect(HesapGecisi.instance.perde.value, isNull);
      expect(find.text('ayse'), findsNothing);
    });

    testWidgets('nesil değişmezse kapsam korunur (bayrak kapalı = bugünkü)',
        (tester) async {
      await tester.pumpWidget(UygulamaKabugu(
        uygulama: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => ref.read(_sayac.notifier).state++,
              child: Text('sayaç ${ref.watch(_sayac)}'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('sayaç 0'));
      await tester.pump();
      HesapGecisi.instance.perde.value = null;
      await tester.pump();
      expect(find.text('sayaç 1'), findsOneWidget);
    });
  });

  group('hesap seçici', () {
    Future<void> ac(WidgetTester tester, List<KayitliHesap> l,
        {bool kilitli = false}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_SabitAuth.new),
          kayitliHesaplarProvider.overrideWithValue(l),
          hesapEklemeKilitliProvider.overrideWithValue(kilitli),
        ],
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
          home: Scaffold(
            body: Builder(
                builder: (ctx) => HesapSeciciSayfasi(ustContext: ctx)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('aktif hesap işaretli, diğerleri ve düşen oturum',
        (tester) async {
      await ac(tester, [
        _h('yasin'),
        _h('ayse', gunOnce: 1).kopya(sonKullanim: DateTime.now()
            .subtract(const Duration(days: 1))),
        _h('sirket', dustu: true),
      ]);
      expect(find.text('Hesaplar'), findsOneWidget);
      expect(find.text('Bu cihazda açık'), findsOneWidget);
      expect(find.text('Son açılış dün'), findsOneWidget);
      expect(find.text('Tekrar giriş gerekli'), findsOneWidget);
      expect(find.text('Mevcut hesabın açık kalır'), findsOneWidget);
    });

    testWidgets('Premium kilidi ve sınır', (tester) async {
      await ac(tester, [_h('yasin'), _h('ayse')], kilitli: true);
      expect(find.text('Premium ile'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);

      await ac(tester, [for (var i = 0; i < 5; i++) _h('h$i')]);
      expect(find.text('En fazla 5 hesap'), findsOneWidget);
    });

    testWidgets('düzenle modunda Kaldır görünür', (tester) async {
      await ac(tester, [_h('yasin'), _h('ayse')]);
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();
      expect(find.text('Bitti'), findsOneWidget);
      expect(find.text('Hesap ekle'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Kaldır')), findsWidgets);
    });

    testWidgets('dokunma hedefleri ≥ 44 pt (HIG)', (tester) async {
      await ac(tester, [_h('yasin'), _h('ayse')]);
      final dokunulanlar = find.byType(SandikTappable);
      expect(dokunulanlar, findsNWidgets(2)); // ayse satırı + Hesap ekle
      for (final e in dokunulanlar.evaluate()) {
        final kutu = tester.getRect(find.byWidget(e.widget));
        expect(kutu.height, greaterThanOrEqualTo(SandikTouch.min));
      }
    });
  });

  testWidgets('çoklu çıkış sayfası iki seçenek sunar', (tester) async {
    CokluCikis? secim;
    await tester.pumpWidget(MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async => secim = await cokluCikisSor(ctx, 'ayse', 2),
            child: const Text('aç'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    expect(find.text('Bu cihazda 2 hesap açık.'), findsOneWidget);
    expect(find.text('ayse hesabından çık'), findsOneWidget);
    await tester.tap(find.text('Tüm hesaplardan çık'));
    await tester.pumpAndSettle();
    expect(secim, CokluCikis.tumu);
  });
}
