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

/// Metin ALANINA yazılacak sayı: binlik ayraçsız, ondalık `,`, gereksiz
/// sıfırsız (`41,235`, `1000`, `0,125`).
///
/// **Neden:** alanlar `parseTrNumber` ile okunur. Önceden doldurma
/// `double.toString()` ile yapılıyordu (`41.235`); tam 3 ondalıklı bir
/// kotasyon binlik sanılıp 1000 kat büyük kaydediliyordu — kullanıcı
/// önceden doldurulmuş fiyata dokunmadan "Ekle"ye basınca (2026-09-23
/// denetimi F1). Bu biçim `parseTrNumber` ile gidiş-dönüş kayıpsızdır.
String fmtInputTr(double value, {int maxDigits = 8}) {
  final f = NumberFormat('0.${'#' * maxDigits}', 'tr_TR');
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
///
/// Milyar (`Mr`) ve trilyon (`Tn`) basamakları 2026-09-23 denetimi U14'te
/// eklendi: yalnızca `M` vardı ve 80 trilyonluk bir tutar
/// `₺80.000.000,32M` yazılıyordu — kısaltmanın amacı olan "dar alanda
/// okunur" tamamen kayboluyordu. `Mr` [fmtTRYAxis] ile aynı kısaltma.
String fmtTRYCompact(double value) {
  final abs = value.abs();
  final sign = value < 0 ? '-' : '';
  if (abs >= 1e12) {
    return '$sign₺${fmtNum(abs / 1e12, digits: 2)}Tn';
  }
  if (abs >= 1e9) {
    return '$sign₺${fmtNum(abs / 1e9, digits: 2)}Mr';
  }
  if (abs >= 1000000) {
    return '$sign₺${fmtNum(abs / 1000000, digits: 2)}M';
  }
  if (abs >= 1000) {
    return '$sign₺${fmtNum(abs / 1000, digits: 1)}K';
  }
  return '$sign₺${fmtNum(abs, digits: 0)}';
}

/// Grafik ekseni için tutar etiketi — iki sınır AYIRT EDİLEBİLİR olmalı.
///
/// [fmtTRYCompact] tek başına yetmiyor: milyonu iki ondalıkla kısaltıyor
/// ve dar bir bantta iki sınır da aynı metne düşüyor (`₺2,49M` / `₺2,49M`).
/// Böyle bir eksen "hangi aralıkta gezindi" sorusunu yanıtlamaz.
///
/// [span] eksenin toplam genişliğidir; ondalık sayısı ona göre seçilir:
/// bant ne kadar darsa o kadar çok basamak gerekir. Üst sınır olarak 4
/// ondalık: daha fazlası dar bir eksende okunmaz.
String fmtTRYAxis(double value, double span) {
  final abs = value.abs();
  final sign = value < 0 ? '-' : '';

  // Trilyon — `Tn` (U14, 2026-09-23 denetimi; bkz. [fmtTRYCompact]).
  if (abs >= 1e12) {
    final spanTn = span / 1e12;
    final digits = spanTn >= 0.02 ? 2 : (spanTn >= 0.002 ? 3 : 4);
    return '$sign₺${fmtNum(abs / 1e12, digits: digits)}Tn';
  }
  // Milyar — `Mr` kısaltmasıyla. Bu basamak eksikti ve 1,25 milyarlık bir
  // portföy `₺1.250,00M` olarak yazılıyordu: hem uzun hem okunmuyor.
  if (abs >= 1000000000) {
    final spanMr = span / 1000000000;
    final digits = spanMr >= 0.02 ? 2 : (spanMr >= 0.002 ? 3 : 4);
    return '$sign₺${fmtNum(abs / 1000000000, digits: digits)}Mr';
  }
  if (abs >= 1000000) {
    final scaled = abs / 1000000;
    // Bant milyon cinsinden ne kadar dar? 0,01M (10 bin TL) altındaki
    // farklar iki ondalıkla görünmez olur.
    final spanM = span / 1000000;
    final digits = spanM >= 0.02 ? 2 : (spanM >= 0.002 ? 3 : 4);
    return '$sign₺${fmtNum(scaled, digits: digits)}M';
  }
  if (abs >= 1000) {
    final spanK = span / 1000;
    final digits = spanK >= 0.2 ? 1 : 2;
    return '$sign₺${fmtNum(abs / 1000, digits: digits)}K';
  }
  return '$sign₺${fmtNum(abs, digits: span < 10 ? 2 : 0)}';
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
/// - Binlik okuması için ilk grup da geçerli bir binlik grubu olmalı: 1–3
///   hane ve `0` ile başlamayan. `0.125` gram ya da `1234.567` hiçbir
///   yazımda binlik olamaz; eskiden 125 ve 1234567 okunuyordu
///   (2026-09-23 denetimi F1/F15).
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
    final bas = parts.first.startsWith('-') ? parts.first.substring(1) : parts.first;
    final ilkGrupGecerli =
        bas.isNotEmpty && bas.length <= 3 && !bas.startsWith('0');
    final allGroupsAreThree = parts.length > 1 &&
        ilkGrupGecerli &&
        parts.skip(1).every((p) => p.length == 3);
    if (allGroupsAreThree) s = s.replaceAll('.', '');
  }

  final val = double.tryParse(s);
  if (val == null || !val.isFinite) return null;
  return val;
}

// ── Biçimlendirici NESNELERİ ─────────────────────────────────────────────
//
// Bazı çağrı yerleri (grafik tooltip'leri, satır widget'ları) `NumberFormat`
// nesnesini parametre olarak taşıyor. Orada `fmtTRY` gibi bir fonksiyon değil
// nesne gerekir. Nesne de buradan üretilir ki `NumberFormat.currency(locale:
// 'tr_TR' …)` literal'i kod tabanında tek yerde kalsın — 2026-09 denetiminde
// 20 kopyası vardı ve aynı ₺ tutarı için 0/2/3 ondalık arasında değişiyordu.
// Ondalık sayısı çağıranın kararıdır (alış maliyeti 3, tutar 0), ama sembol,
// locale ve ayraçlar buradan gelir.

/// `₺1.234,56` üreten biçimlendirici. [symbol] yalnızca döviz cinsinden
/// gösterilen takip kalemleri için değiştirilir.
NumberFormat tryFormatter({int digits = 0, String symbol = '₺'}) =>
    NumberFormat.currency(locale: 'tr_TR', symbol: symbol, decimalDigits: digits);

/// Miktar: trailing sıfır atan, en fazla [maxDigits] ondalıklı (`1.234,5`).
NumberFormat qtyFormatter({int maxDigits = 4}) =>
    NumberFormat('#,##0${maxDigits > 0 ? '.${'#' * maxDigits}' : ''}', 'tr_TR');

/// Sabit ondalıklı sayı (`1.234,500`) — birim maliyet gibi hizalı sütunlar.
NumberFormat fixedFormatter(int digits) =>
    NumberFormat('#,##0${digits > 0 ? '.${'0' * digits}' : ''}', 'tr_TR');

/// Takvim günü anahtarı — saat/dakika atılmış tarih.
///
/// `DateTime(t.year, t.month, t.day)` 38 yerde elle yazılıyordu. Tek isim,
/// tek anlam: "aynı gün mü" ve "gün sayısı farkı" karşılaştırmaları buradan.
DateTime dayKey(DateTime t) => DateTime(t.year, t.month, t.day);

/// İşlem damgası gerçek bir SAAT taşıyor mu?
///
/// Tarih seçiciyle girilen işlem (`pickSandikDate`) yerel 00:00:00 olarak
/// kaydedilir — saati BİLİNMİYORDUR. "00:00" yazmak uydurma bir saat
/// göstermek olur; o yüzden tam gece yarısı "saat yok" sayılır. Tam 00:00'da
/// gerçekten işlem yapılma olasılığı, yanlış saat göstermenin maliyetinden
/// küçüktür. UTC nesnede yanlış karar verir — `Asset.fromSupabase` yerel
/// saate çevirir (2026-09-24).
bool saatBiliniyor(DateTime t) {
  final y = t.toLocal();
  return y.hour != 0 || y.minute != 0 || y.second != 0 || y.millisecond != 0;
}

/// Zaman damgası: `23 Eyl 2026 · 14:32`, saat yoksa `23 Eyl 2026`.
///
/// İki kullanıcı isteğinin (2026-09-24) ortak cevabı:
///   · portföy hareketleri — "saat bilgisi de ekle"
///   · grafikte gezinirken — "hangi saatteyim görmeliyim"
///
/// Grafikte günlük/haftalık kova 00:00'a oturur; orada saat yazmak "00:00"
/// gürültüsü olurdu. Saatlik kovalar ve "şimdi" noktası ise gerçek saat
/// taşır. Kural tek: [saatBiliniyor].
String fmtTarihSaat(DateTime t) {
  final y = t.toLocal();
  return saatBiliniyor(y)
      ? DateFormat('d MMM yyyy · HH:mm', 'tr_TR').format(y)
      : DateFormat('d MMM yyyy', 'tr_TR').format(y);
}
