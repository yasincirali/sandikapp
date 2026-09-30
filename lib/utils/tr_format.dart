import 'dart:math' as math;
import 'package:intl/intl.dart';

/// Uygulama geneli Türkçe sayı biçimlendirme.
///
/// Kural: binlik ayırıcı `.`, ondalık ayırıcı `,`. Yüzde ve grafik/eksen
/// etiketleri dahil TÜM kullanıcıya görünen sayı bu helper'lardan geçer;
/// aksi halde `toStringAsFixed` çıktısı (`1.5`, `1234.56`) TR locale ile
/// tutarsız olur.

/// Yüzde: `%12,34` — [digits] ondalık hane sayısı. YÖNSÜZ büyüklükler için
/// (pay, oynaklık, güven, stopaj oranı).
///
/// Eskiden `showSign` parametresi vardı: artıyı "%+1,23", eksiyi sayının
/// içine "%-8,48" yazıyordu — tutarların "−₺368" diliyle çelişen ikinci bir
/// yön biçimi (2026-09-29 emülatör testi #5: dönem istatistiği, dönem
/// seçici, arama satırı, kıyas grafiği, yarış kartı). Yönlü yüzde artık
/// yalnızca [fmtPctIsaretli]; parametre, ikinci biçim geri gelmesin diye
/// kaldırıldı (`yonlu_yuzde_tek_kaynak_test`).
String fmtPct(double value, {int digits = 2}) {
  final f = NumberFormat.decimalPattern('tr_TR')
    ..minimumFractionDigits = digits
    ..maximumFractionDigits = digits;
  return '%${f.format(value)}';
}

