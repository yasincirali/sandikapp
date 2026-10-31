import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// sandık PDF'lerinin ortak kimliği (yasin 2026-10-30: "rapor pdf olarak
/// verdiğimiz analizler ve raporlar güzel tasarımla, sandık logosuyla;
/// Premium'a özel olanlara ekstra dikkat, premium bir tecrübe").
///
/// İki PDF var — tablolu rapor (`pdf_yazici.dart`: yıllık rapor, portföy
/// dökümü) ve AI değerlendirme notu (`yorum_notu_pdf.dart`) — ve ikisi de
/// Premium. Önceden ikisinin kafası ayrıydı (biri logosuz düz başlık, öteki
/// logolu künye); artık aynı üst bant, aynı sayfa başı, aynı dipnot:
///
/// * **İlk sayfa üst bandı:** tam genişlik marka yeşili, logo + "sandık",
///   sağda kehribar **PREMIUM** rozeti ve belge türü; altında beyaz başlık.
///   Bant sayfa ARKA PLANINA çizilir ([ilkSayfaArkaPlani]) ki kenar
///   boşluğu olmadan kâğıdın ucuna dayansın; içerik bandın üstüne yazılır
///   ([ustBantIcerigi], yüksekliği [bantIcerikYuksekligi] sabit).
/// * **Sonraki sayfalar:** ince künye (küçük logo, belge adı, PREMIUM) —
///   çok sayfalı tablo ikinci sayfada da kimin belgesi olduğunu söyler.
/// * **Dipnot:** kaynak/uyarı + "n / N".
///
/// Renkler kâğıt için SABİT (uygulama teması değil; ekran karanlık olsa da
/// kâğıt beyazdır) ve uygulamanın marka ailesinden: yeşil `112E28`,
/// kehribar `F5A623`. Kazanç/kayıp kâğıtta okunur koyulukta (beyaz
/// zeminde ≥4.5:1); işaret yalnız renkle verilmez, rakamın önünde +/− var.
abstract final class PdfMarka {
  static const yesil = PdfColor.fromInt(0xFF112E28);
  static const yesilAcik = PdfColor.fromInt(0xFF1C4A3F);
  static const kehribar = PdfColor.fromInt(0xFFF5A623);
  static const kehribarKoyu = PdfColor.fromInt(0xFFB87708);
  static const murekkep = PdfColor.fromInt(0xFF14231D);
  static const gri = PdfColor.fromInt(0xFF55645E);
  static const griAcik = PdfColor.fromInt(0xFF9AA6A1);
  static const cizgi = PdfColor.fromInt(0xFFDAD7CE);
  static const zemin = PdfColor.fromInt(0xFFF6F4EE);
  static const kazanc = PdfColor.fromInt(0xFF0F7A4E);
  static const kayip = PdfColor.fromInt(0xFFB5321E);

  /// Bant üstündeki ikincil metin: yeşil zeminde beyazın %70'i.
  static const bantSoluk = PdfColor.fromInt(0xB3FFFFFF);

  /// Tür/dağılım paleti — uygulamadaki tür renklerinin kâğıt karşılığı
  /// (altın kehribar, fon mavi, hisse turuncu, döviz yeşil …). Sıra
  /// sabittir; renk yalnız süs değil, yanında her zaman ad ve yüzde yazar.
  static const seri = [
    PdfColor.fromInt(0xFF112E28),
    PdfColor.fromInt(0xFFF5A623),
    PdfColor.fromInt(0xFF3B82C4),
    PdfColor.fromInt(0xFF2FA37A),
    PdfColor.fromInt(0xFFE2861F),
    PdfColor.fromInt(0xFF8A6BC9),
    PdfColor.fromInt(0xFF9AA6A1),
  ];

  /// İlk sayfanın bant yüksekliği (kâğıdın tepesinden).
  static const bantYuksekligi = 138.0;

  /// Sayfa üst kenar boşluğu; bant içeriği bunun altından başlar.
  static const ustBosluk = 34.0;

  /// Bant içeriğinin (logo satırı + başlık + alt satır) sabit yüksekliği:
  /// içerik bandın İÇİNDE biter, kalan boşluk bandın alt payıdır.
  static const bantIcerikYuksekligi = bantYuksekligi - ustBosluk - 14;

  /// Sayfa yatay kenar boşluğu (tüm PDF'lerde aynı).
  static const yanBosluk = 40.0;

  static PdfColor isaretRengi(double v) =>
      v > 0 ? kazanc : (v < 0 ? kayip : murekkep);

  /// "PORTFÖY DÖKÜMÜ" — Türkçe büyük harf (i → İ, ı → I).
  static String buyuk(String s) =>
      s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
}

/// İlk sayfanın arka planı: kâğıdın tepesinde tam genişlik yeşil bant ve
/// bandın altında ince kehribar çizgi. Sonraki sayfalarda bir şey çizmez.
pw.Widget ilkSayfaArkaPlani(pw.Context ctx) {
  if (ctx.pageNumber != 1) return pw.SizedBox();
  // `FullPage(ignoreMargins)`: arka plan da sayfa kenar boşluğuna uyar;
  // bant kâğıdın ucuna dayansın diye boşluk yok sayılır.
  return pw.FullPage(
    ignoreMargins: true,
    child: pw.Column(
      children: [
        pw.Container(height: PdfMarka.bantYuksekligi, color: PdfMarka.yesil),
        pw.Container(height: 2.2, color: PdfMarka.kehribar),
        pw.Spacer(),
      ],
    ),
  );
}

