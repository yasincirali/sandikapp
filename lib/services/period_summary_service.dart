import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart' show positionKey;
import 'daily_summary.dart';
import 'history_service.dart';
import 'inflation_service.dart';
import 'xirr_service.dart' show XirrService;
import 'recap_service.dart' show PortfolioCharacter, RecapAsset, RecapService;
import '../utils/tr_format.dart';

/// Özet sekmesinin dönemleri.
///
/// **3A YOK — bilinçli.** Grafik sekmesinin `_periods` dizisi beş dönem
/// taşıyor ve iki sekme aynı `_selectedPeriodIdx`'i paylaşıyor. Buraya
/// altıncı bir dönem eklemek o eşlemeyi kırardı: kullanıcı Grafik'te 6A
/// seçip Özet'e geçtiğinde bambaşka bir pencere görürdü. Dizinin sırası
/// [SummaryPeriod.values] ile BİREBİR aynı olmak zorunda.
enum SummaryPeriod {
  gunluk('GÜNLÜK', 0, intraday: true),
  birHafta('1H', 7),
  birAy('1A', 30),
  altiAy('6A', 180),
  birYil('1Y', 365);

  final String label;

  /// Pencerenin gün cinsinden uzunluğu. Veri katmanı (çözünürlük merdiveni,
  /// önbellek anahtarı) gün cinsinden çalışıyor.
  final int days;

  /// Gün içi (5 dk çözünürlük) dönem mi?
  final bool intraday;

  const SummaryPeriod(this.label, this.days, {this.intraday = false});

  /// Grafik sekmesinin `_periods` dizisindeki karşılığı.
  ///
  /// İki sekme tek bir seçili indeks paylaşıyor; dönüşüm tek yerde durur ki
  /// ikisi ayrışmasın.
  static SummaryPeriod fromIndex(int i) =>
      values[i.clamp(0, values.length - 1)];
}

/// Bir dönemin özeti.
///
/// ## Alanların hepsi nullable — ve bu kasıtlı
/// [RecapData] ile aynı disiplin: veri yoksa `0` UYDURULMAZ. Sıfır bir
/// ÖLÇÜMDÜR ("bu dönem değişmedi") ve ölçüm yokken sıfır basmak kullanıcıyı
/// yanıltır. Seri çekilemediğinde `null` taşınır, ekran da o satırı hiç
/// çizmez.
///
/// ## Değer değişimi ≠ getiri
/// Bu sınıfın var olma sebebi bu ayrım. Dönem içinde alım yapıldığında
/// portföy değeri zıplar; bu bir kazanç DEĞİLDİR. [katkiTRY] o zıplamayı
/// ayırır, [piyasaTRY] geriye kalan saf getiriyi taşır ve [getiriPct]
/// YALNIZCA piyasa hareketinden hesaplanır. Grafik sekmesindeki
/// `_buildPeriodChangeCard` bilinçli olarak HAM "birikim" değişimini
/// gösteriyor (kullanıcı kararı, 2026-08-31); Özet sekmesi ise aynı veriyi
/// kaynağına AYIRARAK gösterir. İkisi çelişmiyor — farklı soruları
/// yanıtlıyorlar ve ekran hangisini yanıtladığını yazıyor.
class PeriodSummary {
  final SummaryPeriod period;

  /// Pencerenin uçları — ekranda tarih aralığı olarak yazılır.
  final DateTime start;
  final DateTime end;

  /// Dönem başı / sonu portföy değeri (TRY). Seri yoksa `null`.
  final double? baslangicTRY;
  final double? sonTRY;

  /// Dönem içinde portföye giren NET para (alım +, satış −).
  ///
  /// `DailySummary.inflowOnDay` ile aynı işaret kuralı: satışta maliyet
  /// değil ele geçen tutar (`sellProceedsTRY`) kullanılır — kârla satılan
  /// pozisyonda ikisi farklıdır ve fark yanlışlıkla "piyasa etkisi"
  /// sayılırdı.
  final double? katkiTRY;

  /// Saf getiri (TRY) = (son − baş) − katkı.
  final double? piyasaTRY;

  /// Saf getiri yüzdesi = [piyasaTRY] / (başlangıç + max(katkı, 0)).
  ///
  /// Payda katkıyı İÇERİR: dönem içinde portföyünü ikiye katlayan kullanıcıda
  /// yalnızca `baslangicTRY`'yi taban almak yüzdeyi şişirirdi. Negatif katkı
  /// (net satış) tabana eklenmez — satılan para artık piyasada değil, ondan
  /// getiri beklenmez.
  final double? getiriPct;

