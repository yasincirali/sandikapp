import 'package:intl/intl.dart';

/// Uygulama geneli Türkçe sayı biçimlendirme.
///
/// Kural: binlik ayırıcı `.`, ondalık ayırıcı `,`. Yüzde ve grafik/eksen
/// etiketleri dahil TÜM kullanıcıya görünen sayı bu helper'lardan geçer;
/// aksi halde `toStringAsFixed` çıktısı (`1.5`, `1234.56`) TR locale ile
/// tutarsız olur.

/// Yüzde: `%12,34` — [digits] ondalık hane sayısı.
String fmtPct(double value, {int digits = 2, bool showSign = false}) {
  final f = NumberFormat.decimalPattern('tr_TR')
    ..minimumFractionDigits = digits
    ..maximumFractionDigits = digits;
  final str = f.format(value);
  final sign = showSign && value > 0 ? '+' : '';
  return '%$sign$str';
}

/// Genel sayı: `1.234,56` — [digits] ondalık hane (default 2).
String fmtNum(double value, {int digits = 2}) {
  final f = NumberFormat.decimalPattern('tr_TR')
    ..minimumFractionDigits = digits
    ..maximumFractionDigits = digits;
  return f.format(value);
}

/// Değişken ondalıklı sayı — 0 ondalık istenen değer için trailing sıfırları
/// atar. `#,##0.####` gibi davranır.
String fmtNumFlex(double value, {int maxDigits = 4}) {
  final f = NumberFormat('#,##0.${'#' * maxDigits}', 'tr_TR');
  return f.format(value);
}

/// TRY para birimi: `₺1.234` (tam sayı) / `₺1.234,56` (ondalıklı).
String fmtTRY(double value, {int digits = 0}) {
  return NumberFormat.currency(
          locale: 'tr_TR', symbol: '₺', decimalDigits: digits)
      .format(value);
}

/// Kısa TRY: `₺1.5K` yerine `₺1,5K`, `₺2.3M` yerine `₺2,3M`. Sadece grafik
/// eksen etiketleri gibi dar alanlarda kullanılmalı; genel değerler `fmtTRY`.
String fmtTRYCompact(double value) {
  final abs = value.abs();
  final sign = value < 0 ? '-' : '';
  if (abs >= 1000000) {
    return '$sign₺${fmtNum(abs / 1000000, digits: 2)}M';
  }
  if (abs >= 1000) {
    return '$sign₺${fmtNum(abs / 1000, digits: 1)}K';
  }
  return '$sign₺${fmtNum(abs, digits: 0)}';
}
