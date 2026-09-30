import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/kap_baglanti_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/kap_baglantisi.dart';

/// "KAP bildirimleri ↗" (karar 7.2, 2026-09-30, ikinci tur). Yanıt
/// örnekleri KAP'ın şirket arama ucundan 2026-09-30'da ölçülen biçimde.
void main() {
  const thyao = '[{"companyCode":"1107","mkkMemberOid":'
      '"4028e4a140f2ed720140f376bebb01a7","title":"TÜRK HAVA YOLLARI A.O.",'
      '"permaLink":"1107-turk-hava-yollari-a-o"}]';
  // "GARAN" bulanık aramada ÜÇ şirket döndü, ilki Garanti Bankası DEĞİL.
  const garan = '[{"companyCode":"2113","title":"GARANTİ BBVA OPERASYONEL '
      'KİRALAMA","permaLink":"2113-garanti-bbva-operasyonel-kiralama-hizmetleri-a-s"},'
      '{"companyCode":"1802","title":"GARANTİ EMEKLİLİK","permaLink":"1802-garanti-emeklilik-ve-hayat-a-s"}]';

  KapBaglantiService servis(String govde, {int kod = 200, List<Uri>? istek}) =>
      KapBaglantiService.test(MockClient((r) async {
        istek?.add(r.url);
        return http.Response.bytes(utf8.encode(govde), kod);
      }));

  group('servis', () {
    test('tek sonuç → varlığın KAP şirket sayfası', () async {
      final istekler = <Uri>[];
      final u = await servis(thyao, istek: istekler).sirketSayfasi('THYAO.IS');
      expect(u.toString(),
          'https://www.kap.org.tr/tr/sirket-bilgileri/ozet/1107-turk-hava-yollari-a-o');
      expect(istekler.single.path, '/tr/api/member/filter/THYAO');
    });

    test('bulanık çoklu, boş sonuç, HTTP hatası, bozuk kod → null', () async {
      expect(await servis(garan).sirketSayfasi('GARAN.IS'), isNull);
      expect(await servis('[]').sirketSayfasi('GLDTR.IS'), isNull);
      expect(await servis('x', kod: 503).sirketSayfasi('THYAO.IS'), isNull);
      expect(await servis(thyao).sirketSayfasi('../etc'), isNull);
    });

    test('önbellek: çözülen ve çözülemeyen kod ikinci kez ağa çıkmaz',
        () async {
      final istekler = <Uri>[];
      final s = servis('[]', istek: istekler);
      await s.sirketSayfasi('GLDTR.IS');
      await s.sirketSayfasi('GLDTR');
      expect(istekler.length, 1);
      expect(s.biliniyor('GLDTR.IS'), isTrue);
      expect(s.onbellekte('GLDTR.IS'), isNull);
    });

    test('HTTP hatası önbelleğe yazılmaz (sonra yeniden sorulur)', () async {
      final s = servis('x', kod: 503);
      await s.sirketSayfasi('THYAO.IS');
      expect(s.biliniyor('THYAO.IS'), isFalse);
    });

    test('beklenmeyen kalıcı adres biçimi reddedilir', () {
      expect(
          KapBaglantiService.tekPermaLink(
              '[{"permaLink":"javascript:alert(1)"}]'),
          isNull);
    });
  });

  group('satır', () {
    Future<void> kur(WidgetTester t, Widget w) => t.pumpWidget(MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('tr'),
          home: Scaffold(body: w),
        ));

    testWidgets('şirket bulununca görünür', (t) async {
      await kur(t,
          KapBaglantisi(tur: AssetType.hisse, ticker: 'THYAO.IS', servis: servis(thyao)));
      await t.pumpAndSettle();
      expect(find.text('KAP bildirimleri'), findsOneWidget);
    });

    testWidgets('bulunamazsa (GLDTR, GARAN) satır HİÇ yok', (t) async {
      await kur(t,
          KapBaglantisi(tur: AssetType.hisse, ticker: 'GLDTR.IS', servis: servis('[]')));
      await t.pumpAndSettle();
      expect(find.text('KAP bildirimleri'), findsNothing);
      await kur(t,
          KapBaglantisi(tur: AssetType.hisse, ticker: 'GARAN.IS', servis: servis(garan)));
      await t.pumpAndSettle();
      expect(find.text('KAP bildirimleri'), findsNothing);
    });

    testWidgets('altın, fon, kripto, endeks: sorgu bile atılmaz', (t) async {
      final istekler = <Uri>[];
      // "AFT" fon kodu KAP aramasında TEK ve YANLIŞ şirket (DO & CO) döndü
      // — fonlarda arama hiç yapılmamalı.
      final s = servis('[{"permaLink":"1530-do-co-aktiengesellschaft"}]',
          istek: istekler);
      for (final (tur, kod) in const [
        (AssetType.altin, 'XAUTRY=X'),
        (AssetType.fon, 'TEFAS:AFT'),
        (AssetType.kripto, 'KRIPTO:BTC'),
        (AssetType.hisse, 'XU100.IS'),
        (AssetType.hisse, 'AAPL'),
      ]) {
        await kur(t, KapBaglantisi(tur: tur, ticker: kod, servis: s));
        await t.pumpAndSettle();
        expect(find.text('KAP bildirimleri'), findsNothing, reason: kod);
      }
      expect(istekler, isEmpty);
    });
  });
}