  /// Dönemin en iyi / en zayıf varlığı — DÖNEME ait, ömürlük değil.
  ///
  /// [RecapData.bestAsset]'ten ayrıldığı nokta bu: orası `gainLossPercentage`
  /// üzerinden ömürlük getiriyi veriyor (üç yıl önce alınmış varlığın bu
  /// yılki getirisi elde yoktu). Burada `byPosition` serisi olduğu için
  /// gerçekten dönemin içindeki hareket ölçülebiliyor.
  final RecapAsset? enIyi;
  final RecapAsset? enZayif;

  /// Nominal getirinin TÜFE'yi kaç PUAN geçtiği. Endeks eksikse `null`.
  final double? tufeFarki;

  /// Dönemin kümülatif TÜFE'si (yüzde). Endeks eksikse `null`.
  ///
  /// [tufeFarki] tek başına kara kutu: "8,2 puan öndesin" diyen bir ekran
  /// kullanıcının TÜİK rakamıyla doğrulamasına izin vermez. Ham TÜFE ayrı
  /// taşınır ki kart üç sayıyı da yazabilsin (nominal, TÜFE, reel).
  final double? tufePct;

  /// Bileşik reel getiri: (1+n)/(1+e) − 1, yüzde.
  ///
  /// [tufeFarki]'ndan FARKLI bir sayıdır ve ikisi birlikte gösterilir.
  /// Puan farkı gündelik dilin okuduğu şey ("TÜFE'yi 6 puan geçtim"),
  /// bileşik reel getiri matematiksel olarak doğru olan. Yüksek enflasyonda
  /// aralarındaki fark büyür: %48,1 nominal / %36,7 TÜFE → puan farkı 11,4
  /// ama reel getiri 8,34. Birini silip diğerini bırakmak, ya doğruluğu ya
  /// okunabilirliği feda ederdi.
  final double? reelGetiriPct;

  /// TÜFE karşılaştırmasında kullanılan NOMİNAL getiri (yüzde).
  ///
  /// **[getiriPct]'ten farklı olabilir ve bu kasıtlı (2026-09-16).** Dönem
  /// kartının penceresi takvimden türetilir (bugünden geriye: "son 1 ay" =
  /// 16 Ağustos–16 Eylül). TÜFE ise AYLIK yayımlanır ve son açıklanmış aya
  /// kadardır (Temmuz sonu–Ağustos sonu). İki pencere örtüşmüyor; 1A'da
  /// hiç kesişmiyordu. Fark bu yüzden [getiriPct] üzerinden değil, TÜFE
  /// penceresinde YENİDEN hesaplanmış bu nominal üzerinden alınır.
  ///
  /// Endeks yoksa `null` — o zaman [tufeFarki] de yoktur.
  final double? tufeNominalPct;

  /// [tufeNominalPct] ve [tufePct]'in ölçüldüğü ORTAK aralık.
  ///
  /// [start]/[end] ile karıştırılmamalı: onlar dönem kartının aralığı.
  /// Kart bu ikisini ayrıca yazar ki kullanıcı "%31,51 hangi tarihler
  /// arası" sorusunu TÜİK'te doğrulayabilsin.
  final DateTime? tufeBaslangic;
  final DateTime? tufeBitis;

  /// Dönem içinde tahsil edilen nakit temettü (TRY). Yoksa `null`.
  ///
  /// Akışa (`katkiTRY`) GİRMEZ, `piyasaTRY` içinde ERİR — temettü ödendiğinde
  /// hisse fiyatı temettü kadar düşer, yani portföy değeri serisinde zaten
  /// görünür. Ayrı satır olarak gösterilmesi "bu getirinin şu kadarı nakit
  /// olarak elime geçti" bilgisini verir; toplama İKİNCİ KEZ eklenmez.
  final double? temettuTRY;

  /// Dönem içinde ödenen komisyon (TRY). Yoksa `null`.
  ///
  /// `totalCostTRY` komisyonu zaten içerdiği için `katkiTRY`'nin İÇİNDEDİR;
  /// ayrı satır yalnızca görünürlük sağlar, toplamdan tekrar düşülmez.
  final double? komisyonTRY;

  /// Dönem başı / sonu tür dağılımı (TRY). Seri yoksa `null`.
  final Map<AssetType, double>? dagilimBasi;
  final Map<AssetType, double>? dagilimSonu;

  /// Gün içi ham (TRY) seri — yalnızca [SummaryPeriod.gunluk] doldurur.
  final List<double> sparkline;

