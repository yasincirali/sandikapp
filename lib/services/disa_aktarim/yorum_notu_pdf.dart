import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../portfoy_yorumu_service.dart' show YorumKapsami, YorumOlcumu;
import '../yorum_notu.dart';
import 'pdf_marka.dart';

/// AI yorumunun A4 "değerlendirme notu" PDF'i (2A, 2026-10-14).
///
/// Düzen banka/aracı kurum araştırma notunu izler (yasin: "daha
/// profesyonel görünüm"): künye (logo, belge adı, dönem/kapsam/tarih),
/// tek cümlelik ana fikir, dört gösterge, solda konu başlıklı değerlendirme,
/// sağda kıyas çubukları + puan farkları + tanımlar, altta kaynak ve "yatırım
/// tavsiyesi değildir". Logo uygulama ikonu (`assets/images/sandik_icon.png`;
/// yasin: "pdf'te logomuz olmalı").
///
/// 2026-10-30: künye yerine tablolu raporla ORTAK üst bant (logo, PREMIUM
/// rozeti, belge adı; `pdf_marka.dart`), ortak sayfa başı ve dipnot — iki
/// Premium PDF aynı kimliği taşır (yasin: "Premium'a özel olanlara ekstra
/// dikkat").
///
/// Renkler kâğıt için sabit (dışa aktarım PDF'iyle aynı aile: marka yeşili,
/// kehribar); ekran karanlık olsa da kâğıt beyazdır. Tutar YOK: yorum
/// paketine tutar girmez, not da yalnız yüzde/puan/gün taşır.
Future<Uint8List> yorumNotuPdf(
  YorumNotu n, {
  required ByteData duz,
  required ByteData kalin,
  required Uint8List logo,
  DateTime? hazirlanma,
}) async {
  final tema = pw.ThemeData.withFont(
    base: pw.Font.ttf(duz),
    bold: pw.Font.ttf(kalin),
  );
  final y = n.yorum;
  final belgeAdi = n.kapsam == YorumKapsami.varlik
      ? 'Varlık değerlendirme notu'
      : 'Portföy değerlendirme notu';
  final doc = pw.Document(title: '$belgeAdi · ${n.donemAdi}', author: 'sandık');
  final logoImg = pw.MemoryImage(logo);
  final tarih = DateFormat('dd.MM.yyyy');

  doc.addPage(
    pw.MultiPage(
      // Üst bant, sayfa başı ve dipnot tablolu raporla ortak (`PdfMarka`,
      // 2026-10-30): iki Premium PDF'in kimliği aynı. Eski künye (logo +
      // ince çizgi) bandın içine taşındı.
      pageTheme: pw.PageTheme(
        theme: tema,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(PdfMarka.yanBosluk,
            PdfMarka.ustBosluk, PdfMarka.yanBosluk, 30),
        buildBackground: ilkSayfaArkaPlani,
      ),
      header: (ctx) => sayfaBasi(ctx, logo: logoImg, belgeAdi: belgeAdi),
      footer: (ctx) => sayfaSonu(
          ctx,
          'Bu not, sandık uygulamasındaki portföy kayıtlarından hesaplanan '
          'oranlarla yapay zekâ tarafından yazılmıştır; tutar içermez. Kıyas '
          'verileri kamuya açık piyasa verisi sağlayıcılarından, TÜFE '
          'TÜİK\'ten alınır. Yatırım tavsiyesi değildir.'),
      build: (ctx) => [
        ustBantIcerigi(
            logo: logoImg,
            belgeTuru: 'Yapay zekâ notu',
            baslik: belgeAdi,
            alt: '${n.donemAdi} · kişisel kullanım içindir'),
        pw.SizedBox(height: 14 + 2.2 + 6),
        _meta([
          ('Dönem', '${tarih.format(y.baslangic)} - ${tarih.format(y.bitis)}'),
          ('Kapsam', n.kapsam == YorumKapsami.varlik ? (n.varlikAdi ?? 'Varlık') : 'Tüm portföy'),
          ('Hazırlanma', tarih.format(hazirlanma ?? y.olusturuldu)),
          ('Para birimi', 'Türk lirası'),
        ]),
        pw.SizedBox(height: 14),
        pw.Text(y.baslik,
            style: pw.TextStyle(
                fontSize: 17, fontWeight: pw.FontWeight.bold, color: _yesil, lineSpacing: 2)),
        pw.SizedBox(height: 12),
        if (n.gostergeler.isNotEmpty) _gostergeler(n.gostergeler),
        pw.SizedBox(height: 14),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _degerlendirme(n)),
            pw.SizedBox(width: 20),
            pw.SizedBox(width: 170, child: _yanSutun(n)),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

const _yesil = PdfColor.fromInt(0xFF112E28);
const _kehribar = PdfColor.fromInt(0xFFF5A623);
const _kehribarKoyu = PdfColor.fromInt(0xFFB87708);
const _murekkep = PdfColor.fromInt(0xFF14231D);
const _gri = PdfColor.fromInt(0xFF55645E);
const _cizgi = PdfColor.fromInt(0xFFDAD7CE);
const _zemin = PdfColor.fromInt(0xFFF3F1EA);
const _kazanc = PdfColor.fromInt(0xFF0F7A4E);
const _kayip = PdfColor.fromInt(0xFFB5321E);
const _notr = PdfColor.fromInt(0xFF9AA6A1);

PdfColor _isaretRengi(String gosterim) {
  final s = gosterim.trim();
  if (s.startsWith('+')) return _kazanc;
  if (s.startsWith('−') || s.startsWith('-')) return _kayip;
  return _murekkep;
}

pw.Widget _meta(List<(String, String)> alanlar) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 7),
      decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _cizgi, width: 0.8))),
      child: pw.Row(
        children: [
          for (final (ad, deger) in alanlar)
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(trBuyuk(ad),
                      style: const pw.TextStyle(
                          fontSize: 6.5, color: _gri, letterSpacing: 0.6)),
                  pw.SizedBox(height: 1),
                  pw.Text(deger,
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold, color: _murekkep)),
                ],
              ),
            ),
        ],
      ),
    );

