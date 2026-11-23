import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/services/varlik_masraflari.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/kapanis_ozeti_sheet.dart';
import 'package:portfoy_takip/widgets/masraf_karti.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart' show KilitSatiri;
import 'package:portfoy_takip/widgets/premium_acildi_sayfasi.dart';

import 'helpers/kaynak.dart';

/// Ar-Ge 23 Kas 17:05 (UI/UX turu 17): varlık sayfasının küçük Premium
/// kapıları. #1 Masraflar'da tutar yokken kilit yok (kalem açıklamaları
/// "nasıl eklenir"in cevabı), #3 satın alma sonrası sayfanın kapanış
/// eşlemesi, #5 Masraflar kilidi ölçülür ve tutar w600. #2 ve #4'ün
/// davranış testleri `kapanis_rapor_kilit_test` / `en_iyi_gun_test`'te.
const _bilgi = [
  MasrafKalemi(
      baslik: 'İşlem komisyonu',
      aciklama: 'Alışta komisyonu girersen burada görünür.',
      nitelik: MasrafNiteligi.bilgi),
  MasrafKalemi(
      baslik: 'Saklama ücreti',
      aciklama: 'Aracı kurumuna göre değişir.',
      nitelik: MasrafNiteligi.bilgi),
];

Future<void> _ciz(WidgetTester tester, MasrafOzeti ozet) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      locale: const Locale('tr', 'TR'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
            child: MasrafKarti(ozet: ozet, kilitli: true)),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  group('#1 Masraflar: tutar yokken kilit yok', () {
    testWidgets('ücretsiz + tutarsız: "Nasıl eklenir" kalemleri açar',
        (tester) async {
      await _ciz(tester, const MasrafOzeti(_bilgi));
      await tester.tap(find.text('Nasıl eklenir'));
      await tester.pump();
      expect(find.text('İşlem komisyonu'), findsOneWidget);
      expect(find.text('Saklama ücreti'), findsOneWidget);
      expect(find.byType(KilitSatiri), findsNothing);
    });

    testWidgets('ücretsiz + ödenen tutar: döküm kilitli, ölçülür',
        (tester) async {
      await _ciz(
          tester,
          const MasrafOzeti([
            MasrafKalemi(
                baslik: 'İşlem komisyonu',
                aciklama: 'Kayıtlı komisyonların toplamı.',
                nitelik: MasrafNiteligi.odendi,
                tutarTry: 12),
            ..._bilgi,
          ]));
      expect(find.byType(KilitSatiri), findsOneWidget);
      expect(find.text('Saklama ücreti'), findsNothing);
      final kilit = tester.widget<KilitSatiri>(find.byType(KilitSatiri));
      expect(kilit.kaynak, 'masraf_dokumu');
      // #5: `ozellik` verilmezse `premium_gate_shown` düşmüyordu.
      expect(kilit.ozellik, 'masraf_dokumu');
    });
  });

  test('#5 Masraflar tutarı ağırlık tavanında (w600)', () {
    final k = ekranKaynagiSync('lib/widgets/masraf_karti.dart');
    expect(k, isNot(contains('FontWeight.w700')));
  });

  test('#3 kapanış kilidinin kaynağı Sattıkların satırını öne alır', () {
    expect(premiumAcildiKaynakHedefi(kapanisRaporPaywallKaynagi),
        PremiumAcildiHedef.sattiklarin);
    // `kapanis_ozeti` hiçbir paywall'un kaynağı değil (paylaşım kampanyası).
    expect(premiumAcildiKaynakHedefi('kapanis_ozeti'), isNull);
    final k = ekranKaynagiSync('lib/widgets/premium_acildi_sayfasi.dart');
    expect(k, isNot(contains("'kapanis_rapor'")),
        reason: 'sabit içe aktarılır, dize tekrar yazılmaz');
  });

  test('#2 kapanış paywall\'ı satın alma sonucunu bekler', () {
    final k = ekranKaynagiSync('lib/widgets/kapanis_ozeti_sheet.dart');
    expect(k, contains('final aldi = await PaywallScreen.show('));
    expect(k, contains('if (aldi != true || !context.mounted) return;'));
  });
}
