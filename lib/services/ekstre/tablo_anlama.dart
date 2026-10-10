import 'dart:math' as math;

import '../bist_hisse_katalogu.dart';
import '../../utils/tr_katla.dart';
import '../csv_import_service.dart';
import 'ekstre_tablosu.dart';
import 'fon_adi.dart';
import 'tablo_okuyucular.dart' show sayiMetni;

/// Bir ekstre sütununun anlamı. Sıra, kanonik çıktının sütun sırasıdır.
enum EkstreRol { sembol, adet, fiyat, tutar, tarih, yon, tur, paraBirimi, isim }

extension EkstreRolAdi on EkstreRol {
  /// Kullanıcıya görünen ad (eşleme düzeltme ekranı).
  String get ad => switch (this) {
        EkstreRol.sembol => 'Sembol',
        EkstreRol.adet => 'Adet',
        EkstreRol.fiyat => 'Birim fiyat / maliyet',
        EkstreRol.tutar => 'Tutar',
        EkstreRol.tarih => 'Tarih',
        EkstreRol.yon => 'Alış / satış',
        EkstreRol.tur => 'Varlık türü',
        EkstreRol.paraBirimi => 'Para birimi',
        EkstreRol.isim => 'Ad',
      };

  /// `ekstre-esle` (AI sütun eşleme) yanıtındaki rol adı
  /// (`supabase/functions/_shared/ekstre_esleme.ts` `ROLLER`).
  String get aiAdi => this == EkstreRol.paraBirimi ? 'para_birimi' : name;

  /// `CsvImportService.parse`'ın TAM eşleştiği kanonik başlık.
  String get kanonikBaslik => switch (this) {
        EkstreRol.sembol => 'sembol',
        EkstreRol.adet => 'adet',
        EkstreRol.fiyat => 'fiyat',
        EkstreRol.tutar => 'tutar',
        EkstreRol.tarih => 'tarih',
        EkstreRol.yon => 'islem turu',
        EkstreRol.tur => 'tur',
        EkstreRol.paraBirimi => 'para birimi',
        EkstreRol.isim => 'isim',
      };
}

/// Bir tablonun anlaşılmış hâli: hangi satır başlık, hangi sütun ne,
/// ne kadar eminiz.
class EkstreAnlami {
  const EkstreAnlami({
    required this.tablo,
    required this.baslikSatiri,
    required this.basliklar,
    required this.roller,
    required this.veri,
    required this.guven,
    required this.atlanan,
    required this.notlar,
    required this.stiller,
    this.ayOnce = const [],
    this.adlaTanimli = false,
  });

  final EkstreTablosu tablo;

  /// Başlık satırının indeksi; başlıksız tabloda -1.
  final int baslikSatiri;

  /// Sütun başına gösterilecek ad (başlık hücresi ya da "Sütun N").
  final List<String> basliklar;
  final Map<EkstreRol, int> roller;

  /// Veri satırları (ham, sütun sayısına doldurulmuş).
  final List<List<String>> veri;

  /// 0–1. < [esik] ise ekran eşlemeyi kullanıcıya gösterip onay ister.
  final double guven;

  /// Alım/satım olmayan (temettü, virman…) ya da toplam satırı olduğu için
  /// atlananların sayısı.
  final int atlanan;
  final List<String> notlar;

  /// Sütun başına sayı biçimi (true = Türkçe: virgül ondalık).
  final List<bool> stiller;

  /// Sütun başına tarih düzeni (true = aa/gg/yyyy, ABD biçimi).
  final List<bool> ayOnce;

  /// Sembol sütunu KOD değil fon ADI (banka ekstresi). Satır yalnız adı
  /// TEFAS koduna çözüldüyse kanonik çıktıya girer (`kanonikSatirlar`'ın
  /// `adKodlari`'ı); çözülmeyen ad asla sembol diye geçmez.
  final bool adlaTanimli;

  static const esik = 0.75;
  bool get eminDegil =>
      guven < esik || !roller.containsKey(EkstreRol.sembol) || !roller.containsKey(EkstreRol.adet);

  /// Kullanıcı düzeltmesiyle yeni eşleme (güven 1: insan onayladı).
  EkstreAnlami yeniRollerle(Map<EkstreRol, int> yeni) => EkstreAnlami(
        tablo: tablo,
        baslikSatiri: baslikSatiri,
        basliklar: basliklar,
        roller: Map.unmodifiable(yeni),
        veri: veri,
        guven: 1,
        atlanan: atlanan,
        notlar: const [],
        stiller: stiller,
        ayOnce: ayOnce,
        // Kullanıcı sembolü başka sütuna taşıdıysa artık kod sütunudur.
        adlaTanimli:
            adlaTanimli && yeni[EkstreRol.sembol] == roller[EkstreRol.sembol],
      );

  /// `CsvImportService.parse`'a verilecek sekmeli metin. Satış/tür/fiyat
  /// mantığı TEK yerde (o serviste) kalır; bu katman yalnızca SÜTUNLARI ve
  /// BİÇİMİ normalleştirir: sayı "1234,56", tarih "gg.aa.yyyy", yön
  /// "Alış/Satış", eksi adet → satış.
  String kanonikMetin() {
    final sutunlar = kanonikSutunlar([this]);
    return [sutunlar.map((r) => r.kanonikBaslik).join('\t'), ...kanonikSatirlar(sutunlar)]
        .join('\n');
  }

  /// Birden çok tablonun (XLSX sayfaları) ortak çıktı sütunları: rollerin
  /// birleşimi + her zaman yön (eksi adet → satış buradan taşınır).
  /// [tarihEkle]: belge tarihi tarihsiz satırlara yazılacak. Adla tanımlı
  /// tablo varsa tür sütunu ("Fon") — üç harfli kod tür çıkarımına kalmasın.
  static List<EkstreRol> kanonikSutunlar(Iterable<EkstreAnlami> anlamlar,
          {bool tarihEkle = false}) =>
      [
        for (final r in EkstreRol.values)
          if (r == EkstreRol.yon ||
              (r == EkstreRol.tarih && tarihEkle) ||
              (r == EkstreRol.tur && anlamlar.any((a) => a.adlaTanimli)) ||
              anlamlar.any((a) => a.roller.containsKey(r)))
            r,
      ];

