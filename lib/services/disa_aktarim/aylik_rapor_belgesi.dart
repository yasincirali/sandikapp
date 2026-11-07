import 'package:intl/intl.dart';

import '../../utils/tr_format.dart';
import '../aylik_rapor_ozeti.dart' show AyinParaAkisi, isaretliTL;
import '../inflation_service.dart';
import '../tuik_takvimi.dart';
import 'dosya_adi.dart';
import 'rapor_belgesi.dart';

/// Aylık raporun PDF'indeki bir varlık notu (saklanan yapay zekâ notu;
/// yeniden üretilmez).
class AylikRaporNotu {
  const AylikRaporNotu({
    required this.kod,
    required this.baslik,
    this.rozet,
    this.maddeler = const [],
  });

  /// Ekrandaki kısa ad ('THYAO', 'TTE').
  final String kod;

  /// Durum etiketinin METNİ ("Alıcı istekli"); sakin ya da rozetsizse null.
  final String? rozet;
  final String baslik;
  final List<String> maddeler;
}

/// Aylık rapor PDF'inin içeriği (2026-10-31; müşteri raporu 31 Eki #1,
/// yasin "yap"). Saf.
///
/// ## Neden
/// Üç PDF vardı (yıllık rapor, portföy dökümü, yapay zekâ notu); "bu ay
/// nasıl geçti" sorusunun PDF'i yoktu. yasin 30 Ekim'de PDF'lere
/// "yorumları da eklenmeli" dedi; aylık rapordaki varlık notları zaten
/// kullanıcının ekranında duran Premium içerik, kendi PDF'ine koymak hiçbir
/// onayı aşmaz.
///
/// ## Kurallar
/// - Uydurma sayı yok. Ayın getirisi hesaplanamadıysa getiri ve reel getiri
///   kutusu çıkmaz. Ayın TÜFE'si henüz açıklanmadıysa kutu boş ya da tahmini
///   değil, açıklanacağı günü yazar ("3 Kasım'da açıklanır", `TuikTakvimi`).
/// - Getiri Performans'ın aylık özetiyle AYNI hesap (`PeriodSummaryService`,
///   yatırılan para sayılmaz); burada yeni formül yok.
/// - Notlar saklanan satırdan okunur ("dönemlik çıktı bir kez üretilir").
/// - Sıra ekranla aynı (rozet önemi); notu çıkmayan varlıklar adlarıyla
///   öne çıkanlarda anılır, sessizce düşmez.
///
/// ## Kapsam ve yeni bölümler (yasin 2026-11-07)
/// "Aylık raporda neden sadece fonların raporları var": belge artık
/// ekranla aynı üç sayısal bölümü taşır (ayın varlıkları, para girişi ve
/// çıkışı, önemli gelişmeler; hesap `AylikRaporOzeti`'nde) ve başlığın
/// altında kapsadığı günleri yazar. Haber metni yok; dipnot bunu söyler.
RaporBelgesi aylikRaporBelgesi({
  required DateTime donem,
  required List<AylikRaporNotu> notlar,
  String? kapsam,
  String? notAraligiCumlesi,
  List<(String, double, double)> varliklar = const [],
  String? olculemeyenCumlesi,
  String? fiyatCumlesi,
  AyinParaAkisi? akis,
  List<(DateTime, String, String)> gelismeler = const [],
  String? haberCumlesi,
  required String ozetCumlesi,
  required String? eksikCumlesi,
  required String kim,
  required DateTime olusturma,
  double? getiriPct,
  double? tufePct,
  AyinPortfoyu? portfoy,
}) {
  final ay = DateFormat('MMMM y', 'tr_TR').format(donem);
  final aciklama = TuikTakvimi.aciklamaTarihi(donem);
  final reel = getiriPct == null || tufePct == null
      ? null
      : InflationService.realReturnPct(getiriPct, tufePct);
  final hareketli = [
    for (final n in notlar)
      if (n.rozet != null) '${n.kod} (${n.rozet!.toLowerCase()})'
  ];
  return RaporBelgesi(
    belgeTuru: 'Aylık rapor',
    kampanya: 'aylik_rapor',
    baslik: 'sandık · $ay raporu',
    altBaslik:
        '$kim · oluşturma ${DateFormat('dd.MM.yyyy HH:mm').format(olusturma)}',
    dosyaAdi: belgeDosyaAdi('Aylık Rapor', ayDonemi(donem)),
    kapsam: kapsam,
    tablolarOnce: true,
    // Sıra (müşteri raporu 2 Kas 13:15 #1): ilk satır kişinin parası
    // (yüzde, TL kâr, ay sonu), ikinci satır kıyas (TÜFE, reel, yatırılan).
    // "Notu çıkan varlık" sayacı çıktı: aynı sayı öne çıkanların ilk
    // cümlesinde yazıyor (fikir 3, tekrar).
    ozet: [
      if (getiriPct != null) ('Ayın getirisi', fmtPctIsaretli(getiriPct)),
      if (portfoy?.piyasaTRY != null)
        ('Ayın kâr/zararı', TlTutar(portfoy!.piyasaTRY!)),
      if (portfoy?.sonTRY != null) ('Ay sonu değer', TlTutar(portfoy!.sonTRY!)),
      // Açıklanmamış TÜFE: kutuya cümle değil "—"; günü etikette küçük
      // yazılır (Ar-Ge 2 Kas 12:45 tasarım #4: rakam puntosunda cümle).
      if (tufePct != null)
        ('Ayın TÜFE\'si', fmtPct(tufePct))
      else
        (
          'Ayın TÜFE\'si · '
              '${DateFormat('d MMMM', 'tr_TR').format(aciklama)}\'da açıklanır',
          '—'
        ),
      if (reel != null) ('Reel getiri', fmtPctIsaretli(reel)),
      if (portfoy?.katkiTRY != null)
        ('Yatırdığın net para', TlTutar(portfoy!.katkiTRY!)),
    ],
    oneCikanlar: [
      ozetCumlesi,
      if (portfoy?.kopruCumlesi case final k?) k,
      if (portfoy?.enIyiCumlesi case final k?) k,
      if (hareketli.isNotEmpty) 'Belirgin hareket: ${hareketli.join(', ')}.',
      if (eksikCumlesi != null) eksikCumlesi,
    ],
    bolumler: [
      for (final n in notlar)
        RaporMetinBolumu(
          baslik: n.kod,
          etiket: n.rozet,
          oz: n.baslik,
          maddeler: n.maddeler,
        ),
    ],
    tablolar: [
      if (varliklar.isNotEmpty)
        RaporTablosu(
          baslik: 'Ayın varlıkları',
          sutunlar: const ['Varlık', 'Ayın değişimi', 'Piyasa etkisi'],
          satirlar: [
            for (final (ad, pct, tl) in varliklar)
              [ad, fmtPctIsaretli(pct, digits: 1), isaretliTL(tl)],
          ],
        ),
      if (akis != null && !akis.bos)
        RaporTablosu(
          baslik: 'Para girişi ve çıkışı',
          sutunlar: const ['Kalem', 'İşlem', 'Tutar'],
          satirlar: [
            if (akis.alimSayisi > 0)
              ['Alımlar', '${akis.alimSayisi}', isaretliTL(akis.alimTRY)],
            if (akis.satisSayisi > 0)
              ['Satışlar', '${akis.satisSayisi}', isaretliTL(-akis.satisTRY)],
            if (akis.temettuSayisi > 0)
              [
                'Temettü',
                '${akis.temettuSayisi}',
                isaretliTL(-akis.temettuTRY)
              ],
          ],
          toplam: ['Net katkın', '', isaretliTL(akis.netTRY)],
        ),
      if (gelismeler.isNotEmpty)
        RaporTablosu(
          baslik: 'Önemli gelişmeler',
          sutunlar: const ['Tarih', 'Varlık', 'Ne oldu'],
          satirlar: [
            for (final (tarih, kod, cumle) in gelismeler)
              [DateFormat('d MMMM', 'tr_TR').format(tarih), kod, cumle],
          ],
        ),
    ],
    dipnotlar: [
      if (fiyatCumlesi != null)
        'Ayın varlıkları ay başına göre değişimdir; ay içindeki alım ve '
            'satımın etkisi ayıklandı. $fiyatCumlesi',
      if (olculemeyenCumlesi != null) olculemeyenCumlesi,
      if (akis != null && !akis.bos)
        'Para girişi ve çıkışı Performans\'taki köprüyle aynı hesaptır: '
            'alımda ödediğin, satışta eline geçen tutar; temettü portföyden '
            'cebine çıkan para.',
      if (gelismeler.isNotEmpty)
        'Gelişmeler: fon akışı TEFAS, hacim Yahoo Finance ve Binance '
            'verisinden; temettüler kendi kayıtlarından.',
      if (notAraligiCumlesi != null) notAraligiCumlesi,
      'Getiri, Performans\'taki aylık özetle aynı hesaptır: ayın içinde '
          'yatırdığın ya da çektiğin para getiri sayılmaz.',
      'TÜFE TÜİK\'ten alınır; bir ayın rakamı ertesi ayın 3\'ünde açıklanır.',
      'Varlık notları ayın kamuya açık piyasa verisinden yapay zekâ ile '
          'yazılmıştır; tutar içermez.',
      if (haberCumlesi != null) haberCumlesi,
    ],
  );
}

