import '../models/asset.dart';
import '../models/position.dart';
import '../utils/tr_format.dart';
import 'birikim_serisi.dart';
import 'para_agirlikli_getiri.dart' show getiriAkisi;

/// Geçilen bir kilometre taşı.
class Milestone {
  /// `portfolio_value` | `gold_count` | `portfolio_age` | `diversification`
  /// | `contribution_streak` | `profit_high`
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
    10000,
    25000,
    50000,
    100000,
    250000,
    500000,
    1000000,
    2500000,
    5000000,
    10000000,
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
      out.add(_seriTasi(ay));
    }
    return out;
  }

  static Milestone _seriTasi(int ay) => Milestone(
        kind: 'contribution_streak',
        value: '${ay}m',
        rank: ay.toDouble(),
        title: '$ay ay art arda birikim',
        body: ay >= 12
            ? '${ay ~/ 12} yıldır her ay portföyüne ekleme yapıyorsun. '
                'Düzen, piyasadan bağımsız tek şey.'
            : '$ay aydır her ay portföyüne ekleme yapıyorsun. Düzen, '
                'piyasadan bağımsız tek şey.',
      );

  static List<Milestone> _valueMilestones(double totalTRY) {
    final out = <Milestone>[];
    for (final esik in valueThresholds) {
      if (totalTRY < esik) break; // liste artan sıralı
      out.add(_degerTasi(esik));
    }
    return out;
  }

  static Milestone _degerTasi(double esik) => Milestone(
        kind: 'portfolio_value',
        value: esik.toStringAsFixed(0),
        rank: esik,
        title: '${_kisaTutar(esik)} geçildi',
        body: 'Portföyün ${_kisaTutar(esik)} sınırını aştı. Biriktirmeye '
            'devam.',
      );

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
        out.add(_altinTasi(sub, esik));
      }
    });
    return out;
  }

  static Milestone _altinTasi(String sub, int esik) {
    final etiket = _goldLabels[sub]!;
    return Milestone(
      kind: 'gold_count',
      value: '$sub:$esik',
      rank: esik.toDouble(),
      title: esik == 1 ? 'İlk $etiket' : '$esik $etiket',
      body: esik == 1
          ? 'Portföyüne ilk $etiket girdi.'
          : 'Toplam $esik $etiket biriktirdin.',
    );
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
      out.add(_yasTasi(yil));
    }
    return out;
  }

  static Milestone _yasTasi(int yil) => Milestone(
        kind: 'portfolio_age',
        value: '${yil}y',
        rank: yil.toDouble(),
        title: yil == 1 ? 'Portföyün 1 yaşında' : 'Portföyün $yil yaşında',
        // "yıldır takiptesin" DEĞİL: tarih kullanıcının girdiği İŞLEM
        // tarihidir, uygulamayı ne zamandır kullandığı değil. Geçmiş tarihli
        // alım girip birkaç haftadır kullanan kullanıcıya "2 yıldır
        // takiptesin" denmişti (2026-09-27). Söylenen, bilinen tek gerçek.
        body: 'İlk alımın $yil yıl önceydi. Sabır bu işin yarısı.',
      );

  static List<Milestone> _diversificationMilestones(List<Asset> aktif) {
    final turler = aktif.map((a) => a.type).toSet();
    final out = <Milestone>[];
    for (final n in typeCounts) {
      if (turler.length < n) break;
      out.add(_cesitTasi(n));
    }
    return out;
  }

  // Gövde "Portföyünde n tür var" değil: rozet şeridi bu taşı geçmişten de
  // gösterir ve kullanıcı bugün daha az türde olabilir.
  static Milestone _cesitTasi(int n) => Milestone(
        kind: 'diversification',
        value: '${n}types',
        rank: n.toDouble(),
        title: '$n farklı varlık türü',
        body: 'Çeşitlendirme riski dağıtır. Portföyün $n türe ulaştı.',
      );

  // ---------------------------------------------------------------------
  // Rozet şeridi (Profil, Ar-Ge 1 Kas 20:45 #1; yasin: ücretsiz)
  // ---------------------------------------------------------------------

  /// Sunucudaki kayıttan (`kind`, `value`) taşı yeniden kurar. Tanınmayan
  /// ya da artık listede olmayan eşik `null` döner: rozet uydurulmaz.
  static Milestone? anahtardan(String kind, String value) {
    switch (kind) {
      case 'portfolio_value':
        final v = double.tryParse(value);
        return v != null && valueThresholds.contains(v) ? _degerTasi(v) : null;
      case 'gold_count':
        final i = value.lastIndexOf(':');
        if (i <= 0) return null;
        final sub = value.substring(0, i);
        final n = int.tryParse(value.substring(i + 1));
        return n != null &&
                _goldLabels.containsKey(sub) &&
                goldCountThresholds.contains(n)
            ? _altinTasi(sub, n)
            : null;
      case 'portfolio_age':
        final y = int.tryParse(value.replaceAll('y', ''));
        return y != null && ageYears.contains(y) ? _yasTasi(y) : null;
      case 'diversification':
        final n = int.tryParse(value.replaceAll('types', ''));
        return n != null && typeCounts.contains(n) ? _cesitTasi(n) : null;
      case 'contribution_streak':
        final ay = int.tryParse(value.replaceAll('m', ''));
        return ay != null && streakMonths.contains(ay) ? _seriTasi(ay) : null;
      // `profit_high` bilerek rozete dönmez: "en yüksek seviyesinde" bir
      // ANIN cümlesidir, kalıcı bir eşik değil. Şeritte haftalar sonra
      // aynı cümleyi göstermek, kâr o zirveden inmişken yanlış olurdu.
      // Kayıt yalnız bir sonraki zirvenin kıyas tabanıdır ([karZirvesi]).
    }
    return null;
  }

  /// Kazanılan taşlar + sıradaki tek hedef.
  ///
  /// **Geçilen eşik kalıcıdır** (müşteri raporu 1 Kas 21:15 koşulu):
  /// kaynak sunucudaki kayıt ([kayitli], `kind:value`) ile bugünkü hesabın
  /// ([bugun]) birleşimi. Piyasa düşüp toplam 100 binin altına inse de
  /// "100 bin ₺ geçildi" rozeti kaybolmaz; kutlanan şey bir andı.
  ///
  /// Sıra [pickOne] önceliği (yaş → seri → değer → altın → çeşitlilik),
  /// tür içinde büyükten küçüğe.
  ///
  /// Sıradaki hedef yalnız portföy değeri eşiğidir: herkes için anlamlı tek
  /// ölçek ve bugünkü veriden hesaplanır (uydurma sayı yok). Hepsi geçildiyse
  /// `null`.
  ///
  /// [ilerleme] ve [kalan] (Ar-Ge 5 Kas 21:00 #1, müşteri YAP): "Sıradaki
  /// 500 bin ₺" boş bir bayraktı; kişi hedefe ne kadar yakın olduğunu
  /// bilmiyordu (Midas/Papara hedef kartı, Strava "sıradakine X kaldı").
  /// İlerleme = bugünkü toplam / eşik (0–1); kalan = eşik − toplam. Toplam
  /// bilinmiyorsa (≤ 0) ikisi de `null`, bayrak eskisi gibi çizilir.
  /// Kayıtlı yüksek eşik toplamın üstündeyse (piyasa düştü) sıradaki daha
  /// büyük eşiktir; ilerleme yine bugünkü toplamdan, uydurma yok.
  static ({
    List<Milestone> kazanilan,
    Milestone? siradaki,
    double? ilerleme,
    double? kalan,
  }) koleksiyon({
    required Set<String> kayitli,
    required List<Milestone> bugun,
    required double totalTRY,
  }) {
    final hepsi = <Milestone>{...bugun};
    for (final k in kayitli) {
      final i = k.indexOf(':');
      if (i <= 0) continue;
      final m = anahtardan(k.substring(0, i), k.substring(i + 1));
      if (m != null) hepsi.add(m);
    }
    const oncelik = [
      'portfolio_age',
      'contribution_streak',
      'portfolio_value',
      'gold_count',
      'diversification',
    ];
    final kazanilan = hepsi.toList()
      ..sort((a, b) {
        final t = oncelik.indexOf(a.kind).compareTo(oncelik.indexOf(b.kind));
        return t != 0 ? t : b.rank.compareTo(a.rank);
      });

    var enYuksek = totalTRY;
    for (final m in kazanilan) {
      if (m.kind == 'portfolio_value' && m.rank > enYuksek) enYuksek = m.rank;
    }
    Milestone? siradaki;
    for (final esik in valueThresholds) {
      if (esik > enYuksek) {
        siradaki = Milestone(
          kind: 'portfolio_value',
          value: esik.toStringAsFixed(0),
          rank: esik,
          title: _kisaTutar(esik),
          body: 'Portföyün ${_kisaTutar(esik)} sınırını geçtiğinde bu taş '
              'açılır.',
        );
        break;
      }
    }
    final bilinir = siradaki != null && totalTRY > 0;
    return (
      kazanilan: kazanilan,
      siradaki: siradaki,
      ilerleme: bilinir ? (totalTRY / siradaki.rank).clamp(0.0, 1.0) : null,
      kalan: bilinir ? siradaki.rank - totalTRY : null,
    );
  }

  /// Kalan tutarın kısa yazımı: 70.000 → "70 bin ₺", 1.250.000 →
  /// "1,3 milyon ₺"; binin altı "1 bin ₺"ün altında kalmasın diye en az
  /// "1 bin ₺" (yuvarlama yukarı: "kaldı" az söylemesin).
  static String kalanKisa(double v) {
    if (v >= 1000000) return _kisaTutar(v);
    final bin = (v / 1000).ceil();
    return '${bin < 1 ? 1 : bin} bin ₺';
  }

  /// Profil satırındaki "8 / 10": portföy değeri merdiveninde kaçıncı
  /// basamaktasın (Profil yeniden tasarımı, yasin 7 Kas).
  ///
  /// Payda [valueThresholds] uzunluğudur, uydurma bir "toplam rozet" sayısı
  /// değil: altın adedi ve yaş taşlarının üst sınırı kişiye göre değişir,
  /// onlarla kurulan bir payda her ay oynardı. Değer merdiveni herkes için
  /// aynı ve sıradaki taş da ondan seçiliyor ([koleksiyon]); satırdaki iki
  /// sayı aynı ölçekten konuşur. Sıradaki taşın altındaki bütün eşikler
  /// geçilmiştir (bugün ya da sunucu kaydıyla); sıradaki yoksa hepsi.
  static ({int gecilen, int toplam}) esikSayaci(Milestone? siradaki) {
    final toplam = valueThresholds.length;
    if (siradaki == null) return (gecilen: toplam, toplam: toplam);
    final i = valueThresholds.indexOf(siradaki.rank);
    return (gecilen: i < 0 ? 0 : i, toplam: toplam);
  }

  /// Şeritte gösterilecekler: her türün (altında her altın cinsinin) en
  /// yükseği. "10 bin, 25 bin, 50 bin geçildi" yan yana tekrar olurdu;
  /// tamamı "Tümü" sayfasında.
  static List<Milestone> vitrin(List<Milestone> kazanilan) {
    final gorulen = <String>{};
    final out = <Milestone>[];
    for (final m in kazanilan) {
      final grup = m.kind == 'gold_count'
          ? 'gold:${m.value.substring(0, m.value.lastIndexOf(':'))}'
          : m.kind;
      if (gorulen.add(grup)) out.add(m);
    }
    return out;
  }

  /// Bakiye gizliyken gösterilecek hâli: tutar taşıyan taşın başlığı ve
  /// gövdesi tutarsız yazılır (müşteri raporu 1 Kas 21:15 koşulu). Altın
  /// adedi, yaş ve tür sayısı tutar değildir, aynen kalır.
  static Milestone gizli(Milestone m, {bool siradaki = false}) {
    // Kâr zirvesinin başlığı tutar taşır ("...: ₺X"); bakiye gizliyken o da
    // çıkar (10 Kas: rozet adları Profil satırında görünür oldu).
    if (m.kind == 'profit_high') {
      return Milestone(
        kind: m.kind,
        value: m.value,
        rank: m.rank,
        title: 'Toplam kârın en yüksek seviyesinde',
        body: 'Bakiye gizliyken tutar gösterilmez.',
      );
    }
    if (m.kind != 'portfolio_value') return m;
    return Milestone(
      kind: m.kind,
      value: m.value,
      rank: m.rank,
      title: siradaki ? 'Portföy eşiği' : 'Portföy eşiği geçildi',
      body: 'Bakiye gizliyken tutar gösterilmez.',
    );
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

  // ---------------------------------------------------------------------
  // Toplam kâr zirvesi (müşteri raporu 10 Kas; ücretsiz)
  // ---------------------------------------------------------------------

  /// Kâr zirvesi taşının türü. Sunucu `milestones.kind` sütununda serbest
  /// metin; şema değişmedi. Eski sürüm bu türü tanımaz ve [anahtardan]
  /// `null` döndüğü için yok sayar (geri uyumlu).
  static const karZirvesiTuru = 'profit_high';

  /// Seri en az bu kadar geriye gitmeli. Birkaç günlük portföyde her
  /// küçük oynama "en yüksek kâr" olurdu; an değil gürültü.
  static const karZirvesiAsgariGecmis = Duration(days: 30);

  /// Yeni kâr önceki zirveyi en az %5 aşmalı. Zirveye yakın gezinen
  /// portföy her gün bir kuruş yeni rekor kırar; eşiksiz taş her hafta
  /// gelir ve anlamını yitirirdi.
  static const karZirvesiArtis = 1.05;

  /// İki kâr zirvesi kaydı arasında en az bu kadar süre. Aylık kutlama
  /// sınırı (`MilestoneRepository.canCelebrate`) ayrıca geçerli; bu sınır
  /// sessiz kayıtların da sıklığını tutar.
  static const karZirvesiAraligi = Duration(days: 7);

  /// Günlük ızgarada iki nokta arasında kabul edilen en büyük boşluk.
  /// Izgara hafta sonunu da üretir (`HistoryService.gridSlotlari`); daha
  /// büyük boşluk eksik veridir.
  static const _karAzamiBosluk = Duration(days: 2);

  /// Kayıtlı kâr zirvelerinin en yükseği ve en son kaydın günü.
  ///
  /// Kayıt biçimi `profit_high:YYYY-MM-DD:tutar` (tutar tam ₺, eksi
  /// olabilir). Ayrı bir tercih anahtarı yerine mevcut `milestones`
  /// tablosu kullanıldı: diğer taşlar gibi cihazlar arası taşınır, yeni
  /// kalıcılık katmanı ve göç gerekmez. Bozuk satır yok sayılır.
  static ({double? zirve, DateTime? sonGun}) karZirvesiKaydi(
      Set<String> kayitli) {
    double? zirve;
    DateTime? sonGun;
    const onek = '$karZirvesiTuru:';
    for (final k in kayitli) {
      if (!k.startsWith(onek)) continue;
      final parca = k.substring(onek.length);
      final i = parca.lastIndexOf(':');
      if (i <= 0) continue;
      final gun = DateTime.tryParse(parca.substring(0, i));
      final tutar = double.tryParse(parca.substring(i + 1));
      if (gun == null || tutar == null) continue;
      if (zirve == null || tutar > zirve) zirve = tutar;
      if (sonGun == null || gun.isAfter(sonGun)) sonGun = gun;
    }
    return (zirve: zirve, sonGun: sonGun);
  }

  /// Haftalık sınır dolmadı mı? Çağıran seriyi indirmeden önce bakar;
  /// sınır doluysa ağa hiç çıkılmaz.
  static bool karZirvesiBekleyebilir(Set<String> kayitli, DateTime now) {
    final son = karZirvesiKaydi(kayitli).sonGun;
    return son == null || dayKey(now).difference(son) >= karZirvesiAraligi;
  }

  /// Toplam kâr yeni bir zirvede mi?
  ///
  /// **Kâr = portföy değeri − net yatırılan**, Performans grafiğinin
  /// "Yatırdığın" çizgisiyle aynı tanım: değer [seri]'den (Performans'ın
  /// kanonik serisi, `DonemOzetiYukleyici.seri`; yeni fiyat merdiveni
  /// kurulmaz, fiyat kaynağı sözleşmesi), net yatırılan [lotlar]ın serinin
  /// son gününe kadarki `getiriAkisi` toplamı (alım +, satış ele geçen −,
  /// nakit temettü −). Para yatırmak değeri de net yatırılanı da aynı
  /// tutarda artırır; kâr değişmez, taş açılmaz ("birikimi kutla, işlemi
  /// değil" ilkesinin piyasa tarafı: kutlanan şey piyasanın getirisi).
  ///
  /// `null` döner (taş yok) eğer:
  /// * [eksikBilesen] (bir bileşenin fiyatı hiç gelmedi, seri tohumla
  ///   taşındı) ya da seride boşluk, sıfır, sonsuz değer var — uydurma
  ///   sayıyla zirve ilan edilmez;
  /// * seri [karZirvesiAsgariGecmis]'ten kısa ya da son noktası bayat;
  /// * son kayıt [karZirvesiAraligi] içinde;
  /// * önceki zirve varken yeni kâr ≤ 0 ya da ≤ zirve × [karZirvesiArtis].
  ///
  /// Hiç kayıt yoksa `ilk: true` döner: taban kaydedilir, kutlanmaz.
  /// Özelliğin ilk açıldığı gün kârda olan herkese "zirvedesin" demek bir
  /// an değil, veri girişi olurdu (`ayir` içindeki `ilkKez` ile aynı ilke).
  static ({Milestone tas, bool ilk})? karZirvesi({
    required Map<int, double> seri,
    required List<Asset> lotlar,
    required Set<String> kayitli,
    required DateTime now,
    bool eksikBilesen = false,
  }) {
    if (eksikBilesen || seri.isEmpty) return null;
    final ts = seri.keys.toList()..sort();
    // Baştaki sıfırlar veri yokluğudur (ilk alımdan önce); sonrasındaki
    // her nokta ölçüm olmalı.
    var bas = 0;
    while (bas < ts.length && (seri[ts[bas]] ?? 0) <= 0) {
      bas++;
    }
    if (bas >= ts.length) return null;
    for (var i = bas; i < ts.length; i++) {
      final y = seri[ts[i]];
      if (y == null || !y.isFinite || y <= 0) return null;
      if (i > bas &&
          ts[i] - ts[i - 1] > _karAzamiBosluk.inMilliseconds) {
        return null;
      }
    }
    final ilkAn = DateTime.fromMillisecondsSinceEpoch(ts[bas]);
    final sonAn = DateTime.fromMillisecondsSinceEpoch(ts.last);
    if (sonAn.difference(ilkAn) < karZirvesiAsgariGecmis) return null;
    if (dayKey(now).difference(dayKey(sonAn)) > _karAzamiBosluk) return null;

    final kayit = karZirvesiKaydi(kayitli);
    if (!karZirvesiBekleyebilir(kayitli, now)) return null;

    final sonGunMs = dayKey(sonAn).millisecondsSinceEpoch;
    var net = 0.0;
    for (final a in lotlar) {
      if (dayKey(a.addedDate).millisecondsSinceEpoch <= sonGunMs) {
        net += getiriAkisi(a);
      }
    }
    final kar = seri[ts.last]! - net;
    final tas = _karTasi(dayKey(now), kar.roundToDouble());

    final zirve = kayit.zirve;
    if (zirve == null) return (tas: tas, ilk: true);
    if (kar <= 0 || kar <= zirve * karZirvesiArtis) return null;
    return (tas: tas, ilk: false);
  }

  static Milestone _karTasi(DateTime gun, double kar) {
    final g = '${gun.year.toString().padLeft(4, '0')}-'
        '${gun.month.toString().padLeft(2, '0')}-'
        '${gun.day.toString().padLeft(2, '0')}';
    // Başlık ve gövde burada Türkçe yedektir; kutlama sayfası bu türü
    // `context.l10n` ile yazar (İngilizce arayüz), tutar [rank]'tan.
    return Milestone(
      kind: karZirvesiTuru,
      value: '$g:${kar.toStringAsFixed(0)}',
      rank: kar,
      title: 'Toplam kârın en yüksek seviyesinde: ${fmtTRY(kar)}',
      body: 'Kâr, portföy değerinden yatırdığın net tutar çıkarılarak '
          'bulunur.',
    );
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
    // `profit_high` en sonda: piyasanın getirdiği bir an, kullanıcının
    // kendi birikiminden (değer, altın, çeşitlilik) önce gelmez.
    for (final kind in [...oncelik, karZirvesiTuru]) {
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
