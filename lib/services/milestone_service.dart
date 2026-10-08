import '../models/asset.dart';
import '../models/position.dart';
import 'birikim_serisi.dart';

/// Geçilen bir kilometre taşı.
class Milestone {
  /// `portfolio_value` | `gold_count` | `portfolio_age` | `diversification`
  /// | `contribution_streak`
  final String kind;

  /// Eşiğin kimliği — aynı eşik iki kez kutlanmasın diye.
  final String value;

  /// Kutlama başlığı.
  final String title;

  /// Tek cümlelik açıklama.
  final String body;

  /// Eşiğin BÜYÜKLÜĞÜ — hangisinin kutlanacağını seçmek için.
  ///
  /// Ayrı bir alan çünkü [value] bir KİMLİKTİR ve metindir; onunla
  /// sıralamak sessizce yanlış sonuç verir: `'25000'` metin olarak
  /// `'100000'`den büyüktür, yani 25 bin eşiği 100 binin önüne geçerdi.
  final double rank;

  const Milestone({
    required this.kind,
    required this.value,
    required this.title,
    required this.body,
    required this.rank,
  });

  @override
  bool operator ==(Object other) =>
      other is Milestone && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => '$kind:$value';
}

/// Kilometre taşı hesabı.
///
/// **Kutlanan şey BİRİKİMDİR, işlem değil.** Robinhood her işlem sonrası
/// konfeti atıyordu; Massachusetts uzlaşması (7,5M$, Ocak 2024) tam olarak
/// bunu hedef aldı. Ayrım ilkesel: işlem ödüllendirildiğinde kullanıcı daha
/// çok işlem yapar ve Barber & Odean verisine göre daha az kazanır.
/// Buradaki eşiklerin hiçbiri bir işleme bağlı değil — portföyün büyümesi,
/// sabır ve çeşitlenme ölçülüyor.
///
/// Hesabın tamamı saf ve durumsuz: girdi portföy, çıktı geçilen eşikler.
/// Kalıcılık ve "daha önce kutlandı mı" sorusu çağıranın işi.
class MilestoneService {
  MilestoneService._();

  /// Portföy değeri eşikleri (TRY).
  ///
  /// Aralıklar yukarı doğru genişler: 10K'dan 25K'ya çıkmak bir başarıdır,
  /// 2,5M'den 2,6M'ye çıkmak değildir. Sabit aralık, büyük portföyde her ay
  /// kutlama üretip anlamı öldürürdü.
  static const valueThresholds = <double>[
    10000, 25000, 50000, 100000, 250000, 500000,
    1000000, 2500000, 5000000, 10000000,
  ];

  /// Altın adedi eşikleri — tür başına.
  ///
  /// Adet ÜZERİNDEN sayılır, gram karşılığı üzerinden değil: "10 çeyreğin
  /// oldu" kullanıcının kafasındaki birimdir ve dönüşüm hatası taşımaz.
  static const goldCountThresholds = <int>[1, 5, 10, 25, 50, 100];

  static const _goldLabels = <String, String>{
    'ALTIN_GRAM': 'gram altın',
    'ALTIN_CEYREK': 'çeyrek altın',
    'ALTIN_YARIM': 'yarım altın',
    'ALTIN_CUMHURIYET': 'Cumhuriyet altını',
    'ALTIN_ATA': 'Ata altını',
    'ALTIN_RESAT': 'Reşat altını',
    'ALTIN_GRAM24': 'gram altın (24 ayar)',
    'ALTIN_HAS': 'has altın',
    'ALTIN_18AYAR': '18 ayar altın',
    'ALTIN_14AYAR': '14 ayar altın',
    'ALTIN_TAM': 'tam altın',
    'ALTIN_HAMIT': 'Hamit altını',
    'ALTIN_IKIBUCUK': 'ikibuçuk altın',
    'ALTIN_GREMSE': 'gremse altın',
    'ALTIN_BESLI': 'beşli altın',
  };

  /// Portföy yaşı eşikleri (yıl).
  static const ageYears = <int>[1, 2, 3, 5, 10];

