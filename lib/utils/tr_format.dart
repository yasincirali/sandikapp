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

/// Altın ağırlığı (gram), birimsiz: `1,75` / `42,6` / `1.250,0`.
///
/// 10 gramın altında iki ondalık (çeyrek 1,75 gr, has karşılığı 1,60 gr;
/// tek ondalık "1,8" diye yuvarlayıp kalıbı yanlış söylerdi), üstünde tek
/// ondalık: toplamda yüzde bir gram okunmaz, yalnız kalabalık yapar.
/// Birim ("gr" / "g") dile göre .arb metninde yazılır.
String fmtGram(double gram) => fmtNum(gram, digits: gram.abs() < 10 ? 2 : 1);

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
String fmtTRYFiyat(double value) => fmtTRY(value, digits: fiyatOndaligi(value));

/// [fmtTRYFiyat]'ın ondalık kuralı — biçimleyiciyi kendisi kuran yerler
/// (varlık ekranının birim fiyatı) aynı kuralı buradan alır.
int fiyatOndaligi(double value) {
  final a = value.abs();
  if (a > 0 && a < 1) {
    return ((-math.log(a) / math.ln10).floor() + 4).clamp(2, 8);
  }
  return 2;
}

/// Birim fiyat biçimleyicisi — fiyat gösteren HER yüzey buradan.
///
/// [azami] null → eski kural ([fiyatOndaligi]: 1 ₺ üstü 2 hane, altı 4
/// anlamlı hane). Takip listesi, varlık sayfası ve arama satırı sabit 2
/// haneydi; SHIB ₺0,00, BES fonu ₺0,18 okunuyordu (varlık detayında
/// ₺0,1791) — bayrak kapalıyken de bu kurala bağlandılar.
///
/// [azami] verilirse KAYNAK HASSASİYETİ (yasin, 2026-10-10: "yuvarlama
/// yapmayalım, fiyat kaynaktan nasıl geliyorsa öyle; 1.23000 ise 1,23
/// olsun, 1.00000012 ise öyle kalsın"): en az 2 hane, en çok [azami];
/// sondaki sıfırlar atılır. [azami] türün standardıdır
/// (`AssetType.fiyatAzamiOndalik`): kaynak veri onu hiç aşmaz; aşan yalnız
/// HESAPLANMIŞ fiyattır (USD × kur, ortalama maliyet) ve oradaki ek
/// haneler kayan nokta/çarpım artığıdır, kaynağın söylediği bir şey değil.
NumberFormat fiyatBicimi(double ornek, {int? azami, String symbol = '₺'}) {
  if (azami == null) {
    return tryFormatter(digits: fiyatOndaligi(ornek), symbol: symbol);
  }
  return tryFormatter(digits: 2, symbol: symbol)
    ..minimumFractionDigits = 2
    ..maximumFractionDigits = math.max(2, azami);
}

/// [fiyat] ekranda [fiyatBicimi] ile yazılınca kaç ondalık görünür.
///
/// [azami] null → [fiyatOndaligi] (eski kural). Verilirse kaynak
/// hassasiyetinin sondaki sıfırları atılmış hâli: ₺312,40 → 2, fon
/// ₺1,234567 → 6. En az 2.
int gosterilenFiyatOndaligi(double fiyat, {int? azami}) {
  if (azami == null) return fiyatOndaligi(fiyat);
  final metin = fiyatBicimi(fiyat, azami: azami).format(fiyat);
  final virgul = metin.lastIndexOf(',');
  if (virgul < 0) return 2;
  final hane = RegExp(r'\d').allMatches(metin.substring(virgul + 1)).length;
  return math.max(2, hane);
}

/// Büyük fiyatla AYNI ondalık sayısında sabit biçimleyici — seriden gelen
/// fiyatlar (aralık uçları, önceki kapanış, lot başı değişim, imleç) için.
///
/// Neden (Ar-Ge 2026-11-07 14:00 #2, yasin "yap"): [fiyatBicimi] kaynak
/// hassasiyetinde sondaki sıfırları atar; kaynaktan gelen ₺312,40 iki hane
/// yazar ama hesaplanmış/düzeltilmiş seri noktası ₺263,9333 dört hane
/// yazıyordu — aynı ekranda iki sayı biçimi. Hane sayısı [referans]
/// fiyatın ekrandaki yazılışından gelir: hisse 2 kalır, ₺0,179147'lik fon
/// ya da SHIB gibi düşük fiyatlı varlık kendi hassasiyetini korur
/// ([fiyatOndaligi] / [azami]). Referansın kendisini biçimlerken çıktı
/// [fiyatBicimi] ile birebir aynıdır.
NumberFormat ayniOndalikFiyatBicimi(double referans,
        {int? azami, String symbol = '₺'}) =>
    tryFormatter(
        digits: gosterilenFiyatOndaligi(referans, azami: azami),
        symbol: symbol);

