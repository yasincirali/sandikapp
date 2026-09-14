import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Baz para birimi (3.2) — KAPSAM ratchet'i.
///
/// Sözleşme (`utils/money_format.dart`): portföy DEĞERLERİ baz birimde
/// yazılır, kote FİYATLAR ₺ (kendi biriminde) kalır. Bu iki küme bir yorumla
/// değil, bu testle ayrı tutulur:
///
/// - Değer kümesindeki dosyalarda 0 ondalıklı ham `tryFormatter(digits: 0)`
///   ya da `fmtTRY(` kalmamalı — kalırsa o tutar tercihi yok sayıp ₺ yazar ve
///   ekran karışık sembolle çıkar (yol haritasının uyardığı "yarım" hâl).
/// - Fiyat kümesindeki dosyalar `BazPara`/`bazParaProvider` KULLANMAMALI —
///   bir hissenin TL fiyatını dolara çevirmek borsadaki sayıyla çelişir.
///
/// Yeni bir tutar sitesi eklerken önce hangi kümede olduğuna karar ver,
/// sonra ilgili listeyi güncelle.
void main() {
  const degerDosyalari = [
    'lib/screens/home_screen.dart',
    'lib/widgets/portfolio_summary_widget.dart',
    'lib/widgets/period_summary_view.dart',
    'lib/screens/portfolio_performance_screen.dart',
    'lib/screens/portfolio_screen.dart',
    // Hareket tutarı da bir değerdir: maliyet zaten bugünkü kurla
    // çevriliyor, aynı sınıf sayının listede ₺ kalması tutarsızdı
    // (2026-09-14, 3. tur).
    'lib/widgets/transaction_row.dart',
  ];

  // Fiyat kümesi: alarm hedefi, kotasyon, form girdisi.
  const fiyatDosyalari = [
    'lib/screens/price_alerts_screen.dart',
    'lib/widgets/alarm_kur_sheet.dart',
    'lib/widgets/alarm_seridi.dart',
    'lib/screens/watchlist_screen.dart',
    'lib/screens/watchlist_detail_screen.dart',
    'lib/screens/add_asset_screen.dart',
  ];

  // Uygulama dışı yüzeyler ve bildirim metinleri ₺ kalır — orada
  // `WidgetRef` yok ve kur tercihi cihaza/sunucuya itilmiyor (bilinçli;
  // TECHNICAL_DEBT "Baz para birimi yalnızca gösterim katmanı").
  const disYuzeyler = [
    'lib/services/live_activity_service.dart',
    'lib/services/home_widget_service.dart',
    'lib/services/daily_summary.dart',
    'lib/services/recap_service.dart',
    'lib/services/milestone_service.dart',
  ];

  final hamDeger = RegExp(r'\b(fmtTRY\(|tryFormatter\(digits: 0\))');

  group('değer dosyaları ham ₺ biçimleyici kullanmaz', () {
    for (final f in degerDosyalari) {
      test(f, () {
        final src = File(f).readAsStringSync();
        final hits = <String>[];
        final lines = src.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (hamDeger.hasMatch(lines[i])) {
            hits.add('${i + 1}: ${lines[i].trim()}');
          }
        }
        expect(hits, isEmpty,
            reason: 'BazPara.formatter / .format kullan:\n${hits.join('\n')}');
        expect(src.contains('BazPara') || src.contains('bazParaProvider'), isTrue,
            reason: 'dosya değer kümesinde ama baz para birimini hiç okumuyor');
      });
    }
  });

  group('fiyat dosyaları çevirim yapmaz', () {
    for (final f in fiyatDosyalari) {
      test(f, () {
        final src = File(f).readAsStringSync();
        expect(src.contains('BazPara'), isFalse,
            reason: 'kote fiyat baz para birimine çevrilmez');
        expect(src.contains('bazParaProvider'), isFalse);
      });
    }
  });

  group('uygulama dışı yüzeyler ₺ kalır (bilinçli)', () {
    for (final f in disYuzeyler) {
      test(f, () {
        final src = File(f).readAsStringSync();
        expect(src.contains('BazPara'), isFalse);
      });
    }
  });

  test('karışık dosya: asset_detail — değişim tutarı çevrilir, fiyat ipucu ₺', () {
    final ad = File('lib/screens/asset_detail_screen.dart').readAsStringSync();
    expect(ad.contains('baz.formatter(digits: 0)'), isTrue,
        reason: 'dönem değişim tutarı portföy değeridir');
    expect(ad.contains('tryFormatter(digits: 0)'), isFalse);
    expect(ad.contains('tryFormatter(digits: 2)'), isTrue,
        reason: 'fiyat ipucu (₺, 2 ondalık) çevrilmez');
  });
}
