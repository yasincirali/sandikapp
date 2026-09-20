import '../config/magaza.dart';
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

  /// Son 12 ayın nakit akışı düzeltmeli PİYASA getirisi (yüzde) —
  /// `RealReturnService.yillikPiyasaGetirisi`. [changePct]'ten farkı:
  /// o portföy DEĞERİNİN değişimi (katkı dahil), bu piyasanın varlıklara
  /// ne yaptığı. Enflasyon karşılaştırması BUNUN üzerinden yapılır ki ana
  /// ekran rozeti ve Performans kartıyla aynı puan çıksın. Seri yoksa null.
  final double? marketReturnPct;

  /// Enflasyonun kaç puan önünde/gerisinde: [marketReturnPct] − TÜFE.
  /// Endeks ya da piyasa getirisi yoksa null.
  final double? inflationSpread;

  /// [inflationSpread]'in ölçüldüğü GERÇEK pencere.
  ///
  /// **Özetin başlığıyla aynı aralık DEĞİL (2026-09-16).** Başlık takvim
  /// yılını söyler ("Özetim 2026") ve [changePct] gerçekten 1 Ocak'tan beri
  /// ölçülür. Enflasyon sayfası ise son 12 AYIN kayan penceresidir ve TÜFE
  /// aylık yayımlandığı için son açıklanan ayda biter — 31 Aralık'ta
  /// açıldığında pencere 30 Kasım'da kapanır, yani Aralık 2025 içeride,
  /// Aralık 2026 dışarıda kalır.
  ///
  /// İki pencereyi eşitlemek mümkün değil: takvim yılının Aralık TÜFE'si
  /// ertesi ayın 3'ünde yayımlanıyor, o tarihe kadar sayfa hiç
  /// gösterilemezdi. Bu yüzden pencere olduğu gibi kalıyor ve UÇLARI
  /// yazılıyor — sayfa hangi aralığı ölçtüğünü söylemek zorunda, yoksa
  /// kullanıcı başlıktaki yılı varsayar.
  final DateTime? inflationStart;
  final DateTime? inflationEnd;

  /// Bugünkü tür dağılımı (TRY). Paylaşım kartı bunu yalnızca ORAN olarak
  /// çizer (dağılım şeridi) — tutar kartta yoktur, kural `share_card_test`
  /// ile kilitli. Boşsa şerit çizilmez.
  final Map<AssetType, double> valueByType;

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
    this.marketReturnPct,
    this.inflationSpread,
    this.inflationStart,
    this.inflationEnd,
    this.valueByType = const {},
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
    double? marketReturnPct,
    DateTime? inflationStart,
    DateTime? inflationEnd,
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
      valueByType: valueByType,
      marketReturnPct: marketReturnPct,
      // Portföy değeri değişimi (`degisim`) DEĞİL, piyasa getirisi:
      // katkının şişirdiği bir rakamı TÜFE ile kıyaslamak, para yatıran
      // herkesi "enflasyonu yendi" gösterirdi ve ana ekranla tutmazdı.
      inflationSpread: (marketReturnPct != null && inflationPct != null)
          ? marketReturnPct - inflationPct
          : null,
      // Uçlar farkla BİRLİKTE taşınır: fark tek başına hangi aralığı
      // ölçtüğünü söylemiyor ve başlıktaki yıl yanıltıcı (alan notuna bak).
      inflationStart: inflationStart,
      inflationEnd: inflationEnd,
    );
  }

  /// Bir yüzdeyi paylaşım metninde kullanılacak biçime getirir.
  ///
  /// Virgüllü ve tek ondalıklı: "12,4". Türkçe ondalık ayırıcı virgüldür ve
  /// paylaşılan metin ekran görüntüsü gibi okunuyor.
  /// Yüzdenin ondalık gövdesi ("12,4"). Ortak biçim: paylaşım metninin
  /// tamamı — açıklama satırları dahil — aynı yuvarlamayı kullanmalı,
  /// yoksa "36,5 − 31,5 = 5,0" çıkarması metin içinde tutmaz.
  static String yuzde(double v) =>
      v.abs().toStringAsFixed(1).replaceAll('.', ',');

  /// İşaretli yüzde: "+%12,4" / "−%3,1". Eksi işareti tipografik (U+2212),
  /// ekrandaki kartla aynı.
  static String isaretli(double v) => '${v >= 0 ? '+' : '−'}%${yuzde(v)}';

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
  ///
  /// ## Zengin satırlar (2026-09-16)
  /// Kartla AYNI kaynaktan beslenen ek satırlar: reel getiri, en iyi / en
  /// zayıf varlık, artıda kapanan gün oranı, yıllıklandırılmış getiri.
  /// Hepsi yüzde ya da gün sayısı — tutar kuralı değişmedi. Varlık adı
  /// olduğu gibi yazılır; adında dört haneli sayı olan bir varlık
  /// (ör. bir vade yılı) metinde tutar sanılabilir, ama adı kırpmak onu
  /// tanınmaz kılardı — bilinçli tercih.
  static String composeShareText({
    required String baslik,
    PortfolioCharacter? karakter,
    double? degisimPct,
    String degisimEtiketi = 'Portföy değişimi',
    double? enflasyonPuan,
    double? reelGetiriPct,
    RecapAsset? enIyi,
    RecapAsset? enZayif,
    ({int artida, int toplam})? gunSayimi,
    double? xirrPct,
    int? takipGunu,
    /// "Nasıl hesaplandı" bölümü için ham girdiler. Hepsi opsiyonel ve
    /// verilmeyen satır hiç yazılmaz (bkz. bölümün kendi notu).
    String? nominalPct,
    String? tufePct,
    String? donemAralik,
    String? nominalAralik,
    /// UTM kampanya etiketi (dönem adı gibi); ölçüm içindir, metne girmez.
    String kampanya = 'ozet',
  }) {
    final satirlar = <String>[baslik, ''];

    if (karakter != null) {
      satirlar.add('${karakter.label} — ${karakter.tagline}');
    }
    if (degisimPct != null) {
      satirlar.add('$degisimEtiketi: ${isaretli(degisimPct)}');
    }
    if (enflasyonPuan != null) {
      final reel =
          reelGetiriPct == null ? '' : ' (reel ${isaretli(reelGetiriPct)})';
      satirlar.add(enflasyonPuan >= 0
          ? 'Enflasyonun ${yuzde(enflasyonPuan)} puan önündeyim$reel'
          : 'Enflasyonun ${yuzde(enflasyonPuan)} puan gerisindeyim$reel');
    }
    if (xirrPct != null) {
      satirlar.add('Yıllıklandırılmış getiri (XIRR): ${isaretli(xirrPct)}');
    }
    if (enIyi != null) {
      satirlar.add('En iyi: ${enIyi.name} ${isaretli(enIyi.changePct)}');
    }
    if (enZayif != null) {
      satirlar.add('En zayıf: ${enZayif.name} ${isaretli(enZayif.changePct)}');
    }
    if (gunSayimi != null && gunSayimi.toplam > 0) {
      satirlar.add(
          '${gunSayimi.toplam} işlem gününün ${gunSayimi.artida}\'i artıda');
    }
    if (takipGunu != null && takipGunu > 0) {
      satirlar.add('$takipGunu gün takip ettim');
    }

    // ── Nasıl hesaplandı ────────────────────────────────────────────────
    //
    // **Neden metne giriyor (2026-09-16).** Paylaşılan metin ekrandan KOPUK
    // dolaşıyor: alan gören kişi kartı değil yalnızca bu satırları okuyor ve
    // "enflasyonun 5 puan önündeyim" iddiasını doğrulayacak hiçbir şeyi yok.
    // Kart içindeyken ham sayılar (nominal, TÜFE) ve ölçüm aralığı ekranda
    // duruyordu; metne geçerken düşüyorlardı.
    //
    // Özellikle iki şey açıkça yazılmalı, çünkü ekranda bile sorulan şeyler
    // bunlar:
    //   · piyasa getirisinin nakit akışından ARINDIRILMIŞ olduğu — yoksa
    //     "para yatırdım, yüzdem neden artmadı" sorusu doğuyor,
    //   · TÜFE penceresinin bugüne kadar GELMEDİĞİ — endeks aylık
    //     yayımlanıyor ve pencere son açıklanan ayda bitiyor.
    //
    // Satırlar KOŞULLU: verilmeyen alan hiç yazılmaz. Boş bir "Nasıl
    // hesaplandı" başlığı, açıklama olmamasından kötüdür.
    final aciklama = <String>[];
    if (degisimPct != null) {
      // Pay ve payda AYRI AYRI açıklanır, gerekçeleriyle.
      //
      // İlk hâli tek cümleydi: "(sonu − başı − net para girişi) ÷ (başı +
      // net para girişi)". Aynı terim bir yerde çıkarılıp bir yerde
      // eklendiği için okuyan kişi çelişki sanıyordu (kullanıcı sorusu,
      // 2026-09-16). İki farklı soruyu ölçüyorlar:
      //   · pay   → "ne kadar KAZANDIM": yatırdığın para kazanç değildir,
      //     çıkarılır; yoksa para yatıran herkes kâr etmiş görünür,
      //   · payda → "bu kazancı HANGİ SERMAYE üretti": yatırdığın para da
      //     piyasada çalıştı, tabana girer; yoksa yüzde şişer (ölçüldü:
      //     %36,5 yerine %43,1).
      aciklama.add('· $degisimEtiketi iki adımda:');
      aciklama.add('  1) Kazanç = (dönem sonu − dönem başı) − yatırdığın '
          'net para. Yatırdığın para kazanç değildir, ayıklanır; kalan '
          'saf piyasa hareketidir.');
      aciklama.add('  2) Yüzde = Kazanç ÷ (dönem başı + yatırdığın net '
          'para). Yatırdığın para da dönem içinde piyasada çalıştı, bu '
          'yüzden tabana dahildir; yoksa yüzde olduğundan yüksek çıkar.');
      aciklama.add('  (Net satış yaptıysan taban artmaz: satılan para '
          'artık piyasada değil.)');
      if (donemAralik != null) {
        aciklama.add('  Ölçüm aralığı: $donemAralik');
      }
    }
    if (enflasyonPuan != null) {
      if (nominalPct != null && tufePct != null) {
        aciklama.add('· Puan farkı: $nominalPct (getirim) − $tufePct (TÜFE) '
            '= ${yuzde(enflasyonPuan)} puan.');
      } else {
        aciklama.add('· Puan farkı: getirim − TÜFE.');
      }
      if (reelGetiriPct != null) {
        aciklama.add('· Reel getiri: (1+getiri) ÷ (1+TÜFE) − 1. Puan '
            'farkından farklıdır; bileşik hesap yüksek enflasyonda daha '
            'doğru sonucu verir.');
      }
      aciklama.add('· TÜFE TÜİK verisidir (TCMB EVDS). Aylık yayımlandığı '
          'için karşılaştırma son açıklanan ayda biter, bugüne kadar '
          'gelmez.');
      if (nominalAralik != null) {
        aciklama.add('  Enflasyon ölçüm aralığı: $nominalAralik');
      }
    }
    if (xirrPct != null) {
      aciklama.add('· XIRR: her para giriş/çıkışını tarihiyle '
          'ağırlıklandıran yıllıklandırılmış getiri. Piyasa getirisinden '
          'farklı olması normaldir — o dönemi, bu para akışını ölçer.');
    }
    if (enIyi != null || enZayif != null) {
      aciklama.add('· En iyi/en zayıf: varlığın ALIŞ fiyatına göre ömürlük '
          'getirisi; döneme ait değildir.');
    }

    if (aciklama.isNotEmpty) {
      satirlar
        ..add('')
        ..add('Nasıl hesaplandı')
        ..addAll(aciklama);
    }

    // Kapanış: imza + indirme bağlantısı.
    //
    // Link 2026-09-20'de girdi. Paylaşılan metin uygulamanın tek organik
    // yayılma kanalı; "sandık ile takip ediyorum" alan kişiyi mağazada
    // aramaya yolluyordu ve "sandık" araması Apple'ın ı→i katlaması yüzünden
    // uygulamayı GETİRMİYOR (ASO_2026_09.md §1). Bağlantı `Magaza`'dan,
    // kanal etiketi `utm_source=share_card` — hangi kanalın kurulum
    // getirdiğini ölçmek için. Dört haneli sayı yasağı URL'yi kapsamaz:
    // URL tutar sanılmaz.
    satirlar
      ..add('')
      ..add('sandık ile takip ediyorum')
      ..add(Magaza.indirBaglantisi(kaynak: 'share_card', kampanya: kampanya));
    return satirlar.join('\n');
  }

  /// Yıllık özetin paylaşım metni.
  ///
  /// [composeShareText]'e delege eder; biçim kuralları orada.
  ///
  /// Yüzde olarak PİYASA getirisi paylaşılır (enflasyon satırıyla aynı
  /// sayı); seri yoksa portföy değeri değişimine düşer ve etiket de onu
  /// söyler.
  static String shareText(RecapData d, {required int year}) => composeShareText(
        baslik: 'sandık Özetim $year',
        kampanya: 'yillik',
        karakter: d.character,
        degisimPct: d.marketReturnPct ?? d.changePct,
        degisimEtiketi:
            d.marketReturnPct != null ? 'Piyasa getirim' : 'Portföy değişimi',
        enflasyonPuan: d.inflationSpread,
        enIyi: d.bestAsset,
        enZayif: d.worstAsset,
        takipGunu: d.trackedDays,
        // Enflasyon penceresi başlıktaki YILDAN farklı (son 12 ayın kayan
        // penceresi, bkz. `RecapData.inflationStart`). Metinde yazılmazsa
        // okuyan kişi başlıktaki yılı varsayar.
        nominalAralik: (d.inflationStart == null || d.inflationEnd == null)
            ? null
            : '${_ayYilMetni(d.inflationStart!)} – '
                '${_ayYilMetni(d.inflationEnd!)}',
      );

  /// "Ağustos 26" — paylaşım metninde ay adı.
  ///
  /// `intl` kullanılmıyor: bu servis saf ve `BuildContext` taşımıyor
  /// (testler ağsız/locale'siz koşuyor). Ay adları Türkçe sabit — metnin
  /// tamamı zaten Türkçe.
  ///
  /// **Yıl İKİ haneli:** paylaşım metninde dört haneli sayı yasak (tutar
  /// sızıntısının imzası), bkz. `PeriodSummaryService._aralikMetni`.
  static String _ayYilMetni(DateTime t) {
    const aylar = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
    ];
    return '${aylar[t.month - 1]} ${(t.year % 100).toString().padLeft(2, '0')}';
  }
}
