import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/config/yasal_belge_kaynaklari.g.dart';
import 'package:portfoy_takip/screens/legal_doc_screen.dart';
import 'package:portfoy_takip/services/yasal_md.dart';
import 'package:portfoy_takip/services/yasal_metin_katalogu.dart';

import 'helpers/yasal_migration.dart';

/// "Webdekiyle de her zaman eşleyelim" kilidi (kullanıcı kararı 2026-10-04).
///
/// Tek kaynak `legal/tr/*.md` (çevirisi `legal/en/*.md`). Dört parça:
/// (a) uygulamanın gösterdiği/onaylattığı metin == md;
/// (b) `docs/**` HTML'i güncel md'den üretilmiş ve elle düzenlenmemiş;
/// (c) md'deki "Sürüm" == katalog sürümü == migration'daki sürüm;
/// (d) İngilizce çeviri hangi TR sürümünü çevirdiğini beyan eder ve geride
///     kalırsa kırılır.
/// Süreç: `yasal_metin_katalogu.dart` → "Metin değişince ne yapılır".
void main() {
  const adimlar = 'Ne yapmalı: (1) legal/tr/<BELGE>.md\'yi düzenle, (2) '
      '"**Sürüm:**" satırını artır (+ "**Yürürlük tarihi:**" / "**Son '
      'güncelleme:**"; çevirisi varsa legal/en/<BELGE>.md "**Version:**" ve '
      '"**Source:** TR x"), (3) `python docs/_build_legal.py` (web HTML + '
      'lib/config/yasal_belge_kaynaklari.g.dart), (4) `flutter test '
      '--run-skipped --tags arac tool/yasal_metin_uret_test.dart` → '
      'build/yasal_metin_ekleri.sql, (5) çıktıyı YENİ bir migration\'a koy '
      '(iki sunucuya birlikte; eski satıra dokunma), (6) kapının "Neler '
      'değişti" notu (yasalKapiDegisiklikNotu). Ayrıntı: '
      'yasal_metin_katalogu.dart → "Metin değişince ne yapılır".';

  String oku(String yol) => File(yol).readAsStringSync();
  String sha(String s) => sha256.convert(utf8.encode(s)).toString();

  group('(a) uygulama metni == md', () {
    test('üretilen sabit her belgede md dosyasının kanonik hâli', () {
      for (final b in YasalBelge.values) {
        expect(b.md, yasalMdKanonik(oku(b.kaynak)),
            reason: '${b.kaynak} değişmiş ama uygulamanın sabiti eski '
                '(lib/config/yasal_belge_kaynaklari.g.dart). $adimlar');
        expect(YasalMetinKatalogu.belge(b).govde, b.md, reason: b.kaynak);
      }
    });

    test('üretilen sabit, YasalBelge ve betik aynı belge listesini taşır', () {
      final kaynaklar = [for (final b in YasalBelge.values) b.kaynak];
      expect(yasalBelgeKaynaklari.keys.toList(), kaynaklar,
          reason: 'python docs/_build_legal.py');
      final betik = oku('docs/_build_legal.py');
      final liste = RegExp(r'UYGULAMA_BELGELERI = \[(.*?)\]', dotAll: true)
          .firstMatch(betik)![1]!;
      expect([for (final m in RegExp(r'"([^"]+)"').allMatches(liste)) m[1]],
          kaynaklar,
          reason: '_build_legal.py UYGULAMA_BELGELERI ile YasalBelge ayrıştı');
    });

    test('ekrana md işareti ya da yer tutucu sızmaz', () {
      for (final b in YasalBelge.values) {
        for (final blok in LegalDocs.bloklar(b)) {
          for (final metin in [blok.text, ...blok.cells]) {
            expect(metin, isNot(contains('**')), reason: '${b.kaynak}: $metin');
            expect(metin, isNot(contains('`')), reason: '${b.kaynak}: $metin');
            expect(metin, isNot(startsWith('#')),
                reason: '${b.kaynak}: $metin');
            expect(metin, isNot(contains('{SUPABASE')),
                reason: '${b.kaynak}: $metin');
          }
        }
      }
    });

    test('md\'deki her yer tutucuyu uygulama doldurur', () {
      final dolanlar = LegalDocs.yerTutucuDegerleri().keys.toSet();
      for (final b in YasalBelge.values) {
        expect(yasalMdYerTutuculari(b.md).difference(dolanlar), isEmpty,
            reason: '${b.kaynak}: LegalDocs.yerTutucuDegerleri doldurmuyor');
      }
    });

    test('web\'in tam metni: Koşullar 19 bölüm, tablo ve künye korunur', () {
      // 1.1'de uygulama web'in kısaltılmış kopyasını gösteriyordu (14 bölüm).
      final kosullar = YasalBelge.kosullar.sablonBloklari;
      expect(kosullar.where((b) => b.type == LegalBlockType.h2), hasLength(19));
      expect(kosullar.first.type, LegalBlockType.h1);
      expect(kosullar[1].type, LegalBlockType.meta);
      final gizlilik = YasalBelge.gizlilik.sablonBloklari;
      expect(gizlilik.where((b) => b.type == LegalBlockType.tableHeader),
          isNotEmpty);
      expect(
          gizlilik.any((b) =>
              b.type == LegalBlockType.tableRow &&
              b.cells.contains('{SUPABASE_ULKE}')),
          isTrue,
          reason: 'Yer sütunu ülke yer tutucusu taşır');
    });

    test('md\'de "---" üstünde boş satır var (web\'de başlık olmasın)', () {
      // python-markdown hemen üstünde metin olan "---"yu h2 yapar; uygulama
      // ayraç çizer. İkisi aynı görünsün diye bu biçim yasak.
      for (final b in YasalBelge.values) {
        final satirlar = b.md.split('\n');
        for (var i = 1; i < satirlar.length; i++) {
          if (RegExp(r'^-{3,}\s*$').hasMatch(satirlar[i])) {
            expect(satirlar[i - 1].trim(), isEmpty,
                reason: '${b.kaynak}:${i + 1} "---" üstü boş değil');
          }
        }
      }
    });
  });

  group('(b) docs/ HTML güncel md\'den üretilmiş', () {
    final sayfalar = <String, String>{
      for (final f in Directory('docs')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('index.html')))
        f.path.replaceAll('\\', '/'):
            f.readAsStringSync().replaceAll('\r\n', '\n'),
    };
    String? meta(String html, String ad) =>
        RegExp('<meta name="$ad" content="([^"]*)">').firstMatch(html)?[1];
    final uretilen = {
      for (final e in sayfalar.entries)
        if (meta(e.value, 'sandik-kaynak') != null) e.key: e.value,
    };

    test('her yasal md en az bir sayfaya üretilmiş', () {
      final kaynaklar = {
        for (final h in uretilen.values) meta(h, 'sandik-kaynak'),
      };
      for (final dizin in ['legal/tr', 'legal/en']) {
        for (final f in Directory(dizin).listSync().whereType<File>()) {
          final yol = '$dizin/${f.uri.pathSegments.last}';
          if (!yol.endsWith('.md')) continue;
          expect(kaynaklar, contains(yol),
              reason: '$yol için docs/ sayfası yok (_build_legal.py → pages). '
                  '$adimlar');
        }
      }
    });

    test('kaynak md hash\'i güncel (md değişip betik koşulmadıysa kırılır)',
        () {
      expect(uretilen, isNotEmpty);
      for (final e in uretilen.entries) {
        final kaynak = meta(e.value, 'sandik-kaynak')!;
        expect(meta(e.value, 'sandik-kaynak-sha256'),
            sha(yasalMdKanonik(oku(kaynak))),
            reason: '${e.key}: $kaynak değişmiş, HTML eski. $adimlar');
      }
    });

    test('sayfa gövdesi elle düzenlenmemiş', () {
      for (final e in uretilen.entries) {
        final html = e.value;
        const basla = '<!-- sandik-govde:basla -->\n';
        const bitti = '\n<!-- sandik-govde:bitti -->';
        final i = html.indexOf(basla);
        final j = html.indexOf(bitti);
        expect(i >= 0 && j > i, isTrue,
            reason: '${e.key}: gövde işaretleri yok');
        final govde = html.substring(i + basla.length, j);
        expect(sha(govde), meta(html, 'sandik-govde-sha256'),
            reason: '${e.key} elle düzenlenmiş. HTML\'e değil md\'ye yaz, '
                'sonra `python docs/_build_legal.py`. $adimlar');
        expect(govde, isNot(contains('{SUPABASE')),
            reason: '${e.key}: yer tutucu web\'de doldurulmamış');
      }
    });

    test('web sayfası ile onaylanan metin aynı kimliği taşır', () {
      // Uygulama belgelerinde HTML'deki kaynak hash'i == katalog hash'i ==
      // veritabanındaki govde_hash: web'de okunan ile onaylanan aynı metin.
      for (final b in YasalBelge.values) {
        final html = uretilen.values
            .where((h) => meta(h, 'sandik-kaynak') == b.kaynak)
            .toList();
        expect(html, hasLength(1), reason: b.kaynak);
        expect(meta(html.single, 'sandik-kaynak-sha256'),
            YasalMetinKatalogu.belge(b).hash,
            reason: b.kaynak);
      }
    });

    test('elle bakılan açılış sayfası betiğin çıktısı değil', () {
      // docs/index.html elle bakılır (2026-10-01); betik onu yazmaz.
      final acilis = sayfalar['docs/index.html'];
      expect(acilis, isNotNull);
      expect(meta(acilis!, 'sandik-kaynak'), isNull);
    });
  });

  group('(c) md sürümü == katalog == migration', () {
    final migrationda = {for (final m in migrationMetinleri()) m.anahtar: m};

    test('her belgenin md künyesi, katalog ve migration aynı sürümü yazar', () {
      for (final b in YasalBelge.values) {
        final mdSurum = yasalMdSurum(oku(b.kaynak));
        final k = YasalMetinKatalogu.belge(b);
        expect(k.surum, mdSurum, reason: b.kaynak);
        final m = migrationda[k.anahtar];
        expect(m, isNotNull,
            reason: '${k.anahtar} (${b.kaynak}) hiçbir migration\'da yok. '
                '$adimlar');
        expect(m!.hash, k.hash,
            reason: '${b.kaynak} metni değişmiş ama "Sürüm: $mdSurum" aynı '
                '(migration: ${m.dosya}). $adimlar');
      }
    });

    test('künyedeki bütün "Sürüm" satırları aynı', () {
      // Açık Rıza Metni sürümü iki yerde yazar (başta ve imza bloğunda).
      for (final b in YasalBelge.values) {
        expect(yasalMdAlan(b.md, 'Sürüm').toSet(), hasLength(1),
            reason: b.kaynak);
      }
    });
  });

  group('(d) İngilizce çeviri kayması', () {
    /// TR karşılığı OLMAYAN İngilizce belgeler — çeviri değil, özgün.
    const ozgunIngilizce = {
      // KVKK Aydınlatma Metni'nin çevirisi DEĞİL: AB/AEA kullanıcıları için
      // GDPR'ın istediği ayrı bildirim (farklı hukuk rejimi). TR'si yok.
      'GDPR_NOTICE.md',
    };

    /// İngilizcesi OLMAYAN Türkçe belgeler. Uydurma çeviri yazılmaz; çeviri
    /// hukuk işi. Uygulama İngilizce arayüzde de Türkçe gösterir.
    const ingilizcesiYok = {
      'KVKK_AYDINLATMA_METNI.md',
      'ACIK_RIZA_METNI.md',
      'COKEZ_VE_DEPOLAMA.md',
    };

    List<String> adlar(String dizin) => [
          for (final f in Directory(dizin).listSync().whereType<File>())
            if (f.path.endsWith('.md')) f.uri.pathSegments.last,
        ]..sort();

    test('her İngilizce belge çeviri ya da bilinen özgün belge', () {
      for (final ad in adlar('legal/en')) {
        if (ozgunIngilizce.contains(ad)) continue;
        expect(File('legal/tr/$ad').existsSync(), isTrue,
            reason: 'legal/en/$ad\'nin TR karşılığı yok; çeviriyse aynı adla '
                'legal/tr/ altında olmalı, özgünse ozgunIngilizce\'ye ekle');
      }
    });

    test('her Türkçe belgenin çevirisi var ya da yokluğu bilinçli', () {
      for (final ad in adlar('legal/tr')) {
        final en = File('legal/en/$ad').existsSync();
        expect(en || ingilizcesiYok.contains(ad), isTrue,
            reason: 'legal/tr/$ad için İngilizce yok ve ingilizcesiYok\'ta da '
                'değil');
        expect(en && ingilizcesiYok.contains(ad), isFalse,
            reason: 'legal/en/$ad var; ingilizcesiYok\'tan çıkar');
      }
    });

    test('çeviri hangi TR sürümünü çevirdiğini beyan eder ve güncel', () {
      for (final ad in adlar('legal/en')) {
        if (ozgunIngilizce.contains(ad)) continue;
        final en = oku('legal/en/$ad');
        final trSurum = yasalMdSurum(oku('legal/tr/$ad'));
        final kaynak = yasalMdAlan(en, 'Source');
        expect(kaynak, hasLength(1),
            reason: 'legal/en/$ad bir "**Source:** TR x" satırı taşımalı');
        final m = RegExp(r'^TR (\S+)').firstMatch(kaynak.single);
        expect(m?[1], trSurum,
            reason: 'legal/tr/$ad $trSurum oldu ama legal/en/$ad hâlâ '
                '"${kaynak.single}" diyor: çeviriyi güncelle, "**Source:** TR '
                '$trSurum" ve "**Version:** $trSurum" yaz, sonra `python '
                'docs/_build_legal.py`.');
        expect(yasalMdSurum(en, etiket: 'Version'), trSurum,
            reason: 'legal/en/$ad "**Version:**" TR sürümüyle aynı olmalı');
      }
    });

    test('çeviri aynı yer tutucuları taşır', () {
      for (final ad in adlar('legal/en')) {
        if (ozgunIngilizce.contains(ad)) continue;
        expect(yasalMdYerTutuculari(oku('legal/en/$ad')),
            yasalMdYerTutuculari(oku('legal/tr/$ad')),
            reason: 'legal/en/$ad');
      }
    });
  });

  group('ayrıştırıcı', () {
    test('kanonik: BOM, CRLF ve sondaki boşluk atılır', () {
      expect(yasalMdKanonik('﻿# A\r\n\r\nb  \r\n\n'), '# A\n\nb');
    });

    test('künye, liste, tablo, alıntı, satır içi işaret', () {
      const md = '# Belge — sandık\n\n'
          '**Yürürlük tarihi:** 4 Ekim 2026\n**Sürüm:** 1.2\n\n---\n\n'
          '## 1. Bölüm\n\n'
          '**İstisnalar:** `Şirket` **sorumlu** değildir.\n\n'
          'Liste:\n- bir\n- *iki*\n\n'
          '| A | B |\n|---|---|\n| x | {SUPABASE_ULKE} |\n\n'
          '> not\n\n'
          '*Dipnot **3 yıl** saklanır.*';
      final b = yasalMdBloklari(md);
      expect([
        for (final x in b) x.type
      ], [
        LegalBlockType.h1,
        LegalBlockType.meta,
        LegalBlockType.divider,
        LegalBlockType.h2,
        LegalBlockType.paragraph,
        LegalBlockType.paragraph,
        LegalBlockType.tableHeader,
        LegalBlockType.tableRow,
        LegalBlockType.meta,
        LegalBlockType.meta,
      ]);
      expect(b[1].text, 'Yürürlük tarihi: 4 Ekim 2026\nSürüm: 1.2');
      // Kalın etiketli gövde cümlesi künye değildir.
      expect(b[4].text, 'İstisnalar: Şirket sorumlu değildir.');
      expect(b[5].text, 'Liste:\n· bir\n· iki');
      expect(b[7].cells, ['x', '{SUPABASE_ULKE}']);
      expect(b[9].text, 'Dipnot 3 yıl saklanır.');
      expect(yasalMdBaslik(md), 'Belge');
      expect(yasalMdSurum(md), '1.2');
      expect(yasalMdYururluk(md), '2026-10-04');
    });

    test('farklı "Sürüm" satırları hata verir', () {
      expect(() => yasalMdSurum('**Sürüm:** 1.2\n\n**Sürüm:** 1.1'),
          throwsStateError);
    });
  });
}
