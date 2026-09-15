import '../models/asset.dart';
import '../utils/tr_format.dart';
import 'period_summary_service.dart';
import '../l10n/l10n.dart';

/// Birikim disiplini — haftalık / aylık / yıllık net katkı serisi.
///
/// **Neden bu, getiriden ayrı bir soru:** getiri piyasanın kullanıcıya ne
/// yaptığını ölçer; birikim kullanıcının KENDİ davranışını ölçer. İkincisi
/// tek kontrol edebildiği değişken. Piyasa kötüyken bile "bu ay da
/// biriktirdin" doğru ve motive edici bir cümledir — ve bir tavsiye
/// değildir, olan biteni bildirir.
///
/// ## Tek kaynak: `PeriodSummaryService.flowOf`
/// Nakit akışının işaret kuralı (alım +, satışta ele geçen tutar −, temettü
/// akışa girmez) TEK yerde duruyor ve burası oraya bakar. İkinci bir akış
/// tanımı yazmak, bu projede ons→gram formülünün beş kopyaya ayrılmasıyla
/// aynı hata sınıfı olurdu.
///
/// Saf ve statik — ağa çıkmaz, `assets` çağırandan gelir.
class ContributionHistoryService {
  ContributionHistoryService._();

  /// Anlamlı bir trend cümlesi için gereken en az kova sayısı.
  ///
  /// İki kovayla "artıyor" demek, tek bir farkı eğilim ilan etmektir.
  static const minKova = 3;

  /// [aralik] çözünürlüğünde, [kovaSayisi] adet GERİYE dönük kova üretir.
  ///
  /// Kovalar eskiden yeniye sıralı döner; sonuncusu İÇİNDE BULUNULAN
  /// (henüz dolmamış) dönemdir ve bu [ContributionBucket.kismi] ile
  /// işaretlenir — yarısı geçmiş bir ayı tam aylarla kıyaslayıp "birikim
  /// düştü" demek yanlış olurdu.
  static List<ContributionBucket> buckets(
    List<Asset> assets, {
    required ContributionInterval aralik,
    required DateTime now,
    int kovaSayisi = 6,
  }) {
    if (kovaSayisi <= 0) return const [];

    final out = <ContributionBucket>[];
    for (var i = kovaSayisi - 1; i >= 0; i--) {
      final (start, end) = aralik.pencere(now, i);
      // `netInflow` pencereyi gün sınırlarına genişletiyor; uçların
      // birbirine değmemesi için bitiş, bir SONRAKİ kovanın başlangıcından
      // bir gün geri alınır (pencere fonksiyonunda yapılıyor).
      final net = PeriodSummaryService.netInflow(assets, start, end);
      out.add(ContributionBucket(
        start: start,
        end: end,
        netTRY: net,
        kismi: i == 0,
      ));
    }
    return out;
  }

  /// Kova dizisinden özet çıkarır.
  ///
  /// `null` döner: kova yoksa. Kovalar VARSA — hepsi sıfır olsa bile —
  /// özet döner: "hiç katkı yapmadın" ölçülmüş bir cevaptır, eksik veri
  /// değildir.
  static ContributionSummary? summarize(List<ContributionBucket> kovalar) {
    if (kovalar.isEmpty) return null;

    final toplam = kovalar.fold<double>(0, (a, b) => a + b.netTRY);

    // "Birikim yapılan dönem": net POZİTİF olan kova. Net satış yapılan ay
    // birikim sayılmaz ve negatif katkı pozitifmiş gibi renklendirilmez.
    final katkiliKovalar = kovalar.where((k) => k.netTRY > 0).toList();

    // Ortalama, katkı yapılan kovalara BÖLÜNÜR — sıfırlı aylar ortalamayı
    // aşağı çekseydi "ayda ortalama ne biriktiriyorum" sorusuna yanlış
    // cevap verirdi. Kaç kovadan hesaplandığı ayrıca taşınır ki ekran
    // cümleyi doğru kurabilsin.
    final ortalama = katkiliKovalar.isEmpty
        ? null
        : katkiliKovalar.fold<double>(0, (a, b) => a + b.netTRY) /
            katkiliKovalar.length;

    ContributionBucket? zirve;
    for (final k in katkiliKovalar) {
      if (zirve == null || k.netTRY > zirve.netTRY) zirve = k;
    }

    // Son vs önceki: KISMİ kova karşılaştırmaya girmez (yarım ay ile tam
    // ay kıyaslanmaz). Tam kovalardan son ikisi alınır.
    final tamlar = kovalar.where((k) => !k.kismi).toList();
    double? sonFark;
    if (tamlar.length >= 2) {
      sonFark = tamlar.last.netTRY - tamlar[tamlar.length - 2].netTRY;
    }

    // Düzenlilik: kaç kovada katkı var. Oran olarak taşınır, "disiplin
    // skoru" gibi bir puana ÇEVRİLMEZ — keyfi skor üretmeme kuralı.
    final duzenlilik = katkiliKovalar.length / kovalar.length;

    return ContributionSummary(
      kovalar: kovalar,
      toplamTRY: toplam,
      katkiliKovaSayisi: katkiliKovalar.length,
      ortalamaTRY: ortalama,
      zirve: zirve,
      sonFarkTRY: sonFark,
      duzenlilik: duzenlilik,
    );
  }

