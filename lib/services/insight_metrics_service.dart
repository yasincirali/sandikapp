import 'dart:math' as math;

import '../models/asset.dart';
import '../models/asset_type.dart';

/// Portföy sağlığı metrikleri — düşüş, oynaklık, yoğunlaşma.
///
/// **Neden ayrı bir servis:** `PeriodSummaryService` dönemin ANLATISINI
/// kuruyor ("nereden geldi, TÜFE'yi geçti mi"). Buradakiler farklı bir
/// soruyu yanıtlıyor: "bu portföy ne kadar sallanıyor, yumurtalar tek
/// sepette mi". İkisini aynı sınıfa koymak, dönem penceresiyle ilgisi
/// olmayan yoğunlaşma hesabını da dönem parametresine bağlardı.
///
/// `RecapService` / `PeriodSummaryService` deseni: tamamı saf ve statik,
/// ağa çıkmaz. Seri ÇAĞIRANIN elinde (`HistoryService` zaten çekmiş olur).
///
/// ## Ortak değişmez: ölçülemeyen sayı UYDURULMAZ
/// Bütün dönüşler nullable. Yetersiz örnekle hesaplanan bir oynaklık
/// rakamı, hesaplamamaktan kötüdür: kullanıcı ona güvenip pozisyon
/// büyüklüğü kararı verir. Eşikler [minOrnek] ve [minGunSayisi] içinde tek
/// yerde durur.
class InsightMetricsService {
  InsightMetricsService._();

  /// Oynaklık/düşüş için gereken en az örnek sayısı.
  ///
  /// 20 iş günü ≈ bir ay. Bunun altında standart sapma tek bir sıçramanın
  /// eseri olur; "portföyün oynaklığı %48" gibi bir rakam tek günlük bir
  /// haberden doğardı.
  static const minOrnek = 20;

  /// Yıllıklandırma için pencerenin en az kaç gün olması gerektiği.
  ///
  /// Bir haftalık pencereden yıllık oynaklık türetmek √252 ile 50 kat
  /// büyütmek demek — matematiksel olarak tanımlı, ürün olarak yalan.
  static const minGunSayisi = 30;

  // ═════════════════════════════════════════════════════════════════════
  // Maksimum düşüş
  // ═════════════════════════════════════════════════════════════════════