/// [fiyatBicimi] ile tek fiyat metni.
String fmtFiyat(double value, {int? azami, String symbol = '₺'}) =>
    fiyatBicimi(value, azami: azami, symbol: symbol).format(value);

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
    final bas =
        parts.first.startsWith('-') ? parts.first.substring(1) : parts.first;
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
    NumberFormat.currency(
        locale: 'tr_TR', symbol: symbol, decimalDigits: digits);

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

/// Takvim yılının ilk günü (yerel 1 Ocak 00:00) — YB dönemi başı.
///
/// [dayKey] ile aynı gerekçe: "yılın başı" tek isimle, tek yerde; dönem
/// penceresi ve grafik ekseni aynı günü okusun.
DateTime yilBasiGunu(DateTime t) => DateTime(t.year);

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


/// Bir raporun KAPSADIĞI tarih aralığı: "1-31 Ekim 2026",
/// "27 Ekim - 2 Kasım 2026", "29 Aralık 2025 - 4 Ocak 2026"; tek gün
/// "6 Kasım 2026".
///
/// ## Neden tek biçimleyici (yasin, 2026-11-07)
/// *"varolan tüm raporlarda kapsadığı ve bilgileri verilen dataların zaman
/// aralığı belirtilmeli … kafa karışıklığı olmamalı"*. Aylık rapor "Ekim
/// 2026 raporu", haftanın özeti "son hafta", yıl özeti "bu yıl" diyordu;
/// hangi günlerin sayıldığını hiçbiri yazmıyordu. Her yüzey kendi
/// `DateFormat` kalıbını kursaydı biri "27.10 - 02.11", biri "27 Eki →
/// 2 Kas" yazardı. Kural tek yerde: aynı ay ve yıl tekrar edilmez (gün
/// aralığı tireyle bitişik), farklı ayda yalnız yıl birleşir, farklı yılda
/// iki uç tam yazılır.
///
/// Ay adları sabit tablodan (`intl` yerel verisi değil): PDF kurucuları ve
/// servisler saf, testleri `initializeDateFormatting` çağırmadan koşuyor;
/// yerel veri yüklenmemişken `DateFormat` istisna fırlatırdı.
///
/// [dil] `context.tarihDili` ('tr_TR' / 'en_US'); PDF'ler Türkçe.
/// [kisa] ay adını kısaltır ("27 Eki - 2 Kas 2026"): dar satır ve bildirim.
/// Uçlar takvim günüdür; saat atılır. Ters verilirse sıralanır.
String fmtTarihAraligi(DateTime bas, DateTime bit,
    {String dil = 'tr_TR', bool kisa = false}) {
  var a = dayKey(bas);
  var b = dayKey(bit);
  if (b.isBefore(a)) (a, b) = (b, a);
  String ay(DateTime t) => _ayAdi(t.month, dil, kisa);
  if (a == b) return '${a.day} ${ay(a)} ${a.year}';
  if (a.year == b.year && a.month == b.month) {
    return '${a.day}-${b.day} ${ay(b)} ${b.year}';
  }
  if (a.year == b.year) {
    return '${a.day} ${ay(a)} - ${b.day} ${ay(b)} ${b.year}';
  }
  return '${a.day} ${ay(a)} ${a.year} - ${b.day} ${ay(b)} ${b.year}';
}

/// Tek takvim günü, rapor dilinde: "6 Kasım 2026". [saat] verilirse
/// "6 Kasım 2026 18:00" — "fiyatlar … itibarıyla" gibi veri anı satırları
/// için; saat bilinmiyorsa ([saatBiliniyor]) yazılmaz, uydurma "00:00" yok.
///
/// [kisa] ay adını kısaltır ("6 Kas 2026"): dar çip ve satır (tarih hızlı
/// seçim çipleri, 2026-11-11 — eski `DateFormat('d MMM yyyy','tr_TR')`
/// kalıbının dil bilen karşılığı).
String fmtTarih(DateTime t,
    {String dil = 'tr_TR', bool saat = false, bool kisa = false}) {
  final y = t.toLocal();
  final gun = '${y.day} ${_ayAdi(y.month, dil, kisa)} ${y.year}';
  if (!saat || !saatBiliniyor(y)) return gun;
  String iki(int v) => v.toString().padLeft(2, '0');
  return '$gun ${iki(y.hour)}:${iki(y.minute)}';
}