  /// Tek çağrıda kova + özet.
  static ContributionSummary? compute(
    List<Asset> assets, {
    required ContributionInterval aralik,
    required DateTime now,
    int kovaSayisi = 6,
  }) =>
      summarize(buckets(
        assets,
        aralik: aralik,
        now: now,
        kovaSayisi: kovaSayisi,
      ));
}

/// Birikim kovasının çözünürlüğü.
enum ContributionInterval {
  haftalik('Haftalık', 'hafta'),
  aylik('Aylık', 'ay'),
  yillik('Yıllık', 'yıl');

  final String label;

  /// Cümle içinde geçen tekil ad ("geçen **ay**").
  final String tekil;

  const ContributionInterval(this.label, this.tekil);

  /// Seçici etiketi — dile göre (3.20). [label] TÜRKÇE kalır: özet/paylaşım
  /// metinleri onu kullanıyor.
  String labelOf(AppLocalizations l) => switch (this) {
        ContributionInterval.haftalik => l.intervalWeekly,
        ContributionInterval.aylik => l.intervalMonthly,
        ContributionInterval.yillik => l.intervalYearly,
      };

  /// "son 6 ay · net" — tekil adı ikame etmek yerine tam cümle, çünkü
  /// Türkçe'de ek uyumu (aya / haftaya / yıla) sözcüğe göre değişiyor.
  String sonNDonem(AppLocalizations l, int n) => switch (this) {
        ContributionInterval.haftalik => l.lastNWeeksNet(n),
        ContributionInterval.aylik => l.lastNMonthsNet(n),
        ContributionInterval.yillik => l.lastNYearsNet(n),
      };

  String ortalamaBasligi(AppLocalizations l) => switch (this) {
        ContributionInterval.haftalik => l.avgContributingWeek,
        ContributionInterval.aylik => l.avgContributingMonth,
        ContributionInterval.yillik => l.avgContributingYear,
      };

  String gecenDonemeGore(AppLocalizations l) => switch (this) {
        ContributionInterval.haftalik => l.vsLastWeek,
        ContributionInterval.aylik => l.vsLastMonth,
        ContributionInterval.yillik => l.vsLastYear,
      };

  String devamEden(AppLocalizations l) => switch (this) {
        ContributionInterval.haftalik => l.ongoingWeek,
        ContributionInterval.aylik => l.ongoingMonth,
        ContributionInterval.yillik => l.ongoingYear,
      };

  String trendCumlesi(AppLocalizations l, int yon) => switch ((this, yon)) {
        (ContributionInterval.haftalik, 1) => l.trendUpWeek,
        (ContributionInterval.aylik, 1) => l.trendUpMonth,
        (ContributionInterval.yillik, 1) => l.trendUpYear,
        (ContributionInterval.haftalik, -1) => l.trendDownWeek,
        (ContributionInterval.aylik, -1) => l.trendDownMonth,
        (ContributionInterval.yillik, -1) => l.trendDownYear,
        (ContributionInterval.haftalik, _) => l.trendFlatWeek,
        (ContributionInterval.aylik, _) => l.trendFlatMonth,
        (ContributionInterval.yillik, _) => l.trendFlatYear,
      };

  /// [geriKova] kadar geriye giden pencerenin uçları.
  ///
  /// `0` içinde bulunulan (kısmi) dönem, `1` bir önceki tam dönem…
  ///
  /// Takvimden hesaplanır, sabit gün sayısından değil — `PeriodSummaryService
  /// .donemBaslangici` ile aynı gerekçe: "bir ay" 30 gün değil, bir önceki
  /// ayın aynı günüdür ve kullanıcının kurduğu cümle takvim ayıdır.
  (DateTime, DateTime) pencere(DateTime now, int geriKova) {
    switch (this) {
      case ContributionInterval.haftalik:
        // Hafta PAZARTESİ başlar (tr_TR yerelinde hafta başı budur).
        final buHaftaBasi =
            dayKey(now).subtract(Duration(days: now.weekday - 1));
        final bas = buHaftaBasi.subtract(Duration(days: 7 * geriKova));
        return (bas, bas.add(const Duration(days: 6)));

      case ContributionInterval.aylik:
        final ay = DateTime(now.year, now.month - geriKova, 1);
        // Ayın son günü: bir sonraki ayın 0'ıncı günü.
        final son = DateTime(ay.year, ay.month + 1, 0);
        return (ay, son);

      case ContributionInterval.yillik:
        final yil = DateTime(now.year - geriKova, 1, 1);
        return (yil, DateTime(yil.year, 12, 31));
    }
  }
}

