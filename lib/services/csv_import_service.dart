import 'package:uuid/uuid.dart';

import '../models/asset_categories.dart';
import '../models/asset_type.dart';
import '../providers/bulk_cart_provider.dart';
import '../utils/tr_format.dart';
import 'fiyat_kaynagi.dart';

/// Yapıştırılan CSV/TSV metnini sepet kalemlerine çevirir — SAF, ağ yok.
///
/// Değerlendirme (2026-09) §5.4: 2.713 satırlık manuel ekleme ekranı
/// aktivasyonun en büyük sürtünmesiydi. Aracı kurum ekstreleri ve
/// Excel'den kopyalanan tablolar bu yoldan tek seferde sepete girer.
///
/// Dosya seçici BİLEREK yok: bir eklenti daha ve iOS/Android izin akışı
/// yerine "kopyala → yapıştır" her cihazda çalışır ve testte deterministik.
///
/// Biçim toleransı:
/// - Ayraç: `;` / `,` / sekme — başlık satırından otomatik.
/// - Başlık: Türkçe/İngilizce takma adlar (bkz. [_aliases]); başlık yoksa
///   sütun sırası `sembol, adet, fiyat, tarih` varsayılır.
/// - Sayılar: `parseTrNumber` (1.234,56 ve 1234.56 ikisi de).
/// - Tarih: `gg.aa.yyyy`, `gg/aa/yyyy`, `yyyy-aa-gg`; boşsa bugün.
///   Dolu ama okunamayan ya da gelecekteki tarih → satır hatası.
/// - Fiyat boş → 0 bırakılır; toplu kayıt tarihin kapanışını çeker.
///   Okunamayan ya da negatif fiyat → satır hatası.
/// - Başlık eşleştirmesi Türkçe-güvenli (bkz. [_katla]): "FİYAT", "TARİH".
/// - Tür: sütun varsa o; yoksa semboldan çıkarım (bkz. [inferType]).
class CsvImportService {
  CsvImportService._();

  static const _uuid = Uuid();

  static const _aliases = <String, List<String>>{
    'ticker': ['sembol', 'kod', 'ticker', 'symbol', 'hisse', 'fon', 'code'],
    'quantity': ['adet', 'miktar', 'lot', 'quantity', 'qty', 'amount'],
    'price': ['fiyat', 'maliyet', 'alış', 'alis', 'price', 'cost', 'birim'],
    'date': ['tarih', 'date', 'alım tarihi', 'alim tarihi'],
    'currency': ['para birimi', 'para', 'currency', 'döviz', 'doviz', 'cur'],
    'type': ['tür', 'tur', 'tip', 'type', 'kategori'],
    'name': ['ad', 'isim', 'name', 'açıklama', 'aciklama'],
  };

