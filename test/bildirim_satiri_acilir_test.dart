import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/app_notification.dart';
import 'package:portfoy_takip/models/price_alert_notification.dart';
import 'package:portfoy_takip/widgets/app_notification_tile.dart';
import 'package:portfoy_takip/widgets/bildirim_satiri.dart';
import 'package:portfoy_takip/widgets/price_alert_tile.dart';

/// Çan satırı açılır/kapanır (yasin, 2026-10-29: "tüm bildirimler çanda
/// okunabilir olmalı; liste expandable olabilir").
///
/// Kilitlenen sözleşme: dokunuş satırı açar (tam başlık ve gövde, satır
/// sınırı yok) ve GEZİNMEZ; gezinme açık satırdaki "Aç" düğmesindedir.
/// Soluk (geçmiş) satır gövdeyi de gösterir, tarih kendi satırında.
void main() {
  Future<void> kur(WidgetTester tester, Widget satir,
      {bool hareketiAzalt = false}) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: hareketiAzalt),
        child: Scaffold(body: SizedBox(width: 360, child: satir)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  const uzunGovde = 'Günlük değişim (önceki kapanışa göre): THYAO +%5,3 '
      '₺312,40 · ASELS −%5,5 ₺150,20 · KCHOL +%5,1 ₺201,00. '
      'Yatırım tavsiyesi değildir.';

  AppNotification bildirim() => AppNotification(
        id: 'n1',
        type: AppNotification.watchlistMove,
        title: 'Takip listende bugün 3 sert hareket',
        body: uzunGovde,
        sentAt: DateTime.now().toUtc(),
      );

  Text metin(WidgetTester tester, String s) => tester.widget<Text>(find.text(s));

  testWidgets('dokunuş açar: tam gövde, "Aç" görünür, gezinme yok',
      (tester) async {
    var acildi = 0;
    await kur(
      tester,
      AppNotificationTile(
        bildirim: bildirim(),
        faded: false,
        onTap: () => acildi++,
        onDismiss: () {},
        onDelete: null,
      ),
    );
    expect(metin(tester, uzunGovde).maxLines, 2);
    expect(find.text('Aç'), findsNothing);

    await tester.tap(find.text('Takip listende bugün 3 sert hareket'));
    await tester.pumpAndSettle();
    expect(acildi, 0, reason: 'satıra dokunmak gezinmez, açar');
    expect(metin(tester, uzunGovde).maxLines, isNull);
    expect(metin(tester, 'Takip listende bugün 3 sert hareket').maxLines,
        isNull);
    expect(find.text('Aç'), findsOneWidget);

    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();
    expect(acildi, 1);

    // İkinci dokunuş kapatır.
    await tester.tap(find.text('Takip listende bugün 3 sert hareket'));
    await tester.pumpAndSettle();
    expect(find.text('Aç'), findsNothing);
    expect(metin(tester, uzunGovde).maxLines, 2);
  });

  testWidgets('"Aç" düğmesi 44 pt dokunma alanı', (tester) async {
    await kur(
      tester,
      AppNotificationTile(
        bildirim: bildirim(),
        faded: false,
        onTap: () {},
        onDismiss: () {},
        onDelete: null,
        baslangictaAcik: true,
      ),
    );
    final boyut = tester.getSize(find.widgetWithText(TextButton, 'Aç'));
    expect(boyut.height, greaterThanOrEqualTo(44));
    expect(boyut.width, greaterThanOrEqualTo(44));
  });

  testWidgets('soluk satır gövdeyi de gösterir; tarih ayrı satırda',
      (tester) async {
    await kur(
      tester,
      AppNotificationTile(
        bildirim: bildirim(),
        faded: true,
        onTap: () {},
        onDismiss: null,
        onDelete: () {},
      ),
    );
    expect(find.text(uzunGovde), findsOneWidget);
    expect(find.textContaining('Bugün'), findsOneWidget);
  });

  testWidgets('ekran okuyucu: açılır durum ve ipucu', (tester) async {
    final handle = tester.ensureSemantics();
    await kur(
      tester,
      AppNotificationTile(
        bildirim: bildirim(),
        faded: false,
        onTap: () {},
        onDismiss: () {},
        onDelete: null,
      ),
    );
    final node = tester.getSemantics(find.byType(BildirimSatiri));
    expect(node.flagsCollection.isExpanded, Tristate.isFalse);
    await tester.tap(find.text('Takip listende bugün 3 sert hareket'));
    await tester.pumpAndSettle();
    expect(
        tester.getSemantics(find.byType(BildirimSatiri)).flagsCollection.isExpanded,
        Tristate.isTrue);
    handle.dispose();
  });

  testWidgets('hareketi azalt: açılış animasyonsuz (tek karede)',
      (tester) async {
    await kur(
      tester,
      AppNotificationTile(
        bildirim: bildirim(),
        faded: false,
        onTap: () {},
        onDismiss: () {},
        onDelete: null,
      ),
      hareketiAzalt: true,
    );
    final boyut = tester.widget<AnimatedSize>(find.byType(AnimatedSize));
    expect(boyut.duration, Duration.zero);
  });

  group('fiyat alarmı satırı', () {
    PriceAlertNotification alarm(String sembol, double fiyat, double hedef) =>
        PriceAlertNotification(
          id: 'a1',
          symbol: sembol,
          label: 'Etiket',
          targetPrice: hedef,
          triggeredPrice: fiyat,
          direction: 'above',
          sentAt: DateTime.now().toUtc(),
        );

    Future<void> kurAlarm(WidgetTester tester, PriceAlertNotification a,
        {bool faded = false}) =>
        kur(
          tester,
          PriceAlertTile(
            bildirim: a,
            faded: faded,
            onTap: () {},
            onDismiss: faded ? null : () {},
            onDelete: faded ? () {} : null,
            baslangictaAcik: true,
          ),
        );

    testWidgets('ABD hissesi dolarla, BIST ₺ ile', (tester) async {
      await kurAlarm(tester, alarm('AAPL', 251.2, 250));
      expect(find.textContaining('\$251,20'), findsOneWidget);
      expect(find.textContaining('₺'), findsNothing);
      await kurAlarm(tester, alarm('THYAO.IS', 321.4, 320));
      expect(find.textContaining('₺321,40'), findsOneWidget);
    });

    testWidgets('1 altı fiyat sıfır görünmez', (tester) async {
      await kurAlarm(tester, alarm('KRIPTO:SHIB', 0.000412, 0.0004));
      expect(find.textContaining('0,000412'), findsOneWidget);
    });

    testWidgets('açık satır tek seferlik olduğunu söyler; soluk satır fiyatı da gösterir',
        (tester) async {
      await kurAlarm(tester, alarm('THYAO.IS', 321.4, 320), faded: true);
      expect(find.textContaining('Tek seferlik alarmdı'), findsOneWidget);
      expect(find.textContaining('₺321,40'), findsOneWidget);
      expect(find.textContaining('Bugün'), findsOneWidget);
    });
  });
}