  /// Dönem içindeki işlem günlerinden kaçı artıda kapadı.
  ///
  /// `(artida, toplam)`. Gün ayrımı yapılamayan çözünürlükte (`weekly`)
  /// `null`.
  final ({int artida, int toplam})? gunSayimi;

  const PeriodSummary({
    required this.period,
    required this.start,
    required this.end,
    this.baslangicTRY,
    this.sonTRY,
    this.katkiTRY,
    this.piyasaTRY,
    this.getiriPct,
    this.enIyi,
    this.enZayif,
    this.tufeFarki,
    this.tufePct,
    this.reelGetiriPct,
    this.tufeNominalPct,
    this.tufeBaslangic,
    this.tufeBitis,
    this.temettuTRY,
    this.komisyonTRY,
    this.dagilimBasi,
    this.dagilimSonu,
    this.sparkline = const [],
    this.gunSayimi,
  });

  /// Dönem kayıpta mı?
  ///
  /// PİYASA hareketine bakar, portföy değerine değil: ₺12.000 alım yapılmış
  /// ve piyasa ₺2.000 kaybetmiş bir dönemde portföy değeri ARTMIŞTIR ama
  /// dönem kayıptadır. Ton anahtarı (kutlama dili yok) bu alana bağlı.
  bool get isNegative => (piyasaTRY ?? 0) < 0;

  /// Gösterilmeye değer mi? Tek bir gerçek sayı olmadan özet gösterilmez.
  bool get isMeaningful => getiriPct != null || enIyi != null;

  /// Ölçüldü ama SIFIR mı?
  ///
  /// `DailySummary.isFlat` ile aynı kural. Sıfır bir YÖN taşımaz: `−₺0` ya da
  /// yeşil bir `+₺0` yazmak olmayan bir hareketi varmış gibi gösterir.
  bool get isFlat =>
      piyasaTRY != null &&
      piyasaTRY!.abs().round() == 0 &&
      (getiriPct?.abs() ?? 0) < 0.005;
}

/// Dönemsel özet hesabı.
///
/// `RecapService` deseni: tamamı saf ve statik. [compute] ağa çıkmaz —
/// `HistoryService` çağrısı ÇAĞIRANIN işi ve sonuç `breakdown` olarak
/// parametreyle gelir. Testler böylece ağ olmadan gerçek veri şekliyle
/// koşabiliyor.
class PeriodSummaryService {
  PeriodSummaryService._();

  /// Bir varlık satırının nakit akışına katkısı (TRY).
  ///
  /// **TEK KAYNAK.** Bu kural daha önce üç yerde ayrı ayrı yazılıydı
  /// (`portfolio_performance_screen._flowOf`, `DailySummary.inflowOnDay`,
  /// ve widget katmanı) — bu projede ons→gram formülünün beş kopyası tam
  /// olarak böyle ayrışmıştı. Yeni hesap buraya bakar.
  ///
  /// Alım para GİRİŞİ (+), satışta ele geçen tutar ÇIKIŞ (−). Temettü ve
  /// silinen lot akışa girmez: `isActive` hem mezar taşını hem yumuşak
  /// silinmiş lot'u eler. Temettü ayrıca miktara hiç girmez.
  static double flowOf(Asset a) {
    if (!a.isActive) return 0;
    if (a.isBuy) return a.totalCostTRY;
    if (a.isSell) return -a.sellProceedsTRY;
    return 0;
  }

  /// [start]…[end] penceresinde portföye giren net nakit (TRY).
  ///
  /// Pencere GÜN sınırlarına genişletilir: `addedDate` gün içi bir damga
  /// taşıyor ve dönem başı 00:00 alındığında o günün alımı pencereye
  /// girmiyordu.
  static double netInflow(
    List<Asset> assets,
    DateTime start,
    DateTime end,
  ) {
    final startMs =
        dayKey(start).millisecondsSinceEpoch;
    final endMs = DateTime(end.year, end.month, end.day, 23, 59, 59)
        .millisecondsSinceEpoch;

    var total = 0.0;
    for (final a in assets) {
      final ms = a.addedDate.millisecondsSinceEpoch;
      if (ms < startMs || ms > endMs) continue;
      total += flowOf(a);
    }
    return total;
  }

