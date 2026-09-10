import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/technical_signal.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/screens/performance_screen.dart';

/// Sinyal şeridi tasarım örneğindeki BİLGİLERİN HEPSİNİ taşımalı.
///
/// Kullanıcı isteği (2026-09-10, görsel örnekle): "tüm bilgiler eklediğim
/// görseldeki şekilde okunabilir olmalı, **data kaybı olmamalı** ve
/// tasarımda da sırıtmamalı."
///
/// Örnekteki alanlar:
///   1. "TEKNİK GÖRÜNÜM"  → üst etiket (şeridin ne olduğu)
///   2. "AŞAĞI TREND"     → yön başlığı
///   3. "2/3 gösterge · güven %67" → dayanak
///   4. "Son bildirim: ▼ aşağı · 10 dk önce" → kayıt + göreli zaman
///   5. "ŞU AN" + yön ikonu → sağ sütun
///
/// Bu dosya kaynak denetimi DEĞİL, gerçek render — metin ekranda yoksa
/// test kırılır. Kaynak denetimi bir alanın `Text` olarak yazıldığını
/// görür ama ekrana ulaşıp ulaşmadığını göremez.
class _SahteSinyaller extends SignalNotifier {
  _SahteSinyaller(this._veri);
  final List<SignalAlert> _veri;

  @override
  Future<List<SignalAlert>> build() async => _veri;
}

Asset _asset() => Asset(
      id: 'lot-1',
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
    );

SignalAlert _alert(DateTime an) => SignalAlert(
      assetId: 'sunucu-lot',
      assetName: 'Türk Hava Yolları',
      assetTicker: 'THYAO.IS',
      assetType: AssetType.hisse,
      signal: SignalType.sell,
      buyCount: 1,
      sellCount: 2,
      confidence: 67,
      detectedAt: an,
    );

Future<void> _bas(WidgetTester tester, DateTime an) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signalProvider.overrideWith(() => _SahteSinyaller([_alert(an)])),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AssetSignalCard(asset: _asset(), onTap: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Ekrandaki tüm `Text`leri tek gövdede toplar — metin birden çok
/// widget'a bölünmüş olsa da arama çalışsın.
String _ekranMetni(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join('\n');

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('üst etiket ekranda — "TEKNİK GÖRÜNÜM"', (tester) async {
    await _bas(tester, DateTime.now().subtract(const Duration(minutes: 10)));
    expect(find.text('TEKNİK GÖRÜNÜM'), findsOneWidget,
        reason: 'Şeridin ne olduğunu söyleyen üst etiket kayıp.');
  });

  testWidgets('göreli zaman ekranda — "10 dk önce"', (tester) async {
    await _bas(tester, DateTime.now().subtract(const Duration(minutes: 10)));
    final metin = _ekranMetni(tester);
    expect(metin.contains('10 dk önce'), isTrue,
        reason: 'Göreli zaman yok. Ekrandaki metin:\n$metin');
    expect(metin.contains('Son bildirim'), isTrue,
        reason: 'Kayıt satırının etiketi kayıp.');
  });

  testWidgets('yön işareti kayıt satırında — "▼ aşağı"', (tester) async {
    await _bas(tester, DateTime.now().subtract(const Duration(minutes: 10)));
    expect(_ekranMetni(tester).contains('▼ aşağı'), isTrue,
        reason: 'Bildirimin YÖNÜ kayıp — kayıt satırı yönsüz kalırsa '
            'kullanıcı hangi sinyalin geldiğini bilemez.');
  });

  testWidgets('sağ sütunda MUTLAK tarih+saat ve yön ikonu', (tester) async {
    // Testte ağ yok → fiyat geçmişi boş → şerit CANLI hesap yapamaz ve
    // kaydı gösterir. Bu, push bildiriminin açtığı gerçek durumla aynı
    // yol; sağ sütun "ŞU AN" değil TAM tarih+saat yazmalı.
    final an = DateTime.now().subtract(const Duration(minutes: 10));
    await _bas(tester, an);

    final metin = _ekranMetni(tester);
    final beklenen = DateFormat('d MMM · HH:mm', 'tr_TR').format(an);
    expect(metin.contains(beklenen), isTrue,
        reason: 'Mutlak tarih+saat kayıp — kullanıcı bildirimin tam '
            'zamanını kaçırmamalı. Ekrandaki metin:\n$metin');

    // Yön ikonu iki kez: solda daire içinde, sağda sütunda (örnekteki gibi).
    expect(find.byIcon(Icons.trending_down_rounded), findsNWidgets(2),
        reason: 'Sağ sütundaki yön ikonu kayıp.');
  });

  testWidgets('göreli VE mutlak zaman BİRLİKTE durur', (tester) async {
    // İkisi birbirinin yerine geçmez: "10 dk önce" hızlı okunur, tam
    // tarih ise aynı gün gelen iki sinyali ayırt ettirir. Kullanıcı
    // ikisini de istedi ("data kaybı olmamalı").
    final an = DateTime.now().subtract(const Duration(minutes: 10));
    await _bas(tester, an);

    final metin = _ekranMetni(tester);
    expect(metin.contains('10 dk önce'), isTrue, reason: 'Göreli kayıp.');
    expect(metin.contains(DateFormat('d MMM · HH:mm', 'tr_TR').format(an)),
        isTrue,
        reason: 'Mutlak kayıp.');
  });

  testWidgets('dokunma göstergesi (chevron) duruyor', (tester) async {
    await _bas(tester, DateTime.now().subtract(const Duration(minutes: 10)));
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget,
        reason: 'Kart tıklanabilir ama bunu gösteren işaret yok.');
  });

  testWidgets('YASAL: "AL"/"SAT" kelimeleri geçmez', (tester) async {
    // Play finansal hizmet politikası: kesin alım-satım tavsiyesi dili
    // kullanılamaz. Şerit yalnızca trend YÖNÜ söyler.
    await _bas(tester, DateTime.now().subtract(const Duration(minutes: 10)));
    final metin = _ekranMetni(tester);
    for (final yasak in ['AL SİNYALİ', 'SAT SİNYALİ', 'ALIM ÖNERİSİ']) {
      expect(metin.contains(yasak), isFalse, reason: '"$yasak" ekranda.');
    }
  });
}
