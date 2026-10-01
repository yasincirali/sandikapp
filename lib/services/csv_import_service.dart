import 'package:uuid/uuid.dart';

import '../models/asset_categories.dart';
import '../models/asset_type.dart';
import '../providers/bulk_cart_provider.dart';
import '../utils/tr_format.dart';
import '../utils/tr_katla.dart';
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
///
/// Aracı kurum ekstreleri (karar 5.1 + 5.4, 2026-09-30):
/// - Kurumların yaygın sütun adları da tanınır ("Menkul Kıymet", "Nominal",
///   "Ortalama Maliyet", "İşlem Tarihi", "Valör"…).
/// - Alış/satış: "İşlem Türü", "Al/Sat", "Yön"… sütunu (değer "Alış" /
///   "Satış" / "A" / "S" / "Buy" / "Sell") ya da sütun yoksa EKSİ adet →
///   satış. Satış satırı sepete `satis: true` ile girer; elde olandan fazla
///   satış toplu kayıtta reddedilir (`IceAktarmaSatislari`).
/// - Fiyat sütunu yok ya da boş ama "Tutar" / "İşlem Tutarı" varsa birim
///   fiyat = |tutar| / adet.
/// - Sembol hücresi "THYAO - Türk Hava Yolları" ya da "THYAO.E" (kurumların
///   hisse soneki) gelirse kod ayıklanır.
class CsvImportService {
  CsvImportService._();

  static const _uuid = Uuid();

  static const _aliases = <String, List<String>>{
    'ticker': ['sembol', 'kod', 'ticker', 'symbol', 'hisse', 'fon', 'code'],
    'quantity': ['adet', 'miktar', 'lot', 'quantity', 'qty', 'amount',
      'nominal', 'pay adedi', 'adet/nominal', 'miktar/nominal'],
    // `price`'tan ÖNCE: "Maliyet Tutarı" / "Toplam Maliyet" birim fiyat
    // değil toplamdır; `maliyet` takma adının önek eşleşmesine düşmesin.
    'total': ['tutar', 'islem tutari', 'toplam tutar', 'toplam maliyet',
      'net tutar', 'brut tutar', 'maliyet tutari', 'toplam'],
    'price': ['fiyat', 'maliyet', 'alış', 'alis', 'price', 'cost', 'birim',
      'ortalama maliyet', 'ort. maliyet', 'ort maliyet', 'ort. mlyt',
      'ort mlyt', 'maliyet fiyati', 'islem fiyati', 'gerceklesen fiyat',
      'gerceklesme fiyati', 'ortalama fiyat', 'ort. fiyat'],
    'date': ['tarih', 'date', 'alım tarihi', 'alim tarihi', 'islem tarihi',
      'valor', 'valor tarihi', 'emir tarihi', 'gerceklesme tarihi'],
    'currency': ['para birimi', 'para', 'currency', 'döviz', 'doviz', 'cur'],
    'type': ['tür', 'tur', 'tip', 'type', 'kategori'],
    'name': ['ad', 'isim', 'name', 'açıklama', 'aciklama'],
  };

  /// Alış/satış sütunu — YALNIZ tam eşleşme. Önek eşleşmesi "işlem" gibi
  /// kısa bir adla "İşlem Tutarı"nı yön sütunu sanardı.
  static const _yonAdlari = <String>{
    'islem turu', 'islem tipi', 'islem yonu', 'al/sat', 'alis/satis',
    'alim/satim', 'a/s', 'yon', 'side', 'b/s', 'buy/sell', 'action',
    'emir yonu', 'emir turu', 'hareket turu',
  };

  /// Kurumların sembol sütunu adları ([_aliases]'a ek; önek eşleşmesi).
  static const _sembolEk = <String>[
    'menkul', 'menkul kiymet', 'kiymet', 'kiymet kodu', 'menkul kodu',
    'enstruman', 'hisse kodu', 'fon kodu', 'varlik kodu',
  ];

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

      final hamSembol = cell('ticker');
      if (hamSembol == null) {
        errors.add('Satır $lineNo: sembol yok.');
        continue;
      }
      final rawTicker = sembolAyikla(hamSembol);
      final okunanAdet = parseTrNumber(cell('quantity') ?? '');
      if (okunanAdet == null || okunanAdet == 0) {
        errors.add('Satır $lineNo ($rawTicker): adet okunamadı.');
        continue;
      }
      // Yön: sütun varsa o; yoksa eksi adet = satış (bazı ekstreler satışı
      // negatif miktarla yazar).
      final hamYon = cell('side');
      final bool satis;
      if (hamYon != null) {
        final y = yonCoz(hamYon);
        if (y == null) {
          errors.add('Satır $lineNo ($rawTicker): alış/satış okunamadı '
              '("$hamYon").');
          continue;
        }
        satis = y;
      } else {
        satis = okunanAdet < 0;
      }
      final qty = okunanAdet.abs();
      // Dolu ama okunamayan fiyat/tarih sessizce 0 / bugün OLMAZ
      // (2026-09-23 denetimi U08): başlık eşleşmediğinde "FİYAT" sütunu hiç
      // okunmuyor, fiyat 0 ve tarih bugün kalıyordu — kullanıcı hatalı
      // maliyeti fark etmeden kaydediyordu. Boş hücre ise belgelenmiş
      // davranıştır (kapanış çekilir / bugün).
      final rawPrice = cell('price');
      // Fiyat yoksa tutardan: birim = |tutar| / adet (kurum ekstresi).
      final rawTotal = cell('total');
      final tutar = rawTotal == null ? null : parseTrNumber(rawTotal);
      if (rawPrice == null && rawTotal != null && tutar == null) {
        errors.add('Satır $lineNo ($rawTicker): tutar okunamadı.');
        continue;
      }
      final parsedPrice = rawPrice != null
          ? parseTrNumber(rawPrice)
          : (tutar != null ? tutar.abs() / qty : 0.0);
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
        satis: satis,
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
      if (!out.containsKey('side') && _yonAdlari.contains(h)) {
        out['side'] = i;
        continue;
      }
      if (!out.containsKey('ticker') &&
          _sembolEk.map(_katla).any((a) => h == a || h.startsWith('$a '))) {
        out['ticker'] = i;
        continue;
      }
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
  /// "alis" / "ALIŞ" / "ALIS" aynı anahtara düşer. Katlama artık ortak
  /// (`utils/tr_katla.dart`) — arama da aynısını kullanır.
  static String _katla(String s) => trKatla(s);

