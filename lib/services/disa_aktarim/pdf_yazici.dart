import 'dart:math' as math;
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../utils/tr_format.dart';
import 'pdf_marka.dart';
import 'rapor_belgeleri.dart' show teknikSembolMu;
import 'rapor_belgesi.dart';

/// [RaporBelgesi] → PDF baytları (Premium, 2026-10-10; tasarım 2026-10-30).
///
/// Yazı tipi uygulamanın DM Sans'ı ([duz], [kalin]: TTF baytları; çağıran
/// `rootBundle`'dan yükler). PDF'in yerleşik Helvetica'sı ı/ş/ğ/İ
/// basamaz; Türkçe belge gömülü yazı tipi ister. [logo] uygulama ikonu
/// (`assets/images/sandik_icon.png`).
///
/// ## Düzen (yasin 2026-10-30: "güzel tasarım, sandık logosu, göze güzel
/// gelen veri sunumu, yorumlar; Premium'a ekstra dikkat")
/// Önceki sürüm düz başlık + iki sütunlu özet tablosu + 10 sütunlu sıkışık
/// tabloydu: "Altın" "Altı/n" diye, tutarlar "₺239.200,/00" diye kırılıyordu.
/// Şimdi yukarıdan aşağı:
/// 1. **Üst bant** (`PdfMarka`): logo, PREMIUM rozeti, başlık.
/// 2. **Gösterge kutuları:** özet satırları 3'lü ızgarada, büyük rakam;
///    kâr/zarar işaretine göre renk + işaret.
/// 3. **Öne çıkanlar:** kayıtlardan hesaplanan düz cümleler (yorum).
/// 4. **Grafikler:** dağılım çubuğu ve varlık bazında yatay çubuklar.
/// 5. **Tablolar:** yalnız bilgi taşıyan sütunlar (tümü boş sütun, hepsi
///    TL olan "Para birimi", hepsi 1 olan "Kur" PDF'te gizlenir — Excel'de
///    durur); sembol adın altında küçük satır; sütun genişliği içeriğe
///    göre; kâr/zarar sütunu renkli ve işaretli; toplam satırı kalın.
/// 6. **Notlar:** dipnotlar küçük, en sonda.
///
/// Renk sabitleri `PdfMarka`'da (kâğıt beyazdır). Tutar `fmtTRY`, tarih
/// gg.aa.yyyy.
Future<Uint8List> pdfYaz(
  RaporBelgesi b, {
  required ByteData duz,
  required ByteData kalin,
  required Uint8List logo,
}) async {
  final tema = pw.ThemeData.withFont(
    base: pw.Font.ttf(duz),
    bold: pw.Font.ttf(kalin),
  );
  final logoImg = pw.MemoryImage(logo);
  // Başlıktaki "sandık · " önekini bant zaten logoyla söylüyor.
  final baslik = b.baslik.startsWith('sandık · ')
      ? b.baslik.substring('sandık · '.length)
      : b.baslik;
  final doc = pw.Document(title: b.baslik, author: 'sandık');
  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        theme: tema,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(PdfMarka.yanBosluk,
            PdfMarka.ustBosluk, PdfMarka.yanBosluk, 28),
        buildBackground: ilkSayfaArkaPlani,
      ),
      header: (ctx) => sayfaBasi(ctx, logo: logoImg, belgeAdi: baslik),
      footer: (ctx) => sayfaSonu(
          ctx,
          'sandık uygulamasındaki kendi kayıtlarından hazırlandı. Yatırım '
          'ya da vergi tavsiyesi değildir.'),
      build: (ctx) => [
        ustBantIcerigi(
            logo: logoImg,
            belgeTuru: b.belgeTuru,
            baslik: _ilkHarfBuyuk(baslik),
            alt: b.altBaslik),
        pw.SizedBox(height: 14 + 2.2 + 16),
        _gostergeler(b.ozet),
        if (b.oneCikanlar.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          _oneCikanlar(b.oneCikanlar),
        ],
        if (b.grafikler.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          _grafikler(b.grafikler),
        ],
        for (final t in b.tablolar) ...[
          pw.SizedBox(height: 18),
          if (t.satirlar.isEmpty) ...[
            bolumBasligi(t.baslik),
            pw.Text('Kayıt yok.',
                style: const pw.TextStyle(fontSize: 8.5, color: PdfMarka.gri)),
          ] else
            ..._tablo(t),
        ],
        pw.SizedBox(height: 18),
        bolumBasligi('Notlar'),
        for (final d in b.dipnotlar)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Text(d,
                style: const pw.TextStyle(
                    fontSize: 7, color: PdfMarka.gri, lineSpacing: 1.3)),
          ),
      ],
    ),
  );
  return doc.save();
}