  /// Adla tanımlı tabloda koda çözülmesi gereken fon adları (adetli satır).
  Iterable<String> get fonAdlari sync* {
    if (!adlaTanimli) return;
    final s = roller[EkstreRol.sembol]!;
    for (final satir in veri) {
      if (s < satir.length && satir[s].trim().isNotEmpty) yield satir[s].trim();
    }
  }

  /// [sutunlar] düzeninde veri satırları (başlıksız).
  ///
  /// [adKodlari]: adla tanımlı tabloda `fonAdiAnahtari(ad)` → TEFAS kodu;
  /// karşılığı olmayan satır ATLANIR. [varsayilanTarih]: tarih sütunu
  /// olmayan tabloda her satırın tarihi (varlık dökümünün "itibariyle"
  /// günü — bugün değil).
  List<String> kanonikSatirlar(
    List<EkstreRol> ciktiRolleri, {
    Map<String, String> adKodlari = const {},
    DateTime? varsayilanTarih,
  }) {
    final yonVar = roller.containsKey(EkstreRol.yon);
    final out = <String>[];
    for (final satir in veri) {
      String h(EkstreRol r) {
        final i = roller[r];
        return i == null || i >= satir.length ? '' : satir[i];
      }

      var sembol = h(EkstreRol.sembol).trim();
      if (sembol.isEmpty) continue; // çok satırlı hücrenin devamı
      if (adlaTanimli) {
        final kod = adKodlari[fonAdiAnahtari(sembol)];
        if (kod == null) continue; // tanınmadı: tahminle eklenmez
        sembol = kod;
      }
      final adet = sayiCoz(h(EkstreRol.adet), turkce: _stil(EkstreRol.adet));
      bool? satis = yonVar ? yonCoz(h(EkstreRol.yon)) : null;
      if (yonVar && satis == null) continue; // alım/satım değil
      satis ??= adet != null && adet < 0;
      final hucreler = <String>[];
      for (final r in ciktiRolleri) {
        switch (r) {
          case EkstreRol.sembol:
            hucreler.add(sembolNormal(sembol));
          case EkstreRol.adet:
            hucreler.add(adet == null ? h(r) : sayiMetni(adet.abs()));
          case EkstreRol.fiyat || EkstreRol.tutar when h(r).trim().isEmpty:
            hucreler.add('');
          case EkstreRol.fiyat:
          case EkstreRol.tutar:
            final v = sayiCoz(h(r), turkce: _stil(r));
            hucreler.add(v == null ? h(r) : sayiMetni(v.abs()));
          case EkstreRol.tarih:
            final i = roller[r];
            final t = i == null
                ? varsayilanTarih
                : tarihCoz(h(r), ayOnce: i < ayOnce.length && ayOnce[i]);
            hucreler.add(t == null
                ? h(r)
                : '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}');
          case EkstreRol.yon:
            hucreler.add(satis ? 'Satış' : 'Alış');
          case EkstreRol.paraBirimi:
            final p = trKatla(h(r).trim());
            hucreler.add(p == 'tl' || p == 'ytl' ? 'TRY' : h(r).trim().toUpperCase());
          case EkstreRol.tur when adlaTanimli:
            hucreler.add('Fon');
          case EkstreRol.tur:
          case EkstreRol.isim:
            hucreler.add(h(r));
        }
      }
      out.add(hucreler.map((x) => x.replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim()).join('\t'));
    }
    return out;
  }

  bool _stil(EkstreRol r) {
    final i = roller[r];
    return i == null || i >= stiller.length ? true : stiller[i];
  }
}

// ── Başlık sözlüğü ───────────────────────────────────────────────────────────
//
// Katlanmış (trKatla) ve noktalama temizlenmiş biçimde. Tam eşleşme 1.0,
// kelime olarak geçiş 0.6. Olumsuz kelime rolü düşürür: "Son Fiyat" /
// "Güncel Değer" maliyet DEĞİLDİR (portföy dökümlerinde ikisi yan yana
// durur; yanlışı seçmek bütün maliyeti bozar).

const _sozluk = <EkstreRol, List<String>>{
  EkstreRol.sembol: [
    'sembol', 'kod', 'menkul', 'menkul kiymet', 'kiymet', 'kiymet kodu',
    'menkul kodu', 'enstruman', 'hisse', 'hisse kodu', 'fon kodu', 'fon',
    'varlik', 'varlik kodu', 'urun', 'urun kodu', 'symbol', 'ticker',
    'instrument', 'security', 'code', 'isin', 'sermaye piyasasi araci',
  ],
  EkstreRol.isim: [
    'ad', 'adi', 'isim', 'unvan', 'sirket', 'sirket adi', 'menkul kiymet adi',
    'fon adi', 'hisse adi', 'urun adi', 'name', 'description', 'security name',
    // Banka fon tablosu: "Yatırım Fonu İsmi" (2026-10-03).
    'fon ismi', 'yatirim fonu ismi', 'fon unvani',
  ],
  EkstreRol.adet: [
    'adet', 'miktar', 'lot', 'nominal', 'pay', 'pay adedi', 'bakiye',
    'kalan', 'eldeki', 'quantity', 'qty', 'units', 'shares', 'adet nominal',
    'miktar nominal', 'islem adedi', 'gerceklesen adet', 'gerceklesen miktar',
    'islem miktari',
  ],
  EkstreRol.fiyat: [
    'fiyat', 'maliyet', 'ortalama maliyet', 'ort maliyet', 'ort mlyt',
    'maliyet fiyati', 'birim fiyat', 'birim maliyet', 'islem fiyati',
    'gerceklesen fiyat', 'gerceklesme fiyati', 'alis fiyati',
    'ortalama fiyat', 'ort fiyat', 'price', 'avg price', 'average price',
    'average cost', 'cost', 'unit price',
  ],
  EkstreRol.tutar: [
    'tutar', 'islem tutari', 'toplam tutar', 'toplam', 'net tutar',
    'brut tutar', 'maliyet tutari', 'toplam maliyet', 'amount', 'total',
    'net amount', 'gross amount', 'islem hacmi',
  ],
  EkstreRol.tarih: [
    'tarih', 'islem tarihi', 'valor', 'valor tarihi', 'emir tarihi',
    'gerceklesme tarihi', 'date', 'trade date', 'settlement date',
    'islem zamani', 'zaman', 'tarih saat', 'alim tarihi',
  ],
  EkstreRol.yon: [
    'islem turu', 'islem tipi', 'islem yonu', 'al sat', 'alis satis',
    'alim satim', 'a s', 'yon', 'side', 'b s', 'buy sell', 'action',
    'emir yonu', 'emir turu', 'hareket turu', 'islem', 'hareket', 'tip', 'type',
  ],
  EkstreRol.tur: [
    'tur', 'varlik turu', 'varlik sinifi', 'kategori', 'tip', 'type',
    'asset class', 'urun turu', 'menkul turu', 'enstruman turu',
  ],
  EkstreRol.paraBirimi: [
    'para birimi', 'doviz cinsi', 'para', 'doviz', 'currency', 'ccy', 'pb',
    'doviz kodu',
  ],
};

