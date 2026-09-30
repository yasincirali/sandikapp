import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'ekstre_tablosu.dart';
import 'metin_cozucu.dart';

/// Dosya biçimi — UZANTIYA DEĞİL içeriğin imzasına bakılır.
///
/// Türk kurumlarının "Excel'e aktar" çıktısının önemli kısmı `.xls`
/// uzantılı bir HTML tablodur; bazıları `.xls` uzantılı CSV'dir. Uzantıya
/// güvenmek bu dosyaları "bozuk Excel" diye reddettirirdi.
enum EkstreBicimi { xlsx, pdf, eskiXls, html, metin }

EkstreBicimi bicimiSez(Uint8List b) {
  bool bas(List<int> imza) {
    if (b.length < imza.length) return false;
    for (var i = 0; i < imza.length; i++) {
      if (b[i] != imza[i]) return false;
    }
    return true;
  }

  if (bas(const [0x50, 0x4B, 0x03, 0x04])) return EkstreBicimi.xlsx; // PK..
  if (bas(const [0x25, 0x50, 0x44, 0x46])) return EkstreBicimi.pdf; // %PDF
  if (bas(const [0xD0, 0xCF, 0x11, 0xE0])) return EkstreBicimi.eskiXls; // OLE2
  final bas2k = metneCevir(Uint8List.sublistView(b, 0, b.length < 4096 ? b.length : 4096))
      .toLowerCase();
  if (bas2k.contains('<table') || bas2k.contains('<html')) return EkstreBicimi.html;
  return EkstreBicimi.metin;
}

/// PDF dışındaki biçimleri okur (PDF: `PdfTabloOkuyucu`, yerel eklenti ister).
List<EkstreTablosu> tablolariOku(Uint8List b) {
  switch (bicimiSez(b)) {
    case EkstreBicimi.xlsx:
      return xlsxOku(b);
    case EkstreBicimi.html:
      return htmlTablolari(metneCevir(b));
    case EkstreBicimi.metin:
      return [ayrilmisMetinOku(metneCevir(b))];
    case EkstreBicimi.eskiXls:
      // BIFF8 ikili biçim — güvenilir saf Dart okuyucusu yok. Dürüst mesaj,
      // yarım okuma değil.
      throw const EkstreOkumaHatasi(
          'Bu dosya eski Excel biçiminde (.xls, 97-2003). Excel\'de ya da '
          'Numbers\'ta açıp "Farklı Kaydet → .xlsx" veya CSV olarak kaydet, '
          'sonra yeniden seç.');
    case EkstreBicimi.pdf:
      throw StateError('PDF bu yoldan okunmaz; pdfTablolari kullan.');
  }
}

// ── Ayrılmış metin (CSV / TSV / noktalı virgül / dikey çizgi) ────────────────

/// Ayraç, ilk satırlardaki alan sayısının TUTARLILIĞINA göre seçilir —
/// yalnızca başlık satırına bakmak (eski yapıştırma yolu) virgül ondalıklı
/// sayıları ayraç sanabiliyordu. Tırnak içi ayraç ve satır sonu korunur.
EkstreTablosu ayrilmisMetinOku(String metin) {
  final ornekSatirlar = metin
      .split(RegExp(r'\r?\n'))
      .where((s) => s.trim().isNotEmpty)
      .take(40)
      .toList();
  var enIyi = '\t';
  var enIyiPuan = -1.0;
  for (final ayrac in const ['\t', ';', '|', ',']) {
    final sayilar = [for (final s in ornekSatirlar) _bol(s, ayrac).length];
    if (sayilar.isEmpty) continue;
    final frekans = <int, int>{};
    for (final n in sayilar) {
      frekans[n] = (frekans[n] ?? 0) + 1;
    }
    final mod = frekans.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (mod.key < 2) continue;
    // Tutarlılık × sütun sayısı; virgül eşitlikte en sona kalır (ondalık).
    final puan = mod.value / sayilar.length * 10 + mod.key * 0.01 -
        (ayrac == ',' ? 0.5 : 0);
    if (puan > enIyiPuan) {
      enIyiPuan = puan;
      enIyi = ayrac;
    }
  }
  return EkstreTablosu(kaynak: 'Metin', satirlar: _rfc4180(metin, enIyi));
}

