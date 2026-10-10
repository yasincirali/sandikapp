import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'rapor_belgesi.dart';

/// [RaporBelgesi] → .xlsx baytları (Premium, 2026-10-10).
///
/// ## Neden elle yazılmış en küçük SpreadsheetML
/// Excel paketi eklemek yerine (bağımlılık + boyut) dosya burada kurulur:
/// .xlsx, birkaç XML dosyası olan bir zip'tir ve ekstre okuyucusunun da
/// kullandığı `archive` paketi zaten bağımlılıktır. Yalnız gereken kadarı:
/// satır içi metin (`inlineStr`, paylaşılan metin tablosu yok), sayı, tarih
/// ve kalın başlık. Tutar sayı olarak yazılır ki müşavir toplayabilsin;
/// tarih Excel seri günüyle ki sıralanabilsin.
///
/// Sayfa düzeni: "Özet" sayfası (başlık, özet satırları, dipnotlar), sonra
/// her tablo kendi sayfasında. Saf: dosya sistemi yok.
Uint8List xlsxYaz(RaporBelgesi b) {
  final sayfalar = <(String, String)>[
    ('Özet', _ozetSayfasi(b)),
    for (final t in b.tablolar) (t.baslik, _tabloSayfasi(t)),
  ];
  final adlar = _benzersizAdlar([for (final s in sayfalar) s.$1]);

  final a = Archive()
    ..addFile(ArchiveFile.string('[Content_Types].xml', _icerikTurleri(sayfalar.length)))
    ..addFile(ArchiveFile.string('_rels/.rels', _kokIliskiler))
    ..addFile(ArchiveFile.string('xl/workbook.xml', _calismaKitabi(adlar)))
    ..addFile(ArchiveFile.string(
        'xl/_rels/workbook.xml.rels', _kitapIliskileri(sayfalar.length)))
    ..addFile(ArchiveFile.string('xl/styles.xml', _stiller));
  for (var i = 0; i < sayfalar.length; i++) {
    a.addFile(
        ArchiveFile.string('xl/worksheets/sheet${i + 1}.xml', sayfalar[i].$2));
  }
  return ZipEncoder().encodeBytes(a);
}

// ── Stiller: 0 düz, 1 sayı #,##0.00, 2 tarih, 3 kalın ────────────────────
const _sDuz = 0, _sSayi = 1, _sTarih = 2, _sKalin = 3;

const _stiller = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<numFmts count="1"><numFmt numFmtId="164" formatCode="dd.mm.yyyy"/></numFmts>'
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="4">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';

String _ozetSayfasi(RaporBelgesi b) {
  final satirlar = <List<(Object?, int?)>>[
    [(b.baslik, _sKalin)],
    [(b.altBaslik, null)],
    [],
    for (final (etiket, deger) in b.ozet) [(etiket, _sKalin), (deger, null)],
    [],
    for (final d in b.dipnotlar) [(d, null)],
  ];
  return _sayfa(satirlar, sutunGenislikleri: const [42, 22]);
}

String _tabloSayfasi(RaporTablosu t) {
  final satirlar = <List<(Object?, int?)>>[
    [for (final s in t.sutunlar) (s, _sKalin)],
    for (final r in t.satirlar) [for (final h in r) (h, null)],
    if (t.toplam != null) [for (final h in t.toplam!) (h, _sKalin)],
  ];
  return _sayfa(satirlar,
      sutunGenislikleri: [for (final _ in t.sutunlar) 18]);
}

String _sayfa(List<List<(Object?, int?)>> satirlar,
    {required List<double> sutunGenislikleri}) {
  final sb = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    ..write('<cols>');
  for (var i = 0; i < sutunGenislikleri.length; i++) {
    sb.write('<col min="${i + 1}" max="${i + 1}" '
        'width="${sutunGenislikleri[i]}" customWidth="1"/>');
  }
  sb.write('</cols><sheetData>');
  for (var r = 0; r < satirlar.length; r++) {
    sb.write('<row r="${r + 1}">');
    final satir = satirlar[r];
    for (var c = 0; c < satir.length; c++) {
      sb.write(_hucre('${sutunHarfi(c)}${r + 1}', satir[c].$1, satir[c].$2));
    }
    sb.write('</row>');
  }
  sb.write('</sheetData></worksheet>');
  return sb.toString();
}

