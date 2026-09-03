import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/screens/comparison_screen.dart';

/// Karşılaştırma ekranı — çizim ve boş durum.
///
/// Ağ çağrısı yapılmadığı sürece ekran boş durumda açılmalı ve HİÇBİR
/// taşma/exception üretmemeli. `flutter analyze` bu sınıf hataları
/// yakalamaz; ekranın gerçekten pump edilmesi gerekir.

/// Çıplak `MaterialApp` yeterli: `context.c` tema uzantısı kayıtlı
/// değilken `SandikPalette.dark`'a düşer (bkz. sandik.dart:816), yani
/// renkler testte de çözülür.
Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(home: child),
    );

void main() {
  // Grafiğin zaman ekseni Türkçe tarih basıyor; locale verisi
  // uygulamada `main.dart` içinde yükleniyor, widget testinde
  // burada. (Kod tabanındaki yerleşik desen.)
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  testWidgets('boş durumda açılır ve çökmez', (tester) async {
    await tester.pumpWidget(_wrap(const ComparisonScreen()));
    await tester.pump();

    expect(find.text('Karşılaştır'), findsOneWidget);
    expect(find.text('Karşılaştırmak için varlık ekleyin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('periyot seçici tüm dönemleri gösterir', (tester) async {
    await tester.pumpWidget(_wrap(const ComparisonScreen()));
    await tester.pump();

    for (final label in ['1H', '1A', '3A', '1Y', '5Y']) {
      expect(find.text(label), findsOneWidget, reason: '$label görünmeli');
    }
  });

  testWidgets('varlık ekle butonu görünür', (tester) async {
    await tester.pumpWidget(_wrap(const ComparisonScreen()));
    await tester.pump();

    expect(find.text('Varlık ekle'), findsOneWidget);
  });

  testWidgets('yatırım tavsiyesi olmadığı uyarısı bulunur', (tester) async {
    // Yasal gereklilik: geçmiş performans gösteren her yüzeyde uyarı
    // bulunmalı. Kaldırılırsa bu test kırılır.
    await tester.pumpWidget(_wrap(const ComparisonScreen()));
    await tester.pump();

    expect(
      find.textContaining('Geçmiş performans gelecek getiri için'),
      findsOneWidget,
    );
  });

  testWidgets('dar ekranda taşma olmaz', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const ComparisonScreen()));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('periyot değiştirmek çökme üretmez', (tester) async {
    await tester.pumpWidget(_wrap(const ComparisonScreen()));
    await tester.pump();

    await tester.tap(find.text('1Y'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