  /// [start]…[end] penceresinde ödenen komisyon (TRY).
  ///
  /// Pencere kuralı [netInflow] ile AYNI olmak zorunda: iki sayı aynı
  /// dönemi anlatmıyorsa köprünün alt satırı toplamla çelişir.
  ///
  /// `commission` varlığın PARA BİRİMİNDE tutuluyor (bkz. `Asset.commission`
  /// notu), bu yüzden `purchaseFxRate` ile çevrilir. Temettü satırlarında
  /// komisyon alanı anlamsız — yalnızca alım/satım taranır.
  static double komisyonInPeriod(
    List<Asset> assets,
    DateTime start,
    DateTime end,
  ) {
    final startMs = dayKey(start).millisecondsSinceEpoch;
    final endMs = DateTime(end.year, end.month, end.day, 23, 59, 59)
        .millisecondsSinceEpoch;

    var toplam = 0.0;
    for (final a in assets) {
      if (!a.isActive) continue;
      if (!a.isBuy && !a.isSell) continue;
      final ms = a.addedDate.millisecondsSinceEpoch;
      if (ms < startMs || ms > endMs) continue;
      toplam += a.commission * a.purchaseFxRate;
    }
    return toplam;
  }

  /// NaN/sonsuz değerleri `null`'a çevirir.
  ///
  /// `InflationService.realReturnPct` tanımsızı NaN ile bildiriyor;
  /// NaN'ı modele taşımak ekranda "%NaN" yazdırırdı.
  static double? _sonluVeyaNull(double v) => v.isFinite ? v : null;

  /// Dönem başlangıcı — TAKVİMDEN, sabit gün sayısından değil.
  ///
  /// `PortfolioPerformanceScreen.donemBaslangici` ile aynı kural: "1 ay" 30
  /// gün değil, bir önceki ayın AYNI günüdür. Sabit gün sayısı kullanıcının
  /// kurduğu cümleyle uyuşmuyordu — 31 günlük aylarda pencere bir gün eksik,
  /// Şubat'ta iki-üç gün fazla oluyordu.
  ///
  /// Ayın 31'i gibi karşılığı olmayan günler ayın son gününe kırpılır
  /// (31 Mart − 1 ay → 28/29 Şubat), aksi halde DateTime bir sonraki aya
  /// taşardı.
  static DateTime donemBaslangici(DateTime bitis, int ayGeri) {
    final hedefAy = bitis.month - ayGeri;
    var yil = bitis.year;
    var ay = hedefAy;
    while (ay <= 0) {
      ay += 12;
      yil -= 1;
    }
    final ayinSonGunu = DateTime(yil, ay + 1, 0).day;
    final gun = bitis.day > ayinSonGunu ? ayinSonGunu : bitis.day;
    return DateTime(yil, ay, gun);
  }

  /// Dönemin pencere uçları.
  ///
  /// 1A / 6A / 1Y takvimden hesaplanır; 1H sabit yedi gündür (hafta kavramı
  /// takvim ayına bağlı değil). GÜNLÜK'te pencere ÇİZİLEN SEANS günüdür —
  /// bugün olmak zorunda değil: piyasa kapalıyken `HistoryService` son
  /// seansı döndürür ve hafta sonu çizilen eğri Cuma'nındır.
  static ({DateTime start, DateTime end}) pencere(
    SummaryPeriod period,
    DateTime now, {
    DateTime? seansGunu,
  }) {
    if (period.intraday) {
      final gun = seansGunu ?? dayKey(now);
      return (
        start: dayKey(gun),
        end: DateTime(gun.year, gun.month, gun.day, 23, 59, 59),
      );
    }
    final ayGeri = switch (period) {
      SummaryPeriod.birAy => 1,
      SummaryPeriod.altiAy => 6,
      SummaryPeriod.birYil => 12,
      _ => null,
    };
    final start = ayGeri == null
        ? now.subtract(Duration(days: period.days))
        : donemBaslangici(now, ayGeri);
    return (
      start: dayKey(start),
      end: now,
    );
  }

  /// Bir zaman serisinin dönem içindeki ilk ve son ölçümü.
  ///
  /// `y <= 0` slotlar ATLANIR: borsa açılmadan önceki boş slotlar bırakılsa
  /// dönem başı sıfır sanılır ve getiri sonsuza giderdi. Aynı kural
  /// `DailySummary.dayValues` içinde de var.
  static ({double first, double last, int firstTs, int lastTs})? uclar(
    Map<int, double> series, {
    int? fromMs,
    int? toMs,
  }) {
    if (series.isEmpty) return null;
    final keys = series.keys.toList()..sort();

    double? first;
    double? last;
    var firstTs = 0;
    var lastTs = 0;
    for (final k in keys) {
      if (fromMs != null && k < fromMs) continue;
      if (toMs != null && k > toMs) break;
      final v = series[k];
      if (v == null || v <= 0) continue;
      if (first == null) {
        first = v;
        firstTs = k;
      }
      last = v;
      lastTs = k;
    }
    if (first == null || last == null) return null;
    return (first: first, last: last, firstTs: firstTs, lastTs: lastTs);
  }

