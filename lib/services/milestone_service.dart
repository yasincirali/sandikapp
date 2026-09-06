import '../models/asset.dart';

/// Geçilen bir kilometre taşı.
class Milestone {
  /// `portfolio_value` | `gold_count` | `portfolio_age` | `diversification`
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
  };

  /// Portföy yaşı eşikleri (yıl).
  static const ageYears = <int>[1, 2, 3, 5, 10];

  /// Kaç farklı varlık TÜRÜ eşiği.
  static const typeCounts = <int>[3, 5];

  /// Portföyün geçtiği tüm eşikler.
  ///
  /// [now] test için enjekte edilir.
  static List<Milestone> evaluate({
    required List<Asset> assets,
    required double totalTRY,
    required DateTime now,
  }) {
    final aktif = assets.where((a) => a.isBuy && a.isActive).toList();
    if (aktif.isEmpty) return const [];

    return [
      ..._valueMilestones(totalTRY),
      ..._goldMilestones(aktif),
      ..._ageMilestones(aktif, now),
      ..._diversificationMilestones(aktif),
    ];
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
    DateTime? enEski;
    for (final a in aktif) {
      if (enEski == null || a.addedDate.isBefore(enEski)) enEski = a.addedDate;
    }
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
        body: 'Sabır bu işin yarısı — $yil yıldır takiptesin.',
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
  /// yaşı (en nadir ve en duygusal) → portföy değeri → altın → çeşitlendirme.
  ///
  /// Hepsini arka arkaya göstermek kutlamayı bildirim yağmuruna çevirirdi.
  static Milestone? pickOne(List<Milestone> yeniler) {
    if (yeniler.isEmpty) return null;
    const oncelik = [
      'portfolio_age',
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