const _olumsuz = <EkstreRol, List<String>>{
  EkstreRol.fiyat: ['son', 'guncel', 'kapanis', 'piyasa', 'anlik', 'cari', 'tutar', 'toplam', 'deger', 'kar', 'zarar'],
  EkstreRol.tutar: ['piyasa', 'guncel', 'son', 'kar', 'zarar', 'komisyon', 'vergi', 'bsmv', 'stopaj', 'deger', 'oran', 'getiri'],
  EkstreRol.adet: ['tutar', 'fiyat', 'deger', 'oran'],
  EkstreRol.sembol: ['adi', 'turu', 'tipi', 'tur', 'ismi', 'unvani'],
  EkstreRol.tarih: ['vade'],
};

String _norm(String s) => trKatla(s)
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Başlık karşılaştırması için kök: iyelik eki düşer ("fiyati" → "fiyat",
/// "adedi" → "adet", "kodu" → "kod"). Kurumlar aynı sütunu "Birim Pay
/// Fiyatı", "İşlem Adedi", "Kıymet Kodu" diye yazar; sözlüğe her çekimi
/// eklemek yerine iki taraf da köke iner (sözlük girdileri de aynı
/// işlemden geçer, bkz. [_sozlukKok]).
const _kokler = {
  'fiyati': 'fiyat', 'tutari': 'tutar', 'adedi': 'adet', 'miktari': 'miktar',
  'tarihi': 'tarih', 'kodu': 'kod', 'adi': 'ad', 'turu': 'tur', 'tipi': 'tip',
  'degeri': 'deger', 'maliyeti': 'maliyet', 'birimi': 'birim', 'cinsi': 'cins',
  'yonu': 'yon', 'zamani': 'zaman', 'sayisi': 'sayi', 'nominali': 'nominal',
  'hacmi': 'hacim', 'unvani': 'unvan', 'ismi': 'isim',
};

String _kok(String normalHucre) =>
    normalHucre.split(' ').map((k) => _kokler[k] ?? k).join(' ');

final _sozlukKok = <EkstreRol, List<String>>{
  for (final e in _sozluk.entries) e.key: [for (final a in e.value) _kok(_norm(a))],
};
final _olumsuzKok = <EkstreRol, Set<String>>{
  for (final e in _olumsuz.entries) e.key: {for (final a in e.value) _kok(a)},
};

/// Başlık sözlüğünün tüm kelimeleri (katlanmış; kök ve çekimli hâl).
/// Tanılama iskeleti (`ekstre_iskeleti.dart`) bu kelimeleri maskelemez:
/// sütun adları kişisel veri değildir ve teşhisin asıl ipucudur.
final Set<String> ekstreSozlukKelimeleri = {
  for (final liste in [..._sozluk.values, ..._olumsuz.values])
    for (final ifade in liste) ..._norm(ifade).split(' '),
  ..._kokler.keys,
  ..._kokler.values,
}..remove('');

/// Katlanmış, noktalamasız biçim — iskeletin sözlük karşılaştırması için.
String ekstreNormal(String s) => _norm(s);

double baslikPuani(EkstreRol r, String hucre) {
  final h = _kok(_norm(hucre));
  if (h.isEmpty || h.length > 40) return 0;
  final kelimeler = h.split(' ').toSet();
  for (final o in _olumsuzKok[r] ?? const <String>{}) {
    if (kelimeler.contains(o)) return -0.6;
  }
  var puan = 0.0;
  for (final a in _sozlukKok[r]!) {
    if (h == a) return 1.0;
    if (h.startsWith('$a ') || h.endsWith(' $a') || h.contains(' $a ')) {
      puan = math.max(puan, 0.6);
    }
  }
  return puan;
}

// ── Hücre çözücüler ──────────────────────────────────────────────────────────

/// Sayı — para simgesi, %, parantezli eksi, sondaki eksi dahil. [turkce]
/// tek ayraçlı belirsiz durumlarda (1.234 / 1,234) karar verir; sütunun
/// biçimi `_sutunStili` ile önceden bulunur.
double? sayiCoz(String ham, {bool turkce = true}) {
  var s = ham.trim();
  if (s.isEmpty) return null;
  var eksi = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    eksi = true;
    s = s.substring(1, s.length - 1);
  }
  // Unicode eksi/tire (PDF'ler U+2212 ve U+2013 basar) → ASCII eksi.
  s = s.replaceAll(RegExp('[\u2212\u2013\u2014]'), '-');
  s = s.replaceAll(RegExp(r'[\s ₺$€£%]|TRY|TL|USD|EUR|GBP', caseSensitive: false), '');
  if (s.endsWith('-')) {
    eksi = true;
    s = s.substring(0, s.length - 1);
  }
  if (s.startsWith('+')) s = s.substring(1);
  if (s.startsWith('-')) {
    eksi = !eksi;
    s = s.substring(1);
  }
  if (!RegExp(r'^[0-9.,]+$').hasMatch(s) || !RegExp(r'[0-9]').hasMatch(s)) return null;
  final nokta = s.lastIndexOf('.');
  final virgul = s.lastIndexOf(',');
  if (nokta >= 0 && virgul >= 0) {
    s = virgul > nokta ? s.replaceAll('.', '').replaceAll(',', '.') : s.replaceAll(',', '');
  } else if (virgul >= 0) {
    final parca = s.split(',');
    if (parca.length > 2 || (!turkce && parca.last.length == 3)) {
      s = s.replaceAll(',', '');
    } else {
      // Tek virgül = ondalık (parseTrNumber'ın deseni).
      s = s.replaceFirst(',', '.');
    }
  } else if (nokta >= 0) {
    final parca = s.split('.');
    if (parca.length > 2 || (turkce && parca.last.length == 3 && parca.first != '0')) {
      s = s.replaceAll('.', '');
    }
  }
  final v = double.tryParse(s);
  if (v == null) return null;
  return eksi ? -v : v;
}