pw.Widget _gostergeler(List<YorumOlcumu> g) => pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _cizgi, width: 0.8),
          bottom: pw.BorderSide(color: _cizgi, width: 0.8),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < g.length; i++)
            pw.Expanded(
              child: pw.Container(
                padding: pw.EdgeInsets.fromLTRB(i == 0 ? 0 : 10, 8, 8, 8),
                decoration: i == g.length - 1
                    ? null
                    : const pw.BoxDecoration(
                        border: pw.Border(
                            right: pw.BorderSide(color: _cizgi, width: 0.8))),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(trBuyuk(YorumNotu.kisaAd(g[i])),
                        style: const pw.TextStyle(
                            fontSize: 6.5, color: _gri, letterSpacing: 0.6)),
                    pw.SizedBox(height: 2),
                    pw.Text(g[i].gosterim,
                        style: pw.TextStyle(
                            fontSize: 16, fontWeight: pw.FontWeight.bold,
                            color: _isaretRengi(g[i].gosterim))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

pw.Widget _bolumBasligi(String t) => pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.only(bottom: 3),
      decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _cizgi, width: 0.8))),
      child: pw.Text(trBuyuk(t),
          style: pw.TextStyle(
              fontSize: 7, fontWeight: pw.FontWeight.bold, color: _yesil,
              letterSpacing: 0.8)),
    );

pw.Widget _degerlendirme(YorumNotu n) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _bolumBasligi('Değerlendirme'),
        for (var i = 0; i < n.yorum.maddeler.length; i++) ...[
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 13,
                child: pw.Text('${i + 1}',
                    style: pw.TextStyle(
                        fontSize: 9.4, fontWeight: pw.FontWeight.bold,
                        color: _kehribarKoyu)),
              ),
              pw.Expanded(
                child: pw.RichText(
                  text: pw.TextSpan(
                    style: const pw.TextStyle(
                        fontSize: 9.4, color: _murekkep, lineSpacing: 2.2),
                    children: [
                      if (n.yorum.maddeler[i].konu case final k?)
                        pw.TextSpan(
                            text: '$k. ',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold, color: _yesil)),
                      pw.TextSpan(text: n.yorum.maddeler[i].metin),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
        ],
      ],
    );