/// Tek bir birikim kovası.
class ContributionBucket {
  final DateTime start;
  final DateTime end;

  /// Pencereye düşen net nakit akışı (TRY). Negatif = net satış.
  final double netTRY;

  /// İçinde bulunulan, henüz DOLMAMIŞ dönem mi?
  final bool kismi;

  const ContributionBucket({
    required this.start,
    required this.end,
    required this.netTRY,
    this.kismi = false,
  });

  bool get pozitif => netTRY > 0;

  /// Ölçüldü ama sıfır mı? (`PeriodSummary.isFlat` ile aynı disiplin:
  /// sıfır bir yön taşımaz, yeşil `+₺0` yazılmaz.)
  bool get bos => netTRY.abs() < 1;
}

/// Birikim serisinin özeti.
class ContributionSummary {
  final List<ContributionBucket> kovalar;

  /// Bütün kovaların toplamı (net — satışlar düşülmüş).
  final double toplamTRY;

  /// Net POZİTİF katkı yapılan kova sayısı.
  final int katkiliKovaSayisi;

  /// Katkı yapılan kovaların ortalaması. Hiç katkı yoksa `null`.
  final double? ortalamaTRY;

  /// En yüksek katkılı kova. Hiç katkı yoksa `null`.
  final ContributionBucket? zirve;

  /// Son TAM kova − bir önceki tam kova. İki tam kova yoksa `null`.
  final double? sonFarkTRY;

  /// Katkılı kova / toplam kova (0…1).
  final double duzenlilik;

  const ContributionSummary({
    required this.kovalar,
    required this.toplamTRY,
    required this.katkiliKovaSayisi,
    required this.duzenlilik,
    this.ortalamaTRY,
    this.zirve,
    this.sonFarkTRY,
  });

  /// Grafik çizilecek kadar kova var mı?
  bool get cizilebilir => kovalar.length >= ContributionHistoryService.minKova;

  /// Hiç para girişi olmamış mı?
  bool get bos => katkiliKovaSayisi == 0;

  /// Kovalardaki en büyük MUTLAK değer — çubuk ölçeklemesi için.
  double get enBuyukMutlak {
    var m = 0.0;
    for (final k in kovalar) {
      final a = k.netTRY.abs();
      if (a > m) m = a;
    }
    return m;
  }

  /// Trend yönü — yalnızca [ContributionHistoryService.minKova] tam kova
  /// varsa. Yetersizse `null` ve ekran trend cümlesi kurmaz.
  ///
  /// Karşılaştırma: son tam kova, ondan önceki tam kovaların ortalamasına
  /// göre. Tek bir önceki kovaya bakmak, dalgalı bir seride her ay yön
  /// değiştiren anlamsız bir cümle üretirdi.
  ///
  /// ## Taban neden KATKILI kovaların ortalaması
  /// İlk hâli bütün tam kovaların ortalamasını alıyordu ve ölçüldü:
  /// dört ay ₺1.000, iki ay hiç katkı yapmayan bir kullanıcıda taban
  /// ₺667'ye düşüyor, sonraki ₺1.020'lik ay "%53 artış" sayılıp trend
  /// ARTIYOR çıkıyordu — oysa kullanıcı hep aynı tutarı yatırmıştı.
  /// Boş aylar tabanı aşağı çekince her normal ay bir sıçrama gibi görünür.
  ///
  /// Katkı YAPILAN ayların ortalaması sorulan soruya denk düşüyor:
  /// "biriktirdiğimde eskisi kadar biriktiriyor muyum?" Hiç katkı olmayan
  /// aylar ayrıca [duzenlilik] ile zaten raporlanıyor, yani bilgi
  /// kaybolmuyor — iki farklı sorunun iki farklı sayısı oluyor.
  ContributionTrend? get trend {
    final tamlar = kovalar.where((k) => !k.kismi).toList();
    if (tamlar.length < ContributionHistoryService.minKova) return null;

    final son = tamlar.last.netTRY;
    final oncekiKatkili =
        tamlar.sublist(0, tamlar.length - 1).where((k) => k.netTRY > 0);
    if (oncekiKatkili.isEmpty) return null;

    final ort = oncekiKatkili.fold<double>(0, (a, b) => a + b.netTRY) /
        oncekiKatkili.length;

    // Eşik: ortalamanın %10'u. Altındaki fark gürültüdür ve "arttı" demek
    // kullanıcının görmediği bir değişimi ilan etmek olurdu.
    final esik = ort.abs() * 0.10;
    if ((son - ort).abs() <= esik) return ContributionTrend.sabit;
    return son > ort ? ContributionTrend.artiyor : ContributionTrend.azaliyor;
  }
}

enum ContributionTrend { artiyor, sabit, azaliyor }