List<String> _bol(String satir, String ayrac) {
  final out = <String>[];
  final buf = StringBuffer();
  var tirnak = false;
  for (var i = 0; i < satir.length; i++) {
    final c = satir[i];
    if (c == '"') {
      tirnak = !tirnak;
    } else if (c == ayrac && !tirnak) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  out.add(buf.toString());
  return out;
}

List<List<String>> _rfc4180(String metin, String ayrac) {
  final satirlar = <List<String>>[];
  var satir = <String>[];
  final buf = StringBuffer();
  var tirnak = false;
  for (var i = 0; i < metin.length; i++) {
    final c = metin[i];
    if (tirnak) {
      if (c == '"') {
        if (i + 1 < metin.length && metin[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          tirnak = false;
        }
      } else {
        buf.write(c);
      }
      continue;
    }
    if (c == '"') {
      tirnak = true;
    } else if (c == ayrac) {
      satir.add(buf.toString().trim());
      buf.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < metin.length && metin[i + 1] == '\n') i++;
      satir.add(buf.toString().trim());
      buf.clear();
      if (satir.any((h) => h.isNotEmpty)) satirlar.add(satir);
      satir = <String>[];
    } else {
      buf.write(c);
    }
  }
  satir.add(buf.toString().trim());
  if (satir.any((h) => h.isNotEmpty)) satirlar.add(satir);
  return satirlar;
}

// ── HTML tablo ("Excel'e aktar" çıktılarının çoğu) ───────────────────────────

List<EkstreTablosu> htmlTablolari(String html) {
  final out = <EkstreTablosu>[];
  final tabloRe = RegExp(r'<table\b[^>]*>(.*?)</table>', caseSensitive: false, dotAll: true);
  final satirRe = RegExp(r'<tr\b[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true);
  final hucreRe = RegExp(r'<t([dh])\b([^>]*)>(.*?)</t\1>', caseSensitive: false, dotAll: true);
  final colspanRe = RegExp(r'colspan\s*=\s*"?(\d+)', caseSensitive: false);
  var no = 0;
  for (final t in tabloRe.allMatches(html)) {
    no++;
    final satirlar = <List<String>>[];
    for (final s in satirRe.allMatches(t.group(1)!)) {
      final hucreler = <String>[];
      for (final h in hucreRe.allMatches(s.group(1)!)) {
        hucreler.add(_htmlMetin(h.group(3)!));
        final span = int.tryParse(colspanRe.firstMatch(h.group(2)!)?.group(1) ?? '') ?? 1;
        for (var k = 1; k < span && k < 50; k++) {
          hucreler.add('');
        }
      }
      if (hucreler.any((x) => x.isNotEmpty)) satirlar.add(hucreler);
    }
    if (satirlar.isNotEmpty) {
      out.add(EkstreTablosu(kaynak: 'Tablo $no', satirlar: satirlar));
    }
  }
  if (out.isEmpty) {
    throw const EkstreOkumaHatasi('Dosyada tablo bulunamadı.');
  }
  return out;
}

String _htmlMetin(String s) {
  final t = s
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  return htmlVarliklari(t).replaceAll(RegExp(r'\s+'), ' ').trim();
}

String htmlVarliklari(String s) {
  const adli = {
    'nbsp': ' ', 'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'",
    'ccedil': 'ç', 'Ccedil': 'Ç', 'ouml': 'ö', 'Ouml': 'Ö', 'uuml': 'ü',
    'Uuml': 'Ü', 'scedil': 'ş', 'Scedil': 'Ş', 'gbreve': 'ğ', 'Gbreve': 'Ğ',
    'inodot': 'ı', 'Idot': 'İ', 'euro': '€',
  };
  return s
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
          (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
      .replaceAllMapped(RegExp(r'&([a-zA-Z]+);'), (m) => adli[m[1]] ?? m[0]!);
}

// ── XLSX (Office Open XML) ───────────────────────────────────────────────────

/// Her çalışma sayfası ayrı tablo. Sayı hücresi "1234,56" (Türkçe ondalık,
/// binlik ayraçsız — tip bilindiği için belirsizlik yok), tarih biçimli
/// sayı hücresi "gg.aa.yyyy" olarak yazılır.
List<EkstreTablosu> xlsxOku(Uint8List b) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(b);
  } catch (_) {
    throw const EkstreOkumaHatasi('Excel dosyası açılamadı (bozuk ya da şifreli).');
  }
  XmlDocument? xml(String yol) {
    final f = zip.findFile(yol);
    if (f == null) return null;
    return XmlDocument.parse(utf8.decode(f.content, allowMalformed: true));
  }

  final paylasilan = <String>[
    for (final si in xml('xl/sharedStrings.xml')?.findAllElements('si') ?? const <XmlElement>[])
      si.findAllElements('t').map((t) => t.innerText).join(),
  ];

  // Tarih biçimli stil indeksleri.
  final tarihStilleri = <int>{};
  final stiller = xml('xl/styles.xml');
  if (stiller != null) {
    final ozel = <int, String>{
      for (final f in stiller.findAllElements('numFmt'))
        int.tryParse(f.getAttribute('numFmtId') ?? '') ?? -1: f.getAttribute('formatCode') ?? '',
    };
    final xfs = stiller.findAllElements('cellXfs').firstOrNull?.findElements('xf').toList() ?? const [];
    for (var i = 0; i < xfs.length; i++) {
      final id = int.tryParse(xfs[i].getAttribute('numFmtId') ?? '') ?? 0;
      final yerlesik = (id >= 14 && id <= 22) || (id >= 45 && id <= 47);
      final kod = (ozel[id] ?? '').toLowerCase().replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]'), '');
      final ozelTarih = kod.contains('d') && kod.contains('y') || kod.contains('m') && kod.contains('y');
      if (yerlesik || ozelTarih) tarihStilleri.add(i);
    }
  }

  // Sayfa adları ve dosyaları.
  final iliskiler = <String, String>{
    for (final r in xml('xl/_rels/workbook.xml.rels')?.findAllElements('Relationship') ?? const <XmlElement>[])
      r.getAttribute('Id') ?? '': r.getAttribute('Target') ?? '',
  };
  final sayfalar = <(String, String)>[];
  for (final s in xml('xl/workbook.xml')?.findAllElements('sheet') ?? const <XmlElement>[]) {
    // `r:id` — önek dosyadan dosyaya değişebilir, yerel ada bakılır.
    final rid = s.attributes
            .where((a) => a.name.local == 'id')
            .firstOrNull
            ?.value ??
        '';
    var hedef = iliskiler[rid] ?? '';
    if (hedef.isEmpty) continue;
    hedef = hedef.startsWith('/') ? hedef.substring(1) : 'xl/$hedef';
    sayfalar.add((s.getAttribute('name') ?? 'Sayfa', hedef));
  }

  final out = <EkstreTablosu>[];
  for (final (ad, yol) in sayfalar) {
    final doc = xml(yol);
    if (doc == null) continue;
    final satirlar = <List<String>>[];
    for (final row in doc.findAllElements('row')) {
      final hucreler = <String>[];
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r') ?? '';
        final sutun = _sutunIndeksi(ref);
        while (sutun != null && hucreler.length < sutun) {
          hucreler.add('');
        }
        hucreler.add(_hucreMetni(c, paylasilan, tarihStilleri));
      }
      if (hucreler.any((h) => h.trim().isNotEmpty)) satirlar.add(hucreler);
    }
    if (satirlar.isNotEmpty) out.add(EkstreTablosu(kaynak: ad, satirlar: satirlar));
  }
  if (out.isEmpty) throw const EkstreOkumaHatasi('Excel dosyasında dolu sayfa yok.');
  return out;
}