/// Yönlü yüzde: `+%1,23` / `−%0,06` — tutarla AYNI işaret biçimi.
///
/// [fmtPct] eksiyi sayının içine koyar ("%-0,23"); uygulamanın tutarları ise
/// U+2212 ile başa yazar ("−₺368"). Yan yana duran tutar ve yüzde aynı dili
/// konuşsun diye yönlü yüzde TEK yerden (2026-09-29 emülatör testi: piyasa
/// şeridi "%-0,23", Bugün kartı "−%0,06" yazıyordu). Sıfıra yuvarlanan değer
/// işaretsiz: "−%0,00" yönü olmayan şeye yön yazardı.
String fmtPctIsaretli(double pct, {int digits = 2}) {
  final metin = fmtPct(pct.abs(), digits: digits);
  if (metin == fmtPct(0, digits: digits)) return metin;
  return '${pct > 0 ? '+' : '\u2212'}$metin';
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

/// Birim FİYAT (tutar değil): 1 ₺ ve üstünde 2 ondalık, altında en az 4
/// anlamlı hane (en çok 8 ondalık). SHIB ~0,0004 ₺ `fmtTRY(digits: 2)` ile
/// "₺0,00" okunurdu — sıfır fiyatlı gibi. Toplam/değer için `fmtTRY` kalır.
String fmtTRYFiyat(double value) {
  final a = value.abs();
  var digits = 2;
  if (a > 0 && a < 1) {
    digits = ((-math.log(a) / math.ln10).floor() + 4).clamp(2, 8);
  }
  return fmtTRY(value, digits: digits);
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

/// [fmtTRYCompact] + sondaki anlamsız sıfırlar atılır: `₺250K`, `₺2,5M`,
/// `₺1,25M`.
///
/// Hedef gibi YUVARLAK tutarlar içindir: hedef çiplerinde "₺250,0K" ve
/// "₺2,50M" yazıyordu (2026-09-29 emülatör testi #31) — ",0" okuyana
/// hassasiyet değil gürültü söyler. [fmtTRYCompact] kendisi değişmedi:
/// eksenler ve baz para parite testi (`money_format_test`) sabit ondalığa
/// yaslanıyor; aynı eksende "₺1,5M | ₺1,55M" karışık hane okunmaz.
String fmtTRYCompactSade(double value) {
  final s = fmtTRYCompact(value);
  // Yalnızca sondaki ondalık kısım: ",50M" → ",5M", ",0K" → "K".
  return s.replaceFirstMapped(RegExp(r',(\d*?)0+([A-Za-z]*)$'),
      (m) => '${m[1]!.isEmpty ? '' : ',${m[1]}'}${m[2]}');
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
///
/// ## Çok çizgili eksende [span] = ADIM (2026-09-29 emülatör testi #7)
/// Performans grafiği `fmtTRYCompact` ile "₺1,39M | ₺1,39M | ₺1,39M |
/// ₺1,39M", varlık detayı "₺1 | ₺1" yazıyordu: ızgara adımı (~₺2.500 /
/// ₺0,25) etiketin gösterdiği hassasiyetten (₺10.000 / ₺1) küçüktü.
/// Kural "komşu iki etiket ayırt edilebilir"; iki sınırlı yüzeyde (widget,
/// Live Activity) komşu = iki uç, yani [span] bant genişliği; ızgaralı
/// grafikte komşu = bir ADIM ötesi, yani [span] = eksen adımı.
String fmtTRYAxis(double value, double span) {
  final sign = value < 0 ? '-' : '';
  return '$sign₺${eksenGovdesi(value.abs(), span)}';
}

/// Ayırt etme hanesi: [olcekliAdim] kadar ayrık iki değeri FARKLI metne
/// yazmaya yeten en az ondalık (çözünürlük 10^-hane ≤ adım).
int _ayirtHanesi(double olcekliAdim) {
  if (!(olcekliAdim > 0) || !olcekliAdim.isFinite) return 0;
  return (-math.log(olcekliAdim) / math.ln10 - 1e-9).ceil();
}

/// Eksen etiketinin sembolsüz, işaretsiz gövdesi ("2,45M", "1.500,00") —
/// [fmtTRYAxis] ve `BazPara.axis` AYNI kademe kuralını paylaşsın diye tek
/// yerde (ikisi ayrı kopya taşıyordu).
///
/// Her kademenin TABAN hanesi eski kuraldır (geniş bantta sade: "₺2,45M");
/// taban [span]'ı ayırt etmeye yetmiyorsa hane artar, kademenin tavanını
/// da aşıyorsa kısaltmasız yazılır ("₺1.390.123"). Böylece yeterli olduğu
/// her durumda çıktı eskisiyle birebir aynı kalır, yalnızca tekrar eden
/// etiket üreten durumlar değişir.
String eksenGovdesi(double abs, double span) {
  final s = span.abs();
  int buyukTaban(double olcekli) =>
      olcekli >= 0.02 ? 2 : (olcekli >= 0.002 ? 3 : 4);
  String? kademe(double bolen, String ek, int taban, int tavan) {
    final hane = math.max(taban, _ayirtHanesi(s / bolen));
    if (hane > tavan) return null;
    return '${fmtNum(abs / bolen, digits: hane)}$ek';
  }

  final String? kisa;
  if (abs >= 1e12) {
    // Trilyon — `Tn` (U14, 2026-09-23 denetimi; bkz. [fmtTRYCompact]).
    kisa = kademe(1e12, 'Tn', buyukTaban(s / 1e12), 4);
  } else if (abs >= 1e9) {
    // Milyar — `Mr` kısaltmasıyla. Bu basamak eksikti ve 1,25 milyarlık bir
    // portföy `₺1.250,00M` olarak yazılıyordu: hem uzun hem okunmuyor.
    kisa = kademe(1e9, 'Mr', buyukTaban(s / 1e9), 4);
  } else if (abs >= 1e6) {
    // Bant milyon cinsinden ne kadar dar? 0,01M (10 bin TL) altındaki
    // farklar iki ondalıkla görünmez olur.
    kisa = kademe(1e6, 'M', buyukTaban(s / 1e6), 4);
  } else if (abs >= 1000) {
    kisa = kademe(1000, 'K', s / 1000 >= 0.2 ? 1 : 2, 2);
  } else {
    kisa = null;
  }
  if (kisa != null) return kisa;
  final hane = math.max(s < 10 ? 2 : 0, _ayirtHanesi(s)).clamp(0, 8);
  return fmtNum(abs, digits: hane);
}

/// Izgaralı eksende adımı TAM gösteren ondalık sayısı: 0,25'lik adım iki
/// haneyle ("0,25 · 0,50"), 2,5'lik bir haneyle, 5'lik hanesiz yazılır.
///
/// Tam gösterim ayırt etmeyi de garanti eder (adımın katları farklı metne
/// düşer). Yüzde ekseni aynı kuralı `yuzdeEkseni.ondalik` ile uygular; bu,
/// fiyat ve kıyas-yüzde eksenleri içindir. [enCok] dar eksende okunurluk
/// tavanı.
int eksenOndaligi(double adim, {int enAz = 0, int enCok = 4}) {
  if (!(adim > 0) || !adim.isFinite) return enAz;
  var d = enAz;
  while (d < enCok) {
    final o = adim * math.pow(10, d);
    if ((o - o.roundToDouble()).abs() <= 1e-6 * math.max(1.0, o.abs())) break;
    d++;
  }
  return d;
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
///
/// [yilsiz]: yıl zaten bir üst başlıkta yazılıysa (tüm hareketler ekranı
/// ay kapları "EYLÜL 2026") satırda tekrar etmez — "25 Eyl · 14:29".
String fmtTarihSaat(DateTime t, {bool yilsiz = false}) {
  final y = t.toLocal();
  final gun = yilsiz ? 'd MMM' : 'd MMM yyyy';
  return saatBiliniyor(y)
      ? DateFormat('$gun · HH:mm', 'tr_TR').format(y)
      : DateFormat(gun, 'tr_TR').format(y);
}

