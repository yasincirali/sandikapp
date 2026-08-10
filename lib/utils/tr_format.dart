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

/// Kullanıcının yazdığı sayıyı Türkçe biçime göre çözer.
///
/// **Neden gerekli:** kod tabanında dört ayrı yerde
/// `double.tryParse(text.replaceAll(',', '.'))` deseni vardı. Bu desen
/// Türkçe girdide **sessizce yanlış sonuç** verir, çünkü `.` binlik
/// ayracıdır:
///
/// | girdi | eski sonuç | doğrusu |
/// |---|---|---|
/// | `1.000` | **1.0** | 1000 |
/// | `10.000` | **10.0** | 10000 |
/// | `1.234,5` | **null** | 1234.5 |
/// | `1,5` | 1.5 | 1.5 ✓ |
///
/// Yani "1.000 lot" yazan kullanıcı portföyüne **1 lot** kaydediyordu ve
/// hiçbir uyarı almıyordu — finansal bir uygulamada sessiz veri bozulması.
///
/// Kural:
/// - Hem `.` hem `,` varsa: SONUNCUSU ondalık ayracıdır, diğeri binliktir.
/// - Yalnızca `,` varsa: ondalık ayracıdır (`1,5` → 1.5).
/// - Yalnızca `.` varsa: belirsiz. Nokta sonrası **tam 3 hane** ve birden
///   fazla grup varsa binlik sayılır (`1.000`, `1.000.000`); aksi halde
///   ondalık kabul edilir (`1.5` → 1.5). Bu, hem klavyeden `.` ile ondalık
///   yazan kullanıcıyı hem binlik ayracını korur.
double? parseTrNumber(String text) {
  var s = text.trim();
  if (s.isEmpty) return null;
  s = s.replaceAll(RegExp(r'[\s\u00A0₺$€£]'), '');
  if (s.isEmpty) return null;

  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');

  if (lastDot >= 0 && lastComma >= 0) {
    // İkisi de var → sonuncusu ondalık.
    if (lastComma > lastDot) {
      s = s.replaceAll('.', '').replaceFirst(',', '.');
    } else {
      s = s.replaceAll(',', '');
    }
  } else if (lastComma >= 0) {
    s = s.replaceFirst(',', '.');
  } else if (lastDot >= 0) {
    // Yalnızca nokta: binlik mi ondalık mı?
    final parts = s.split('.');
    final allGroupsAreThree =
        parts.length > 1 && parts.skip(1).every((p) => p.length == 3);
    if (allGroupsAreThree) s = s.replaceAll('.', '');
  }

  final val = double.tryParse(s);
  if (val == null || !val.isFinite) return null;
  return val;
}