  /// Kaç farklı varlık TÜRÜ eşiği.
  static const typeCounts = <int>[3, 5];

  /// Aylık birikim serisi eşikleri (ay). Bayrak `birikim_serisi`.
  ///
  /// Eşik bir İŞLEME değil sürekliliğe bağlı: tek alım hiçbir şey açmaz,
  /// üç ay art arda biriktirmek açar ("birikimi kutla, işlemi değil").
  static const streakMonths = <int>[3, 6, 12, 24, 36];

  /// Portföyün geçtiği tüm eşikler.
  ///
  /// [now] test için enjekte edilir.
  ///
  /// [seri] verilirse (bayrak açık) birikim serisi eşikleri de döner;
  /// "ulaşılan" eşik EN UZUN seriye göre — seri sonradan sıfırlansa da
  /// geçilmiş eşik geçilmiştir ve aynı eşik ikinci kez kutlanmaz.
  static List<Milestone> evaluate({
    required List<Asset> assets,
    required double totalTRY,
    required DateTime now,
    BirikimSerisi? seri,
  }) {
    // `aktifLotlar` + aggregate: ham `isBuy` tamamen SATILMIŞ pozisyonu da
    // "elimde" sayardı — kullanıcı sattığı altından "altın biriktirici",
    // sattığı hisselerden "çeşitlilik" rozeti kazanıyordu (denetim
    // 2026-09-22). Rozet gerçek mülkiyeti ödüllendirmeli.
    final aktif = _aktifGorunum(assets);
    if (aktif.isEmpty) return const [];

    return [
      ..._valueMilestones(totalTRY),
      ..._goldMilestones(aktif),
      ..._ageMilestones(aktif, now),
      ..._diversificationMilestones(aktif),
      if (seri != null) ..._streakMilestones(seri),
    ];
  }

  static List<Milestone> _streakMilestones(BirikimSerisi seri) {
    final out = <Milestone>[];
    for (final ay in streakMonths) {
      if (seri.enUzun < ay) break;
      out.add(Milestone(
        kind: 'contribution_streak',
        value: '${ay}m',
        rank: ay.toDouble(),
        title: '$ay ay art arda birikim',
        body: ay >= 12
            ? '${ay ~/ 12} yıldır her ay portföyüne ekleme yapıyorsun. '
                'Düzen, piyasadan bağımsız tek şey.'
            : '$ay aydır her ay portföyüne ekleme yapıyorsun. Düzen, '
                'piyasadan bağımsız tek şey.',
      ));
    }
    return out;
  }

  static List<Milestone> _valueMilestones(double totalTRY) {
    final out = <Milestone>[];
    for (final esik in valueThresholds) {
      if (totalTRY < esik) break; // liste artan sıralı
      out.add(Milestone(
        kind: 'portfolio_value',
        value: esik.toStringAsFixed(0),
        rank: esik,
        title: '${_kisaTutar(esik)} geçildi',
        body: 'Portföyün ${_kisaTutar(esik)} sınırını aştı. Biriktirmeye '
            'devam.',
      ));
    }
    return out;
  }

  static List<Milestone> _goldMilestones(List<Asset> aktif) {
    final adetler = <String, double>{};
    for (final a in aktif) {
      final sub = a.subCategory?.trim() ?? '';
      if (!_goldLabels.containsKey(sub)) continue;
      adetler[sub] = (adetler[sub] ?? 0) + a.quantity;
    }

    final out = <Milestone>[];
    adetler.forEach((sub, adet) {
      final tam = adet.floor();
      for (final esik in goldCountThresholds) {
        if (tam < esik) break;
        final etiket = _goldLabels[sub]!;
        out.add(Milestone(
          kind: 'gold_count',
          value: '$sub:$esik',
          rank: esik.toDouble(),
          title: esik == 1 ? 'İlk $etiket' : '$esik $etiket',
          body: esik == 1
              ? 'Portföyüne ilk $etiket girdi.'
              : 'Toplam $esik $etiket biriktirdin.',
        ));
      }
    });
    return out;
  }

