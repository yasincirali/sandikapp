import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/models/yuzde_alarmi.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/providers/yuzde_alarmi_provider.dart';
import 'package:portfoy_takip/screens/price_alerts_screen.dart';
import 'package:portfoy_takip/screens/watchlist_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Takip listesi satırındaki alarm çanı (2026-10-26): etkin alarm → çan +
/// fiyata en yakın hedef (+N); tetiklenmiş/kapalı alarm çan göstermez;
/// alarmsız satır eskisi gibi; çan ayrı 44 pt hedef, o varlığın alarmlarını
/// açar; büyük yazıda taşma yok.
PriceAlert _alarm(String id, String sembol, double hedef,
        {bool enabled = true, DateTime? tetik, String yon = 'above'}) =>
    PriceAlert(
      id: id,
      userId: 'u1',
      symbol: sembol,
      label: sembol == 'SISE.IS' ? 'Şişe Cam' : 'Türk Hava Yolları',
      targetPrice: hedef,
      direction: yon,
      enabled: enabled,
      triggeredAt: tetik,
      createdAt: DateTime(2026, 10, 1),
    );

WatchlistItem _kalem(String id, String ticker, String ad, double? fiyat) =>
    WatchlistItem(
      id: id,
      userId: 'u1',
      ticker: ticker,
      name: ad,
      type: AssetType.hisse,
      currency: 'TRY',
      addedAt: DateTime(2026, 9, 1),
      currentPrice: fiyat,
      periodChangePct: 1.0,
    );

class _SabitListe extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => [
        _kalem('1', 'SISE.IS', 'Şişe Cam', 38.46),
        _kalem('2', 'THYAO.IS', 'Türk Hava Yolları', 300),
        _kalem('3', 'ASELS.IS', 'Aselsan', 150),
      ];
}

List<PriceAlert> _alarmlar = const [];

class _SabitAlarmlar extends PriceAlertsNotifier {
  @override
  Future<List<PriceAlert>> build() async => _alarmlar;
}

List<YuzdeAlarmi> _yuzdeler = const [];

class _SabitYuzdeler extends YuzdeAlarmlariNotifier {
  @override
  Future<List<YuzdeAlarmi>> build() async => _yuzdeler;
}

YuzdeAlarmi _yuzde(String id, String sembol, double esik,
        {YuzdeYon yon = YuzdeYon.ikisi,
        bool enabled = true,
        String? sonTetikGunu}) =>
    YuzdeAlarmi(
      id: id,
      userId: 'u1',
      symbol: sembol,
      label: sembol,
      esikPct: esik,
      yon: yon,
      enabled: enabled,
      sonTetikGunu: sonTetikGunu,
      createdAt: DateTime(2026, 10, 28),
    );

