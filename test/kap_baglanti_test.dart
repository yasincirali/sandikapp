import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/kap_baglanti_service.dart';
import 'package:portfoy_takip/widgets/kap_baglantisi.dart';

/// "KAP bildirimleri ↗" (karar 7.2, 2026-09-30). Yanıt örnekleri KAP'ın
/// şirket arama ucundan 2026-09-30'da ölçülen biçimde.
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

  test('tek sonuç → şirketin KAP bildirim listesi (en yeni üstte)', () async {
    final istekler = <Uri>[];
    final u = await servis(thyao, istek: istekler).sirketSayfasi('THYAO.IS');
    expect(u.toString(),
        'https://www.kap.org.tr/tr/bildirim-sorgu-sonuc'
        '?member=4028e4a140f2ed720140f376bebb01a7');
    expect(istekler.single.path, '/tr/api/member/filter/THYAO');
  });

  test('bulanık çoklu sonuç → YANLIŞ şirket değil, sorgu sayfası', () async {
    final u = await servis(garan).sirketSayfasi('GARAN.IS');
    expect(u, KapBaglantiService.sorguSayfasi);
  });

  test('boş sonuç, HTTP hatası ve bozuk kod → sorgu sayfası', () async {
    expect(await servis('[]').sirketSayfasi('ZZZZZ.IS'),
        KapBaglantiService.sorguSayfasi);
    expect(await servis('x', kod: 503).sirketSayfasi('THYAO.IS'),
        KapBaglantiService.sorguSayfasi);
    expect(await servis(thyao).sirketSayfasi('../etc'),
        KapBaglantiService.sorguSayfasi);
  });

  test('aynı kod ikinci kez ağa çıkmaz (oturum önbelleği)', () async {
    final istekler = <Uri>[];
    final s = servis(thyao, istek: istekler);
    await s.sirketSayfasi('THYAO.IS');
    await s.sirketSayfasi('THYAO');
    expect(istekler.length, 1);
  });

  test('beklenmeyen üye kimliği biçimi reddedilir', () {
    expect(
        KapBaglantiService.tekUyeKimligi(
            '[{"mkkMemberOid":"x&member=../../"}]'),
        isNull);
  });

  test('yalnız BIST hissesinde görünür; endeks ve diğer türlerde değil', () {
    expect(KapBaglantisi.gosterilir(AssetType.hisse, 'THYAO.IS'), isTrue);
    expect(KapBaglantisi.gosterilir(AssetType.hisse, 'XU100.IS'), isFalse);
    expect(KapBaglantisi.gosterilir(AssetType.hisse, 'AAPL'), isFalse);
    expect(KapBaglantisi.gosterilir(AssetType.fon, 'TEFAS:TTE'), isFalse);
  });
}
