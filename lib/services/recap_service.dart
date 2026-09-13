import '../models/asset.dart';
import '../models/asset_type.dart';

/// Portföyün karakteri — paylaşılabilirliğin çekirdeği.
///
/// İnsanlar veriyi değil KİMLİĞİ paylaşır. "Portföyüm %12 arttı" kimseye
/// anlatılmaz; "Ben Altıncıyım" anlatılır. Spotify Wrapped'in işleyen
/// parçası da buydu.
enum PortfolioCharacter {
  altinci('Altıncı', 'Sarının gücüne inanıyorsun'),
  dovizci('Dövizci', 'Kurları yakından izliyorsun'),
  hisseci('Hisseci', 'Borsada oyuncusun'),
  foncu('Fon Yatırımcısı', 'İşi profesyonellere bırakıyorsun'),
  emtiaci('Emtiacı', 'Alışılmadık bir yol seçtin'),
  mevduatci('Mevduatçı', 'Güvenli limanı tercih ediyorsun'),
  dengeli('Dengeli', 'Yumurtaları tek sepete koymuyorsun');

  final String label;
  final String tagline;
  const PortfolioCharacter(this.label, this.tagline);
}

/// Bir varlığın özet içindeki payı.
class RecapAsset {
  final String name;
  final double changePct;
  const RecapAsset(this.name, this.changePct);
}

/// Özetin tüm içeriği.
///
/// Alanların çoğu NULLABLE: veri yetersizse o sayfa hiç gösterilmez.
/// Eksik veriyi sıfırla doldurmak, kullanıcıya yanlış bir yıl anlatırdı.
class RecapData {
  /// `monthly` | `yearly`
  final String period;

  /// Dönem başındaki ve sonundaki portföy değeri (TRY). Snapshot yoksa null.
  final double? startTotalTRY;
  final double? endTotalTRY;

  /// Dönem içindeki değişim yüzdesi. Uçlardan biri yoksa null.
  final double? changePct;

  /// Portföydeki en çok kazandıran / kaybettiren varlık.
  ///
  /// **Ömürlük getiridir, döneme ait değil**: üç yıl önce alınmış bir varlığın
  /// bu yılki getirisi elimizde yok. Ekranda da öyle etiketlenir.
  final RecapAsset? bestAsset;
  final RecapAsset? worstAsset;

  final PortfolioCharacter character;

  /// Kaç ayrı GÜN portföye bakıldı (snapshot atılan gün sayısı).
  final int trackedDays;

  /// En uzun tutulan varlık ve kaç gündür tutulduğu.
  final RecapAsset? mostPatient;
  final int? mostPatientDays;

  /// Portföydeki farklı varlık türü sayısı.
  final int typeCount;

  /// Enflasyonun kaç puan önünde/gerisinde. Endeks yoksa null.
  final double? inflationSpread;

  const RecapData({
    required this.period,
    required this.character,
    required this.trackedDays,
    required this.typeCount,
    this.startTotalTRY,
    this.endTotalTRY,
    this.changePct,
    this.bestAsset,
    this.worstAsset,
    this.mostPatient,
    this.mostPatientDays,
    this.inflationSpread,
  });

  /// Gösterilmeye değer mi?
  ///
  /// Tek başına bir karakter etiketi özet değildir. En az bir gerçek sayı
  /// olmalı — yoksa kullanıcı boş bir kutlama görür ve özelliği ciddiye almaz.
  bool get isMeaningful =>
      changePct != null || bestAsset != null || trackedDays >= 5;
}

/// Yıllık/aylık "sandık Özeti" hesabı.
///
/// Tamamı saf: girdi varlıklar + snapshot serisi, çıktı [RecapData].
/// Ağ, kalıcılık ve ekran çağıranın işi.
class RecapService {
  RecapService._();

  /// Bir tür portföyün bu oranını geçerse karakter o tür olur.
  ///
  /// %50 seçildi: "çoğunluk" sezgisiyle örtüşüyor. Daha düşük bir eşik
  /// (%40) dengeli bir portföyü yanlışlıkla etiketler; daha yükseği
  /// (%70) neredeyse herkesi "Dengeli" yapar ve etiket ayırt ediciliğini
  /// kaybeder — paylaşılabilirliğin tamamı ayırt edicilikte.
  static const characterThreshold = 0.5;

  /// Yıllık özetin gösterildiği pencere.
  ///
  /// **26 Aralık — 10 Ocak.** 31 Aralık DEĞİL: Wrapped'in erken çıkma sebebi
  /// yıl sonu gürültüsünden önce olmak. 31'inde herkesin akışı yılbaşı
  /// mesajıyla dolu ve paylaşım oranı düşer.
  ///
  /// Ocak'a taşması kasıtlı: tatilde uygulamayı açmayan kullanıcı özetini
  /// tamamen kaçırmasın.
  static bool isYearlyWindow(DateTime now) =>
      (now.month == 12 && now.day >= 26) || (now.month == 1 && now.day <= 10);