  /// Metni çözer. Hiç satır yoksa `rows` boş, `errors` nedenini söyler.
  static CsvImportResult parse(String text, {DateTime? today}) {
    final now = today ?? DateTime.now();
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trimRight())
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return const CsvImportResult(rows: [], errors: ['Metin boş.']);
    }

    final delim = _detectDelimiter(lines.first);
    final first = _split(lines.first, delim);
    final header = _mapHeader(first);
    final hasHeader = header.containsKey('ticker');
    final dataLines = hasHeader ? lines.skip(1) : lines;
    final cols = hasHeader
        ? header
        : const {'ticker': 0, 'quantity': 1, 'price': 2, 'date': 3};

    final rows = <BulkCartItem>[];
    final errors = <String>[];
    var lineNo = hasHeader ? 1 : 0;
    for (final line in dataLines) {
      lineNo++;
      final cells = _split(line, delim);
      String? cell(String key) {
        final i = cols[key];
        if (i == null || i >= cells.length) return null;
        final v = cells[i].trim();
        return v.isEmpty ? null : v;
      }

      final rawTicker = cell('ticker');
      if (rawTicker == null) {
        errors.add('Satır $lineNo: sembol yok.');
        continue;
      }
      final qty = parseTrNumber(cell('quantity') ?? '');
      if (qty == null || qty <= 0) {
        errors.add('Satır $lineNo ($rawTicker): adet okunamadı.');
        continue;
      }
      // Dolu ama okunamayan fiyat/tarih sessizce 0 / bugün OLMAZ
      // (2026-09-23 denetimi U08): başlık eşleşmediğinde "FİYAT" sütunu hiç
      // okunmuyor, fiyat 0 ve tarih bugün kalıyordu — kullanıcı hatalı
      // maliyeti fark etmeden kaydediyordu. Boş hücre ise belgelenmiş
      // davranıştır (kapanış çekilir / bugün).
      final rawPrice = cell('price');
      final parsedPrice = rawPrice == null ? 0.0 : parseTrNumber(rawPrice);
      if (parsedPrice == null) {
        errors.add('Satır $lineNo ($rawTicker): fiyat okunamadı.');
        continue;
      }
      final price = parsedPrice;
      if (price < 0) {
        errors.add('Satır $lineNo ($rawTicker): fiyat negatif.');
        continue;
      }
      final rawDate = cell('date');
      final parsedDate = _parseDate(rawDate);
      if (rawDate != null && parsedDate == null) {
        errors.add('Satır $lineNo ($rawTicker): tarih okunamadı.');
        continue;
      }
      final date = parsedDate ?? now;
      if (date.isAfter(now)) {
        errors.add('Satır $lineNo ($rawTicker): tarih gelecekte.');
        continue;
      }

      final type = _typeFromCell(cell('type')) ?? inferType(rawTicker);
      final norm = normalizeTicker(rawTicker, type);
      final currency =
          (cell('currency') ?? norm.currency ?? type.defaultCurrency)
              .toUpperCase();

      rows.add(BulkCartItem(
        id: _uuid.v4(),
        type: type,
        name: cell('name') ?? norm.name,
        ticker: norm.ticker,
        quantity: qty,
        price: price,
        currency: currency,
        subCategory: norm.subCategory,
        unitType: norm.unitType,
        isManualPrice: price > 0 && type == AssetType.diger,
        addedDate: date,
      ));
    }
    return CsvImportResult(rows: rows, errors: errors);
  }

  static String _detectDelimiter(String headerLine) {
    final counts = {
      ';': ';'.allMatches(headerLine).length,
      '\t': '\t'.allMatches(headerLine).length,
      ',': ','.allMatches(headerLine).length,
    };
    // `,` ondalık ayracı da olabilir; eşitlikte `;` ve sekme öne alınır.
    var best = ';';
    var bestN = -1;
    for (final e in counts.entries) {
      if (e.value > bestN) {
        best = e.key;
        bestN = e.value;
      }
    }
    return bestN <= 0 ? ';' : best;
  }

  static List<String> _split(String line, String delim) {
    // Tırnaklı hücreler ("Türk Hava Yolları, A.Ş.") ayraç içerebilir.
    final out = <String>[];
    final buf = StringBuffer();
    var inQuote = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuote = !inQuote;
        continue;
      }
      if (ch == delim && !inQuote) {
        out.add(buf.toString());
        buf.clear();
        continue;
      }
      buf.write(ch);
    }
    out.add(buf.toString());
    return out;
  }

  static Map<String, int> _mapHeader(List<String> cells) {
    final out = <String, int>{};
    for (var i = 0; i < cells.length; i++) {
      final h = _katla(cells[i].trim());
      for (final e in _aliases.entries) {
        if (out.containsKey(e.key)) continue;
        if (e.value.map(_katla).any((a) => h == a || h.startsWith('$a '))) {
          out[e.key] = i;
          break;
        }
      }
    }
    return out;
  }

  /// Başlık/tür eşleştirmesi için Türkçe-güvenli katlama: küçük harf +
  /// ASCII'ye indirgeme.
  ///
  /// 2026-09-23 denetimi U08: Dart'ın `toLowerCase()`'i dilden bağımsızdır;
  /// "İ"yi "i̇" (i + U+0307 birleşik nokta) yapar. "FİYAT" → "fi̇yat" hiçbir
  /// takma adla eşleşmiyor, fiyat 0 ve tarih bugün kalıyordu. Tek başına
  /// İ→i / I→ı eşlemesi de yetmez: İngilizce "PRICE" "prıce" olurdu. Bu
  /// yüzden iki taraf da (başlık ve takma ad) ASCII'ye katlanır; "alış" /
  /// "alis" / "ALIŞ" / "ALIS" aynı anahtara düşer.
  static String _katla(String s) {
    const harita = {
      'İ': 'i', 'I': 'i', 'ı': 'i', '\u0307': '',
      'Ğ': 'g', 'ğ': 'g', 'Ü': 'u', 'ü': 'u', 'Ş': 's', 'ş': 's',
      'Ö': 'o', 'ö': 'o', 'Ç': 'c', 'ç': 'c',
    };
    final b = StringBuffer();
    for (final ch in s.split('')) {
      b.write(harita[ch] ?? ch);
    }
    return b.toString().toLowerCase();
  }

  static DateTime? _parseDate(String? s) {
    if (s == null) return null;
    final t = s.trim();
    var m = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{4})$').firstMatch(t);
    if (m != null) {
      return _safeDate(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
    }
    m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
    if (m != null) {
      return _safeDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    }
    return null;
  }

  static DateTime? _safeDate(int y, int mo, int d) {
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, mo, d);
    return dt.month == mo ? dt : null;
  }

  static AssetType? _typeFromCell(String? s) {
    if (s == null) return null;
    // U08: "HİSSE" / "DÖVİZ" de tanınsın — başlıkla aynı katlama.
    final t = _katla(s.trim());
    for (final v in AssetType.values) {
      if (t == _katla(v.name) || t == _katla(v.label)) return v;
    }
    if (t.startsWith('hisse') || t == 'stock') return AssetType.hisse;
    if (t.startsWith('fon') || t == 'fund') return AssetType.fon;
    if (t.startsWith('doviz') || t == 'fx') {
      return AssetType.doviz;
    }
    if (t.startsWith('altin') || t == 'gold') {
      return AssetType.altin;
    }
    if (t.startsWith('kripto') || t == 'crypto' || t == 'coin') {
      return AssetType.kripto;
    }
    return null;
  }

  /// Semboldan tür çıkarımı — tür sütunu yokken.
  ///
  /// Kurallar sıralı: döviz kodu → altın anahtar sözcüğü → TEFAS 3 harf →
  /// BIST 4-6 harf (`.IS` olsun olmasın) → diğer.
  static AssetType inferType(String raw) {
    final t = raw.trim().toUpperCase();
    // Kripto YALNIZCA açık işaretle tanınır: `KRIPTO:BTC`, `BTC-USD`,
    // `BTCUSDT`. Çıplak "BTC" üç harfli olduğu için TEFAS fon koduyla
    // (AAK, TTE…) ayırt edilemez; tür sütunu verilmediyse fon kalır —
    // yanlış türde kripto, yanlış türde fondan daha kötü değil ama
    // tahminle birini bozmak ikisini de bozmaktır.
    if (kriptoKodunuCoz(t) != null) return AssetType.kripto;
    if (const {'USD', 'EUR', 'GBP', FiyatKaynagi.usdTry, 'EURTRY=X', 'GBPTRY=X'}
        .contains(t)) {
      return AssetType.doviz;
    }
    if (t.contains('ALTIN') || t.contains('ALTİN') || t == FiyatKaynagi.xauTry) {
      return AssetType.altin;
    }
    final core = t.endsWith('.IS') ? t.substring(0, t.length - 3) : t;
    // `.IS` soneki BIST demektir — uzunluğa bakılmaz (ör. ISCTR.IS, TCD.IS).
    if (t.endsWith('.IS') && RegExp(r'^[A-Z0-9]{2,6}$').hasMatch(core)) {
      return AssetType.hisse;
    }
    if (RegExp(r'^[A-Z]{3}$').hasMatch(core)) return AssetType.fon;
    if (RegExp(r'^[A-Z]{4,6}$').hasMatch(core)) return AssetType.hisse;
    return AssetType.diger;
  }

  /// Kripto sembolünün açık biçimlerinden coin kodu: `KRIPTO:BTC`,
  /// `BTC-USD`, `BTC-TRY`, `BTCUSDT`, `BTC/TRY`. Biçim dışıysa `null`.
  static String? kriptoKodunuCoz(String raw) {
    final t = raw.trim().toUpperCase();
    final onekli = kriptoKodu(t);
    if (onekli != null) return onekli;
    final m = RegExp(r'^([A-Z0-9]{2,10})(?:[-/](?:USD|USDT|TRY)|USDT)$').firstMatch(t);
    return m?.group(1);
  }

  /// Sembolü uygulamanın saklama biçimine çevirir.
  static ({
    String ticker,
    String name,
    String? subCategory,
    String unitType,
    String? currency,
  }) normalizeTicker(String raw, AssetType type) {
    final t = raw.trim().toUpperCase();
    switch (type) {
      case AssetType.hisse:
        final ticker = t.endsWith('.IS') ? t : '$t.IS';
        return (
          ticker: ticker,
          name: ticker.substring(0, ticker.length - 3),
          subCategory: null,
          unitType: 'piece',
          currency: 'TRY',
        );
      case AssetType.doviz:
        final code = t.replaceAll('TRY=X', '');
        return (
          ticker: '${code}TRY=X',
          name: code,
          subCategory: code,
          unitType: 'piece',
          // **`code` DEĞİL 'TRY' — dövizde fiyat KURUN KENDİSİDİR.**
          //
          // Ölçülen arıza (kullanıcı bildirimi, 2026-09-16): CSV'den
          // `USD;2200;38,50` girilince satır `currency: 'USD'` ile
          // kaydediliyordu. `totalCostTRY` = miktar × fiyat ×
          // `purchaseFxRate` olduğu için maliyet kur kadar ÇARPILIYOR ve
          // ₺84.700 yerine ₺3.260.950 çıkıyordu — 38 kat. Portföy toplamı
          // ve bütün yüzdeler bozuluyordu.
          //
          // Dövizde `purchasePrice` "1 birim kaç TL" demektir, yani zaten
          // TL cinsindendir; ikinci bir çevrim yapılmamalı.
          // `add_asset_screen` bunu 2026'dan beri böyle yazıyor
          // (`currency = 'TRY'`); CSV yolu o kuralı kaçırmıştı. İki yol
          // aynı varlığı aynı şekilde kaydetmek ZORUNDA.
          currency: 'TRY',
        );
      case AssetType.altin:
        // Varsayılan 22 ayar gram; alt tür sembolden ya da metinden.
        final sub = altinAltTuru(t);
        return (
          // Sembol `goldTickerMap`'ten — ekleme ekranıyla AYNI kaynak.
          // Eskiden `ALTIN_${sub.name}` kuruluyordu ve gram satırı
          // `ALTIN_GR22` oluyordu: fiyat servisinin tanımadığı bir sembol,
          // yani CSV'den gelen gram altın hiç fiyatlanmıyordu.
          ticker: goldTickerMap[sub.label] ?? 'ALTIN_GRAM',
          name: sub.label,
          subCategory: sub.name,
          unitType: sub.unitType,
          currency: 'TRY',
        );
      case AssetType.fon:
        return (
          ticker: t,
          name: t,
          subCategory: null,
          unitType: 'piece',
          currency: 'TRY',
        );
      case AssetType.kripto:
        // Tür sütunu "kripto" dediyse çıplak kod (BTC) de kabul edilir.
        final kod = kriptoKodunuCoz(t) ?? t;
        return (
          ticker: kriptoSembolu(kod),
          name: kod,
          subCategory: null,
          unitType: 'piece',
          // Fiyat sunucuda TL'dir (kripto_fiyat); maliyet de TL girilir.
          currency: 'TRY',
        );
      case AssetType.emtia:
      case AssetType.diger:
        return (
          ticker: t,
          name: raw.trim(),
          subCategory: null,
          unitType: 'piece',
          currency: null,
        );
    }
  }
}