  /// Bir slot haritasının belirli bir damgadaki değeri (o damgaya kadarki
  /// en son ölçüm).
  static double? _degerAt(Map<int, double> series, int ts) {
    double? out;
    final keys = series.keys.toList()..sort();
    for (final k in keys) {
      if (k > ts) break;
      final v = series[k];
      if (v != null && v > 0) out = v;
    }
    return out;
  }

  /// Türe göre dağılım — verilen damgada.
  static Map<AssetType, double>? _dagilim(
    Map<AssetType, Map<int, double>> byType,
    int ts,
  ) {
    if (byType.isEmpty) return null;
    final out = <AssetType, double>{};
    byType.forEach((tur, seri) {
      final v = _degerAt(seri, ts);
      if (v != null && v > 0) out[tur] = v;
    });
    return out.isEmpty ? null : out;
  }

  /// Dönemin en iyi / en zayıf pozisyonu.
  ///
  /// Ölçüm DÖNEME aittir: her pozisyonun kendi serisinin iki ucu arasındaki
  /// yüzde değişim. Dönem içinde alım yapılan pozisyon ELENİR — miktar
  /// arttığı için serisi zıplar ve o zıplama getiri sanılırdı. Elemek,
  /// yanlış bir şampiyon ilan etmekten iyidir.
  static ({RecapAsset? enIyi, RecapAsset? enZayif}) enIyiEnZayif({
    required Map<String, Map<int, double>> byPosition,
    required int fromMs,
    required int toMs,
    required Set<String> akisliPozisyonlar,
    required String Function(String positionKey) etiket,
  }) {
    final olculebilir = <({String key, double pct})>[];

    byPosition.forEach((key, seri) {
      if (akisliPozisyonlar.contains(key)) return;
      final u = uclar(seri, fromMs: fromMs, toMs: toMs);
      if (u == null || u.first <= 0) return;
      // Tek noktalı seri değişim TAŞIMAZ — iki uç aynı slot ise yüzde 0
      // çıkar ve "değişmedi" ile ayırt edilemez.
      if (u.firstTs == u.lastTs) return;
      olculebilir.add((key: key, pct: (u.last / u.first - 1) * 100));
    });

    if (olculebilir.isEmpty) return (enIyi: null, enZayif: null);
    olculebilir.sort((a, b) => a.pct.compareTo(b.pct));

    final dusuk = olculebilir.first;
    final yuksek = olculebilir.last;

    // En iyi yalnızca GERÇEKTEN artıdaysa, en zayıf yalnızca GERÇEKTEN
    // ekside gösterilir. Kârdaki bir varlığı "en zayıfın" diye sunmak
    // bilgilendirmeyi azarlamaya çevirir (RecapService ile aynı kural).
    return (
      enIyi: yuksek.pct > 0 ? RecapAsset(etiket(yuksek.key), yuksek.pct) : null,
      enZayif: (dusuk.pct < 0 && dusuk.key != yuksek.key)
          ? RecapAsset(etiket(dusuk.key), dusuk.pct)
          : null,
    );
  }

  /// Dönem içindeki işlem günlerinden kaçı artıda kapadı.
  ///
  /// Gün başına SON ölçüm alınır ve ardışık günler karşılaştırılır. Nakit
  /// akışından arındırılmaz: bu sayım bir getiri ölçüsü değil, "dönem ne
  /// kadar dalgalıydı" bağlamıdır ve ekranda da öyle etiketlenir.
  static ({int artida, int toplam})? gunSayimi(
    Map<int, double> total, {
    required int fromMs,
    required int toMs,
  }) {
    if (total.isEmpty) return null;

    final gunSon = <int, double>{};
    final keys = total.keys.toList()..sort();
    for (final k in keys) {
      if (k < fromMs || k > toMs) continue;
      final v = total[k];
      if (v == null || v <= 0) continue;
      final d = DateTime.fromMillisecondsSinceEpoch(k);
      gunSon[dayKey(d).millisecondsSinceEpoch] = v;
    }
    if (gunSon.length < 2) return null;

    final gunler = gunSon.keys.toList()..sort();
    var artida = 0;
    for (var i = 1; i < gunler.length; i++) {
      if (gunSon[gunler[i]]! > gunSon[gunler[i - 1]]!) artida++;
    }
    return (artida: artida, toplam: gunler.length - 1);
  }