String _hucre(String ref, Object? deger, int? stil) {
  if (deger == null) return '';
  if (deger is TlTutar) {
    return '<c r="$ref" s="${stil == _sKalin ? _sKalin : _sSayi}">'
        '<v>${_sayi(deger.deger)}</v></c>';
  }
  if (deger is num) {
    return '<c r="$ref" s="${stil ?? _sDuz}"><v>${_sayi(deger)}</v></c>';
  }
  if (deger is DateTime) {
    return '<c r="$ref" s="$_sTarih"><v>${excelSeriGunu(deger)}</v></c>';
  }
  return '<c r="$ref" t="inlineStr" s="${stil ?? _sDuz}">'
      '<is><t xml:space="preserve">${xmlKacis(deger.toString())}</t></is></c>';
}

/// Sayı: nokta ondalıklı, gereksiz sıfırsız; NaN/sonsuz yazılmaz (0).
String _sayi(num v) {
  if (v.isNaN || v.isInfinite) return '0';
  final d = v.toDouble();
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
  return d.toString();
}

/// 0 → A, 25 → Z, 26 → AA.
String sutunHarfi(int i) {
  var n = i + 1;
  final sb = StringBuffer();
  while (n > 0) {
    final m = (n - 1) % 26;
    sb.write(String.fromCharCode(65 + m));
    n = (n - 1) ~/ 26;
  }
  return sb.toString().split('').reversed.join();
}

/// Excel seri günü (1900 sistemi; 1899-12-30 tabanı, saat yok).
int excelSeriGunu(DateTime t) =>
    DateTime.utc(t.year, t.month, t.day)
        .difference(DateTime.utc(1899, 12, 30))
        .inDays;

String xmlKacis(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Excel sayfa adı: en çok 31 karakter, `[]:*?/\` yok, benzersiz.
List<String> _benzersizAdlar(List<String> adlar) {
  final yasak = RegExp(r'[\[\]:*?/\\]');
  final kullanilan = <String>{};
  return [
    for (final ham in adlar)
      () {
        var ad = ham.replaceAll(yasak, ' ').trim();
        if (ad.isEmpty) ad = 'Sayfa';
        if (ad.length > 31) ad = ad.substring(0, 31);
        var aday = ad;
        var i = 2;
        while (!kullanilan.add(aday.toLowerCase()) && i < 100) {
          final ek = ' $i';
          aday = (ad.length + ek.length > 31 ? ad.substring(0, 31 - ek.length) : ad) + ek;
          i++;
        }
        return aday;
      }(),
  ];
}

String _icerikTurleri(int sayfa) {
  final sb = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
    ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
    ..write('<Default Extension="xml" ContentType="application/xml"/>')
    ..write('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
    ..write('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
  for (var i = 1; i <= sayfa; i++) {
    sb.write('<Override PartName="/xl/worksheets/sheet$i.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
  }
  sb.write('</Types>');
  return sb.toString();
}

const _kokIliskiler = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

String _calismaKitabi(List<String> adlar) {
  final sb = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
    ..write('<sheets>');
  for (var i = 0; i < adlar.length; i++) {
    sb.write('<sheet name="${xmlKacis(adlar[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
  }
  sb.write('</sheets></workbook>');
  return sb.toString();
}

String _kitapIliskileri(int sayfa) {
  final sb = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
  for (var i = 1; i <= sayfa; i++) {
    sb.write('<Relationship Id="rId$i" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
        'Target="worksheets/sheet$i.xml"/>');
  }
  sb.write('<Relationship Id="rId${sayfa + 1}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
      'Target="styles.xml"/>');
  sb.write('</Relationships>');
  return sb.toString();
}