class CsvImportResult {
  const CsvImportResult({required this.rows, required this.errors});
  final List<BulkCartItem> rows;
  final List<String> errors;
  bool get isEmpty => rows.isEmpty;
}

/// CSV'deki altın satırının alt türü. Önce birebir iç sembol
/// (`ALTIN_CEYREK`, `ALTIN_GRAM24`…), sonra metindeki anahtar kelime;
/// hiçbiri yoksa 22 ayar gram (eski varsayılan). Ons burada yok: iç
/// sembolü `XAUUSD=X`'tir ve CSV'de altın değil emtia satırı olarak gelir.
///
/// Anahtar kelime sırası önemlidir — uzun/özgül olan önce: "ATA BEŞLİ"
/// beşli, "ATA" değil; "YARIM" ile "TAM" çakışmasın diye yarım önce.
GoldSubCategory altinAltTuru(String raw) {
  final t = raw.trim().toUpperCase();
  for (final g in GoldSubCategory.values) {
    if (goldTickerMap[g.label] == t && t.startsWith('ALTIN_')) return g;
  }
  bool icerir(List<String> k) => k.any(t.contains);
  if (icerir(['GREMSE'])) return GoldSubCategory.gremse;
  if (icerir(['IKIBUCUK', 'İKİBUÇUK', 'IKIBUÇUK'])) {
    return GoldSubCategory.ikibucuk;
  }
  if (icerir(['BESLI', 'BEŞLİ', 'BEŞLI'])) return GoldSubCategory.besli;
  if (icerir(['HAMIT', 'HAMİT'])) return GoldSubCategory.hamit;
  if (icerir(['RESAT', 'REŞAT'])) return GoldSubCategory.resat;
  if (icerir(['CUMHURIYET', 'CUMHURİYET'])) return GoldSubCategory.cumhuriyet;
  if (icerir(['CEYREK', 'ÇEYREK'])) return GoldSubCategory.ceyrek;
  if (icerir(['YARIM'])) return GoldSubCategory.yarim;
  if (icerir(['ATA'])) return GoldSubCategory.ata;
  if (icerir(['TAM'])) return GoldSubCategory.tam;
  if (icerir(['HAS'])) return GoldSubCategory.has;
  if (icerir(['24'])) return GoldSubCategory.gr24;
  if (icerir(['18'])) return GoldSubCategory.gr18;
  if (icerir(['14'])) return GoldSubCategory.gr14;
  return GoldSubCategory.gr22;
}
