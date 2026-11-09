import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Web enflasyon hesaplayıcısının (docs/enflasyon/) kapısı (2026-10-20).
///
/// - `docs/data/tufe.json`: `tool/tufe_web.py` yazar, `tufe-web.yml` PR açar.
///   Uydurma sayı yasak: boş liste geçerli (sayfa boş durum gösterir), sıfır
///   ya da negatif endeks, tekrar eden/ters sıralı ay, açıklanmamış ay geçmez.
/// - Hesap `docs/enflasyon/hesap.js`'te; sayfanın koştuğu dosyanın aynısı
///   `node` ile koşulur. Node yoksa (yerel makine) o test atlanır; CI
///   (ubuntu-latest) Node taşır.
/// - Sayfa sözleşmesi: kaynak ve "yatırım tavsiyesi değildir" notu, kampanya
///   etiketli mağaza bağlantısı, uzun/orta tire yok.
void main() {
  String oku(String yol) =>
      File(yol).readAsStringSync().replaceAll('\r\n', '\n');

  group('tufe.json', () {
    final kok = jsonDecode(oku('docs/data/tufe.json')) as Map<String, dynamic>;
    final aylar = (kok['aylar'] as List).cast<Map<String, dynamic>>();

    test('şema: kaynak, seri ve aylar', () {
      expect(kok['kaynak'], 'TÜİK');
      // Seri adı baz yılını ayırt eder; veri varsa boş olamaz.
      if (aylar.isEmpty) {
        expect(kok['seri'], isNull);
      } else {
        expect(kok['seri'], isA<String>());
        expect((kok['seri'] as String).isNotEmpty, isTrue);
      }
    });

    test('aylar sıralı, tekil, açıklanmış ve endeks > 0', () {
      final simdi = DateTime.now();
      final buAy =
          '${simdi.year.toString().padLeft(4, '0')}-${simdi.month.toString().padLeft(2, '0')}';
      String? onceki;
      for (final a in aylar) {
        final ay = a['ay'] as String;
        expect(RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(ay), isTrue,
            reason: ay);
        expect(ay.compareTo(buAy) < 0, isTrue,
            reason: '$ay açıklanmamış ay (bu ay $buAy)');
        if (onceki != null) {
          expect(ay.compareTo(onceki) > 0, isTrue,
              reason: '$onceki → $ay sıralı/tekil değil');
        }
        onceki = ay;
        final endeks = a['endeks'];
        expect(endeks, isA<num>(), reason: ay);
        expect((endeks as num) > 0, isTrue, reason: '$ay endeks $endeks');
      }
    });
  });

  group('hesap.js', () {
    final node = Process.runSync('node', ['--version'], runInShell: true);
    final nodeVar = node.exitCode == 0;
    final yol = File('docs/enflasyon/hesap.js').absolute.path;

    Map<String, dynamic> kos(String govde) {
      final r = Process.runSync('node', [
        '-e',
        'const H=require(${jsonEncode(yol)});'
            'const fs=require("fs");'
            'process.stdout.write(JSON.stringify((function(){$govde})()));',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return jsonDecode(r.stdout as String) as Map<String, dynamic>;
    }

    test('karşılık = tutar × son / ilk; açıklanmamış ay hesaplanmaz', () {
      final s = kos('''
        const v={aylar:[{ay:"2025-02",endeks:110},{ay:"2025-01",endeks:100},
                        {ay:"2026-09",endeks:150}]};
        return {
          r: H.hesapla(v, 10000, "2025-01"),
          ayni: H.hesapla(v, 10000, "2026-09"),
          gelecek: H.hesapla(v, 10000, "2026-10"),
          sifir: H.hesapla(v, 0, "2025-01"),
          tek: H.hesapla({aylar:[{ay:"2026-09",endeks:150}]}, 1, "2026-09"),
          bos: H.hesapla({aylar:[]}, 1, "2025-01"),
          sayi: [H.sayiOku("10.000"), H.sayiOku("2.500,50"), H.sayiOku("abc")],
          ad: H.ayAdi("2026-09")
        };''');
      final r = s['r'] as Map<String, dynamic>;
      expect(r['karsilik'], closeTo(15000, 1e-9));
      expect(r['artis'], closeTo(0.5, 1e-12));
      expect(r['alimGucuKaybi'], closeTo(1 / 3, 1e-12));
      expect(r['sonAy'], '2026-09');
      // "Bugün" son açıklanan ay; kendisiyle ya da açıklanmamış ayla kıyas yok.
      expect(s['ayni'], isNull);
      expect(s['gelecek'], isNull);
      expect(s['sifir'], isNull);
      expect(s['tek'], isNull);
      expect(s['bos'], isNull);
      expect((s['sayi'] as List).take(2), [10000, 2500.5]);
      expect((s['sayi'] as List)[2], isNull); // NaN → JSON null
      expect(s['ad'], 'Eylül 2026');
    }, skip: nodeVar ? false : 'node yok');

    // "Sonucu paylaş" (2026-10-24): bağlantı yalnız ay + isteğe bağlı tutar
    // taşır; saçma değerle açılan bağlantı uydurma sonuç göstermez (null →
    // sayfa formu boş açar); varsayılan metin tutarı içermez.
    test('paylaşım bağlantısı sınırlı ve doğrulanmış', () {
      final s = kos('''
        const v={aylar:[{ay:"2025-01",endeks:100},{ay:"2025-02",endeks:110},
                        {ay:"2026-09",endeks:150}]};
        const o=q=>H.paylasimOku(q,v);
        return {
          bos: o(""), yabanci: o("?utm_source=x"),
          ay: o("?ay=2025-01"), ikisi: o("?ay=2025-02&tutar=2500.5"),
          kotu: ["?ay=2026-09","?ay=2024-12","?ay=2025-13","?ay=x",
                 "?tutar=0","?tutar=-5","?tutar=1e5","?tutar=abc","?tutar=1.234",
                 "?tutar=10000000000000","?ay=2025-01&ay=2025-02",
                 "?ay=2025-01&tutar=abc"].map(o),
          veriYok: H.paylasimOku("?ay=2025-01",{aylar:[]}),
          adres: H.paylasimAdresi("https://a.b/enflasyon/?ay=2024-01#x","2025-01",null),
          adresT: H.paylasimAdresi("https://a.b/enflasyon/","2025-01",10000.456),
          adresSacma: H.paylasimAdresi("https://a.b/e/","2025-01",1e13),
          metin: H.paylasimMetni(H.hesapla(v,10000,"2025-01"),"2025-01",null),
          metinT: H.paylasimMetni(H.hesapla(v,10000,"2025-01"),"2025-01",10000)
        };''');
      expect(s['bos'], {'bos': true});
      expect(s['yabanci'], {'bos': true});
      expect(s['ay'], {'ay': '2025-01', 'tutar': null});
      expect(s['ikisi'], {'ay': '2025-02', 'tutar': 2500.5});
      expect(s['kotu'], everyElement(isNull));
      expect(s['veriYok'], isNull);
      expect(s['adres'], 'https://a.b/enflasyon/?ay=2025-01');
      expect(s['adresT'], 'https://a.b/enflasyon/?ay=2025-01&tutar=10000.46');
      expect(s['adresSacma'], 'https://a.b/e/?ay=2025-01');
      final metin = s['metin'] as String;
      expect(metin, contains('%50,0 arttı'));
      expect(metin, contains('%33,3 azaldı'));
      expect(metin.contains('₺'), isFalse, reason: 'varsayılan metin tutar taşımaz');
      expect(s['metinT'], contains('10.000 ₺'));
      for (final t in ['—', '–']) {
        expect(metin.contains(t) || (s['metinT'] as String).contains(t), isFalse);
      }
    }, skip: nodeVar ? false : 'node yok');

    test('yayımlanan veriyle her başlangıç ayı sonlu ve pozitif', () {
      final s = kos('''
        const v=JSON.parse(fs.readFileSync("docs/data/tufe.json","utf8"));
        const a=H.gecerliAylar(v);
        const kotu=a.slice(0,-1).filter(x=>{
          const r=H.hesapla(v,1000,x.ay);
          return !r || !isFinite(r.karsilik) || r.karsilik<=0;
        }).map(x=>x.ay);
        return {n:a.length, ham:(v.aylar||[]).length, kotu};''');
      // Süzgeç sessizce satır atmasın: dosyadaki her ay geçerli olmalı.
      expect(s['n'], s['ham']);
      expect(s['kotu'], isEmpty);
    }, skip: nodeVar ? false : 'node yok');
  });

  group('sayfa', () {
    final html = oku('docs/enflasyon/index.html');
    final gorunen = html
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
        .replaceAll(RegExp(r'<style.*?</style>', dotAll: true), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');

    test('kaynak, tavsiye notu ve kampanyalı mağaza bağlantısı', () {
      expect(gorunen, contains('Kaynak: TÜİK'));
      expect(gorunen, contains('Yatırım tavsiyesi değildir'));
      expect(gorunen, contains('enflasyonu yendi mi?'));
      expect(html, contains('../data/tufe.json'));
      expect(html, contains('src="hesap.js"'));
      expect(
          RegExp(r'https://apps\.apple\.com/tr/app/id6786837699\?[^"]*utm_medium=enflasyon')
              .hasMatch(html),
          isTrue);
    });

    test('paylaş düğmesi: navigator.share, yoksa pano; varsayılan tutarsız', () {
      expect(gorunen, contains('Sonucu paylaş'));
      expect(gorunen, contains('Tutarı da paylaş'));
      expect(html, contains('navigator.share'));
      expect(html, contains('navigator.clipboard'));
      expect(html, contains('H.paylasimOku(location.search'));
      // Kutu işaretli DEĞİLSE tutar bağlantıya/metne girmez.
      expect(html, contains('tutarEkle.checked ? sonuc.tutar : null'));
      expect(RegExp(r'id="tutar-ekle"[^>]*checked').hasMatch(html), isFalse);
    });

    test('uzun/orta tire yok', () {
      for (final t in ['—', '–']) {
        expect(gorunen.contains(t), isFalse, reason: t);
      }
    });

    test('ana sayfadan bağlantı var', () {
      expect(oku('docs/index.html'), contains('href="enflasyon/"'));
    });
  });
}
