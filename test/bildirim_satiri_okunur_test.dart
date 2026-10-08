import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/app_notification.dart';
import 'package:portfoy_takip/widgets/app_notification_tile.dart';

/// Bildirim satırı: başlık iki satıra kadar tam, zaman her satırda, saat
/// yerel (2026-10-02 müşteri testi).
///
/// "▼ ARDYZ son kapanışta %9,5 düştü" tek satırda "▼ ARDYZ son kapanış…"
/// görünüyordu — yüzde kayboluyordu. Etkin bildirimde zaman yoktu; aynı hisse
/// için "düştü" ve "yükseldi" alt alta duruyor, hangisinin bugün olduğu
/// anlaşılmıyordu. `sent_at` UTC geldiği hâlde saat çevrilmeden yazılıyordu.
void main() {
  Future<void> kur(WidgetTester tester, AppNotification b,
      {bool faded = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: AppNotificationTile(
            bildirim: b,
            faded: faded,
            onTap: () {},
            onDismiss: faded ? null : () {},
            onDelete: faded ? () {} : null,
          ),
        ),
      ),
    ));
  }

  final dun = DateTime.now().subtract(const Duration(days: 1));
  final dunUtc = DateTime.utc(dun.year, dun.month, dun.day, 15, 10);

  AppNotification bildirim() => AppNotification(
        id: 'n1',
        type: AppNotification.dailyBrief,
        title: '▼ ARDYZ son kapanışta %9,5 düştü',
        body: 'Portföyünde en çok hareket eden hisse.',
        sentAt: dunUtc,
      );

  testWidgets('başlık üç satıra kadar kesilmez', (tester) async {
    await kur(tester, bildirim());
    final baslik = tester.widget<Text>(find.text('▼ ARDYZ son kapanışta %9,5 düştü'));
    // Taşma ölçümü yapılmaz: test fontu (Ahem) her harfi kare çizer,
    // gerçek genişliği temsil etmez. Kural üç satır izni.
    expect(baslik.maxLines, 3);
  });

  testWidgets('etkin bildirimde yerel saatli zaman yazar', (tester) async {
    await kur(tester, bildirim());
    final yerel = dunUtc.toLocal();
    final saat = '${yerel.hour.toString().padLeft(2, '0')}:'
        '${yerel.minute.toString().padLeft(2, '0')}';
    expect(find.textContaining(saat), findsOneWidget);
    expect(find.text('Portföyünde en çok hareket eden hisse.'), findsOneWidget);
  });
}
