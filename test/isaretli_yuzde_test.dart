import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/widgets/bugun_karti.dart';

import 'helpers/kaynak.dart';

/// Büyüme planı F3 — anlaşılırlık (2026-09-29).
///
/// 1. Bugün kartında yüzde, tutarla AYNI işaret biçimini taşır: yön yalnız
///    renkte kalırsa renk körlüğünde ve ekran okuyucuda kaybolur.
/// 2. Enflasyon farkı yönü KELİMEYLE söyler; işaretli çıplak "−20,6 puan"
///    jargonu kalkar. Hesap değişmez, yalnızca metin.
void main() {
  group('isaretliYuzde', () {
    test('pozitif: "+" önek', () {
      expect(isaretliYuzde(1.234), '+%1,23');
    });

    test('negatif: U+2212 eksi (tire değil), tutardaki gibi', () {
      final m = isaretliYuzde(-0.06);
      expect(m, '−%0,06');
      expect(m.codeUnitAt(0), 0x2212);
      expect(m.contains('-'), isFalse);
    });

    test('sıfır ve sıfıra yuvarlanan: işaret YOK', () {
      expect(isaretliYuzde(0), '%0,00');
      expect(isaretliYuzde(0.004), '%0,00');
      expect(isaretliYuzde(-0.004), '%0,00');
    });

    test('hane sayısı korunur', () {
      expect(isaretliYuzde(-12.345, digits: 1), '−%12,3');
    });

    test('kaynak: kartta işaretsiz fmtPct(x.abs()) yüzdesi kalmadı', () {
      final src = ekranKaynagiSync('lib/widgets/bugun_karti.dart')
          .split('\n')
          .where((s) => !s.trimLeft().startsWith('//'))
          .join('\n');
      // 2026-10-01 "sakin pano" (PR #63): kart yüzdeyi işaretsiz yazar ama
      // YÖN artık renkte kalmıyor — günlük rozette OK (`yon`). 2026-09-29'daki
      // kural "yön yalnız renkte kalmasın"dı. (Haftalık kutunun yön KELİMESİ
      // — `todayWeekUp/Down` — D düzeniyle 2026-10-05'te kalktı.)
      // 2026-10-09 benchmark düzeni: yüzde rozeti yok; yüzde ekran
      // okuyucuya İŞARETLİ gider (`isaretliYuzde`), kartta işaretsiz
      // `fmtPct(x.abs())` kalmadı.
      expect(RegExp(r'fmtPct\([^)]*\.abs\(\)').allMatches(src).length, 0);
      expect(src.contains('yuzde = isaretliYuzde(s.changePct);'), isTrue,
          reason: 'günlük yüzde yönü işaretle söylemeli');
    });
  });

  test('piyasa şeridi de aynı biçim: eksi "−%0,23", "%-0,23" değil', () {
    // 2026-09-29 emülatör testi: şerit ekran okuyucu metni "%-0,23" yazıyordu.
    expect(fmtPctIsaretli(-0.23), '\u2212%0,23');
    expect(fmtPctIsaretli(0.08), '+%0,08');
    expect(fmtPctIsaretli(0.001), '%0,00');
    final kaynak = ekranKaynagiSync('lib/widgets/piyasa_seridi.dart');
    expect(kaynak.contains('fmtPctIsaretli(degisimPct!)'), isTrue);
  });

  group('enflasyon farkı — yön kelimede', () {
    final tr = lookupAppLocalizations(const Locale('tr'));
    final en = lookupAppLocalizations(const Locale('en'));

    test('Bugün kartı: önde / geride / başa baş', () {
      expect(reelFarkMetni(tr, fark: 5.24, onde: true), '5,2 puan önde');
      expect(reelFarkMetni(tr, fark: -20.6, onde: false), '20,6 puan geride');
      expect(reelFarkMetni(tr, fark: 0.02, onde: true), 'başa baş');
      expect(reelFarkMetni(en, fark: -20.6, onde: false), '20,6 pts behind');
    });

    test('değerde işaret ve çıplak "puan" kalmadı', () {
      for (final m in [
        reelFarkMetni(tr, fark: 5.2, onde: true),
        reelFarkMetni(tr, fark: -20.6, onde: false),
      ]) {
        expect(m.contains('−') || m.contains('+') || m.contains('-'), isFalse,
            reason: m);
        expect(RegExp(r'^\S+ puan$').hasMatch(m), isFalse, reason: m);
      }
    });

    test('yıl sonu özeti: yön cümlede, iki dilde', () {
      expect(tr.recapPointsAhead('5,2'), 'Enflasyonu 5,2 puan geçtin');
      expect(tr.recapPointsBehind('20,6'),
          'Enflasyonun 20,6 puan gerisinde kaldın');
      expect(en.recapPointsAhead('5.2'), contains('beat inflation'));
      expect(en.recapPointsBehind('20.6'), contains('trailed inflation'));
    });
  });
}