/// Aylık raporun "ayın portföyü" sayıları (müşteri raporu 2 Kas 13:15 #1,
/// Ar-Ge 12:45 #1). Hepsi Performans › 1A özetinin AYNI hesabından
/// (`PeriodSummary`); burada yeni formül yok.
///
/// **Neden:** rapor yüzde, TÜFE ve piyasa notlarından ibaretti; "Ekim'de
/// ne oldu?" sorusunun kişiye ait yarısı (ay sonu değer, TL kâr, yatırılan
/// para, hangi varlık taşıdı) yoktu. Uydurma yok: bir ayak bilinmiyorsa
/// (seri eksik) o kutu ve köprü cümlesi çıkmaz.
class AyinPortfoyu {
  const AyinPortfoyu({
    this.baslangicTRY,
    this.sonTRY,
    this.katkiTRY,
    this.piyasaTRY,
    this.enIyi,
    this.enZayif,
  });

  final double? baslangicTRY;
  final double? sonTRY;

  /// Ay içinde giren net para (alım +, satış ve nakit temettü −).
  final double? katkiTRY;

  /// Piyasanın payı: (son − baş) − katkı.
  final double? piyasaTRY;

  /// (ad, ayın yüzde değişimi); ay içinde alım yapılan pozisyon elenmiş
  /// (`PeriodSummaryService.enIyiEnZayif`).
  final (String, double)? enIyi;
  final (String, double)? enZayif;

