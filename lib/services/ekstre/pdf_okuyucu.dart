import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import 'ekstre_tablosu.dart';
import 'pdf_tablo.dart';

/// PDF → tablo: pdfrx (PDFium, MIT) karakter kutularını verir, tabloyu
/// `sayfadanSatirlar` kurar. Eklentiye dokunan tek dosya burası; geometri
/// saf Dart'ta test edilir.
///
/// Neden pdfrx: Android'in yerleşik `PdfRenderer`'ı metin çıkarmaz; iOS
/// PDFKit ayrı bir kanal ister. pdfrx iki platformda aynı motoru (PDFium)
/// kullanır — iki platform aynı PDF'ten aynı tabloyu çıkarır.
Future<List<EkstreTablosu>> pdfTablolari(Uint8List bytes) async {
  await pdfrxFlutterInitialize();
  final PdfDocument doc;
  try {
    doc = await PdfDocument.openData(bytes, sourceName: 'ekstre.pdf');
  } on PdfPasswordException {
    throw const EkstreOkumaHatasi(
        'PDF şifreli. Kurumun sitesinden şifresiz indir ya da açıp '
        '"PDF olarak yazdır" ile kaydet.');
  } catch (_) {
    throw const EkstreOkumaHatasi('PDF açılamadı (bozuk olabilir).');
  }
  try {
    final satirlar = <List<String>>[];
    for (final sayfa in doc.pages) {
      final ham = await sayfa.loadText();
      if (ham == null) continue;
      final metin = ham.fullText;
      final kutular = ham.charRects;
      final n = metin.length < kutular.length ? metin.length : kutular.length;
      satirlar.addAll(sayfadanSatirlar([
        for (var i = 0; i < n; i++)
          PdfKarakter(metin[i], kutular[i].left, kutular[i].right,
              kutular[i].top, kutular[i].bottom),
      ]));
    }
    if (satirlar.isEmpty) {
      throw const EkstreOkumaHatasi(
          'Bu PDF metin içermiyor (taranmış görüntü olabilir). Kurumun '
          'sitesinden "Excel\'e aktar" ya da metinli PDF indir.');
    }
    return [EkstreTablosu(kaynak: 'PDF', satirlar: satirlar)];
  } finally {
    await doc.dispose();
  }
}
