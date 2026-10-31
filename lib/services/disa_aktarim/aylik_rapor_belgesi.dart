import 'package:intl/intl.dart';

import '../../utils/tr_format.dart';
import '../inflation_service.dart';
import '../tuik_takvimi.dart';
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
RaporBelgesi aylikRaporBelgesi({
  required DateTime donem,
  required List<AylikRaporNotu> notlar,
  required String ozetCumlesi,
  required String? eksikCumlesi,
  required String kim,
  required DateTime olusturma,
  double? getiriPct,
  double? tufePct,
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
    dosyaAdi: 'sandik-${DateFormat('yyyy-MM').format(donem)}-aylik-rapor',
    ozet: [
      if (getiriPct != null) ('Ayın getirisi', fmtPctIsaretli(getiriPct)),
      (
        'Ayın TÜFE\'si',
        tufePct != null
            ? fmtPct(tufePct)
            : '${DateFormat('d MMMM', 'tr_TR').format(aciklama)}\'da açıklanır'
      ),
      if (reel != null) ('Reel getiri', fmtPctIsaretli(reel)),
      ('Notu çıkan varlık', '${notlar.length}'),
    ],
    oneCikanlar: [
      ozetCumlesi,
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
    tablolar: const [],
    dipnotlar: [
      'Getiri, Performans\'taki aylık özetle aynı hesaptır: ayın içinde '
          'yatırdığın ya da çektiğin para getiri sayılmaz.',
      'TÜFE TÜİK\'ten alınır; bir ayın rakamı ertesi ayın 3\'ünde açıklanır.',
      'Varlık notları ayın kamuya açık piyasa verisinden yapay zekâ ile '
          'yazılmıştır; tutar içermez. Yatırım tavsiyesi değildir.',
    ],
  );
}