  static List<Milestone> _ageMilestones(List<Asset> aktif, DateTime now) {
    // En ESKİ alım portföyün yaşıdır. Kullanıcı arada varlık silip ekleyebilir
    // ama "ne zamandır yatırım yapıyorum" sorusunun cevabı ilk adımdır.
    final enEski = _enEskiAlim(aktif);
    if (enEski == null) return const [];

    final gun = now.difference(enEski).inDays;
    final out = <Milestone>[];
    for (final yil in ageYears) {
      if (gun < yil * 365) break;
      out.add(Milestone(
        kind: 'portfolio_age',
        value: '${yil}y',
        rank: yil.toDouble(),
        title: yil == 1 ? 'Portföyün 1 yaşında' : 'Portföyün $yil yaşında',
        // "yıldır takiptesin" DEĞİL: tarih kullanıcının girdiği İŞLEM
        // tarihidir, uygulamayı ne zamandır kullandığı değil. Geçmiş tarihli
        // alım girip birkaç haftadır kullanan kullanıcıya "2 yıldır
        // takiptesin" denmişti (2026-09-27). Söylenen, bilinen tek gerçek.
        body: 'İlk alımın $yil yıl önceydi. Sabır bu işin yarısı.',
      ));
    }
    return out;
  }

  static List<Milestone> _diversificationMilestones(List<Asset> aktif) {
    final turler = aktif.map((a) => a.type).toSet();
    final out = <Milestone>[];
    for (final n in typeCounts) {
      if (turler.length < n) break;
      out.add(Milestone(
        kind: 'diversification',
        value: '${n}types',
        rank: n.toDouble(),
        title: '$n farklı varlık türü',
        body: 'Çeşitlendirme riski dağıtır. Portföyünde $n tür var.',
      ));
    }
    return out;
  }

  /// 100000 → "100 bin ₺", 1000000 → "1 milyon ₺"
  static String _kisaTutar(double v) {
    if (v >= 1000000) {
      final m = v / 1000000;
      final s = m == m.roundToDouble()
          ? m.toStringAsFixed(0)
          : m.toStringAsFixed(1).replaceAll('.', ',');
      return '$s milyon ₺';
    }
    return '${(v / 1000).toStringAsFixed(0)} bin ₺';
  }

  /// Kutlanacak TEK eşik.
  ///
  /// Ayda en fazla bir kutlama yapılır (bkz. RETENTION_STRATEJISI.md §5.E);
  /// birden çok yeni eşik varsa **en değerlisi** seçilir. Sıra: portföy
  /// Yaş kutlaması yalnız yıl dönümü bu kadar YAKINSA: zamanın geçmesiyle
  /// gelen bir an. Geçmiş tarihli alım girilince eşik anında aşılır —
  /// o bir an değil, veri girişi.
  static const yildonumuPenceresi = Duration(days: 14);