/// Bandın üstüne yazılan içerik: logo + "sandık" ve sağda PREMIUM rozeti +
/// belge türü; altında başlık ve alt satır. Yükseklik sabit
/// ([PdfMarka.bantIcerikYuksekligi]) ki uzun başlık banttan taşmasın:
/// başlık en fazla iki satır, sığmazsa küçülür.
pw.Widget ustBantIcerigi({
  required pw.ImageProvider logo,
  required String belgeTuru,
  required String baslik,
  required String alt,
}) =>
    pw.SizedBox(
      height: PdfMarka.bantIcerikYuksekligi,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.ClipRRect(
                horizontalRadius: 5,
                verticalRadius: 5,
                child: pw.Image(logo, width: 22, height: 22),
              ),
              pw.SizedBox(width: 7),
              pw.Text('sandık',
                  style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white)),
              pw.Spacer(),
              pw.Text(PdfMarka.buyuk(belgeTuru),
                  style: const pw.TextStyle(
                      fontSize: 7,
                      color: PdfMarka.bantSoluk,
                      letterSpacing: 0.9)),
              pw.SizedBox(width: 8),
              premiumRozeti(),
            ],
          ),
          pw.Spacer(),
          pw.Text(baslik,
              maxLines: 2,
              style: pw.TextStyle(
                  fontSize: 19,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  lineSpacing: 2)),
          pw.SizedBox(height: 5),
          pw.Text(alt,
              maxLines: 1,
              style: const pw.TextStyle(
                  fontSize: 8.5, color: PdfMarka.bantSoluk)),
        ],
      ),
    );

/// Kehribar zeminli küçük "PREMIUM" rozeti — Premium belgenin imzası.
pw.Widget premiumRozeti() => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.2),
      decoration: pw.BoxDecoration(
        color: PdfMarka.kehribar,
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Text('PREMIUM',
          style: pw.TextStyle(
              fontSize: 6.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfMarka.yesil,
              letterSpacing: 1)),
    );

/// İkinci ve sonraki sayfaların ince künyesi (ilk sayfada bant var, boş).
pw.Widget sayfaBasi(pw.Context ctx,
    {required pw.ImageProvider logo, required String belgeAdi}) {
  if (ctx.pageNumber == 1) return pw.SizedBox();
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 12),
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: const pw.BoxDecoration(
        border: pw.Border(
            bottom: pw.BorderSide(color: PdfMarka.cizgi, width: 0.8))),
    child: pw.Row(
      children: [
        pw.ClipRRect(
          horizontalRadius: 3,
          verticalRadius: 3,
          child: pw.Image(logo, width: 12, height: 12),
        ),
        pw.SizedBox(width: 5),
        pw.Text('sandık',
            style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfMarka.yesil)),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Text(belgeAdi,
              maxLines: 1,
              style: const pw.TextStyle(fontSize: 7.5, color: PdfMarka.gri)),
        ),
        premiumRozeti(),
      ],
    ),
  );
}

/// Her sayfanın dipnotu: kaynak/uyarı metni solda, sayfa numarası sağda.
///
/// [baglanti] verilirse sayfa numarasının solunda gri, küçük "sandık ile
/// hazırlandı" bağlantısı (2026-10-31, müşteri raporu 31 Eki #2, yasin
/// "yap"). PDF'in doğası başkasına gitmek (mali müşavir, eş, banka); okuyan
/// "bu neyle yapıldı" diye sorduğunda cevap kâğıtta durur. Bilinçli olarak
/// SESSİZ: "indir"/"ücretsiz dene" çağrısı ve QR yok, Premium belge reklam
/// broşürü gibi durmasın. Hedef `Magaza.indirBaglantisi` (paylaşım kartı ve
/// davetle aynı tek kaynak, UTM taşır, göndereni izlemez).
pw.Widget sayfaSonu(pw.Context ctx, String metin, {String? baglanti}) =>
    pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
          border: pw.Border(
              top: pw.BorderSide(color: PdfMarka.cizgi, width: 0.8))),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Text(metin,
                style: const pw.TextStyle(
                    fontSize: 6.6, color: PdfMarka.gri, lineSpacing: 1.4)),
          ),
          if (baglanti != null) ...[
            pw.SizedBox(width: 14),
            pw.UrlLink(
              destination: baglanti,
              child: pw.Text(hazirlandiMetni,
                  style: const pw.TextStyle(
                      fontSize: 6.6,
                      color: PdfMarka.gri,
                      decoration: pw.TextDecoration.underline,
                      decorationColor: PdfMarka.cizgi)),
            ),
          ],
          pw.SizedBox(width: 14),
          pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 6.6, color: PdfMarka.gri)),
        ],
      ),
    );

/// Dipnot bağlantısının metni (iki PDF yazıcısı ve test aynı sabiti okur).
const hazirlandiMetni = 'sandık ile hazırlandı';

/// Bölüm başlığı: küçük büyük harf, yeşil, altında ince çizgi.
pw.Widget bolumBasligi(String t, {String? sag}) => pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 7),
      padding: const pw.EdgeInsets.only(bottom: 3),
      decoration: const pw.BoxDecoration(
          border: pw.Border(
              bottom: pw.BorderSide(color: PdfMarka.cizgi, width: 0.8))),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(PdfMarka.buyuk(t),
                style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfMarka.yesil,
                    letterSpacing: 0.8)),
          ),
          if (sag != null)
            pw.Text(sag,
                style: const pw.TextStyle(fontSize: 7, color: PdfMarka.gri)),
        ],
      ),
    );