  /// Tam özeti kurar.
  ///
  /// Saf: ağ yok, `DateTime.now()` yok — [now] parametreyle gelir.
  ///
  /// [gunlukOzet] yalnızca [SummaryPeriod.gunluk] için verilir ve verildiğinde
  /// günlük rakamlar ONDAN okunur. **İkinci bir günlük hesap YAZILMAZ:**
  /// widget, Live Activity, üst kart ve bu sekme aynı rakamı göstermek
  /// ZORUNDA (bkz. `daily_summary.dart` "Değişmezler"). Burada ayrı bir
  /// formül kurmak o değişmezi sessizce kırardı.
  static PeriodSummary compute({
    required SummaryPeriod period,
    required List<Asset> assets,
    required PortfolioHistoryBreakdown breakdown,
    required DateTime now,
    DailySummary? gunlukOzet,
    double? inflationPct,
    String Function(String positionKey)? etiket,
    DateTime? pencereBaslangici,
  }) {
    // [pencereBaslangici] verildiğinde takvimden TÜRETİLEN başlangıç
    // yerine o kullanılır. Tek çağıranı `RealReturnService`: TÜFE
    // karşılaştırmasında pencere endeksin son açıklanmış ayından gelir,
    // bugünden değil (gerekçe orada). Dışarıdan pencere geçirmek yerine
    // `now`'ı oynatmak yetmezdi — `pencere()` başlangıcı `now`'dan
    // türetiyor ve hizalama geri alınırdı.
    final p = pencereBaslangici == null
        ? pencere(period, now, seansGunu: breakdown.seansGunu)
        : (start: dayKey(pencereBaslangici), end: now);
    final fromMs = p.start.millisecondsSinceEpoch;
    final toMs = p.end.millisecondsSinceEpoch;

    // ── GÜNLÜK: ortak katmana DELEGE ────────────────────────────────────
    if (period.intraday && gunlukOzet != null) {
      final u = uclar(breakdown.total, fromMs: fromMs, toMs: toMs);
      final katki = netInflow(assets, p.start, p.end);
      return PeriodSummary(
        period: period,
        start: p.start,
        end: p.end,
        baslangicTRY: gunlukOzet.sparkline.isEmpty
            ? u?.first
            : gunlukOzet.sparkline.first,
        sonTRY:
            gunlukOzet.sparkline.isEmpty ? u?.last : gunlukOzet.sparkline.last,
        katkiTRY: katki,
        // Ortak katman zaten nakit akışından ARINDIRMIŞ rakamı veriyor.
        piyasaTRY: gunlukOzet.changeTRY,
        getiriPct: gunlukOzet.changePct,
        sparkline: gunlukOzet.sparkline,
        dagilimBasi: _dagilim(breakdown.byType, fromMs),
        dagilimSonu: _dagilim(breakdown.byType, toMs),
        enIyi:
            _gunIciEnHareketli(breakdown, fromMs, toMs, assets, etiket)?.enIyi,
        enZayif: _gunIciEnHareketli(breakdown, fromMs, toMs, assets, etiket)
            ?.enZayif,
      );
    }

    // ── Dönem uçları ────────────────────────────────────────────────────
    final u = uclar(breakdown.total, fromMs: fromMs, toMs: toMs);
    if (u == null) {
      // Seri yok: HİÇBİR sayı uydurulmaz. Ekran "henüz veri yok" der.
      return PeriodSummary(
        period: period,
        start: p.start,
        end: p.end,
      );
    }

    final katki = netInflow(assets, p.start, p.end);
    final brut = u.last - u.first;
    final piyasa = brut - katki;

    // Temettü ve komisyon: köprünün ALT SATIRLARI, ayrı bileşen değil.
    // İkisi de zaten mevcut sayıların içinde (alan notlarına bakın); burada
    // yalnızca görünür kılınıyorlar. Sıfırsa `null` taşınır ki ekran hiç
    // olmayan bir satırı "₺0" diye çizmesin.
    final temettuHam = XirrService.dividendsInPeriod(assets, p.start, p.end);
    final temettu = temettuHam.abs() < 0.005 ? null : temettuHam;
    final komisyonHam = komisyonInPeriod(assets, p.start, p.end);
    final komisyon = komisyonHam.abs() < 0.005 ? null : komisyonHam;

    // Payda: dönem başı + POZİTİF katkı. Negatif katkı (net satış)
    // eklenmez — satılan para artık piyasada değil.
    final taban = u.first + (katki > 0 ? katki : 0);
    final pct = taban > 0 ? piyasa / taban * 100 : null;

    // Dönem içinde AKIŞ görmüş pozisyonlar en iyi/en zayıf yarışından
    // elenir (miktar değişimi getiri sanılmasın).
    final akisli = <String>{};
    for (final a in assets) {
      final ms = a.addedDate.millisecondsSinceEpoch;
      if (ms < fromMs || ms > toMs) continue;
      if (flowOf(a) == 0) continue;
      akisli.add(positionKey(a));
    }

    final uclar2 = enIyiEnZayif(
      byPosition: breakdown.byPosition,
      fromMs: fromMs,
      toMs: toMs,
      akisliPozisyonlar: akisli,
      etiket: etiket ?? (k) => k,
    );

    return PeriodSummary(
      period: period,
      start: p.start,
      end: p.end,
      baslangicTRY: u.first,
      sonTRY: u.last,
      katkiTRY: katki,
      piyasaTRY: piyasa,
      getiriPct: pct,
      enIyi: uclar2.enIyi,
      enZayif: uclar2.enZayif,
      tufeFarki: (pct != null && inflationPct != null)
          ? InflationService.spreadPoints(pct, inflationPct)
          : null,
      tufePct: inflationPct,
      // Bileşik reel getiri puan farkının YANINDA taşınır (alan notuna
      // bakın). NaN filtrelenir: −%100 enflasyonda payda sıfırlanıyor ve
      // `realReturnPct` tanımsızı NaN ile bildiriyor — NaN'ı ekrana
      // taşımak "%NaN" yazdırırdı.
      reelGetiriPct: (pct != null && inflationPct != null)
          ? _sonluVeyaNull(InflationService.realReturnPct(pct, inflationPct))
          : null,
      temettuTRY: temettu,
      komisyonTRY: komisyon,
      dagilimBasi: _dagilim(breakdown.byType, u.firstTs),
      dagilimSonu: _dagilim(breakdown.byType, u.lastTs),
      gunSayimi: gunSayimi(breakdown.total, fromMs: fromMs, toMs: toMs),
      sparkline: donemSerisi(breakdown.total, fromMs: fromMs, toMs: toMs),
    );
  }