/// Gün + tam ay, rapor dilinde: "4 Kasım" / "November 4". Yıl [bugun]ün
/// yılından farklıysa eklenir ("28 Aralık 2025"): 3A penceresi yıl
/// başını aşabiliyor ve yılsız "28 Aralık" hangi yılın günü belli etmez.
/// Performans'ın "en iyi / en zor gün" satırı (2026-11-11).
String fmtGunAy(DateTime t, {String dil = 'tr_TR', DateTime? bugun}) {
  final y = t.toLocal();
  final yilli = y.year != (bugun ?? DateTime.now()).year;
  final ay = _ayAdi(y.month, dil, false);
  if (dil.startsWith('en')) {
    return yilli ? '$ay ${y.day}, ${y.year}' : '$ay ${y.day}';
  }
  return yilli ? '${y.day} $ay ${y.year}' : '${y.day} $ay';
}

/// "… beri" cümlesinin tarih parçası: Türkçe "12 Eyl'den" (ayrılma hâli
/// ekiyle), İngilizce "Sep 12". Yıl [bugun]ün yılından farklıysa eklenir:
/// "12 Eyl 2025'ten" / "Sep 12, 2025".
///
/// ## Neden ek kodda (takip "Eklediğimden beri", 2026-11-08)
/// Türkçe ayrılma eki kısaltmaya değil OKUNUŞA uyar: "Eyl" "Eylül" diye
/// okunur, ek "-den" olur; "Ağu" "Ağustos" → "-tan". Ek ay adının (yıl
/// varsa yılın okunuşunun) son hecesinden belirlenir; ".arb"a "{tarih}'den
/// beri" yazmak Mart'ta "Mart'den" üretirdi. "12 Eyl itibarıyla" gibi ekten
/// kaçan nötr kalıp da düşünüldü; kural kapalı bir küme (12 ay + rakam
/// okunuşları) olduğu için doğru eki yazmak daha kısa ve doğal.
///
/// [kisa] `false` → tam ay adı ("12 Eylül'den"): ekran okuyucu cümlesi
/// kısaltmayı harf harf okumasın.
String tarihtenBeriParcasi(DateTime t,
    {String dil = 'tr_TR', bool kisa = true, DateTime? bugun}) {
  final y = t.toLocal();
  final yilli = y.year != (bugun ?? DateTime.now()).year;
  final ay = _ayAdi(y.month, dil, kisa);
  if (dil.startsWith('en')) {
    return yilli ? '$ay ${y.day}, ${y.year}' : '$ay ${y.day}';
  }
  if (yilli) return "${y.day} $ay ${y.year}'${_sayiAyrilmaEki(y.year)}";
  return "${y.day} $ay'${_ayAyrilmaEki[y.month - 1]}";
}

/// Tam ay adının ayrılma eki (Ocak'tan, Nisan'dan, Eylül'den…).
const _ayAyrilmaEki = [
  'tan', 'tan', 'tan', 'dan', 'tan', 'dan', //
  'dan', 'tan', 'den', 'den', 'dan', 'tan',
];

/// Bir sayının okunuşuna göre ayrılma eki: son sıfır olmayan basamağın
/// okunuşu belirler (2025 "yirmi beş" → 'ten', 2026 "altı" → 'dan',
/// 2030 "otuz" → 'dan', 2000 "bin" → 'den').
String _sayiAyrilmaEki(int n) {
  const birler = ['', 'den', 'den', 'ten', 'ten', 'ten', 'dan', 'den', 'den', 'dan'];
  const onlar = ['', 'dan', 'den', 'dan', 'tan', 'den', 'tan', 'ten', 'den', 'dan'];
  final m = n.abs();
  if (m % 10 != 0) return birler[m % 10];
  if ((m ~/ 10) % 10 != 0) return onlar[(m ~/ 10) % 10];
  return 'den'; // yüz / bin
}

const _ayTr = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', //
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];
const _ayTrKisa = [
  'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', //
  'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
];
const _ayEn = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _ayEnKisa = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Haftanın günü, takvim dilinde: "Cuma" / "Friday". Ay adlarıyla aynı
/// gerekçe: sabit tablo, `intl` yerel verisi yüklenmeden de çalışır
/// (tarih hızlı seçim çipi "son iş günü"nü gün adıyla yazar, 2026-11-11).
String gunAdi(DateTime t, {String dil = 'tr_TR'}) {
  final en = dil.startsWith('en');
  return (en ? _gunEn : _gunTr)[t.weekday - 1];
}

const _gunTr = [
  'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar',
];
const _gunEn = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

String _ayAdi(int ay, String dil, bool kisa) {
  final en = dil.startsWith('en');
  final t = en ? (kisa ? _ayEnKisa : _ayEn) : (kisa ? _ayTrKisa : _ayTr);
  return t[ay - 1];
}