  /// "Ay başında ₺480.000 olan portföyün ay sonunda ₺501.640 oldu.
  /// Piyasanın etkisi +₺11.640, yatırdığın net para +₺10.000." Dört ayağın
  /// hepsi biliniyorsa; Türkçe ek sayıya bitişmesin diye tutarlar cümlenin
  /// ekten bağımsız yerinde.
  String? get kopruCumlesi {
    final b = baslangicTRY, s = sonTRY, k = katkiTRY, p = piyasaTRY;
    if (b == null || s == null || k == null || p == null) return null;
    String tl(double v) => fmtTRY(v, digits: 0);
    String isaretli(double v) =>
        v.abs() < 0.5 ? tl(0) : '${v > 0 ? '+' : '−'}${tl(v.abs())}';
    return 'Ay başında ${tl(b)} olan portföyün ay sonunda ${tl(s)} oldu. '
        'Piyasanın etkisi ${isaretli(p)}, yatırdığın net para '
        '${isaretli(k)}.';
  }

  /// "En çok kazandıran THYAO (+%8,20), en çok düşüren AFT (−%3,10)."
  String? get enIyiCumlesi {
    final i = enIyi, z = enZayif;
    if (i == null && z == null) return null;
    final parca = [
      if (i != null && i.$2 > 0)
        'en çok kazandıran ${i.$1} (${fmtPctIsaretli(i.$2)})',
      if (z != null && z.$2 < 0 && z.$1 != i?.$1)
        'en çok düşüren ${z.$1} (${fmtPctIsaretli(z.$2)})',
    ];
    if (parca.isEmpty) return null;
    final c = parca.join(', ');
    return '${c[0].toUpperCase()}${c.substring(1)}.';
  }
}
