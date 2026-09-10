import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/technical_signal.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/screens/performance_screen.dart';

/// "Aktif Sinyal" bölümünün GERÇEKTEN ÇİZİLDİĞİNİ doğrular.
///
/// **Neden ayrı bir dosya:** `varlik_sinyal_karti_test.dart` seçim kuralını
/// (hangi kayıt aktif) saf fonksiyon üzerinden kilitliyor. Ama bir widget
/// derlenip testleri geçip yine de ekranda hiçbir şey çizmeyebilir —
/// emülatör Flutter'ı render edemediği için (bkz. CLAUDE.md) gözle
/// bakmanın da yolu yok. Bu dosya o boşluğu kapatır: widget'ı gerçekten
/// pump eder ve kullanıcının GÖRECEĞİ metni arar.
class _SahteSinyaller extends SignalNotifier {
  _SahteSinyaller(this._veri);
  final List<SignalAlert> _veri;

  @override
  Future<List<SignalAlert>> build() async => _veri;
}

Asset _asset({AssetType type = AssetType.hisse}) => Asset(
      id: 'lot-1',
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: type,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
    );

SignalAlert _alert({
  required DateTime at,
  SignalType signal = SignalType.sell,
  int buyCount = 1,
  int sellCount = 3,
  double confidence = 60,
  DateTime? dismissedAt,
}) =>
    SignalAlert(
      assetId: 'sunucu-lot',
      assetName: 'Türk Hava Yolları',
      assetTicker: 'THYAO.IS',
      assetType: AssetType.hisse,
      signal: signal,
      buyCount: buyCount,
      sellCount: sellCount,
      confidence: confidence,
      detectedAt: at,
      dismissedAt: dismissedAt,
    );

Future<void> _pump(
  WidgetTester tester,
  List<SignalAlert> alerts, {
  AssetType type = AssetType.hisse,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signalProvider.overrideWith(() => _SahteSinyaller(alerts)),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AktifSinyalBolumu(asset: _asset(type: type)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('aktif kayıt varsa bölüm ÇİZİLİR', (tester) async {
    await _pump(tester, [
      _alert(at: DateTime.now().subtract(const Duration(hours: 3))),
    ]);

    expect(find.text('AKTİF SİNYAL'), findsOneWidget);
    // Yasal dil: "SAT" değil trend yönü (ekranın geri kalanıyla aynı).
    expect(find.text('AŞAĞI TREND'), findsOneWidget);
    expect(find.text('%60'), findsOneWidget);
    expect(find.text('3 saat önce'), findsOneWidget);
    expect(find.text('3/4 gösterge'), findsOneWidget);
  });

  testWidgets('yukarı trend yeşil ve doğru sözcükle çizilir', (tester) async {
    await _pump(tester, [
      _alert(
        at: DateTime.now().subtract(const Duration(minutes: 30)),
        signal: SignalType.buy,
        buyCount: 4,
        sellCount: 1,
        confidence: 82,
      ),
    ]);

    expect(find.text('YUKARI TREND'), findsOneWidget);
    expect(find.text('%82'), findsOneWidget);
    expect(find.text('4/5 gösterge'), findsOneWidget);
    expect(find.text('30 dk önce'), findsOneWidget);
  });

  testWidgets('kayıt yoksa hiçbir şey çizilmez', (tester) async {
    await _pump(tester, const []);
    expect(find.text('AKTİF SİNYAL'), findsNothing);
  });

  testWidgets('silinmiş kayıtta bölüm çizilmez', (tester) async {
    await _pump(tester, [
      _alert(
        at: DateTime.now().subtract(const Duration(hours: 2)),
        dismissedAt: DateTime.now(),
      ),
    ]);
    expect(find.text('AKTİF SİNYAL'), findsNothing);
  });

  testWidgets('eski kayıtta bölüm çizilmez', (tester) async {
    await _pump(tester, [
      _alert(at: DateTime.now().subtract(const Duration(days: 9))),
    ]);
    expect(find.text('AKTİF SİNYAL'), findsNothing);
  });

  testWidgets('gösterge sayısı yoksa kırılım satırı çizilmez', (tester) async {
    // Sıfır/sıfır bir dağılım bilgi taşımaz; kart yine de görünmeli ama
    // altındaki sayaç satırı olmamalı.
    await _pump(tester, [
      _alert(
        at: DateTime.now().subtract(const Duration(hours: 1)),
        buyCount: 0,
        sellCount: 0,
      ),
    ]);
    expect(find.text('AKTİF SİNYAL'), findsOneWidget);
    expect(find.textContaining('gösterge'), findsNothing);
  });

  // Dar ekran + büyük yazı. İlk yazılışında bu test GERÇEK bir taşma
  // yakaladı (141px ve 266px): güven skoru bloğu ile sayaç satırı doğal
  // genişliklerini istiyordu, uzun tarih biçimi ise tek başına 470px
  // tutuyordu. Emülatör Flutter'ı render edemediği için (bkz. CLAUDE.md)
  // bu hata ancak burada görülebilirdi.
  //
  // `MediaQuery`'yi elle sarmak YETMEZ: dıştaki `MaterialApp` kendi
  // MediaQuery'sini kurar ve genişlik yine tam ekran kalır — ölçüm
  // sırasında ekran genişliği 0.0 çıkıp testin dar ekranı hiç
  // sınamadığı ortaya çıktı. Genişliği `SizedBox` ile dayatmak
  // kesin ve okunur bir sınırdır.
  for (final (genislik, olcek) in const [
    (320.0, 1.0),
    (320.0, 1.6),
    (390.0, 2.0),
  ]) {
    testWidgets('taşmaz — ${genislik.toInt()}pt × $olcek', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signalProvider.overrideWith(() => _SahteSinyaller([
                  _alert(
                    at: DateTime.now().subtract(const Duration(hours: 5)),
                    confidence: 100,
                    buyCount: 12,
                    sellCount: 34,
                  ),
                ])),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(olcek)),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: genislik,
                    child: SingleChildScrollView(
                      child: AktifSinyalBolumu(asset: _asset()),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