  /// Dönem penceresine düşen HAM (TRY) değer serisi — eğri çizimi için.
  ///
  /// 1Y bloğundaki "yıl eğrisi" bunu kullanıyor. Daha önce yalnızca GÜNLÜK
  /// dalı `sparkline`'ı dolduruyordu, dolayısıyla o blok ÖLÜ KODDU: kart
  /// `sparkline.length >= 2` kapısının arkasındaydı ve dizi her zaman
  /// boştu, yani hiç çizilmiyordu (sessiz eksik — hata vermiyor,
  /// görünmüyor).
  ///
  /// `y <= 0` slotlar atlanır: veri başlamadan önceki boş slotlar bırakılsa
  /// eğri sıfırdan zıplayarak başlar ve gerçek hareket düzleşir. Aynı kural
  /// `DailySummary.dayValues` ve [uclar] içinde de var.
  ///
  /// Normalize EDİLMEZ — çizim tarafı `DailySummary.normalizeForSparkline`
  /// ile ölçekliyor ve o kural ortak katmanda tek yerde duruyor.
  static List<double> donemSerisi(
    Map<int, double> total, {
    required int fromMs,
    required int toMs,
  }) {
    if (total.isEmpty) return const [];
    final keys = total.keys.toList()..sort();
    final out = <double>[];
    for (final k in keys) {
      if (k < fromMs) continue;
      if (k > toMs) break;
      final v = total[k];
      if (v == null || v <= 0) continue;
      out.add(v);
    }
    // Tek noktalı bir "eğri" yanıltıcıdır; çizim tarafı da iki nokta
    // istiyor. Boş dönmek o kapıyı kapatır.
    return out.length < 2 ? const [] : out;
  }

  /// Gün içinde en çok hareket eden pozisyon.
  static ({RecapAsset? enIyi, RecapAsset? enZayif})? _gunIciEnHareketli(
    PortfolioHistoryBreakdown breakdown,
    int fromMs,
    int toMs,
    List<Asset> assets,
    String Function(String)? etiket,
  ) {
    if (breakdown.byPosition.isEmpty) return null;
    final akisli = <String>{};
    for (final a in assets) {
      final ms = a.addedDate.millisecondsSinceEpoch;
      if (ms < fromMs || ms > toMs) continue;
      if (flowOf(a) == 0) continue;
      akisli.add(positionKey(a));
    }
    return enIyiEnZayif(
      byPosition: breakdown.byPosition,
      fromMs: fromMs,
      toMs: toMs,
      akisliPozisyonlar: akisli,
      etiket: etiket ?? (k) => k,
    );
  }