  /// Özetin ait olduğu yıl.
  ///
  /// Ocak'ta açılan özet BİR ÖNCEKİ yılındır — 3 Ocak'ta "2027 Özetin"
  /// demek üç günlük bir yılı özetlemek olurdu.
  static int yearFor(DateTime now) => now.month == 1 ? now.year - 1 : now.year;

  static PortfolioCharacter characterFor(Map<AssetType, double> valueByType) {
    final toplam = valueByType.values.fold<double>(0, (a, b) => a + b);
    if (toplam <= 0) return PortfolioCharacter.dengeli;

    AssetType? enBuyuk;
    double enBuyukDeger = 0;
    valueByType.forEach((tur, deger) {
      if (deger > enBuyukDeger) {
        enBuyukDeger = deger;
        enBuyuk = tur;
      }
    });
    if (enBuyuk == null) return PortfolioCharacter.dengeli;
    if (enBuyukDeger / toplam < characterThreshold) {
      return PortfolioCharacter.dengeli;
    }

    return switch (enBuyuk!) {
      AssetType.altin => PortfolioCharacter.altinci,
      AssetType.doviz => PortfolioCharacter.dovizci,
      AssetType.hisse => PortfolioCharacter.hisseci,
      AssetType.fon => PortfolioCharacter.foncu,
      AssetType.emtia => PortfolioCharacter.emtiaci,
      AssetType.mevduat => PortfolioCharacter.mevduatci,
      AssetType.diger => PortfolioCharacter.dengeli,
    };
  }

  /// Snapshot serisinden kaç AYRI GÜN kayıt olduğu.
  ///
  /// Gün sayılır, kayıt değil: uygulamayı bir günde on kez açan kullanıcı
  /// "10 gün takip ettin" görmemeli.
  static int distinctDays(List<({int ts, Map<String, double> values})> seri) {
    final gunler = <int>{};
    for (final s in seri) {
      final t = DateTime.fromMillisecondsSinceEpoch(s.ts);
      gunler.add(
        DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch ~/
            Duration.millisecondsPerDay,
      );
    }
    return gunler.length;
  }

  /// Snapshot'ın toplam TRY değeri (tüm kategorilerin toplamı).
  static double snapshotTotal(Map<String, double> values) =>
      values.values.fold<double>(0, (a, b) => a + b);

  static RecapData compute({
    required String period,
    required List<Asset> assets,
    required List<({int ts, Map<String, double> values})> snapshots,
    required double Function(double value, String currency) toTRY,
    required DateTime now,
    double? inflationPct,
  }) {
    final aktif = assets.where((a) => a.isBuy && a.isActive).toList();

    // ── Tür dağılımı ────────────────────────────────────────────────────
    final valueByType = <AssetType, double>{};
    for (final a in aktif) {
      valueByType[a.type] =
          (valueByType[a.type] ?? 0) + toTRY(a.totalValue, a.currency);
    }

    // ── Dönem uçları ────────────────────────────────────────────────────
    final sirali = [...snapshots]..sort((a, b) => a.ts.compareTo(b.ts));
    final basTotal = sirali.isEmpty ? null : snapshotTotal(sirali.first.values);
    final sonTotal = sirali.isEmpty ? null : snapshotTotal(sirali.last.values);
    double? degisim;
    if (basTotal != null && sonTotal != null && basTotal > 0) {
      degisim = (sonTotal / basTotal - 1) * 100;
    }

    // ── En iyi / en kötü ────────────────────────────────────────────────
    //
    // Maliyeti olmayan varlık elenir: `gainLossPercentage` payda sıfırken
    // 0 döner ve gerçek bir "değişmedi" ile ayırt edilemez.
    final olculebilir = aktif.where((a) => a.totalCost > 0).toList();
    RecapAsset? enIyi;
    RecapAsset? enKotu;
    if (olculebilir.isNotEmpty) {
      final sirali2 = [...olculebilir]
        ..sort((a, b) => a.gainLossPercentage.compareTo(b.gainLossPercentage));
      final ilk = sirali2.first;
      final son = sirali2.last;
      if (son.gainLossPercentage > 0) {
        enIyi = RecapAsset(son.name, son.gainLossPercentage);
      }
      // En kötü yalnızca GERÇEKTEN kayıptaysa gösterilir. Kârdaki bir
      // varlığı "en kötün" diye sunmak kutlamayı azarlamaya çevirir.
      if (ilk.gainLossPercentage < 0 && ilk != son) {
        enKotu = RecapAsset(ilk.name, ilk.gainLossPercentage);
      }
    }

    // ── En sabırlı ──────────────────────────────────────────────────────
    Asset? enEski;
    for (final a in aktif) {
      if (enEski == null || a.addedDate.isBefore(enEski.addedDate)) enEski = a;
    }

    return RecapData(
      period: period,
      startTotalTRY: basTotal,
      endTotalTRY: sonTotal,
      changePct: degisim,
      bestAsset: enIyi,
      worstAsset: enKotu,
      character: characterFor(valueByType),
      trackedDays: distinctDays(snapshots),
      mostPatient: enEski == null ? null : RecapAsset(enEski.name, 0),
      mostPatientDays:
          enEski == null ? null : now.difference(enEski.addedDate).inDays,
      typeCount: valueByType.keys.length,
      inflationSpread: (degisim != null && inflationPct != null)
          ? degisim - inflationPct
          : null,
    );
  }

