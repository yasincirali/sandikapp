import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../utils/tr_format.dart';
import 'rapor_belgesi.dart';

/// [RaporBelgesi] → PDF baytları (Premium, 2026-10-10).
///
/// Yazı tipi uygulamanın DM Sans'ı ([duz], [kalin]: TTF baytları; çağıran
/// `rootBundle`'dan yükler). PDF'in yerleşik Helvetica'sı ı/ş/ğ/İ
/// basamaz; Türkçe belge gömülü yazı tipi ister.
///
/// Görünüm sade ve basılabilir: beyaz zemin, marka yeşili başlık, kehribar
/// ince çizgi. Renk sabitleri burada (PDF, uygulama teması değil; ekran
/// karanlık olsa da kâğıt beyazdır). Tutar `fmtTRY`, tarih gg.aa.yyyy.
Future<Uint8List> pdfYaz(
  RaporBelgesi b, {
  required ByteData duz,
  required ByteData kalin,
}) async {
  final tema = pw.ThemeData.withFont(
    base: pw.Font.ttf(duz),
    bold: pw.Font.ttf(kalin),
  );
  final doc = pw.Document(title: b.baslik, author: 'sandık');
  doc.addPage(
    pw.MultiPage(
      theme: tema,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _gri)),
      ),
      build: (ctx) => [
        pw.Text(b.baslik,
            style: pw.TextStyle(
                fontSize: 18, fontWeight: pw.FontWeight.bold, color: _yesil)),
        pw.SizedBox(height: 4),
        pw.Text(b.altBaslik,
            style: const pw.TextStyle(fontSize: 9, color: _gri)),
        pw.SizedBox(height: 8),
        pw.Container(height: 1.5, color: _kehribar),
        pw.SizedBox(height: 12),
        _ozet(b.ozet),
        for (final t in b.tablolar) ...[
          pw.SizedBox(height: 16),
          pw.Text(t.baslik,
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold, color: _yesil)),
          pw.SizedBox(height: 6),
          if (t.satirlar.isEmpty)
            pw.Text('Kayıt yok.',
                style: const pw.TextStyle(fontSize: 9, color: _gri))
          else
            _tablo(t),
        ],
        pw.SizedBox(height: 18),
        for (final d in b.dipnotlar)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Text(d,
                style: const pw.TextStyle(fontSize: 8, color: _gri)),
          ),
      ],
    ),
  );
  return doc.save();
}

const _yesil = PdfColor.fromInt(0xFF112E28);
const _kehribar = PdfColor.fromInt(0xFFF5A623);
const _gri = PdfColor.fromInt(0xFF4A5B54);
const _zemin = PdfColor.fromInt(0xFFF4F1EA);

final _tarih = DateFormat('dd.MM.yyyy');

/// Hücre metni: tutar `fmtTRY` (kuruşlu), tarih gg.aa.yyyy, sayı Türkçe.
String hucreMetni(Object? h) {
  if (h == null) return '—';
  if (h is TlTutar) return fmtTRY(h.deger, digits: 2);
  if (h is DateTime) return _tarih.format(h);
  if (h is num) {
    return NumberFormat.decimalPatternDigits(locale: 'tr_TR', decimalDigits: 2)
        .format(h);
  }
  return h.toString();
}

pw.Widget _ozet(List<(String, Object?)> satirlar) => pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(2),
      },
      children: [
        for (final (etiket, deger) in satirlar)
          pw.TableRow(
            decoration: const pw.BoxDecoration(
                border: pw.Border(
                    bottom: pw.BorderSide(color: _zemin, width: 0.8))),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 4),
                child: pw.Text(etiket, style: const pw.TextStyle(fontSize: 10)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 4),
                child: pw.Text(hucreMetni(deger),
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
      ],
    );

pw.Widget _tablo(RaporTablosu t) {
  bool sagaYasli(int i) {
    for (final r in t.satirlar) {
      final h = i < r.length ? r[i] : null;
      if (h != null) return h is num || h is TlTutar;
    }
    return false;
  }

  final hizalar = <int, pw.Alignment>{
    for (var i = 0; i < t.sutunlar.length; i++)
      i: sagaYasli(i) ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
  };
  return pw.TableHelper.fromTextArray(
    headers: t.sutunlar,
    data: [
      for (final r in t.satirlar) [for (final h in r) hucreMetni(h)],
      if (t.toplam != null) [for (final h in t.toplam!) h == null ? '' : hucreMetni(h)],
    ],
    border: null,
    headerStyle: pw.TextStyle(
        fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
    headerDecoration: const pw.BoxDecoration(color: _yesil),
    headerAlignments: hizalar,
    cellAlignments: hizalar,
    cellStyle: const pw.TextStyle(fontSize: 8),
    oddRowDecoration: const pw.BoxDecoration(color: _zemin),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
  );
}
