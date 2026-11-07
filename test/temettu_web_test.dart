import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/services/temettu_gecmisi.dart';

/// Web net temettü hesaplayıcısı (`docs/temettu/index.html`, müşteri raporu
/// 8 Kas 00:30 #4) uygulamayla AYNI oranı ve formülü kullanır.
///
/// Sayfa JavaScript'tir, testte koşturulamaz; `maliyet_web_test` gibi iki
/// yoldan kilitlenir: (1) sayfadaki oran (`data-oran` + betik sabiti)
/// uygulamanın Remote Config varsayılanı `temettu_stopaj_orani`'na eşit,
/// örneğin `data-*` değerleri uygulamanın fonksiyonlarıyla
/// (`TemettuGecmisi.oneriTutari`, `maliyeteGoreVerim`) aynı sonucu verir;
/// (2) betikteki formül ifadeleri uygulamanınkiyle aynı. Ayrıca: fiyat ve
/// harici kaynak yok, tavsiye notu ve kampanya etiketli bağlantı var, uzun
/// tire, ünlem ve "en iyi" yok, site haritasında.
void main() {
  final html = File('docs/temettu/index.html').readAsStringSync();
  final tr = NumberFormat.decimalPattern('tr_TR');

  test('oran uygulamanın varsayılanıyla aynı, tarihi sayfada yazılı', () {
    final uygulama = RemoteConfigService.instance.temettuStopajOrani;
    expect(uygulama, isNotNull);
    final m = RegExp(r'<p class="oran" id="oran" data-oran="([0-9.]+)" '
            r'data-tarih="([0-9-]+)">([^<]*)</p>')
        .firstMatch(html);
    expect(m, isNotNull);
    expect(double.parse(m!.group(1)!), uygulama);
    expect(html, contains('var STOPAJ = ${m.group(1)};'));
    // Görünen metin oranı ve geçerlilik tarihini yazar.
    final yuzde = (uygulama! * 100).round();
    expect(m.group(3), contains('%$yuzde'));
    final t = DateTime.parse(m.group(2)!);
    final tarih = '${t.day.toString().padLeft(2, '0')}.'
        '${t.month.toString().padLeft(2, '0')}.${t.year}';
    expect(m.group(3), contains(tarih));
    // Oranın kaynak yorumu (remote_config_service) aynı tarihi söyler.
    final rc =
        File('lib/services/remote_config_service.dart').readAsStringSync();
    expect(rc, contains(tarih));
    expect(html, contains('Stopaj (%$yuzde)'));
  });

  test('örnek uygulamanın net ve maliyete göre verim hesabıyla aynı', () {
    final m = RegExp(r'<p id="ornek" data-lot="([0-9.]+)" '
            r'data-pay="([0-9.]+)" data-alis="([0-9.]+)" '
            r'data-brut="([0-9.]+)" data-stopaj="([0-9.]+)" '
            r'data-net="([0-9.]+)" data-verim="([0-9.]+)">')
        .firstMatch(html);
    expect(m, isNotNull);
    double d(int i) => double.parse(m!.group(i)!);
    final oran = RemoteConfigService.instance.temettuStopajOrani;
    final lot = d(1), pay = d(2), alis = d(3);
    final brut = lot * pay;
    expect(brut, d(4));
    expect(brut * oran!, closeTo(d(5), 1e-9));
    final net = TemettuGecmisi.oneriTutari(brut, oran);
    expect(net.net, isTrue);
    expect(net.tutar, closeTo(d(6), 1e-9));

    // Maliyete göre verim: uygulamanın kart fonksiyonu, bir alış ve o net
    // temettü kaydından oluşan defterle.
    final simdi = DateTime(2026, 11, 8);
    Asset lotu(String id, AssetKind kind) => Asset(
          id: id,
          userId: 'u',
          name: 'DENEME',
          ticker: 'DENEM.IS',
          type: AssetType.hisse,
          quantity: kind == AssetKind.buy ? lot : 0,
          purchasePrice: alis,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: alis,
          addedDate: DateTime(2026, 6, 1),
          kind: kind,
          dividendAmount: kind == AssetKind.dividend ? net.tutar! : 0,
        );
    final alim = lotu('al', AssetKind.buy);
    final verim = TemettuGecmisi.maliyeteGoreVerim(
        [alim, lotu('tem', AssetKind.dividend)], alim,
        simdi: simdi);
    expect(verim, isNotNull);
    expect(double.parse(verim!.toStringAsFixed(2)), d(7));

    // Metin örnekle aynı sayıları Türkçe biçimde yazar.
    final metin = html.substring(m!.end, html.indexOf('</p>', m.end));
    for (final s in [
      tr.format(lot),
      NumberFormat('#,##0.00', 'tr_TR').format(pay),
      tr.format(brut),
      tr.format(d(5)),
      tr.format(d(6)),
      tr.format(alis),
      tr.format(lot * alis),
      '%${NumberFormat('0.00', 'tr_TR').format(d(7))}',
    ]) {
      expect(metin, contains(s));
    }
  });

  test('betikteki formül uygulamanınkiyle aynı', () {
    expect(html, contains('var brut = lot * pay;'));
    expect(html, contains('var net = brut * (1 - STOPAJ);'));
    expect(html, contains('var maliyet = lot * alis;'));
    expect(html, contains('var verim = net / maliyet * 100;'));
    // Alış fiyatı yoksa verim satırı çizilmez.
    expect(html, contains('if (alis > 0) {'));
  });

  test('fiyat yok, harici kaynak yok, tavsiye notu ve etiketli bağlantı', () {
    expect(RegExp(r'<script[^>]+src=').hasMatch(html), isFalse);
    expect(
        RegExp(r'''(src|href)="https?://(?!apps\.apple\.com|yasincirali\.github\.io)''')
            .hasMatch(html),
        isFalse);
    expect(html, contains('utm_medium=temettu'));
    expect(html, contains('Yatırım tavsiyesi değildir.'));
    expect(html, isNot(contains('–')));
    expect(html, isNot(contains('—')));
    expect(html.toLowerCase(), isNot(contains('en iyi')));
    final gorunen = html
        .substring(html.indexOf('<body>'), html.indexOf('<script>'))
        .replaceAll(RegExp(r'<[^>]*>'), '');
    expect(gorunen, isNot(contains('!')));
  });

  test('site haritasında', () {
    expect(File('docs/sitemap.xml').readAsStringSync(),
        contains('https://yasincirali.github.io/sandikapp/temettu/'));
  });
}