  /// Bir yüzdeyi paylaşım metninde kullanılacak biçime getirir.
  ///
  /// Virgüllü ve tek ondalıklı: "12,4". Türkçe ondalık ayırıcı virgüldür ve
  /// paylaşılan metin ekran görüntüsü gibi okunuyor.
  static String _yuzde(double v) =>
      v.abs().toStringAsFixed(1).replaceAll('.', ',');

  /// Paylaşım metninin ÇEKİRDEĞİ — tek kaynak.
  ///
  /// ## Neden skaler parametreler, neden ortak bir arayüz değil
  /// İki çağıran var ve veri şekilleri örtüşmüyor: [RecapData] `character`'ı
  /// ZORUNLU taşıyor ve `trackedDays` var; `PeriodSummary`'de karakter ayrı
  /// bir parametre olarak geliyor (ekranda öyle) ve takip günü kavramı yok.
  /// İkisine ortak bir taban sınıf ya da arayüz uydurmak, yalnızca bu metin
  /// için var olan yapay bir hiyerarşi üretirdi. Çıkarılmış skalerler
  /// almak ikisini de sadeleştiriyor.
  ///
  /// ## TUTAR YOKTUR — pazarlıksız
  /// Yüzde ve etiket yeter: **tutarlı bir kart paylaşılmaz, tutarsız kart
  /// paylaşılır.** Paylaşılabilirlik bu özelliğin tek amacı, dolayısıyla
  /// kuralın da tek bekçisi bu fonksiyon. Bu yüzden imza TRY taşıyan hiçbir
  /// alan KABUL ETMİYOR — çağıran taraf yanlışlıkla tutar geçemiyor.
  /// (`recap_service_test` bunu ayrıca kovalıyor: `₺` yok ve yıl dışında
  /// dört haneli sayı yok.)
  ///
  /// [baslik] "sandık Özetim 2026" ya da "sandık · Bu ay" gibi tek satır.
  /// Yıl DIŞINDA dört haneli sayı içermemeli, yoksa tutar sanılır.
  static String composeShareText({
    required String baslik,
    PortfolioCharacter? karakter,
    double? degisimPct,
    String degisimEtiketi = 'Portföy değişimi',
    double? enflasyonPuan,
    int? takipGunu,
  }) {
    final satirlar = <String>[baslik, ''];

    if (karakter != null) {
      satirlar.add('${karakter.label} — ${karakter.tagline}');
    }
    if (degisimPct != null) {
      final yon = degisimPct >= 0 ? '+' : '−';
      satirlar.add('$degisimEtiketi: $yon%${_yuzde(degisimPct)}');
    }
    if (enflasyonPuan != null) {
      satirlar.add(enflasyonPuan >= 0
          ? 'Enflasyonun ${_yuzde(enflasyonPuan)} puan önündeyim'
          : 'Enflasyonun ${_yuzde(enflasyonPuan)} puan gerisindeyim');
    }
    if (takipGunu != null && takipGunu > 0) {
      satirlar.add('$takipGunu gün takip ettim');
    }

    satirlar
      ..add('')
      ..add('sandık ile takip ediyorum');
    return satirlar.join('\n');
  }

  /// Yıllık özetin paylaşım metni.
  ///
  /// [composeShareText]'e delege eder; biçim kuralları orada.
  static String shareText(RecapData d, {required int year}) => composeShareText(
        baslik: 'sandık Özetim $year',
        karakter: d.character,
        degisimPct: d.changePct,
        enflasyonPuan: d.inflationSpread,
        takipGunu: d.trackedDays,
      );
}
