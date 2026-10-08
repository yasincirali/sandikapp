import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import 'ekstre_tablosu.dart';
import 'pdf_tablo.dart';

/// PDF → tablo: pdfrx (PDFium, MIT) karakter kutularını verir, tabloları
/// `pdfSonucu` kurar. Eklentiye dokunan tek dosya burası; geometri saf
/// Dart'ta test edilir.
///
/// Neden pdfrx: Android'in yerleşik `PdfRenderer`'ı metin çıkarmaz; iOS
/// PDFKit ayrı bir kanal ister. pdfrx iki platformda aynı motoru (PDFium)
/// kullanır — iki platform aynı PDF'ten aynı tabloyu çıkarır.
///
/// Tablolarla birlikte sayfaların DÜZ METNİ de döner: belge tarihi
/// ("31/05/2026 tarihi itibariyle") ve banka adı tablo dışındadır.
Future<({List<EkstreTablosu> tablolar, String metin})> pdfOku(
  Uint8List bytes,
) async {
  await pdfrxFlutterInitialize();
  final PdfDocument doc;
  try {
    doc = await PdfDocument.openData(bytes, sourceName: 'ekstre.pdf');
  } on PdfPasswordException {
    throw const EkstreOkumaHatasi(
      'PDF şifreli. Kurumun sitesinden şifresiz indir ya da açıp '
      '"PDF olarak yazdır" ile kaydet.',
    );
  } catch (_) {
    throw const EkstreOkumaHatasi('PDF açılamadı (bozuk olabilir).');
  }
  try {
    // Sayfalar ayrı toplanır, tablolar HEPSİNDEN birlikte kurulur: sayfalar
    // boyunca süren tablonun sütun bantları ortaktır (bkz. pdf_tablo.dart).
    final sayfalar = <List<PdfKarakter>>[];
    for (final sayfa in doc.pages) {
      final ham = await sayfa.loadText();
      if (ham == null) continue;
      // pdfrx PDFium karakteri başına BİR kutu ekler ama metne
      // `writeCharCode` yazar: BMP dışı bir karakter iki UTF-16 birimi
      // olur ve `fullText[i]` o noktadan sonra kutusundan kayar. Rune
      // (kod noktası) dizisi kutularla birebir hizalıdır.
      final harfler = ham.fullText.runes.toList();
      final kutular = ham.charRects;
      final n =
          harfler.length < kutular.length ? harfler.length : kutular.length;
      sayfalar.add([
        for (var i = 0; i < n; i++)
          PdfKarakter(
            String.fromCharCode(harfler[i]),
            kutular[i].left,
            kutular[i].right,
            kutular[i].top,
            kutular[i].bottom,
          ),
      ]);
    }
    final sonuc = pdfSonucu(sayfalar);
    if (sonuc.metin.trim().isEmpty) {
      throw const EkstreOkumaHatasi(
        'Bu PDF metin içermiyor (taranmış görüntü olabilir). Kurumun '
        'sitesinden "Excel\'e aktar" ya da metinli PDF indir.',
      );
    }
    return sonuc;
  } finally {
    await doc.dispose();
  }
}
