import 'dart:convert';
import 'dart:typed_data';

/// Bayt → metin, kodlamayı TAHMİN ederek.
///
/// Türk kurumlarının CSV/TXT ve "Excel" (HTML) çıktıları üç kodlamadan
/// biriyle geliyor: UTF-8 (BOM'lu ya da BOM'suz), UTF-16 (Excel'in
/// "Unicode metin" kaydı) ve Windows-1254 (eski masaüstü yazılımları).
/// Yanlış tahmin "ALIŞ"ı "ALIÞ" yapar ve yön sütunu hiç eşleşmez —
/// sessiz bir hata. Sıra: BOM → UTF-16 sezgisi (sıfır bayt oranı) → katı
/// UTF-8 → Windows-1254.
String metneCevir(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    return utf8.decode(b.sublist(3), allowMalformed: true);
  }
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) return _utf16(b, 2, le: true);
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) return _utf16(b, 2, le: false);
  // BOM'suz UTF-16: ASCII ağırlıklı metinde baytların yarısı sıfırdır.
  final ornek = b.length < 400 ? b.length : 400;
  if (ornek >= 4) {
    var ciftSifir = 0, tekSifir = 0;
    for (var i = 0; i + 1 < ornek; i += 2) {
      if (b[i] == 0) ciftSifir++;
      if (b[i + 1] == 0) tekSifir++;
    }
    final yarim = ornek / 2;
    if (tekSifir > yarim * 0.4) return _utf16(b, 0, le: true);
    if (ciftSifir > yarim * 0.4) return _utf16(b, 0, le: false);
  }
  try {
    return const Utf8Decoder(allowMalformed: false).convert(b);
  } on FormatException {
    return _cp1254(b);
  }
}

String _utf16(Uint8List b, int bas, {required bool le}) {
  final birimler = <int>[];
  for (var i = bas; i + 1 < b.length; i += 2) {
    birimler.add(le ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
  }
  return String.fromCharCodes(birimler);
}

/// Windows-1254 (Türkçe) — 0x80–0x9F bölgesi ve altı Türkçe harf Latin-1'den
/// farklıdır; gerisi Latin-1 ile aynı.
const _cp1254Ozel = <int, int>{
  0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026,
  0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160,
  0x8B: 0x2039, 0x8C: 0x0152, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
  0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC,
  0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153, 0x9F: 0x0178,
  0xD0: 0x011E, 0xDD: 0x0130, 0xDE: 0x015E, // Ğ İ Ş
  0xF0: 0x011F, 0xFD: 0x0131, 0xFE: 0x015F, // ğ ı ş
};

String _cp1254(Uint8List b) {
  final sb = StringBuffer();
  for (final x in b) {
    sb.writeCharCode(x < 0x80 ? x : (_cp1254Ozel[x] ?? x));
  }
  return sb.toString();
}