String _ilkHarfBuyuk(String s) => s.isEmpty
    ? s
    : PdfMarka.buyuk(s.substring(0, 1)) + s.substring(1);

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

/// Kâr/zarar gibi YÖNLÜ tutar: "+₺1.234,50" / "−₺368,00" (U+2212).
String _isaretli(double v, {int digits = 2}) {
  final m = fmtTRY(v.abs(), digits: digits);
  if (v.abs() < 0.005) return m;
  return '${v > 0 ? '+' : '−'}$m';
}

/// Etiketi yön taşıyan bir tutar mı ("Kâr/zarar …")? Özet ve tabloda aynı
/// kural: yönlü tutar işaretli ve renkli yazılır, diğerleri mürekkep.
bool _yonlu(String etiket) => etiket.toLowerCase().contains('kâr/zarar');

// ── Gösterge kutuları ──────────────────────────────────────────────────────

pw.Widget _gostergeler(List<(String, Object?)> ozet) {
  const sutun = 3;
  final satirlar = <pw.Widget>[];
  for (var i = 0; i < ozet.length; i += sutun) {
    final parca = ozet.sublist(i, math.min(i + sutun, ozet.length));
    satirlar.add(pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var j = 0; j < sutun; j++) ...[
          if (j > 0) pw.SizedBox(width: 8),
          pw.Expanded(
            child: j < parca.length ? _kutu(parca[j]) : pw.SizedBox(),
          ),
        ],
      ],
    ));
    if (i + sutun < ozet.length) satirlar.add(pw.SizedBox(height: 8));
  }
  return pw.Column(children: satirlar);
}

pw.Widget _kutu((String, Object?) kalem) {
  final (etiket, deger) = kalem;
  // "  bunun yurt dışı …" gibi girintili alt satır kutuda düz yazılır.
  final ad = etiket.trim();
  var renk = PdfMarka.murekkep;
  var metin = hucreMetni(deger);
  if (deger is TlTutar) {
    metin = _yonlu(ad) ? _isaretli(deger.deger) : fmtTRY(deger.deger, digits: 2);
    if (_yonlu(ad)) renk = PdfMarka.isaretRengi(deger.deger);
  }
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 9),
    decoration: pw.BoxDecoration(
      color: PdfMarka.zemin,
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(PdfMarka.buyuk(ad),
            maxLines: 2,
            style: const pw.TextStyle(
                fontSize: 6.3, color: PdfMarka.gri, letterSpacing: 0.5)),
        pw.SizedBox(height: 4),
        pw.Text(metin,
            maxLines: 1,
            style: pw.TextStyle(
                fontSize: deger is TlTutar ? 12.5 : 11.5,
                fontWeight: pw.FontWeight.bold,
                color: renk)),
      ],
    ),
  );
}

// ── Öne çıkanlar ───────────────────────────────────────────────────────────

pw.Widget _oneCikanlar(List<String> cumleler) => pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            left: pw.BorderSide(color: PdfMarka.kehribar, width: 2.4)),
      ),
      padding: const pw.EdgeInsets.fromLTRB(12, 2, 0, 2),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('ÖNE ÇIKANLAR',
              style: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfMarka.kehribarKoyu,
                  letterSpacing: 0.9)),
          pw.SizedBox(height: 5),
          for (final c in cumleler)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3.5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 3.6, right: 7),
                    width: 3.5,
                    height: 3.5,
                    decoration: const pw.BoxDecoration(
                        color: PdfMarka.yesil, shape: pw.BoxShape.circle),
                  ),
                  pw.Expanded(
                    child: pw.Text(c,
                        style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfMarka.murekkep,
                            lineSpacing: 1.6)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

// ── Grafikler ──────────────────────────────────────────────────────────────

/// İki grafik yan yana, tek grafik tam genişlik; fazlası alt alta ikişer.
pw.Widget _grafikler(List<RaporGrafigi> g) {
  final satirlar = <pw.Widget>[];
  for (var i = 0; i < g.length; i += 2) {
    if (i > 0) satirlar.add(pw.SizedBox(height: 14));
    satirlar.add(pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _grafik(g[i])),
        if (i + 1 < g.length) ...[
          pw.SizedBox(width: 20),
          pw.Expanded(child: _grafik(g[i + 1])),
        ],
      ],
    ));
  }
  return pw.Column(children: satirlar);
}

pw.Widget _grafik(RaporGrafigi g) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        bolumBasligi(g.baslik, sag: g.not),
        switch (g.tur) {
          RaporGrafikTuru.dagilim => _dagilim(g.kalemler),
          RaporGrafikTuru.cubuk => _cubuklar(g.kalemler),
        },
      ],
    );