  /// Alış/satış hücresi → `true` satış, `false` alış, `null` okunamadı.
  static bool? yonCoz(String hucre) {
    final t = _katla(hucre.trim());
    if (t.isEmpty) return null;
    if (t == 's' || t == 'sell' || t.startsWith('sat')) return true;
    if (t == 'a' || t == 'b' || t == 'buy' || t == 'al' ||
        t.startsWith('alis') || t.startsWith('alim')) {
      return false;
    }
    return null;
  }

  /// Kurum sembol hücresinden kod: "THYAO - Türk Hava Yolları" → "THYAO",
  /// "THYAO.E" (BIST hisse soneki) → "THYAO", "THYAO TÜRK HAVA YOLLARI A.O."
  /// → "THYAO". "GRAM ALTIN" / "ÇEYREK ALTIN" gibi boşluklu altın adları
  /// bölünmez.
  ///
  /// Kod + ad aynı hücrede ve arada yalnız boşluk (2026-10-02): MKK
  /// e-Yatırımcı ve banka PDF'lerinde "Kıymet" sütunu böyle gelir; " - "
  /// olmadığı için hücre olduğu gibi kalıyor, hiçbir sembole benzemiyor ve
  /// TABLO bütünüyle reddediliyordu ("sembol içeren tablo bulunamadı").
  /// Kural: ilk kelime bilinen BIST kodu ya da ISIN ise kesin; değilse
  /// 3–6 harfli büyük harf kod + ardından en az iki kelimelik ad (ve
  /// altın/döviz deyimi değil) → ilk kelime. Tek kelimelik kuyruk ("GRAM
  /// ALTIN") bölünmez.
  static String sembolAyikla(String hucre) {
    var t = hucre.trim();
    final tire = t.indexOf(' - ');
    if (tire > 0) t = t.substring(0, tire).trim();
    final e = RegExp(r'^([A-Za-z]{4,6})\.E$').firstMatch(t);
    if (e != null) t = e.group(1)!;
    final bosluk = t.indexOf(' ');
    if (bosluk > 0) {
      final ilk = t.substring(0, bosluk);
      final kuyruk = t.substring(bosluk + 1).trim();
      final u = ilk.toUpperCase();
      final kesin = bist100StocksMap.containsKey('$u.IS') ||
          RegExp(r'^TR[A-Z0-9]{10}$').hasMatch(u) ||
          _dovizKodlari.contains(u);
      final kodGibi = RegExp(r'^[A-Z][A-Z0-9]{2,5}$').hasMatch(ilk) &&
          kuyruk.split(RegExp(r'\s+')).length >= 2 &&
          !_altinDeyimi.hasMatch(trKatla(t));
      if (kesin || kodGibi) t = ilk;
    }
    return t;
  }

  static const _dovizKodlari = {
    'USD', 'EUR', 'GBP', 'CHF', 'JPY', 'CAD', 'AUD', 'SAR', 'RUB', 'CNY',
    'NOK', 'SEK', 'DKK',
  };

  static final _altinDeyimi = RegExp(
      r'\b(altin|gram|ceyrek|yarim|tam|ata|resat|cumhuriyet|hamit|gremse|'
      r'besli|ikibucuk|has|ons|gumus)\b');

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
      // Mevduat ve BES CSV'den gelmez: lotları sözleşmesiz anlamsızdır
      // (faiz/vade ya da katkı planı olmadan birim değeri hesaplanamaz).
      // Tanınmayan tür olarak satır hatası üretir; kullanıcı kendi formunu
      // kullanır.
      if (v.sozlesmeli) continue;
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
          // Etiket — ekleme formunun yazdığı biçim. Enum adı (`ceyrek`)
          // yazılıyordu: pozisyon anahtarı formdan eklenen aynı altından
          // ayrılıp Portföy'de iki satır çıkıyordu, düzenleme formu da
          // türü tanımıyordu (2026-10-01; eski satırlar okumada
          // `altinAltAnahtari` ile birleşir).
          subCategory: sub.label,
          unitType: sub.unitType,
          currency: 'TRY',
        );
      case AssetType.fon:
        return (
          // `TEFAS:` önekiyle — ekleme formunun yazdığı biçim
          // (`AddAssetFormNotifier.selectFund`). 2026-09-29'a kadar çıplak
          // kod (`TCD`) yazılıyordu: fiyat servisi fonu yalnızca önekten
          // tanıdığı için satır Yahoo'ya gidiyor, fiyatlanmıyordu (bulgu #2;
          // okuma tarafı `kanonikTicker` eski satırları da çevirir).
          ticker: kanonikTicker(
              type: AssetType.fon, ticker: t, isManualPrice: false),
          name: t.replaceFirst(tefasOneki, ''),
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
      // Ulaşılamaz (`_typeFromCell` sözleşmeli türü tanımaz); switch
      // eksiksiz kalsın diye burada.
      case AssetType.mevduat:
      case AssetType.bes:
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
