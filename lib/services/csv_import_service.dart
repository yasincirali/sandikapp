import 'package:uuid/uuid.dart';

import '../models/asset_categories.dart';
import '../models/asset_type.dart';
import '../providers/bulk_cart_provider.dart';
import '../utils/tr_format.dart';

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
/// - Tarih: `gg.aa.yyyy`, `gg/aa/yyyy`, `yyyy-aa-gg`; yoksa bugün.
/// - Fiyat boş → 0 bırakılır; toplu kayıt tarihin kapanışını çeker.
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
      final price = parseTrNumber(cell('price') ?? '') ?? 0;
      if (price < 0) {
        errors.add('Satır $lineNo ($rawTicker): fiyat negatif.');
        continue;
      }
      final date = _parseDate(cell('date')) ?? now;
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
      final h = cells[i].trim().toLowerCase();
      for (final e in _aliases.entries) {
        if (out.containsKey(e.key)) continue;
        if (e.value.any((a) => h == a || h.startsWith('$a '))) {
          out[e.key] = i;
          break;
        }
      }
    }
    return out;
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
    final t = s.trim().toLowerCase();
    for (final v in AssetType.values) {
      if (t == v.name || t == v.label.toLowerCase()) return v;
    }
    if (t.startsWith('hisse') || t == 'stock') return AssetType.hisse;
    if (t.startsWith('fon') || t == 'fund') return AssetType.fon;
    if (t.startsWith('döviz') || t.startsWith('doviz') || t == 'fx') {
      return AssetType.doviz;
    }
    if (t.startsWith('altın') || t.startsWith('altin') || t == 'gold') {
      return AssetType.altin;
    }
    return null;
  }

  /// Semboldan tür çıkarımı — tür sütunu yokken.
  ///
  /// Kurallar sıralı: döviz kodu → altın anahtar sözcüğü → TEFAS 3 harf →
  /// BIST 4-6 harf (`.IS` olsun olmasın) → diğer.
  static AssetType inferType(String raw) {
    final t = raw.trim().toUpperCase();
    if (const {'USD', 'EUR', 'GBP', 'USDTRY=X', 'EURTRY=X', 'GBPTRY=X'}
        .contains(t)) {
      return AssetType.doviz;
    }
    if (t.contains('ALTIN') || t.contains('ALTİN') || t == 'XAUTRY=X') {
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
        // Varsayılan 22 ayar gram; çeyrek/yarım gibi alt türler metinden.
        final sub = t.contains('CEYREK') || t.contains('ÇEYREK')
            ? GoldSubCategory.ceyrek
            : GoldSubCategory.gr22;
        return (
          ticker: 'ALTIN_${sub.name.toUpperCase()}',
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