pw.Widget _yanSutun(YorumNotu n) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (n.kiyaslar.isNotEmpty) ...[
          _bolumBasligi('Dönem getirisi, %'),
          _kiyasGrafigi(n.kiyaslar),
          pw.SizedBox(height: 14),
        ],
        if (n.farklar.isNotEmpty) ...[
          _bolumBasligi('Fark, puan'),
          for (final f in n.farklar)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: _cizgi, width: 0.6))),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                      child: pw.Text(YorumNotu.kisaAd(f),
                          style: const pw.TextStyle(fontSize: 7.6, color: _murekkep))),
                  pw.SizedBox(width: 6),
                  pw.Text(f.gosterim,
                      style: pw.TextStyle(
                          fontSize: 7.6, fontWeight: pw.FontWeight.bold,
                          color: _isaretRengi(f.gosterim))),
                ],
              ),
            ),
          pw.SizedBox(height: 14),
        ],
        pw.Container(
          color: _zemin,
          padding: const pw.EdgeInsets.all(8),
          child: pw.RichText(
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 7.2, color: _gri, lineSpacing: 1.6),
              children: [
                pw.TextSpan(
                    text: 'Tanımlar. ',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _murekkep)),
                const pw.TextSpan(
                    text: 'Reel getiri: dönem getirisinin enflasyondan (TÜFE) '
                        'arındırılmış hâli. En derin düşüş: dönem içinde bir '
                        'zirveden sonraki en büyük geri çekilme. Oynaklık: günlük '
                        'getirilerin yıllıklandırılmış standart sapması. Puan: iki '
                        'yüzde arasındaki fark.'),
              ],
            ),
          ),
        ),
      ],
    );

/// Sıfır ekseni tek ölçekle: negatif değer eksenin soluna, pozitif sağına.
pw.Widget _kiyasGrafigi(List<KiyasCubugu> k) {
  const etiketGen = 52.0;
  const degerGen = 30.0;
  const alan = 170.0 - etiketGen - degerGen;
  final enBuyuk = k.map((e) => e.deger).fold<double>(0, (a, b) => b > a ? b : a);
  final enKucuk = k.map((e) => e.deger).fold<double>(0, (a, b) => b < a ? b : a);
  final aralik = (enBuyuk - enKucuk) == 0 ? 1.0 : enBuyuk - enKucuk;
  final sifir = -enKucuk / aralik * alan;
  return pw.Column(
    children: [
      for (final c in k)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Row(
            children: [
              pw.SizedBox(
                width: etiketGen,
                child: pw.Text(c.ad,
                    maxLines: 1,
                    style: pw.TextStyle(
                        fontSize: 7.2,
                        color: c.kendisi ? _murekkep : _gri,
                        fontWeight: c.kendisi ? pw.FontWeight.bold : pw.FontWeight.normal)),
              ),
              pw.SizedBox(
                width: alan,
                height: 9,
                child: pw.Stack(
                  children: [
                    pw.Positioned(
                      left: sifir,
                      top: 0,
                      bottom: 0,
                      child: pw.Container(width: 0.6, color: _cizgi),
                    ),
                    pw.Positioned(
                      left: c.deger >= 0 ? sifir : sifir + c.deger / aralik * alan,
                      top: 1,
                      child: pw.Container(
                        width: (c.deger.abs() / aralik * alan).clamp(0.6, alan),
                        height: 7,
                        color: c.kendisi
                            ? _yesil
                            : c.ad == 'Gram altın'
                                ? _kehribar
                                : _notr,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(
                width: degerGen,
                child: pw.Text(c.gosterim,
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                        fontSize: 7.2, fontWeight: pw.FontWeight.bold,
                        color: _murekkep)),
              ),
            ],
          ),
        ),
    ],
  );
}

