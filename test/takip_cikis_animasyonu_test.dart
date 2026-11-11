import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/watchlist_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **Takipten çıkarılan satır solup daralarak gider (2026-11-11).**
///
/// Eskiden satır bir karede siliniyordu. Kilitlenen sözleşme: çıkış
/// süresince satır ağaçta kalır, `notifier.remove` animasyon BİTİNCE ve
/// bir kez çağrılır; çift tetikleme yok sayılır; hata yolunda satır geri
/// açılır; hareketi azalt açıkken animasyon yoktur, kaldırma hemen olur.
class _Liste extends WatchlistNotifier {
  _Liste({this.hata = false});

  final bool hata;
  int removeSayisi = 0;

  @override
  Future<List<WatchlistItem>> build() async => [
        _kalem('1', 'SISE.IS', 'Şişe Cam'),
        _kalem('2', 'XU100.IS', 'BIST 100 Endeksi'),
      ];

  // Hata yolu listeye dokunmadan fırlatır: gerçek sağlayıcı iyimser
  // düşürüp geri koyar, o zaman satır yeni bir durumla (tam boy) yeniden
  // kurulur. Burada ölçülen ZOR yol: aynı satır durumu kalır ve kendisi
  // geri açılmalı.
  @override
  Future<void> remove(String id) async {
    removeSayisi++;
    if (hata) throw Exception('ağ yok');
    final once = state.valueOrNull ?? const [];
    state = AsyncData(once.where((w) => w.id != id).toList());
  }
}

WatchlistItem _kalem(String id, String ticker, String ad) => WatchlistItem(
      id: id,
      userId: 'u1',
      ticker: ticker,
      name: ad,
      type: AssetType.hisse,
      currency: 'TRY',
      addedAt: DateTime(2026, 9, 1),
      currentPrice: 38.46,
      periodChangePct: -2.93,
    );

Future<void> _pump(WidgetTester tester, _Liste liste,
    {bool hareketiAzalt = false}) async {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      watchlistProvider.overrideWith(() => liste),
      watchlistChartProvider.overrideWith((ref) async => const {}),
      activePartnersProvider.overrideWithValue(const []),
      watchlistLimitProvider.overrideWithValue(1 << 30),
    ],
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: hareketiAzalt),
        child: child!,
      ),
      home: const Scaffold(body: WatchlistBody()),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

final _satir = find.bySemanticsLabel(RegExp(r'^Şişe Cam, '));

/// Ekran okuyucunun "Takipten çıkar" özel eylemini çalıştırır.
void _cikar(WidgetTester tester) {
  final dugum = tester.getSemantics(_satir);
  tester.binding.performSemanticsAction(SemanticsActionEvent(
    type: SemanticsAction.customAction,
    viewId: tester.view.viewId,
    nodeId: dugum.id,
    arguments: CustomSemanticsAction.getIdentifier(
        const CustomSemanticsAction(label: 'Takipten çıkar')),
  ));
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('çıkış süresince satır var, sonra yok; remove bir kez',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final liste = _Liste();
    await _pump(tester, liste);
    expect(_satir, findsOneWidget);

    _cikar(tester);
    await tester.pump();
    await tester.pump(SandikMotion.state ~/ 2);
    expect(find.text('Şişe Cam'), findsOneWidget,
        reason: 'Satır animasyon bitmeden ağaçtan kalktı (bir karede '
            'yok oluyor).');
    expect(liste.removeSayisi, 0,
        reason: 'Kaldırma animasyon bitmeden çağrıldı: liste sırası '
            'animasyon sürerken kayar.');

    // Çift tetikleme: animasyon sürerken ikinci çıkar yok sayılır.
    _cikar(tester);
    await tester.pump(SandikMotion.state);
    await tester.pump();
    expect(find.text('Şişe Cam'), findsNothing);
    expect(liste.removeSayisi, 1);
    expect(find.text('BIST 100 Endeksi'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('hareketi azalt açık: animasyon yok, hemen kaldırılır',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final liste = _Liste();
    await _pump(tester, liste, hareketiAzalt: true);

    _cikar(tester);
    await tester.pump();
    expect(liste.removeSayisi, 1,
        reason: 'Hareketi azalt açıkken kaldırma beklememeli.');
    await tester.pump();
    expect(find.text('Şişe Cam'), findsNothing);
    semantics.dispose();
  });

  testWidgets('hata: satır geri açılır, hata mesajı görünür', (tester) async {
    final semantics = tester.ensureSemantics();
    final liste = _Liste(hata: true);
    await _pump(tester, liste);

    _cikar(tester);
    await tester.pump();
    await tester.pump(SandikMotion.state);
    // Hata dönüşü ve geri açılış birkaç kare sürer.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(liste.removeSayisi, 1);
    expect(find.text('Şişe Cam'), findsOneWidget);
    expect(find.textContaining('Takipten çıkarılamadı'), findsOneWidget);
    // Satır tam boyda: daralmış (görünmez) hâlde kalmadı.
    expect(tester.getSize(find.byType(SizeTransition).first).height,
        greaterThan(40));
    // Geri açılan satır yeniden çıkarılabilir (kilit kalkmış).
    _cikar(tester);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(liste.removeSayisi, 2);
    await tester.pump(const Duration(seconds: 5));
    semantics.dispose();
  });
}
