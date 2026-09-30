import '../models/sozlesme.dart';

/// BES kuralları — hak ediş, devlet katkısı oranı ve yıllık sınır.
///
/// Saf fonksiyonlar; ekran ve provider hesap yapmaz, buradan sorar.
///
/// ## Hak ediş (4632 sayılı kanun, 2016 sonrası tablo)
/// Sistemde kalınan süreye göre devlet katkısının çıkışta eline geçen payı:
/// 3 yıldan az %0, 3–6 yıl %15, 6–10 yıl %35, 10 yıl ve üstü %60. 10 yıl +
/// 56 yaş (ya da emeklilik, vefat, maluliyet) %100'dür; doğum tarihi
/// SAKLANMADIĞI için burada %60'ta durur ve ekran bunu söyler.
///
/// ## Devlet katkısı oranı ve sınırı
/// 2026-01-01'den itibaren %20 (Cumhurbaşkanı kararı, RG 2026-01-07;
/// önce %30). Yıllık üst sınır o yılın brüt asgari ücret toplamının oran
/// kadarıdır: 2026'da 396.360 × %20 = ₺79.272. Yeni yılın tutarı Ocak'ta
/// asgari ücretle belli olur ve tabloya EKLENİR; tabloda olmayan yıl için
/// sınır `null` döner — uydurma sınır uygulanmaz, ekran kullanıcıya
/// düzenlenebilir tutar gösterir.
abstract final class BesHesabi {
  /// Hak ediş basamakları: (tam yıl eşiği, yüzde).
  static const hakEdisBasamaklari = <(int, double)>[
    (0, 0),
    (3, 15),
    (6, 35),
    (10, 60),
  ];

  /// [giris]'ten [simdi]'ye TAM yıl.
  static int tamYil(DateTime giris, DateTime simdi) {
    var y = simdi.year - giris.year;
    final yilDonumu = DateTime(simdi.year, giris.month, giris.day);
    if (simdi.isBefore(yilDonumu)) y--;
    return y < 0 ? 0 : y;
  }

  /// Bugünkü hak ediş yüzdesi.
  static double hakEdisOrani(DateTime giris, DateTime simdi) {
    final y = tamYil(giris, simdi);
    var oran = 0.0;
    for (final (esik, o) in hakEdisBasamaklari) {
      if (y >= esik) oran = o;
    }
    return oran;
  }

  /// Bir sonraki basamak: kaç yıl sonra, yüzde kaç. Son basamaktaysa `null`.
  static ({int yil, double oran})? sonrakiBasamak(
      DateTime giris, DateTime simdi) {
    final y = tamYil(giris, simdi);
    for (final (esik, o) in hakEdisBasamaklari) {
      if (esik > y) return (yil: esik - y, oran: o);
    }
    return null;
  }

  /// [tarih]'te yapılan katkıya uygulanan devlet katkısı yüzdesi.
  static double devletKatkisiOrani(DateTime tarih) {
    if (!tarih.isBefore(DateTime(2026))) return 20;
    if (!tarih.isBefore(DateTime(2022))) return 30;
    return 25;
  }

  /// Yıllık devlet katkısı üst sınırı (TL); tabloda olmayan yıl `null`.
  static const Map<int, double> yillikSinirTablosu = {2026: 79272};

  static double? yillikSinir(int yil) => yillikSinirTablosu[yil];

  /// [katki] TL'lik katkının devlet katkısı; yılın kalan sınırına kırpılır.
  ///
  /// [buYilAlinan] bu yıl bu sözleşmeye zaten yazılmış devlet katkısı.
  /// Sınır bilinmiyorsa kırpılmaz (`sinirBilinmiyor: true`) — ekran tutarı
  /// düzenlenebilir gösterir.
  static ({double tutar, bool sinirDoldu, bool sinirBilinmiyor})
      devletKatkisi({
    required double katki,
    required DateTime tarih,
    required double buYilAlinan,
  }) {
    if (katki <= 0) {
      return (tutar: 0, sinirDoldu: false, sinirBilinmiyor: false);
    }
    final ham = katki * devletKatkisiOrani(tarih) / 100;
    final sinir = yillikSinir(tarih.year);
    if (sinir == null) {
      return (tutar: ham, sinirDoldu: false, sinirBilinmiyor: true);
    }
    final kalan = sinir - buYilAlinan;
    if (kalan <= 0) {
      return (tutar: 0, sinirDoldu: true, sinirBilinmiyor: false);
    }
    return (
      tutar: ham < kalan ? ham : kalan,
      sinirDoldu: ham >= kalan,
      sinirBilinmiyor: false,
    );
  }

  /// [tutar]'ı fon dağılımına böler: `{kod: TL}`.
  ///
  /// Oranlar toplamı 100 değilse ORANLANIR (toplam korunur); boş dağılım
  /// boş harita döner. Son fon kuruş farkını üstlenir — Σ parça == bütün.
  static Map<String, double> katkiyiBol(
      double tutar, List<FonPayi> dagilim) {
    final toplamOran = dagilim.fold<double>(0, (s, f) => s + f.oran);
    if (tutar <= 0 || toplamOran <= 0) return const {};
    final out = <String, double>{};
    var dagitilan = 0.0;
    for (var i = 0; i < dagilim.length; i++) {
      final f = dagilim[i];
      final pay = i == dagilim.length - 1
          ? tutar - dagitilan
          : tutar * f.oran / toplamOran;
      out[f.kod] = (out[f.kod] ?? 0) + pay;
      dagitilan += pay;
    }
    return out;
  }

  /// Dağılım geçerli mi: en az bir fon, oranlar toplamı %100 (±0,01).
  static bool dagilimGecerli(List<FonPayi> dagilim) {
    if (dagilim.isEmpty) return false;
    final t = dagilim.fold<double>(0, (s, f) => s + f.oran);
    return (t - 100).abs() < 0.01;
  }

  /// Bu ayın katkısı bekleniyor mu: aylık tutar ve gün tanımlı, bugün o
  /// günü geçti ve bu takvim ayında sözleşmeye katkı lotu yazılmadı.
  static bool katkiBekleniyor({
    required Sozlesme s,
    required DateTime simdi,
    required Iterable<DateTime> katkiTarihleri,
  }) {
    final gun = s.katkiGunu;
    if (s.aylikKatki == null || gun == null || !s.acik) return false;
    if (simdi.day < gun) return false;
    return !katkiTarihleri
        .any((t) => t.year == simdi.year && t.month == simdi.month);
  }
}