/// Tek yığılmış çubuk + lejant. Pay yalnız pozitif değerlerden; her
/// kalemin yanında ad + yüzde + tutar (renk tek başına anlam taşımaz).
pw.Widget _dagilim(List<(String, double)> kalemler) {
  final pozitif = [for (final k in kalemler) if (k.$2 > 0) k];
  final toplam = pozitif.fold(0.0, (t, k) => t + k.$2);
  if (toplam <= 0) return pw.SizedBox();
  PdfColor renk(int i) => PdfMarka.seri[i % PdfMarka.seri.length];
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.ClipRRect(
        horizontalRadius: 4,
        verticalRadius: 4,
        child: pw.Row(
          children: [
            for (var i = 0; i < pozitif.length; i++)
              pw.Expanded(
                flex: math.max(1, (pozitif[i].$2 / toplam * 1000).round()),
                child: pw.Container(
                  height: 12,
                  margin: pw.EdgeInsets.only(
                      right: i == pozitif.length - 1 ? 0 : 1.2),
                  color: renk(i),
                ),
              ),
          ],
        ),
      ),
      pw.SizedBox(height: 8),
      for (var i = 0; i < pozitif.length; i++)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            children: [
              pw.Container(
                width: 7,
                height: 7,
                decoration: pw.BoxDecoration(
                    color: renk(i),
                    borderRadius: pw.BorderRadius.circular(2)),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: pw.Text(pozitif[i].$1,
                    style: const pw.TextStyle(
                        fontSize: 8, color: PdfMarka.murekkep)),
              ),
              pw.SizedBox(
                width: 38,
                child: pw.Text(
                    fmtPct(pozitif[i].$2 / toplam * 100, digits: 1),
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfMarka.murekkep)),
              ),
              pw.SizedBox(
                width: 62,
                child: pw.Text(fmtTRY(pozitif[i].$2),
                    textAlign: pw.TextAlign.right,
                    style:
                        const pw.TextStyle(fontSize: 7.5, color: PdfMarka.gri)),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Yatay çubuklar: uzunluk |değer| / en büyük |değer|, renk işarete göre,
/// tutar işaretli. En fazla 8 kalem (kalanı tabloda).
pw.Widget _cubuklar(List<(String, double)> kalemler) {
  final liste = kalemler.take(8).toList();
  final enBuyuk = liste.fold(0.0, (m, k) => math.max(m, k.$2.abs()));
  if (enBuyuk <= 0) return pw.SizedBox();
  return pw.Column(
    children: [
      for (final (ad, v) in liste)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            children: [
              pw.SizedBox(
                width: 72,
                child: pw.Text(ad,
                    maxLines: 1,
                    style: const pw.TextStyle(
                        fontSize: 7.5, color: PdfMarka.murekkep)),
              ),
              pw.Expanded(
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: math.max(1, (v.abs() / enBuyuk * 1000).round()),
                      child: pw.Container(
                        height: 8,
                        decoration: pw.BoxDecoration(
                          color: v >= 0 ? PdfMarka.kazanc : PdfMarka.kayip,
                          borderRadius: pw.BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    pw.Expanded(
                      flex: math.max(
                          1, 1000 - (v.abs() / enBuyuk * 1000).round()),
                      child: pw.SizedBox(),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(
                width: 66,
                child: pw.Text(_isaretli(v, digits: 0),
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfMarka.isaretRengi(v))),
              ),
            ],
          ),
        ),
    ],
  );
}

// ── Tablo ──────────────────────────────────────────────────────────────────

/// Tablo + (varsa) gizlenen sütunların notu.
List<pw.Widget> _tablo(RaporTablosu t) {
  final n = t.sutunlar.length;
  Object? hucre(List<Object?> r, int i) => i < r.length ? r[i] : null;
  bool hepsi(int i, bool Function(Object?) f) =>
      t.satirlar.every((r) => f(hucre(r, i)));

  // PDF'te bilgi taşımayan sütunlar gizlenir (Excel'de kalır).
  final gizli = <int>{};
  final notlar = <String>[];
  for (var i = 0; i < n; i++) {
    final ad = t.sutunlar[i];
    if (hepsi(i, (h) => h == null)) {
      gizli.add(i);
    } else if (ad == 'Para birimi') {
      final ilk = hucre(t.satirlar.first, i);
      if (hepsi(i, (h) => h == ilk)) {
        gizli.add(i);
        notlar.add('Tüm kayıtların para birimi $ilk.');
      }
    } else if (ad == 'Kur' && hepsi(i, (h) => h == null || h == 1 || h == 1.0)) {
      gizli.add(i);
    }
  }
  // Sembol, adın altında küçük satır olarak yazılır.
  final adSutunu = t.sutunlar.indexOf('Varlık');
  final sembolSutunu = t.sutunlar.indexOf('Sembol');
  final birlesik = adSutunu >= 0 && sembolSutunu >= 0;
  if (birlesik) gizli.add(sembolSutunu);

  final sutunlar = [for (var i = 0; i < n; i++) if (!gizli.contains(i)) i];
  bool sagaYasli(int i) {
    for (final r in t.satirlar) {
      final h = hucre(r, i);
      if (h != null) return h is num || h is TlTutar;
    }
    return false;
  }

  // Genişlik içeriğe göre: en uzun hücre ya da başlığın en uzun kelimesi.
  double genislik(int i) {
    var m = t.sutunlar[i]
        .split(' ')
        .fold(0, (a, w) => math.max(a, w.length))
        .toDouble();
    for (final r in [...t.satirlar, if (t.toplam != null) t.toplam!]) {
      final h = hucre(r, i);
      final s = i == adSutunu && birlesik
          ? math.max(hucreMetni(h).length * 0.8, 10.0)
          : hucreMetni(h).length.toDouble();
      m = math.max(m, s);
    }
    return m.clamp(4, i == adSutunu ? 26 : 16).toDouble();
  }

  pw.Widget yazi(String s, int i,
      {bool kalin = false, PdfColor? renk, double boy = 7.4}) {
    return pw.Text(s,
        textAlign: sagaYasli(i) ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
            fontSize: boy,
            fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: renk ?? PdfMarka.murekkep));
  }

  pw.Widget deger(List<Object?> r, int i, {bool toplam = false}) {
    final h = hucre(r, i);
    if (toplam && h == null) return pw.SizedBox();
    if (i == adSutunu && birlesik && !toplam) {
      final sembol = hucreMetni(hucre(r, sembolSutunu));
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          yazi(hucreMetni(h), i, kalin: true),
          // İç anahtar (ALTIN_GRAM, USDTRY=X) okunmaz; ad yeter.
          if (!teknikSembolMu(sembol)) ...[
            pw.SizedBox(height: 1),
            pw.Text(sembol,
                style:
                    const pw.TextStyle(fontSize: 6.3, color: PdfMarka.gri)),
          ],
        ],
      );
    }
    if (h is TlTutar && _yonlu(t.sutunlar[i])) {
      return yazi(_isaretli(h.deger), i,
          kalin: true, renk: PdfMarka.isaretRengi(h.deger));
    }
    return yazi(hucreMetni(h), i, kalin: toplam);
  }

  const hucrePay = pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4.5);
  final kolonlar = {
    for (var k = 0; k < sutunlar.length; k++)
      k: pw.FlexColumnWidth(genislik(sutunlar[k])),
  };
  final basSatiri = pw.TableRow(
    decoration: const pw.BoxDecoration(
      color: PdfMarka.zemin,
      border:
          pw.Border(bottom: pw.BorderSide(color: PdfMarka.yesil, width: 0.9)),
    ),
    children: [
      for (final i in sutunlar)
        pw.Padding(
          padding: hucrePay,
          child: pw.Text(t.sutunlar[i],
              textAlign: sagaYasli(i) ? pw.TextAlign.right : pw.TextAlign.left,
              style: pw.TextStyle(
                  fontSize: 6.6,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfMarka.yesil)),
        ),
    ],
  );
  final satirlar = [
    for (final r in t.satirlar)
      pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.middle,
        decoration: const pw.BoxDecoration(
          border: pw.Border(
              bottom: pw.BorderSide(color: PdfMarka.cizgi, width: 0.5)),
        ),
        children: [
          for (final i in sutunlar)
            pw.Padding(padding: hucrePay, child: deger(r, i)),
        ],
      ),
    if (t.toplam != null)
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          border:
              pw.Border(top: pw.BorderSide(color: PdfMarka.yesil, width: 0.9)),
        ),
        children: [
          for (final i in sutunlar)
            pw.Padding(
                padding: hucrePay, child: deger(t.toplam!, i, toplam: true)),
        ],
      ),
  ];
  // Başlık + sütun başları + ilk satırlar BÖLÜNMEZ: sayfa dibinde yalnız
  // başlığı kalmış tablo olmasın (ilk önizlemede "İşlemler" başlığı 1.
  // sayfanın dibinde, satırları 2. sayfadaydı). Kalan satırlar aynı sütun
  // genişlikleriyle ikinci tabloda akar ve sayfalara bölünür.
  const ilkParca = 3;
  return [
    pw.Inseparable(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          bolumBasligi(t.baslik, sag: '${t.satirlar.length} kayıt'),
          pw.Table(
              columnWidths: kolonlar,
              children: [basSatiri, ...satirlar.take(ilkParca)]),
        ],
      ),
    ),
    if (satirlar.length > ilkParca)
      pw.Table(columnWidths: kolonlar, children: satirlar.sublist(ilkParca)),
    for (final not in notlar)
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Text(not,
            style: const pw.TextStyle(fontSize: 6.8, color: PdfMarka.gri)),
      ),
  ];
}