int? _sutunIndeksi(String ref) {
  final m = RegExp(r'^([A-Z]+)').firstMatch(ref);
  if (m == null) return null;
  var n = 0;
  for (final k in m[1]!.codeUnits) {
    n = n * 26 + (k - 64);
  }
  return n - 1;
}

String _hucreMetni(XmlElement c, List<String> paylasilan, Set<int> tarihStilleri) {
  final tip = c.getAttribute('t');
  final v = c.findElements('v').firstOrNull?.innerText ?? '';
  switch (tip) {
    case 's':
      final i = int.tryParse(v);
      return i != null && i < paylasilan.length ? paylasilan[i].trim() : '';
    case 'inlineStr':
      return c.findAllElements('t').map((t) => t.innerText).join().trim();
    case 'str':
    case 'e':
      return v.trim();
    case 'b':
      return v == '1' ? 'DOĞRU' : 'YANLIŞ';
  }
  final sayi = double.tryParse(v);
  if (sayi == null) return v.trim();
  final stil = int.tryParse(c.getAttribute('s') ?? '');
  if (stil != null && tarihStilleri.contains(stil) && sayi > 0 && sayi < 100000) {
    final g = DateTime.utc(1899, 12, 30).add(Duration(days: sayi.floor()));
    return '${_iki(g.day)}.${_iki(g.month)}.${g.year}';
  }
  return sayiMetni(sayi);
}

String _iki(int n) => n.toString().padLeft(2, '0');

/// Kanonik sayı metni: "1234,56" — binlik ayraç YOK, ondalık virgül.
/// `parseTrNumber` bunu tek anlamlı okur ("1.234" gibi belirsizlik doğmaz).
String sayiMetni(double x) {
  var s = x.toStringAsFixed(8);
  s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s.replaceAll('.', ',');
}