const _aylar = {
  'ocak': 1, 'oca': 1, 'jan': 1, 'january': 1, 'subat': 2, 'sub': 2, 'feb': 2,
  'february': 2, 'mart': 3, 'mar': 3, 'march': 3, 'nisan': 4, 'nis': 4,
  'apr': 4, 'april': 4, 'mayis': 5, 'may': 5, 'haziran': 6, 'haz': 6,
  'jun': 6, 'june': 6, 'temmuz': 7, 'tem': 7, 'jul': 7, 'july': 7,
  'agustos': 8, 'agu': 8, 'aug': 8, 'august': 8, 'eylul': 9, 'eyl': 9,
  'sep': 9, 'sept': 9, 'september': 9, 'ekim': 10, 'eki': 10, 'oct': 10,
  'october': 10, 'kasim': 11, 'kas': 11, 'nov': 11, 'november': 11,
  'aralik': 12, 'ara': 12, 'dec': 12, 'december': 12,
};

/// Tarih — gg.aa.yyyy[ ss:dd[:ss]], gg/aa/yyyy, gg-aa-yyyy, yyyy-aa-gg[T…],
/// gg.aa.yy, "12 Eylül 2026", "Sep 12, 2026". [ayOnce] aa/gg/yyyy için.
DateTime? tarihCoz(String ham, {bool ayOnce = false}) {
  final t = ham.trim();
  if (t.isEmpty) return null;
  var m = RegExp(r'^(\d{4})[-./](\d{1,2})[-./](\d{1,2})').firstMatch(t);
  if (m != null) return _gun(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  // Bitişik yyyyaagg (MKK/takas çıktıları): yalnız 8 hane ve geçerli ay/gün.
  m = RegExp(r'^(19|20)(\d{2})(\d{2})(\d{2})$').firstMatch(t);
  if (m != null) {
    return _gun(int.parse('${m[1]}${m[2]}'), int.parse(m[3]!), int.parse(m[4]!));
  }
  m = RegExp(r'^(\d{1,2})[./\-](\d{1,2})[./\-](\d{2,4})(?:\s|$|T)').firstMatch(t);
  if (m != null) {
    var y = int.parse(m[3]!);
    if (m[3]!.length == 2) y += 2000;
    final a = int.parse(m[1]!), b = int.parse(m[2]!);
    return ayOnce ? _gun(y, a, b) : _gun(y, b, a);
  }
  final k = trKatla(t).replaceAll(',', ' ');
  m = RegExp(r'^(\d{1,2})\s+([a-z]+)\.?\s+(\d{4})').firstMatch(k);
  if (m != null && _aylar.containsKey(m[2])) {
    return _gun(int.parse(m[3]!), _aylar[m[2]]!, int.parse(m[1]!));
  }
  m = RegExp(r'^([a-z]+)\.?\s+(\d{1,2})\s+(\d{4})').firstMatch(k);
  if (m != null && _aylar.containsKey(m[1])) {
    return _gun(int.parse(m[3]!), _aylar[m[1]]!, int.parse(m[2]!));
  }
  return null;
}

DateTime? _gun(int y, int a, int g) {
  if (y < 1990 || y > 2100 || a < 1 || a > 12 || g < 1 || g > 31) return null;
  final d = DateTime(y, a, g);
  return d.month == a ? d : null;
}

/// Alış/satış; açıklama metninin İÇİNDE de arar ("THYAO Hisse Alış").
/// `null`: alım/satım değil (temettü, virman, bedelsiz…) ya da okunamadı.
bool? yonCoz(String ham) {
  final kesin = CsvImportService.yonCoz(ham);
  if (kesin != null) return kesin;
  final k = ' ${_norm(ham)} ';
  const satis = [' satis', ' satim', ' sell', ' sat ', ' sold'];
  const alis = [' alis', ' alim', ' buy', ' al ', ' bought'];
  final s = satis.any(k.contains), a = alis.any(k.contains);
  if (s == a) return null;
  return s;
}

const _dovizler = {'USD', 'EUR', 'GBP', 'CHF', 'JPY', 'CAD', 'AUD', 'SAR', 'RUB', 'CNY', 'NOK', 'SEK', 'DKK'};

/// ISIN'den BIST kodu: TRATHYAO91M5 → THYAO (bilinen sembollerde varsa).
String? isindenKod(String s) {
  final u = s.trim().toUpperCase();
  if (!RegExp(r'^TR[A-Z0-9]{10}$').hasMatch(u)) return null;
  for (final n in const [5, 4, 6]) {
    if (3 + n > u.length) continue;
    final aday = u.substring(3, 3 + n);
    if (BistHisseKatalogu.instance.kodMu(aday)) return aday;
  }
  return null;
}

/// Kanonik çıktıda sembol: ISIN bilinen koda çevrilir, gerisi olduğu gibi
/// (`CsvImportService.sembolAyikla` "KOD - Ad" / "KOD.E"yi zaten çözer).
String sembolNormal(String ham) => isindenKod(ham) ?? ham.trim();

/// 0–1: hücre bir sembol gibi mi?
double sembolPuani(String ham) {
  // Fon UNVANI kod değildir: "GARANTİ PORTFÖY ALTIN KATILIM FONU" altın
  // deyimiyle 0,9, "YAPI KREDİ PORTFÖY…" ilk kelimesiyle ("YAPI") 0,7
  // alıyordu. Üç fonluk bir banka tablosunda ad sütununun sembol oranı
  // 0,5'i aşıp `isim` rolünü kaybetti ve tablo hiç anlaşılmadı; dört fonda
  // (gerçek ekstre) eşiğin altında kaldığı için görünmedi (2026-10-05).
  // Türk fon unvanlarının hepsinde "PORTFÖY" geçer.
  if (RegExp(r'\bportfoy\b').hasMatch(trKatla(ham))) return 0;
  final s = CsvImportService.sembolAyikla(ham).trim();
  if (s.isEmpty) return 0;
  final u = s.toUpperCase();
  if (BistHisseKatalogu.instance.kodMu(u)) return 1;
  if (isindenKod(u) != null) return 1;
  if (CsvImportService.kriptoKodunuCoz(u) != null && u.length <= 12) return 0.8;
  final k = trKatla(s);
  if (RegExp(r'\b(altin|gram|ceyrek|cumhuriyet|resat|ons|xau|gumus)\b').hasMatch(k)) return 0.9;
  if (_dovizler.contains(u)) return 0.9;
  if (RegExp(r'^TR[A-Z0-9]{10}$').hasMatch(u)) return 0.7; // ISIN, kodu bilinmeyen
  if (RegExp(r'^[A-Z]{3}$').hasMatch(s)) return 0.8; // TEFAS fon kodu
  if (RegExp(r'^[A-Z][A-Z0-9]{3,5}$').hasMatch(s)) return 0.7;
  return 0;
}

bool _paraBirimiMi(String s) {
  final u = s.trim().toUpperCase();
  return u == 'TRY' || u == 'TL' || u == 'YTL' || _dovizler.contains(u);
}

bool _turMu(String s) {
  const turler = {
    'hisse', 'hisse senedi', 'pay', 'fon', 'yatirim fonu', 'doviz', 'altin',
    'emtia', 'kripto', 'diger', 'stock', 'equity', 'fund', 'etf', 'varant',
  };
  return turler.contains(_norm(s));
}

bool _toplamSatiriMi(List<String> satir) {
  for (final h in satir) {
    final k = _norm(h);
    if (k.startsWith('toplam') || k.startsWith('genel toplam') || k.startsWith('ara toplam') || k == 'total') {
      return true;
    }
  }
  return false;
}

// ── Sütun profili ────────────────────────────────────────────────────────────

class _Profil {
  int dolu = 0;
  double sayi = 0, tarih = 0, sembol = 0, yon = 0, para = 0, tur = 0, tam = 0, metin = 0;
  bool turkce = true;
  bool ayOnce = false;
  List<double?> degerler = const [];

  double oran(double x) => dolu == 0 ? 0 : x / dolu;
}

/// Sütunun sayı biçimi kanıtı: (Türkçe, İngilizce) sayısı. "1,000" ya da
/// "250" tek başına kanıt değildir — öyle bir sütunun biçimi TABLONUN geri
/// kalanından gelir (bkz. `tabloyuAnla`): İngilizce ekstrede "1,000" adet
/// Türkçe varsayımla 1 okunuyordu (test: İngilizce CSV).
(int, int) _stilKaniti(Iterable<String> hucreler) {
  var tr = 0, en = 0;
  for (final ham in hucreler) {
    final s = ham.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (s.isEmpty) continue;
    final n = s.lastIndexOf('.'), v = s.lastIndexOf(',');
    if (n >= 0 && v >= 0) {
      v > n ? tr++ : en++;
    } else if (v >= 0 && s.length - v - 1 != 3) {
      tr++;
    } else if (n >= 0 && s.length - n - 1 != 3) {
      en++;
    } else if (v >= 0 && ','.allMatches(s).length > 1) {
      en++;
    } else if (n >= 0 && '.'.allMatches(s).length > 1) {
      tr++;
    }
  }
  return (tr, en);
}

/// Hücrelerin sayı biçimi Türkçe mi (virgül ondalık)? Kanıt yoksa `true`
/// (yerli kurum). Mevduat tablosu gibi rol çıkarımına girmeyen okuyucular
/// için.
bool sayiStiliTurkceMi(Iterable<String> hucreler) {
  final (tr, en) = _stilKaniti(hucreler);
  return tr >= en;
}

_Profil _profilCikar(List<String> hucreler, {required bool tabloTurkce}) {
  final p = _Profil();
  final dolular = hucreler.where((h) => h.trim().isNotEmpty).take(400).toList();
  p.dolu = dolular.length;
  final (tr, en) = _stilKaniti(dolular);
  p.turkce = tr == en ? tabloTurkce : tr > en;
  final degerler = <double?>[];
  for (final h in hucreler) {
    if (h.trim().isEmpty) {
      degerler.add(null);
      continue;
    }
    final v = sayiCoz(h, turkce: p.turkce);
    degerler.add(v);
  }
  p.degerler = degerler;
  for (final h in dolular) {
    final v = sayiCoz(h, turkce: p.turkce);
    var t = tarihCoz(h);
    if (t == null && tarihCoz(h, ayOnce: true) != null) {
      // 09/13/2026: gün önce okunamayan tek bir hücre sütunu ABD düzenine
      // çevirir (ay 13 olamaz).
      p.ayOnce = true;
      t = tarihCoz(h, ayOnce: true);
    }
    if (t != null) {
      p.tarih++;
    } else if (v != null) {
      p.sayi++;
      if (v == v.roundToDouble()) p.tam++;
    } else {
      p.metin++;
    }
    p.sembol += sembolPuani(h);
    if (yonCoz(h) != null) p.yon++;
    if (_paraBirimiMi(h)) p.para++;
    if (_turMu(h)) p.tur++;
  }
  return p;
}

// ── Anlama ───────────────────────────────────────────────────────────────────

/// Birden çok tablodan (XLSX sayfaları, HTML tabloları) en iyisini anlar.
/// Hiçbirinde sembol + adet bulunamazsa `null`.
List<EkstreAnlami> tablolariAnla(List<EkstreTablosu> tablolar) {
  final out = <EkstreAnlami>[];
  for (final t in tablolar) {
    final a = tabloyuAnla(t);
    if (a != null && a.roller.containsKey(EkstreRol.sembol) && a.veri.isNotEmpty) {
      out.add(a);
    }
  }
  out.sort((a, b) => (b.veri.length * b.guven).compareTo(a.veri.length * a.guven));
  return out;
}

EkstreAnlami? tabloyuAnla(EkstreTablosu tablo) {
  final ham = [
    for (final s in tablo.satirlar) [for (final h in s) h.trim()],
  ].where((s) => s.any((h) => h.isNotEmpty)).toList();
  if (ham.isEmpty) return null;
  final genislik = ham.map((s) => s.length).reduce(math.max);
  final satirlar = [
    for (final s in ham) [...s, for (var i = s.length; i < genislik; i++) ''],
  ];

  // 1) Başlık satırı: ilk 40 satır içinde en çok FARKLI rolü karşılayan.
  var baslik = -1;
  var baslikPuan = 1;
  for (var i = 0; i < satirlar.length && i < 40; i++) {
    final roller = <EkstreRol>{};
    for (final h in satirlar[i]) {
      for (final r in EkstreRol.values) {
        if (baslikPuani(r, h) >= 0.6) roller.add(r);
      }
    }
    final anlamli = roller.contains(EkstreRol.sembol) ||
        roller.contains(EkstreRol.adet) ||
        roller.contains(EkstreRol.fiyat) ||
        roller.contains(EkstreRol.tutar);
    if (anlamli && roller.length > baslikPuan) {
      baslikPuan = roller.length;
      baslik = i;
    }
  }
  final baslikHucreleri = baslik >= 0 ? satirlar[baslik] : List.filled(genislik, '');

  // 2) Veri satırları: başlıktan sonra; tekrar eden başlık (PDF'in her
  // sayfası), toplam ve tek hücreli (başlık/dipnot) satırlar çıkar.
  final baslikAnahtari = baslikHucreleri.map(_norm).join('|');
  var atlanan = 0;
  final veri = <List<String>>[];
  for (var i = baslik + 1; i < satirlar.length; i++) {
    final s = satirlar[i];
    if (s.where((h) => h.isNotEmpty).length < 2) continue;
    if (baslik >= 0 && s.map(_norm).join('|') == baslikAnahtari) continue;
    if (_toplamSatiriMi(s)) {
      atlanan++;
      continue;
    }
    veri.add(s);
  }
  if (veri.isEmpty) return null;

  // 3) Sütun profilleri. Sayı biçimi önce sütunun kendi kanıtından, yoksa
  // tablonun toplam kanıtından (kanıt hiç yoksa Türkçe — yerli kurum).
  var tabloTr = 0, tabloEn = 0;
  for (var c = 0; c < genislik; c++) {
    final (tr, en) = _stilKaniti([for (final s in veri) s[c]]);
    tabloTr += tr;
    tabloEn += en;
  }
  final profiller = [
    for (var c = 0; c < genislik; c++)
      _profilCikar([for (final s in veri) s[c]], tabloTurkce: tabloTr >= tabloEn),
  ];

  // 4) Rol puanları: başlık kanıtı + içerik kanıtı; içerik ŞARTI sağlanmazsa
  // başlık tek başına rolü veremez (yanlış başlık > boş sütun değil).
  final adaylar = <(EkstreRol, int, double, bool)>[]; // rol, sütun, puan, başlıktan mı
  for (var c = 0; c < genislik; c++) {
    final p = profiller[c];
    if (p.dolu == 0) continue;
    for (final r in EkstreRol.values) {
      final b = baslikPuani(r, baslikHucreleri[c]);
      if (b < 0) continue;
      final double icerik;
      final bool sart;
      switch (r) {
        case EkstreRol.sembol:
          icerik = p.oran(p.sembol);
          sart = icerik >= (b >= 0.6 ? 0.3 : 0.55) && p.oran(p.sayi) < 0.5;
        case EkstreRol.adet:
        case EkstreRol.fiyat:
        case EkstreRol.tutar:
          icerik = p.oran(p.sayi);
          sart = icerik >= 0.7;
        case EkstreRol.tarih:
          icerik = p.oran(p.tarih);
          sart = icerik >= 0.7;
        case EkstreRol.yon:
          icerik = p.oran(p.yon);
          sart = icerik >= (b >= 0.6 ? 0.3 : 0.6);
        case EkstreRol.tur:
          icerik = p.oran(p.tur);
          sart = icerik >= 0.6;
        case EkstreRol.paraBirimi:
          icerik = p.oran(p.para);
          sart = icerik >= 0.7;
        case EkstreRol.isim:
          icerik = p.oran(p.metin);
          sart = b >= 0.6 && icerik >= 0.6 && p.oran(p.sembol) < 0.5;
      }
      if (!sart) continue;
      // Sayısal roller başlıksız ayırt edilemez; onları 5. adım çözer.
      final sayisal = r == EkstreRol.adet || r == EkstreRol.fiyat || r == EkstreRol.tutar;
      if (sayisal && b < 0.6) continue;
      adaylar.add((r, c, b * 1.5 + icerik * 2, b >= 0.6));
    }
  }
  // Eşitlikte SOLDAKİ sütun: `List.sort` kararlı değil. Banka fon tablosunda
  // "Pay Adedi" ve "Bakiye" ikisi de adet sözlüğünde tam eşleşir (aynı
  // puan); hangisinin seçileceği rastlantıya kalıyordu. Ekstrelerde miktar
  // tutardan önce gelir.
  adaylar.sort((a, b) {
    final d = b.$3.compareTo(a.$3);
    return d != 0 ? d : a.$2.compareTo(b.$2);
  });
  final roller = <EkstreRol, int>{};
  final kullanilan = <int>{};
  final baslikla = <EkstreRol>{};
  for (final (r, c, _, bb) in adaylar) {
    if (roller.containsKey(r) || kullanilan.contains(c)) continue;
    roller[r] = c;
    kullanilan.add(c);
    if (bb) baslikla.add(r);
  }

  // Kodu olmayan fon tablosu (banka ekstresi: "Yatırım Fonu İsmi"): ad
  // sütunu sembolün yerini tutar, satır ADLA TANIMLIDIR. Kod, TEFAS
  // unvanlarıyla eşleşerek sonradan bulunur (`fon_adi.dart`); bulunamayan
  // satır içe aktarılmaz — kanonik çıktıya ad olduğu gibi GİRMEZ.
  var adlaTanimli = false;
  if (!roller.containsKey(EkstreRol.sembol) &&
      roller.containsKey(EkstreRol.isim)) {
    roller[EkstreRol.sembol] = roller[EkstreRol.isim]!;
    adlaTanimli = true;
  }

  // 5) Sayısal roller: adet × fiyat ≈ tutar ilişkisi. Başlık bu rolleri
  // vermediyse (başlıksız tablo ya da hiç görülmemiş başlık) sayısal
  // sütunların hangisinin hangisi olduğu ÇARPIMDAN çıkar.
  final notlar = <String>[];
  final sayisalSutunlar = [
    for (var c = 0; c < genislik; c++)
      if (!kullanilan.contains(c) && profiller[c].dolu > 0 && profiller[c].oran(profiller[c].sayi) >= 0.8) c,
  ];
  final eksikSayisal = [
    for (final r in const [EkstreRol.adet, EkstreRol.fiyat, EkstreRol.tutar])
      if (!roller.containsKey(r)) r,
  ];
  var iliskiyle = false;
  if (eksikSayisal.isNotEmpty) {
    final havuz = [
      ...sayisalSutunlar,
      for (final r in const [EkstreRol.adet, EkstreRol.fiyat, EkstreRol.tutar])
        if (roller[r] != null) roller[r]!,
    ];
    // Başlıktan bilinen adet/fiyat çarpanın İÇİNDE olmalı. Aksi hâlde
    // portföy dökümünde adet × SON FİYAT ≈ PİYASA DEĞERİ ilişkisi yakalanıp
    // "Piyasa Değeri" tutar sayılıyor, ardından 6. adım adet × maliyet ≠
    // tutar diye güveni düşürüp "fiyat güncel olabilir" uyarısı veriyordu —
    // maliyet doğruyken sahte uyarı (2026-10-02).
    final sabitAdet = roller[EkstreRol.adet], sabitFiyat = roller[EkstreRol.fiyat];
    (int, int, int)? enIyi;
    var enIyiOran = 0.6;
    for (final a in havuz) {
      for (final b in havuz) {
        if (b <= a) continue;
        if (sabitAdet != null && a != sabitAdet && b != sabitAdet) continue;
        if (sabitFiyat != null && a != sabitFiyat && b != sabitFiyat) continue;
        for (final t in havuz) {
          if (t == a || t == b) continue;
          if (t == sabitAdet || t == sabitFiyat) continue;
          final oran = _carpimOrani(profiller[a].degerler, profiller[b].degerler, profiller[t].degerler);
          if (oran > enIyiOran) {
            enIyiOran = oran;
            enIyi = (a, b, t);
          }
        }
      }
    }
    if (enIyi != null) {
      final (a, b, t) = enIyi;
      // Adet: tam sayı oranı yüksek olan (lot); eşitse küçük medyanlı olmayan
      // — fiyat genelde adetten küçük değil, belirsiz: başlık varsa o kazanır.
      final aTam = profiller[a].oran(profiller[a].tam), bTam = profiller[b].oran(profiller[b].tam);
      var adet = aTam >= bTam ? a : b;
      var fiyat = adet == a ? b : a;
      if (roller[EkstreRol.adet] == fiyat || roller[EkstreRol.fiyat] == adet) {
        final x = adet;
        adet = fiyat;
        fiyat = x;
      }
      for (final (r, c) in [(EkstreRol.adet, adet), (EkstreRol.fiyat, fiyat), (EkstreRol.tutar, t)]) {
        if (roller.containsKey(r)) continue;
        if (roller.values.contains(c)) continue;
        roller[r] = c;
        kullanilan.add(c);
      }
      iliskiyle = true;
    }
    if (!roller.containsKey(EkstreRol.adet)) {
      // Son çare: en çok tam sayı içeren boş sayısal sütun.
      final kalan = sayisalSutunlar.where((c) => !kullanilan.contains(c)).toList()
        ..sort((x, y) => profiller[y].oran(profiller[y].tam).compareTo(profiller[x].oran(profiller[x].tam)));
      if (kalan.isNotEmpty) {
        roller[EkstreRol.adet] = kalan.first;
        kullanilan.add(kalan.first);
        notlar.add('Adet sütunu içerikten tahmin edildi; kontrol et.');
      }
    }
  }

  // Adla tanımlı tablo yalnız ADETLİ ise pozisyondur. Adetsiz ad + tutar
  // listesi ("Vadesiz Mevduat 11.173,97", hesap numaraları) bir varlık
  // dökümü özetidir; her satırı "fon tanınmadı" diye raporlamak gürültü.
  if (adlaTanimli && !roller.containsKey(EkstreRol.adet)) {
    roller.remove(EkstreRol.sembol);
    adlaTanimli = false;
  }

  // 6) Güven.
  var guven = 1.0;
  if (!roller.containsKey(EkstreRol.sembol) || !roller.containsKey(EkstreRol.adet)) {
    guven = 0;
  } else {
    if (!baslikla.contains(EkstreRol.sembol)) guven *= 0.85;
    if (!baslikla.contains(EkstreRol.adet)) guven *= iliskiyle ? 0.85 : 0.6;
    if (!roller.containsKey(EkstreRol.fiyat) && !roller.containsKey(EkstreRol.tutar)) {
      notlar.add('Fiyat sütunu yok: her satır için o günün kapanış fiyatı kullanılır.');
    }
    // Üçü birden varsa tutarlılık: tutmuyorsa "fiyat" belki son fiyattır.
    final a = roller[EkstreRol.adet], f = roller[EkstreRol.fiyat], t = roller[EkstreRol.tutar];
    if (a != null && f != null && t != null) {
      final o = _carpimOrani(profiller[a].degerler, profiller[f].degerler, profiller[t].degerler);
      if (o < 0.5) {
        guven *= 0.8;
        notlar.add('Adet × fiyat tutarla uyuşmuyor. Fiyat sütunu güncel fiyat olabilir, kontrol et.');
      }
    }
    if (baslik < 0) {
      guven *= 0.9;
      notlar.add('Başlık satırı bulunamadı; sütunlar içerikten çıkarıldı.');
    }
  }
  if (roller.containsKey(EkstreRol.yon)) {
    final c = roller[EkstreRol.yon]!;
    final disarida = veri.where((s) => s[c].isNotEmpty && yonCoz(s[c]) == null).length;
    if (disarida > 0) {
      atlanan += disarida;
      notlar.add('$disarida satır alım/satım değil (temettü, virman, bedelsiz…), atlandı.');
    }
  }

  return EkstreAnlami(
    tablo: tablo,
    baslikSatiri: baslik,
    basliklar: [
      for (var c = 0; c < genislik; c++)
        baslikHucreleri[c].isNotEmpty ? baslikHucreleri[c] : 'Sütun ${c + 1}',
    ],
    roller: Map.unmodifiable(roller),
    veri: veri,
    guven: guven,
    atlanan: atlanan,
    notlar: notlar,
    stiller: [for (final p in profiller) p.turkce],
    ayOnce: [for (final p in profiller) p.ayOnce],
    adlaTanimli: adlaTanimli,
  );
}

/// Dışarıdan verilmiş eşlemeyle anlam (AI sütun eşleme, 2026-10-05).
///
/// [baslikSatiri] ve [roller] HAM tablonun (`tablo.satirlar`) satır/sütun
/// numaralarıdır — tanılama iskeletinin numaraları. Veri satırları,
/// sayı stili ve tarih düzeni [tabloyuAnla] ile aynı kurallarla çıkar;
/// eşlemeyi yalnız sütun SEÇER, değerleri belge verir.
///
/// İçerik kapısı: sembol sütunu boşsa ya da adet sütununun satırlarının
/// yarısından azı sayıysa `null` — model yanlış sütun gösterdiyse
/// uydurma satır üretilmez. Sembol sütunu çoğunlukla kod değil AD ise
/// (fon unvanı) tablo adla tanımlıdır: kod TEFAS unvanından çözülür.
EkstreAnlami? tabloyuRollerleAnla(
  EkstreTablosu tablo,
  int baslikSatiri,
  Map<EkstreRol, int> roller,
) {
  final satirlar = [
    for (final s in tablo.satirlar) [for (final h in s) h.trim()],
  ];
  if (satirlar.isEmpty) return null;
  final genislik = satirlar.map((s) => s.length).reduce(math.max);
  for (final s in satirlar) {
    while (s.length < genislik) {
      s.add('');
    }
  }
  final sembol = roller[EkstreRol.sembol], adet = roller[EkstreRol.adet];
  if (sembol == null || adet == null) return null;
  if (roller.values.any((c) => c < 0 || c >= genislik)) return null;
  final baslik =
      baslikSatiri >= 0 && baslikSatiri < satirlar.length ? baslikSatiri : -1;
  final baslikHucreleri =
      baslik >= 0 ? satirlar[baslik] : List.filled(genislik, '');
  final baslikAnahtari = baslikHucreleri.map(_norm).join('|');
  var atlanan = 0;
  final veri = <List<String>>[];
  for (var i = baslik + 1; i < satirlar.length; i++) {
    final s = satirlar[i];
    if (s.where((h) => h.isNotEmpty).length < 2) continue;
    if (baslik >= 0 && s.map(_norm).join('|') == baslikAnahtari) continue;
    if (_toplamSatiriMi(s)) {
      atlanan++;
      continue;
    }
    if (s[sembol].isEmpty) continue;
    veri.add(s);
  }
  if (veri.isEmpty) return null;
  var tabloTr = 0, tabloEn = 0;
  for (var c = 0; c < genislik; c++) {
    final (tr, en) = _stilKaniti([for (final s in veri) s[c]]);
    tabloTr += tr;
    tabloEn += en;
  }
  final profiller = [
    for (var c = 0; c < genislik; c++)
      _profilCikar([for (final s in veri) s[c]], tabloTurkce: tabloTr >= tabloEn),
  ];
  if (profiller[adet].oran(profiller[adet].sayi) < 0.5) return null;
  final adla = profiller[sembol].oran(profiller[sembol].sembol) < 0.5;
  return EkstreAnlami(
    tablo: tablo,
    baslikSatiri: baslik,
    basliklar: [
      for (var c = 0; c < genislik; c++)
        baslikHucreleri[c].isNotEmpty ? baslikHucreleri[c] : 'Sütun ${c + 1}',
    ],
    roller: Map.unmodifiable(roller),
    veri: veri,
    // Eşik üstü: kanonik çıktıya girer. Kart yine de "yapay zekâ önerisi,
    // kontrol et" der (not) ve "Sütunları düzelt" açık kalır.
    guven: 0.8,
    atlanan: atlanan,
    notlar: const [],
    stiller: [for (final p in profiller) p.turkce],
    ayOnce: [for (final p in profiller) p.ayOnce],
    adlaTanimli: adla,
  );
}

/// a × b ≈ t (±%2) olan satırların, üçü de dolu satırlara oranı.
double _carpimOrani(List<double?> a, List<double?> b, List<double?> t) {
  var dolu = 0, tutan = 0;
  for (var i = 0; i < a.length && i < b.length && i < t.length; i++) {
    final x = a[i], y = b[i], z = t[i];
    if (x == null || y == null || z == null || z == 0) continue;
    dolu++;
    if (((x * y).abs() - z.abs()).abs() <= z.abs() * 0.02 + 0.01) tutan++;
  }
  return dolu < 2 ? 0 : tutan / dolu;
}
