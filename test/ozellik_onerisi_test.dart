import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/ozellik_onerisi_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/main_navigation_screen.dart';
import 'package:portfoy_takip/services/ozellik_onerisi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/ozellik_onerisi_karti.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ana ekran özellik önerisi (yasin isteği 2026-10-20): kullanılmayan
/// özelliğe tek kart, kapatılabilir, yönlendirir.
final _simdi = DateTime(2026, 10, 20, 21);

OzellikOnerisi? _karar({
  int varlik = 3,
  int? alarm = 0,
  int? takip = 0,
  int? ortak = 0,
  bool zirveAcik = true,
  bool? zirveRizasi = false,
  Set<String> kapatilan = const {},
  DateTime? sonKapatma,
}) =>
    siradakiOneri(
      varlikSayisi: varlik,
      alarmSayisi: alarm,
      takipSayisi: takip,
      ortakSayisi: ortak,
      zirveAcik: zirveAcik,
      zirveRizasi: zirveRizasi,
      kapatilanlar: kapatilan,
      sonKapatma: sonKapatma,
      simdi: _simdi,
    );

void main() {
  group('siradakiOneri', () {
    test('sıra: alarm, takip, ortak, Zirve', () {
      expect(_karar(), OzellikOnerisi.alarm);
      expect(_karar(alarm: 2), OzellikOnerisi.takip);
      expect(_karar(alarm: 2, takip: 1), OzellikOnerisi.ortak);
      expect(_karar(alarm: 2, takip: 1, ortak: 1), OzellikOnerisi.zirve);
      expect(_karar(alarm: 2, takip: 1, ortak: 1, zirveRizasi: true), isNull,
          reason: 'hepsi kullanılıyor');
    });

    test('varlık yoksa susar (iş ilk varlığı eklemek)', () {
      expect(_karar(varlik: 0), isNull);
    });

    test('kapatılan bir daha gelmez, sıradaki gelir', () {
      expect(_karar(kapatilan: {'alarm'}), OzellikOnerisi.takip);
      expect(_karar(kapatilan: {'alarm', 'takip', 'ortak', 'zirve'}), isNull);
    });

    test('kapatmadan sonra 3 gün nefes', () {
      final dun = _simdi.subtract(const Duration(days: 1));
      expect(_karar(kapatilan: {'alarm'}, sonKapatma: dun), isNull);
      final once = _simdi.subtract(const Duration(days: 3));
      expect(
          _karar(kapatilan: {'alarm'}, sonKapatma: once), OzellikOnerisi.takip);
    });

    test('yüklenmemiş veri: yanlış "kurmadın" yerine susar', () {
      expect(_karar(alarm: null), isNull);
      expect(_karar(alarm: 1, takip: null), isNull,
          reason: 'sıra yüklemeye göre atlamaz');
      expect(_karar(alarm: 1, takip: 1, ortak: 1, zirveRizasi: null), isNull);
    });

    test('Zirve bayrağı kapalıysa Zirve önerisi yok', () {
      expect(_karar(alarm: 1, takip: 1, ortak: 1, zirveAcik: false), isNull);
    });

    test('anahtarlar sabit (kalıcı kayıt bunlarla tutulur)', () {
      expect(OzellikOnerisi.values.map((o) => o.anahtar),
          ['alarm', 'takip', 'ortak', 'zirve']);
    });
  });

  group('OzellikOnerisiKarti', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
    });

    Future<ProviderContainer> ac(WidgetTester t, OzellikOnerisi? oneri,
        {double olcek = 1}) async {
      final c = ProviderContainer(overrides: [
        ozellikOnerisiProvider.overrideWithValue(oneri),
      ]);
      addTearDown(c.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(olcek)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: OzellikOnerisiKarti()),
          ),
        ),
      ));
      await t.pumpAndSettle();
      return c;
    }

    testWidgets('öneri yoksa yer kaplamaz', (t) async {
      await ac(t, null);
      expect(find.byType(SandikCard), findsNothing);
    });

    testWidgets('her öneri kendi başlığıyla çizilir', (t) async {
      for (final (o, metin) in [
        (OzellikOnerisi.alarm, 'Fiyat alarmı kur'),
        (OzellikOnerisi.takip, 'Almadan önce takibe al'),
        (OzellikOnerisi.ortak, 'Ortak ekle, birlikte izleyin'),
        (OzellikOnerisi.zirve, 'Zirvedeki portföylerde ne var?'),
      ]) {
        await ac(t, o);
        expect(find.text(metin), findsOneWidget, reason: o.name);
      }
    });

    testWidgets('kapat: öneri ve zaman kalıcı kaydedilir', (t) async {
      final c = await ac(t, OzellikOnerisi.takip);
      await t.tap(find.byTooltip('Bu öneriyi gizle'));
      await t.pump();
      expect(c.read(ozellikOnerisiKapatilanProvider), {'takip'});
      expect(c.read(ozellikOnerisiSonKapatmaProvider), greaterThan(0));
    });

    testWidgets('ortak: Profil sekmesine götürür ve öneri düşer', (t) async {
      MainNavigationScreen.sekmeIstegi.value = null;
      addTearDown(() => MainNavigationScreen.sekmeIstegi.value = null);
      final c = await ac(t, OzellikOnerisi.ortak);
      await t.tap(find.text('Ortak ekle, birlikte izleyin'));
      await t.pump();
      expect(MainNavigationScreen.sekmeIstegi.value,
          MainNavigationScreen.profilSekmesi);
      expect(c.read(ozellikOnerisiKapatilanProvider), {'ortak'});
    });

    testWidgets('dokunma alanı ≥44 pt, ×2 ve ×3,1 yazıda taşma yok', (t) async {
      for (final olcek in [1.0, 2.0, 3.1]) {
        await ac(t, OzellikOnerisi.zirve, olcek: olcek);
        expect(t.takeException(), isNull, reason: 'ölçek $olcek');
        final kapat = t.getSize(find.byTooltip('Bu öneriyi gizle'));
        expect(kapat.width, greaterThanOrEqualTo(44));
        expect(kapat.height, greaterThanOrEqualTo(44));
      }
    });
  });
}