Future<void> _pump(WidgetTester tester,
    {double genislik = 390, double olcek = 1}) async {
  tester.view.physicalSize = Size(genislik * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      watchlistProvider.overrideWith(_SabitListe.new),
      watchlistChartProvider.overrideWith((ref) async => const {}),
      activePartnersProvider.overrideWithValue(const []),
      watchlistLimitProvider.overrideWithValue(1 << 30),
      priceAlertsProvider.overrideWith(_SabitAlarmlar.new),
      yuzdeAlarmlariProvider.overrideWith(_SabitYuzdeler.new),
    ],
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(olcek)),
        child: child!,
      ),
      home: const Scaffold(body: WatchlistBody()),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Finder _can() => find.bySemanticsLabel('Alarmları aç');

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _alarmlar = const [];
    _yuzdeler = const [];
  });

  // Ar-Ge 27 Eki 12:45 #1 (yasin 29 Eki "yap"): çan yüzde alarmını da okur.
  group('takipCaniOzeti (saf)', () {
    test('yalnız yüzde alarmı → en dar eşik önde, kalanlar +N', () {
      final o = takipCaniOzeti(const [], [
        _yuzde('a', 'X', 3),
        _yuzde('b', 'X', 1, yon: YuzdeYon.dusus),
        _yuzde('c', 'X', 2, enabled: false),
        _yuzde('d', 'Y', 1),
      ], sembol: 'X')!;
      expect(o.fiyat, isNull);
      expect(o.yuzde!.id, 'b');
      expect(o.digerSayisi, 1, reason: 'kapalı ve başka sembol sayılmaz');
      expect(yuzdeKisaMetni(o.yuzde!), '\u2212%1');
    });

    test('fiyat alarmı varsa önde; yüzde alarmları +N sayısına girer', () {
      final o = takipCaniOzeti([_alarm('a', 'X', 40)], [_yuzde('b', 'X', 2)],
          sembol: 'X', guncelFiyat: 38)!;
      expect(o.fiyat!.id, 'a');
      expect(o.yuzde, isNull);
      expect(o.digerSayisi, 1);
    });

    test('hiç etkin alarm yoksa null', () {
      expect(takipCaniOzeti(const [], const [], sembol: 'X'), isNull);
      expect(
          takipCaniOzeti(const [], [_yuzde('a', 'X', 2, enabled: false)],
              sembol: 'X'),
          isNull);
    });

    test('kısa metin yönü işaretle yazar', () {
      expect(yuzdeKisaMetni(_yuzde('a', 'X', 2)), '±%2');
      expect(
          yuzdeKisaMetni(_yuzde('a', 'X', 2, yon: YuzdeYon.yukselis)), '+%2');
      expect(yuzdeKisaMetni(_yuzde('a', 'X', 1.5)), '±%1,5');
    });
  });

  testWidgets('yalnız yüzde alarmı → çan "±%2"; cümlede günlük yüzde',
      (tester) async {
    _yuzdeler = [_yuzde('y', 'SISE.IS', 2)];
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    expect(find.text('±%2'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    final etiket = tester
        .getSemantics(find.bySemanticsLabel(RegExp(r'^Şişe Cam, ')))
        .label;
    expect(etiket, contains('Günlük %2 hareket alarmı kurulu'));
    expect(etiket, isNot(contains('bugün çaldı')));
    semantics.dispose();
  });

  testWidgets('bugün çalmış yüzde alarmı → boş zil, cümlede "bugün çaldı"',
      (tester) async {
    _yuzdeler = [
      _yuzde('y', 'SISE.IS', 2, sonTetikGunu: yuzdeAlarmGunu(DateTime.now())),
    ];
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_rounded), findsNothing);
    final etiket = tester
        .getSemantics(find.bySemanticsLabel(RegExp(r'^Şişe Cam, ')))
        .label;
    expect(etiket, contains('bugün çaldı'));
    semantics.dispose();
  });

  testWidgets('fiyat + yüzde alarmı → fiyat hedefi ve +1', (tester) async {
    _alarmlar = [_alarm('a', 'SISE.IS', 40)];
    _yuzdeler = [_yuzde('y', 'SISE.IS', 2)];
    await _pump(tester);
    expect(find.text('₺40,00 +1'), findsOneWidget);
    expect(find.text('±%2'), findsNothing);
  });

  group('etkinAlarmOzeti (saf)', () {
    test('etkin alarm yoksa null; tetiklenmiş ve kapalı sayılmaz', () {
      expect(etkinAlarmOzeti(const []), isNull);
      expect(
        etkinAlarmOzeti([
          _alarm('a', 'SISE.IS', 40, tetik: DateTime(2026, 10, 2)),
          _alarm('b', 'SISE.IS', 41, enabled: false),
        ], guncelFiyat: 38),
        isNull,
      );
    });

    test('güncel fiyata en yakın hedef; kalanlar +N', () {
      final o = etkinAlarmOzeti([
        _alarm('a', 'X', 4500),
        _alarm('b', 'X', 4300, yon: 'below'),
        _alarm('c', 'X', 4250, tetik: DateTime(2026, 10, 2)),
        _alarm('d', 'X', 3000, yon: 'below'),
      ], guncelFiyat: 4200)!;
      expect(o.enYakin.id, 'b');
      expect(o.digerSayisi, 2, reason: 'tetiklenmiş alarm +N\'e girmez');
    });

    test('fiyat bilinmiyorsa liste sırası (uydurma mesafe yok)', () {
      final o = etkinAlarmOzeti([_alarm('a', 'X', 10), _alarm('b', 'X', 5)],
          guncelFiyat: null)!;
      expect(o.enYakin.id, 'a');
      expect(o.digerSayisi, 1);
    });

    test('eşit mesafede listedeki ilk kazanır', () {
      final o = etkinAlarmOzeti([_alarm('a', 'X', 110), _alarm('b', 'X', 90)],
          guncelFiyat: 100)!;
      expect(o.enYakin.id, 'a');
    });
  });

  testWidgets('etkin alarm → çan + hedef; semantik cümlede hedef',
      (tester) async {
    _alarmlar = [_alarm('a', 'SISE.IS', 40)];
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    expect(find.text('₺40,00'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    expect(_can(), findsOneWidget);

    final satir = find.bySemanticsLabel(RegExp(r'^Şişe Cam, '));
    final etiket = tester.getSemantics(satir).label;
    expect(etiket, contains('₺40,00 için alarm kurulu'));
    expect(etiket, isNot(contains('alarm daha')));
    expect(etiket, isNot(contains('Alarmları aç')),
        reason: 'çan kendi düğümü; satır cümlesine karışmaz');
    semantics.dispose();
  });

  testWidgets('çoklu etkin alarm → en yakın hedef + N', (tester) async {
    _alarmlar = [
      _alarm('a', 'THYAO.IS', 330),
      _alarm('b', 'THYAO.IS', 290, yon: 'below'),
      _alarm('c', 'THYAO.IS', 250, yon: 'below'),
    ];
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    expect(find.text('₺290,00 +2'), findsOneWidget);
    final etiket = tester
        .getSemantics(find.bySemanticsLabel(RegExp(r'^Türk Hava Yolları, ')))
        .label;
    expect(etiket, contains('₺290,00 için alarm kurulu ve 2 alarm daha'));
    semantics.dispose();
  });

  testWidgets('tetiklenmiş ya da kapalı alarm çan göstermez', (tester) async {
    _alarmlar = [
      _alarm('a', 'SISE.IS', 40, tetik: DateTime(2026, 10, 2)),
      _alarm('b', 'THYAO.IS', 290, enabled: false),
    ];
    await _pump(tester);
    expect(find.byIcon(Icons.notifications_active_rounded), findsNothing);
    expect(find.textContaining('₺40,00'), findsNothing);
  });

  testWidgets('alarmsız satır eskisiyle aynı yükseklikte ve çansız',
      (tester) async {
    _alarmlar = const [];
    await _pump(tester);
    final once = tester.getSize(find
        .ancestor(of: find.text('ASELS'), matching: find.byType(Container))
        .first);

    // Aynı kapsamda alarm listesi değişir (alarm kuruldu): yalnız alarm
    // sağlayıcısı yeniden okunur.
    _alarmlar = [_alarm('a', 'SISE.IS', 40)];
    ProviderScope.containerOf(tester.element(find.text('ASELS')))
        .invalidate(priceAlertsProvider);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final sonra = tester.getSize(find
        .ancestor(of: find.text('ASELS'), matching: find.byType(Container))
        .first);
    expect(sonra, once, reason: 'başka satırın alarmı bu satırı değiştirmez');
    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
  });

  testWidgets('çan ≥44 pt ve dokununca o varlığın alarmlarını açar',
      (tester) async {
    _alarmlar = [
      _alarm('a', 'SISE.IS', 40),
      _alarm('b', 'THYAO.IS', 290),
    ];
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    final can = find.ancestor(
        of: find.byIcon(Icons.notifications_active_rounded),
        matching: find.byType(SandikTappable));
    final boyut = tester.getSize(can.first);
    expect(boyut.width, greaterThanOrEqualTo(SandikTouch.min));
    expect(boyut.height, greaterThanOrEqualTo(SandikTouch.min));
    semantics.dispose();

    await tester.tap(can.first);
    await tester.pumpAndSettle();

    final ekran =
        tester.widget<PriceAlertsScreen>(find.byType(PriceAlertsScreen));
    expect(ekran.sembol, 'SISE.IS');
    // Süzülmüş liste: yalnız Şişe Cam'in alarmı.
    expect(find.text('Şişe Cam'), findsOneWidget);
    expect(find.text('Türk Hava Yolları'), findsNothing);
  });

  testWidgets('3.1× yazıda taşma yok, hedef görünür', (tester) async {
    _alarmlar = [
      _alarm('a', 'THYAO.IS', 290),
      _alarm('b', 'THYAO.IS', 350),
    ];
    // Bilinen, bu işten bağımsız taşmalar: gövdenin başlıkları ("N varlık"
    // + sıralama düğmesi, "Listede n" kartı) 3.1×'te 320 pt'ye sığmıyor
    // (2026-10-26 bulgusu; ayrı iş). Yalnız takip SATIRININ kaynağındaki
    // (`_Row` … `_EmptyState` arası, çan dahil) taşma testi kırar.
    final kaynak =
        ekranKaynagiSync('lib/screens/watchlist_screen.dart').split('\n');
    final bas = kaynak.indexWhere((l) => l.startsWith('class _Row ')) + 1;
    final son =
        kaynak.indexWhere((l) => l.startsWith('class _EmptyState ')) + 1;
    expect(bas, greaterThan(0));
    expect(son, greaterThan(bas));
    final konum = RegExp(r'watchlist_screen\.dart:(\d+):');
    final hatalar = <FlutterErrorDetails>[];
    final eski = FlutterError.onError;
    FlutterError.onError = hatalar.add;
    await _pump(tester, genislik: 320, olcek: 3.1);
    FlutterError.onError = eski;
    final ilgili = [
      for (final h in hatalar)
        if (konum
            .allMatches(h.toString())
            .map((m) => int.parse(m[1]!))
            .any((satir) => satir >= bas && satir < son))
          h,
    ];
    expect(ilgili, isEmpty, reason: ilgili.join('\n'));
    expect(find.text('₺290,00 +1'), findsOneWidget);
    // Ad kısalmaz: çan sığmayınca alt satıra iner (ad'ın altında).
    final ad = tester.getRect(find.text('THYAO'));
    final hedef = tester.getRect(find.text('₺290,00 +1'));
    expect(hedef.top, greaterThanOrEqualTo(ad.bottom));
  });
}