  /// Yeni geçilen eşikleri ikiye ayırır: KUTLANACAK olanlar ve yalnız
  /// kaydedilecek (sessiz) olanlar. Kayıt ikisi için de yapılır — yoksa
  /// aynı eşik sonra yeniden "yeni" görünürdü.
  ///
  /// Doğru zaman kuralları (2026-09-27, kullanıcı: "logout sonrası 2 yıldır
  /// birikimin var, 2 milyonu geçtin geldi — doğru yer ve zamanda gelmeli"):
  /// * [ilkKez]: kullanıcı HİÇ ölçülmemiş (sunucuda kaydı yok) — mevcut
  ///   portföyünü giriyordur. Canlı veride (26–27 Eylül) iki yeni kullanıcı
  ///   varlıklarını girer girmez "250 bin ₺ geçildi" / "25 bin ₺ geçildi"
  ///   gördü: geçilen bir eşik yok, veri girişi var ("birikimi kutla,
  ///   işlemi değil"). Hepsi sessiz; sonraki GERÇEK büyüme kutlanır.
  /// * [girisSonrasi]: girişten sonraki ilk YERLEŞİK ölçüm hepsini sessiz
  ///   kaydeder. Giriş bir başarı anı değil; hesaptaki birikmiş eşikleri
  ///   o an "yeni" diye art arda kutlamak bildirim yağmuruydu. Başka
  ///   cihaz, yeniden giriş ve sunucu geçişi (Frankfurt) bu dala düşer.
  /// * Yaş: yıl dönümü [yildonumuPenceresi] içinde değilse sessiz.
  /// * Geri kalanı (değer, altın, çeşitlilik) kutlanır — oturum içinde
  ///   gözlenmiş bir geçiştir.
  ///
  /// SAF — yer (ana ekran mı) ve kullanıcı kontrolleri çağıranda.
  ///
  /// Seri eşiği yalnız BU AYIN katkısı seriyi tam o eşiğe getirdiyse
  /// kutlanır ([seri] `buAyKatkiVar` ve `guncel == eşik`). Geçmiş tarihli
  /// alım girip seriyi geriye dönük uzatmak bir an değil, veri girişidir;
  /// bayrak açıldığında eski serisi olan kullanıcı da eşiklerini sessiz
  /// kaydeder.
  static ({List<Milestone> kutla, List<Milestone> sessiz}) ayir({
    required List<Milestone> yeniler,
    required List<Asset> assets,
    required DateTime now,
    required bool girisSonrasi,
    required bool ilkKez,
    BirikimSerisi? seri,
  }) {
    if (girisSonrasi || ilkKez) return (kutla: const [], sessiz: yeniler);
    final enEski = _enEskiAlim(_aktifGorunum(assets));
    final kutla = <Milestone>[];
    final sessiz = <Milestone>[];
    for (final m in yeniler) {
      if (m.kind == 'portfolio_age') {
        final yil = int.tryParse(m.value.replaceAll('y', '')) ?? 0;
        final yildonumu = enEski?.add(Duration(days: yil * 365));
        final yakin = yildonumu != null &&
            !now.isBefore(yildonumu) &&
            now.difference(yildonumu) <= yildonumuPenceresi;
        (yakin ? kutla : sessiz).add(m);
      } else if (m.kind == 'contribution_streak') {
        final ay = int.tryParse(m.value.replaceAll('m', '')) ?? 0;
        final simdi = seri != null && seri.buAyKatkiVar && seri.guncel == ay;
        (simdi ? kutla : sessiz).add(m);
      } else {
        kutla.add(m);
      }
    }
    return (kutla: kutla, sessiz: sessiz);
  }

  static List<Asset> _aktifGorunum(List<Asset> assets) => [
        for (final p in aggregatePositionsByOwner(
            [for (final l in lotlarSahibeGore(assets)) aktifLotlar(l)]))
          p.asDisplayAsset()
      ];

  static DateTime? _enEskiAlim(List<Asset> aktif) {
    DateTime? enEski;
    for (final a in aktif) {
      if (enEski == null || a.addedDate.isBefore(enEski)) enEski = a.addedDate;
    }
    return enEski;
  }

  /// yaşı (en nadir ve en duygusal) → birikim serisi → portföy değeri →
  /// altın → çeşitlendirme. Seri değerden önce: kullanıcının kendi
  /// davranışı, piyasanın getirdiği büyümeden daha doğru bir kutlama.
  ///
  /// Hepsini arka arkaya göstermek kutlamayı bildirim yağmuruna çevirirdi.
  static Milestone? pickOne(List<Milestone> yeniler) {
    if (yeniler.isEmpty) return null;
    const oncelik = [
      'portfolio_age',
      'contribution_streak',
      'portfolio_value',
      'gold_count',
      'diversification',
    ];
    for (final kind in oncelik) {
      final eslesen = yeniler.where((m) => m.kind == kind).toList();
      if (eslesen.isEmpty) continue;
      // Aynı türde birden çok yeni eşik varsa en yükseği kutlanır.
      // Sıralama `rank` ile: `value` metindir ve `'25000'` metin olarak
      // `'100000'`den büyüktür.
      eslesen.sort((a, b) => a.rank.compareTo(b.rank));
      return eslesen.last;
    }
    return yeniler.first;
  }
}