  /// Kayıptaki dönemde gösterilecek bağlam cümlesi.
  ///
  /// **Ton anahtarı (`RETENTION_STRATEJISI.md` §8).** Kayıp anında uyarı
  /// dili ("Portföyün düştü!") panik satışı tetikler; kutlama dili ise
  /// Monzo Wrapped'in eleştirildiği hatadır. İkisi de yok. Yerine DAHA UZUN
  /// pencere bağlamı verilir: "Bu ay ekside. Yıl hâlâ +%31,8."
  ///
  /// Öneri/eylem dili de YOK (§9 SPK): durum bildirilir, eylem önerilmez.
  /// [uzunDonemPct] yoksa yalnızca nötr durum cümlesi döner.
  /// Dönemin cümle içinde kullanılan adı ("Bu ay", "Bu yıl").
  ///
  /// Hem ton cümlesi hem paylaşım başlığı buradan okur — iki yerde ayrı
  /// yazılsa biri güncellenip öteki kalırdı.
  static String donemAdi(SummaryPeriod p) => switch (p) {
        SummaryPeriod.gunluk => 'Bugün',
        SummaryPeriod.birHafta => 'Bu hafta',
        SummaryPeriod.birAy => 'Bu ay',
        SummaryPeriod.altiAy => 'Bu altı ay',
        SummaryPeriod.birYil => 'Bu yıl',
      };

  static String tonCumlesi(PeriodSummary s, {double? uzunDonemPct}) {
    final ad = donemAdi(s.period);

    if (s.isFlat) return '$ad piyasa hareketi yok.';

    if (s.isNegative) {
      if (uzunDonemPct != null && uzunDonemPct > 0) {
        final v = uzunDonemPct.toStringAsFixed(1).replaceAll('.', ',');
        return '$ad ekside. Daha uzun pencerede hâlâ +%$v.';
      }
      return '$ad ekside.';
    }

    if (uzunDonemPct != null && uzunDonemPct < 0) {
      final v = uzunDonemPct.abs().toStringAsFixed(1).replaceAll('.', ',');
      return '$ad artıda. Daha uzun pencerede −%$v.';
    }
    return '$ad artıda.';
  }

  /// Dönem özetinin paylaşım metni.
  ///
  /// `RecapService.composeShareText`'e DELEGE eder — metnin biçimi ve
  /// **TUTAR İÇERMEME** kuralı tek yerde durur. İkinci bir metin kurucusu
  /// yazmak o kuralın ikinci bir kopyasını doğurur ve biri güncellenip
  /// öteki kalırdı (`TECHNICAL_DEBT.md`'de bu yüzden ertelenmişti).
  ///
  /// **Başlıkta TARİH ARALIĞI yok — bilinçli.** "14 Ağu → 13 Eyl" gibi bir
  /// aralık hem gereksiz (dönem adı zaten söylüyor) hem de riskli: yıl
  /// içeren dört haneli sayılar paylaşılan metinde TUTAR gibi okunur.
  /// `recap_service_test`'in "dört haneli sayı tutar demektir" iddiası da
  /// tam olarak bunu kovalıyor.
  ///
  /// Yüzde SAF PİYASA getirisidir ([PeriodSummary.getiriPct]), portföy
  /// değeri değişimi değil — etiket de bunu söylüyor. Katkının şişirdiği
  /// bir rakamı "getirim" diye paylaşmak, ekranın tüm mesajını tersine
  /// çevirirdi.
  ///
  /// Ölçülebilir bir yüzde yoksa `null` döner ve çağıran taraf paylaşım
  /// butonunu HİÇ göstermez: içinde tek bir sayı olmayan bir kart
  /// paylaşılmaz.
  ///
  /// [xirrPct] özetin parçası değil (ağdan sonra, ayrı hesaplanıyor) ve
  /// yalnızca gösterildiği seviyede geçirilir — ekranda görünmeyen bir
  /// sayı paylaşıma girmez.
  static String? shareText(
    PeriodSummary s, {
    PortfolioCharacter? karakter,
    double? xirrPct,
  }) {
    if (s.getiriPct == null) return null;

    return RecapService.composeShareText(
      baslik: 'sandık · ${donemAdi(s.period)}',
      karakter: karakter,
      degisimPct: s.getiriPct,
      degisimEtiketi: 'Piyasa getirim',
      enflasyonPuan: s.tufeFarki,
      reelGetiriPct: s.reelGetiriPct,
      enIyi: s.enIyi,
      enZayif: s.enZayif,
      gunSayimi: s.gunSayimi,
      xirrPct: xirrPct,
    );
  }
}