  /// Serinin gördüğü en büyük tepe→dip gerilemesi.
  ///
  /// Dönüş: yüzde (pozitif sayı, "%14,2 geriledi"), dibin ve tepenin zaman
  /// damgaları, ve dipten sonra tepeye GERİ DÖNÜLDÜYSE toparlanma gün
  /// sayısı.
  ///
  /// **Neden nakit akışına bakmıyor:** düşüş, portföy DEĞERİNİN geçmiş
  /// zirvesinden ne kadar uzaklaştığını ölçer. Dönem içinde para yatıran
  /// kullanıcıda değer zıplar ve zirve yükselir — bu doğrudur, kullanıcı
  /// gerçekten o zirveyi görmüştür. Getiri ölçmüyoruz, PSİKOLOJİK dip
  /// ölçüyoruz: "hesabımda gördüğüm en yüksek rakamdan ne kadar aşağı
  /// indim". Bu yüzden `piyasaTRY` ayrıştırması burada uygulanmaz ve
  /// uygulanmaması kasıtlıdır.
  ///
  /// `y <= 0` slotlar atlanır (`PeriodSummaryService.donemSerisi` ile aynı
  /// kural): veri başlamadan önceki boş slotlar bırakılsa düşüş %100
  /// görünürdü.
  static Drawdown? maxDrawdown(Map<int, double> seri) {
    final ts = seri.keys.toList()..sort();
    final noktalar = <({int ts, double v})>[];
    for (final t in ts) {
      final v = seri[t];
      if (v == null || v <= 0) continue;
      noktalar.add((ts: t, v: v));
    }
    if (noktalar.length < minOrnek) return null;

    var zirveV = noktalar.first.v;
    var zirveTs = noktalar.first.ts;
    var enKotuPct = 0.0;
    int? dipTs;
    int? dipZirveTs;
    var dipV = 0.0;

    for (final n in noktalar) {
      if (n.v > zirveV) {
        zirveV = n.v;
        zirveTs = n.ts;
        continue;
      }
      final dususPct = (zirveV - n.v) / zirveV * 100;
      if (dususPct > enKotuPct) {
        enKotuPct = dususPct;
        dipTs = n.ts;
        dipZirveTs = zirveTs;
        dipV = n.v;
      }
    }

    // Hiç gerilememiş portföy: 0 UYDURULMAZ ama bu bir ölçümdür —
    // "hiç düşmedin" gerçek bir cevap. Sıfırla döner, çağıran taraf
    // isterse ayrı cümle kurar.
    if (dipTs == null || dipZirveTs == null) {
      return Drawdown(
        yuzde: 0,
        zirveTs: zirveTs,
        dipTs: noktalar.last.ts,
        toparlanmaGun: null,
      );
    }

    // Toparlanma: dipten SONRA zirve değerine geri dönüldü mü?
    final dipZirveV = seri[dipZirveTs] ?? dipV;
    int? toparlanma;
    for (final n in noktalar) {
      if (n.ts <= dipTs) continue;
      if (n.v >= dipZirveV) {
        toparlanma = DateTime.fromMillisecondsSinceEpoch(n.ts)
            .difference(DateTime.fromMillisecondsSinceEpoch(dipTs))
            .inDays;
        break;
      }
    }

    return Drawdown(
      yuzde: enKotuPct,
      zirveTs: dipZirveTs,
      dipTs: dipTs,
      toparlanmaGun: toparlanma,
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // Oynaklık
  // ═════════════════════════════════════════════════════════════════════

  /// Yıllıklandırılmış oynaklık (standart sapma), yüzde.
  ///
  /// **Çözünürlük tuzağı — bu hesabın en kritik yeri.** `HistoryService`
  /// serileri çözünürlük merdiveninden geliyor: 1Y penceresi GÜNLÜK değil
  /// haftalık bar taşıyabilir. Bar süresini bilmeden √252 ile çarpmak,
  /// haftalık seride oynaklığı 2,2 kat şişirirdi. Bu yüzden yıllıklandırma
  /// faktörü [barSuresiGun]'den TÜRETİLİR, sabit değildir.
  ///
  /// `null` döner: örnek az, pencere kısa ya da bar süresi bilinmiyorsa.
  static double? annualizedVolatility(
    Map<int, double> seri, {
    required double barSuresiGun,
  }) {
    if (barSuresiGun <= 0) return null;

    final ts = seri.keys.toList()..sort();
    final degerler = <double>[];
    for (final t in ts) {
      final v = seri[t];
      if (v == null || v <= 0) continue;
      degerler.add(v);
    }
    if (degerler.length < minOrnek) return null;

    final kapsananGun = (ts.last - ts.first) / Duration.millisecondsPerDay;
    if (kapsananGun < minGunSayisi) return null;

    // Logaritmik getiri: bileşik büyümede toplanabilir olan tek biçim.
    // Basit yüzde getiride +%50/−%50 ardışığı sıfır sanılır.
    final getiriler = <double>[];
    for (var i = 1; i < degerler.length; i++) {
      getiriler.add(math.log(degerler[i] / degerler[i - 1]));
    }
    if (getiriler.length < 2) return null;

    final ort = getiriler.reduce((a, b) => a + b) / getiriler.length;
    final varyans =
        getiriler.map((g) => (g - ort) * (g - ort)).reduce((a, b) => a + b) /
            (getiriler.length - 1); // örneklem varyansı (n−1)
    final barStd = math.sqrt(varyans);

    // Yılda kaç bar var? Takvim günü üzerinden — 252 iş günü varsayımı
    // haftalık/aylık barda yanlış olurdu.
    final yildakiBar = 365.0 / barSuresiGun;
    return barStd * math.sqrt(yildakiBar) * 100;
  }

  // ═════════════════════════════════════════════════════════════════════
  // Yoğunlaşma
  // ═════════════════════════════════════════════════════════════════════

  /// Pozisyon ve tür yoğunlaşması — bugünkü portföyden.
  ///
  /// Dönem penceresi ALMAZ: "yumurtalar tek sepette mi" sorusu bugüne
  /// aittir, geçmişe değil.
  ///
  /// `isBuy && isActive` filtresi CLAUDE.md "kapanmış pozisyon" kuralının
  /// karşılığı: bugünkü mülkiyeti soran yer aktif lotlara bakar.
  static Concentration? concentration(
    List<Asset> assets,
    double Function(double value, String currency) toTRY,
  ) {
    // Pozisyon anahtarı bazında topla: aynı hissenin üç lotu tek pozisyon.
    final pozisyon = <String, double>{};
    final turler = <AssetType, double>{};
    final etiket = <String, String>{};

    for (final a in assets) {
      if (!a.isBuy || !a.isActive) continue;
      final deger = toTRY(a.totalValue, a.currency);
      if (deger <= 0) continue;
      final key = '${a.type.name}|${a.ticker}|${a.subCategory ?? ''}';
      pozisyon[key] = (pozisyon[key] ?? 0) + deger;
      etiket[key] = a.name;
      turler[a.type] = (turler[a.type] ?? 0) + deger;
    }

    final toplam = pozisyon.values.fold<double>(0, (a, b) => a + b);
    if (toplam <= 0 || pozisyon.isEmpty) return null;

    final sirali = pozisyon.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // HHI (Herfindahl): payların karesi toplamı. 1/n ile tam dağılmış,
    // 1 ile tek varlık. Kullanıcıya HAM gösterilmez — "keyfi risk skoru
    // üretme" kuralı. Yalnızca eşik cümlesi için kullanılır.
    var hhi = 0.0;
    for (final v in pozisyon.values) {
      final pay = v / toplam;
      hhi += pay * pay;
    }

    final turPaylari = <AssetType, double>{
      for (final e in turler.entries) e.key: e.value / toplam * 100,
    };

    return Concentration(
      enBuyukEtiket: etiket[sirali.first.key] ?? '—',
      enBuyukPay: sirali.first.value / toplam * 100,
      pozisyonSayisi: pozisyon.length,
      hhi: hhi,
      turPaylari: turPaylari,
    );
  }
}

/// Maksimum düşüş sonucu.
class Drawdown {
  /// Tepe→dip gerileme, POZİTİF yüzde (%14,2 → 14.2).
  final double yuzde;

  final int zirveTs;
  final int dipTs;

  /// Dipten sonra eski zirveye dönene kadar geçen gün. Hâlâ dönülmediyse
  /// `null` — "toparlanmadı" ile "0 günde toparlandı" karıştırılmamalı.
  final int? toparlanmaGun;

  const Drawdown({
    required this.yuzde,
    required this.zirveTs,
    required this.dipTs,
    this.toparlanmaGun,
  });

  /// Hiç gerileme görülmedi mi?
  bool get isFlat => yuzde.abs() < 0.05;

  /// Toparlandı mı?
  bool get toparlandi => toparlanmaGun != null;
}

/// Yoğunlaşma sonucu.
class Concentration {
  final String enBuyukEtiket;

  /// En büyük pozisyonun portföydeki payı, yüzde.
  final double enBuyukPay;

  final int pozisyonSayisi;

  /// Herfindahl endeksi (0…1). UI'da ham gösterilmez.
  final double hhi;

  /// Tür → yüzde pay.
  final Map<AssetType, double> turPaylari;

  const Concentration({
    required this.enBuyukEtiket,
    required this.enBuyukPay,
    required this.pozisyonSayisi,
    required this.hhi,
    required this.turPaylari,
  });

  /// En yüksek paylı tür ve payı.
  ({AssetType tur, double pay})? get baskinTur {
    if (turPaylari.isEmpty) return null;
    final e = turPaylari.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return (tur: e.key, pay: e.value);
  }

  /// Tek varlığa aşırı bağımlılık eşiği.
  ///
  /// %40 keyfi DEĞİL: bu eşiğin üstünde tek varlığın %20 düşüşü portföyü
  /// %8'den fazla düşürür — kullanıcının "çeşitlendirdim" algısıyla
  /// çelişmeye başladığı nokta. Eşik AŞILDIĞINDA bile "riskli" denmez,
  /// yalnızca oran gösterilir (bir varlığın riskli olduğunu iddia etmeme
  /// kuralı).
  bool get tekVarlikAgir => enBuyukPay >= 40;
}
