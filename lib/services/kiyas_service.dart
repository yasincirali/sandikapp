import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import 'daily_summary.dart';
import 'fiyat_kaynagi.dart';
import 'para_agirlikli_getiri.dart';
import 'period_summary_service.dart';

/// Kıyas hesabına giren tek nakit akışı: an (ms) ve TL tutar.
///
/// İşaret [PeriodSummaryService.flowOf] ile aynı: alım para GİRİŞİ (+),
/// satıştan ele geçen ve nakit temettü ÇIKIŞ (−).
typedef KiyasAkisi = ({int ts, double tutar});

/// Tek kıyas varlığının sonucu.
@immutable
class KiyasHesabi {
  /// Aynı paralar bu varlığa yatırılsaydı dönem sonundaki değeri (TL).
  final double sonTRY;

  /// Kıyasın para ağırlıklı dönem getirisi (%) — kullanıcınınkiyle AYNI
  /// motor, aynı akışlar, aynı ağırlıklar ([paraAgirlikliGetiriPct]).
  final double getiriPct;

  /// Kullanıcının getirisi − kıyasın getirisi (yüzde PUAN). Pozitifse
  /// kullanıcı öndedir. Kullanıcının getirisi bilinmiyorsa `null`.
  final double? farkPuan;

  const KiyasHesabi({
    required this.sonTRY,
    required this.getiriPct,
    this.farkPuan,
  });
}

/// Kullanıcının dönemi — kıyasın "senin portföyün" tarafı.
///
/// [KiyasGirdisi.kur] ekranın Özet hesabıyla AYNI girdilerden
/// (`breakdown.total`, kapsam lot'ları, canlı uç) ve AYNI kurallarla
/// (`PeriodSummaryService.piyasaEtkisi`) kurulur: dönem başı değeri ve anı,
/// dönem sonu ve akış penceresi orada nasıl belirleniyorsa burada da öyle.
///
/// Değer eşitliği taşır ki `kiyasProvider` ailesinin anahtarı olabilsin.
@immutable
class KiyasGirdisi {
  final SummaryPeriod period;

  /// Pencere uçları — kart aralığı yazarken kullanır.
  final DateTime start;
  final DateTime end;

  /// Dönem başı portföy değeri (TL) ve ÖLÇÜLDÜĞÜ an (serinin pencere
  /// içindeki ilk dolu slotu; `piyasaEtkisi` `ilkTs`).
  final double basTRY;
  final int basTs;

  /// Dönem sonu portföy değeri (TL) ve anı (canlı uçta "şimdi").
  final double sonTRY;
  final int sonTs;

  /// `(basTs, akış sonu]` aralığındaki akışlar — temettü dahil.
  final List<KiyasAkisi> akislar;

  /// Kullanıcının AYNI akışlarla para ağırlıklı getirisi (%).
  ///
  /// Temettü yoksa Özet'teki `getiriPct` ile birebir aynıdır (aynı akış,
  /// aynı ağırlık; `kiyas_service_test` kilitler). Temettü VARSA farklıdır
  /// ve bu kasıtlı: Özet temettüyü akışa koymaz (değer serisinde "erir",
  /// bkz. `PeriodSummary.temettuTRY`), kıyas ise koymak ZORUNDA — yoksa
  /// kullanıcının cebine giren para kıyas varlığında yatırımda kalmış
  /// sayılır ve kıyas haksız yere öne geçer. İki taraf aynı akışı görsün
  /// diye kullanıcının getirisi de burada temettü dahil yeniden hesaplanır;
  /// kart bu durumda bir not düşer ([temettuVar]).
  final double? getiriPct;

  /// Akışlarda nakit temettü var mı?
  final bool temettuVar;

  const KiyasGirdisi({
    required this.period,
    required this.start,
    required this.end,
    required this.basTRY,
    required this.basTs,
    required this.sonTRY,
    required this.sonTs,
    required this.akislar,
    required this.getiriPct,
    required this.temettuVar,
  });

  /// Ekranın Özet girdilerinden kurar. GÜNLÜK'te ya da seri iki uç
  /// taşımıyorsa `null` (sayı uydurulmaz).
  ///
  /// GÜNLÜK neden yok: gün içi kıyas BIST 100'ün seans saatleriyle
  /// dövizin 7/24 kotasyonunu aynı 5 dakikalık ızgaraya yerleştirmeyi
  /// gerektirir ve "bugün altına koysaydın" sorusunun cevabı zaten piyasa
  /// bandındaki günlük değişimdir.
  ///
  /// [canliSon] ve [now] `PeriodSummaryService.compute`'a verilenlerin
  /// AYNISI olmalı; aksi halde kullanıcı satırı Özet'le ayrışır.
  static KiyasGirdisi? kur({
    required SummaryPeriod period,
    required List<Asset> lotlar,
    required Map<int, double> seri,
    required DateTime now,
    double? canliSon,
  }) {
    if (period.intraday) return null;
    final p = PeriodSummaryService.pencere(period, now);
    final pe = PeriodSummaryService.piyasaEtkisi(
      seri: seri,
      lotlar: lotlar,
      start: p.start,
      end: p.end,
      canliSon: canliSon,
    );
    if (pe == null) return null;

    // Uç canlı mı — `piyasaEtkisi`'nin kuralı (sonucu dönmediği için
    // aynı koşul burada okunur; değişirse ikisi birlikte değişmeli).
    final canli = canliSon != null &&
        (canliSon > 0 ||
            (canliSon == 0 &&
                lotlar.isNotEmpty &&
                DailySummary.acikPozisyonYok(lotlar)));
    final sonTs = canli ? p.end.millisecondsSinceEpoch : pe.sonTs;
    final akisSonuMs = canli
        ? DateTime(p.end.year, p.end.month, p.end.day, 23, 59, 59)
            .millisecondsSinceEpoch
        : pe.sonTs;

    final akis = KiyasService.akislar(lotlar,
        basTs: pe.ilkTs, akisSonuMs: akisSonuMs);
    var temettu = false;
    for (final a in lotlar) {
      if (!a.isActive || !a.isDividend) continue;
      final ms = a.addedDate.millisecondsSinceEpoch;
      if (ms > pe.ilkTs && ms <= akisSonuMs && a.dividendTRY != 0) {
        temettu = true;
        break;
      }
    }
    return KiyasGirdisi(
      period: period,
      start: p.start,
      end: p.end,
      basTRY: pe.ilk,
      basTs: pe.ilkTs,
      sonTRY: pe.son,
      sonTs: sonTs,
      akislar: akis,
      getiriPct: paraAgirlikliGetiriPct(
        bas: pe.ilk,
        son: pe.son,
        akislar: KiyasService.agirliklar(akis, basTs: pe.ilkTs, sonTs: sonTs),
      ),
      temettuVar: temettu,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KiyasGirdisi &&
      other.period == period &&
      other.start == start &&
      other.end == end &&
      other.basTRY == basTRY &&
      other.basTs == basTs &&
      other.sonTRY == sonTRY &&
      other.sonTs == sonTs &&
      other.getiriPct == getiriPct &&
      other.temettuVar == temettuVar &&
      listEquals(other.akislar, akislar);

  @override
  int get hashCode => Object.hash(period, start, end, basTRY, basTs, sonTRY,
      sonTs, getiriPct, temettuVar, Object.hashAll(akislar));
}

/// Kartın tamamı: kullanıcının dönemi + hesaplanabilen kıyaslar.
@immutable
class KiyasOzeti {
  final KiyasGirdisi girdi;

  /// Hesaplanabilen kıyaslar, [KiyasVarligi] sırasıyla. Fiyatı eksik ya da
  /// çekişi kıyas değerini aşan varlık burada YOKTUR — kart o satırı çizmez.
  final Map<KiyasVarligi, KiyasHesabi> satirlar;

  const KiyasOzeti({required this.girdi, required this.satirlar});
}

/// **"Başka yere koysaydın" — kamu piyasası eşdeğeri (PME) hesabı.**
///
/// ## Soru (kullanıcı onayı, 2026-10-01)
/// "Bu dönem portföyüme koyduğum paraları aynı günlerde dolara / altına /
/// BIST 100'e koysaydım dönem sonunda ne olurdu?"
///
/// ## Yöntem (Long–Nickels PME)
/// Kıyas varlığı kullanıcının GERÇEK para akışlarını aynı TL tutarlarla
/// aynı anlarda alır:
///   * dönem başında portföyün değeri kadar kıyas birimi alınır,
///   * her alımda tutar ÷ o günkü fiyat kadar birim eklenir,
///   * her satış ve nakit temettüde aynı TL tutar kadar birim çıkarılır,
///   * dönem sonu değeri = kalan birim × dönem sonu fiyatı.
/// Getiri, kullanıcınınkiyle AYNI motorla ([paraAgirlikliGetiriPct]) ve
/// AYNI ağırlıklarla (`PeriodSummaryService.paraAgirlikliGetiri`) hesaplanır:
/// iki rakam aynı akışlardan, yalnızca farklı bir dönem sonu değerinden
/// türer. Fark böylece "zamanlaman" değil yalnızca "seçtiğin varlık"tır.
///
/// ## Sayı uydurulmaz
/// Fiyat bulunamayan bir an varsa ya da bir çekiş o andaki kıyas değerini
/// aşarsa (kıyasta satılacak o kadar birim yok — PME'nin bilinen sınırı;
/// "negatif bakiye" taşımak anlamsız bir sayı üretir) sonuç `null` olur.
///
/// Kıyasta alım-satım makası, komisyon ve vergi yoktur; kullanıcının
/// tarafında ise komisyon akışın içindedir (`totalCostTRY`). Fark küçükse
/// bu asimetri hükmü çevirebilir — kart bunu "yaklaşık" bir kıyas olarak
/// sunar, işlem önerisi olarak değil.
class KiyasService {
  KiyasService._();

  /// Akış anındaki fiyat: O ANDA ya da ÖNCESİNDEKİ SON ölçüm.
  ///
  /// ## Neden "öncesindeki son" (en yakın değil)
  /// En yakın ölçüm ileriye de bakabilir: pazartesi öğlen yapılan bir
  /// alımı salı kapanışıyla fiyatlamak, kullanıcının o gün bilemeyeceği
  /// bir fiyatı kıyasa yazmaktır. Geçmişe bakan kural hafta sonu/tatilde
  /// yapılan alımı son seansın kapanışıyla eşler — o gün gerçekten
  /// alınabilecek fiyat budur. Günlük seride bir günün ölçümü 00:00
  /// damgasında o günün kapanışını taşır (`ResolutionTier.normalizeTs`);
  /// yani gün içi alım o günün kapanışından fiyatlanır — günlük PME'nin
  /// standart kabulü.
  ///
  /// ## Sınırlar
  /// * [geriTolerans]: en son ölçüm bundan eskiyse fiyat BİLİNMİYOR sayılır
  ///   (seride delik). 10 gün: Kurban Bayramı'nda borsa 9 güne kadar
  ///   kapalı kalabiliyor; daha uzun bir boşluk tatil değil eksik veridir.
  /// * [ileriTolerans]: yalnızca serinin SOL KENARINDA — anın öncesinde hiç
  ///   ölçüm yoksa ilk ölçüm, bu kadar yakınsa kullanılır. Yahoo `range`
  ///   pencereyi dönem başına gün hassasiyetinde oturtmaz (5Y'de `5y`
  ///   aralığı tam beş yıl önce başlar); dönem başı bir-iki gün dışarıda
  ///   kalabilir. `HistoryService._closestOrNull` ile aynı kural, ama
  ///   sınırlı: bir haftadan uzaksa sayı uydurulmaz.
  static const geriTolerans = Duration(days: 10);
  static const ileriTolerans = Duration(days: 7);

  /// [seri]'de [ts] anındaki fiyat ([geriTolerans]/[ileriTolerans]
  /// kurallarıyla). Bulunamazsa `null`.
  static double? fiyatAt(Map<int, double> seri, int ts) =>
      _FiyatBulucu(seri).at(ts);

  /// Kullanıcının `(basTs, akisSonuMs]` aralığındaki nakit akışları.
  ///
  /// Alım/satım [PeriodSummaryService.flowOf]'tan (TEK kural); nakit
  /// temettü ÇIKIŞ olarak eklenir (gerekçe `KiyasGirdisi.getiriPct`).
  /// Damga kapısı `PeriodSummaryService.paraAgirlikliGetiri` ile aynı.
  static List<KiyasAkisi> akislar(
    List<Asset> lotlar, {
    required int basTs,
    required int akisSonuMs,
  }) {
    final out = <KiyasAkisi>[];
    for (final a in lotlar) {
      final ms = a.addedDate.millisecondsSinceEpoch;
      if (ms <= basTs || ms > akisSonuMs) continue;
      var f = PeriodSummaryService.flowOf(a);
      if (f == 0 && a.isActive && a.isDividend) f = -a.dividendTRY;
      if (f == 0 || !f.isFinite) continue;
      out.add((ts: ms, tutar: f));
    }
    out.sort((a, b) => a.ts.compareTo(b.ts));
    return out;
  }

  /// Akışların para ağırlıklı getiri ağırlıkları — dönemde KALDIĞI süre
  /// payı. `PeriodSummaryService.paraAgirlikliGetiri` ile aynı formül.
  static List<DonemAkisi> agirliklar(
    List<KiyasAkisi> akislar, {
    required int basTs,
    required int sonTs,
  }) {
    final sure = sonTs - basTs;
    return [
      for (final a in akislar)
        (
          f: a.tutar,
          w: sure <= 0 ? 0.0 : ((sonTs - a.ts) / sure).clamp(0.0, 1.0),
        ),
    ];
  }

  /// Tek kıyas varlığı için PME hesabı.
  ///
  /// [akislar] dönem içindeki akışlar (sıra önemsiz; burada sıralanır).
  /// [fiyatSerisi] kıyas varlığının `{ms: TL fiyat}` serisi.
  /// [kullaniciGetiriPct] verilirse fark (puan) da hesaplanır.
  ///
  /// `null`: dönem başı değeri pozitif değil, bir anın fiyatı bilinmiyor
  /// ya da bir çekiş kıyas değerini aşıyor.
  static KiyasHesabi? kiyasla({
    required double basTRY,
    required int basTs,
    required int sonTs,
    required List<KiyasAkisi> akislar,
    required Map<int, double> fiyatSerisi,
    double? kullaniciGetiriPct,
  }) {
    if (!(basTRY > 0) || !basTRY.isFinite || sonTs < basTs) return null;
    final fiyat = _FiyatBulucu(fiyatSerisi);
    final p0 = fiyat.at(basTs);
    if (p0 == null) return null;

    final sirali = [...akislar]..sort((a, b) => a.ts.compareTo(b.ts));
    var birim = basTRY / p0;
    for (final a in sirali) {
      final p = fiyat.at(a.ts);
      if (p == null) return null;
      birim += a.tutar / p;
      if (birim < 0) {
        // Kuruş altı fark yuvarlamadır (her şeyi satan kullanıcıda kıyas
        // tam sıfıra iner); daha büyüğü gerçek aşırı çekiştir.
        if (birim * p < -0.01) return null;
        birim = 0;
      }
    }
    final pSon = fiyat.at(sonTs);
    if (pSon == null) return null;
    final son = birim * pSon;
    final pct = paraAgirlikliGetiriPct(
      bas: basTRY,
      son: son,
      akislar: agirliklar(sirali, basTs: basTs, sonTs: sonTs),
    );
    if (pct == null || !pct.isFinite || !son.isFinite) return null;
    return KiyasHesabi(
      sonTRY: son,
      getiriPct: pct,
      farkPuan: kullaniciGetiriPct == null ? null : kullaniciGetiriPct - pct,
    );
  }

  /// Kartın tamamı. Kullanıcının getirisi yoksa `null` — kıyaslanacak bir
  /// "senin" yoksa kıyas da yoktur.
  static KiyasOzeti? ozet(
    KiyasGirdisi g,
    Map<KiyasVarligi, Map<int, double>> seriler,
  ) {
    final kendi = g.getiriPct;
    if (kendi == null || !kendi.isFinite) return null;
    final satirlar = <KiyasVarligi, KiyasHesabi>{};
    for (final v in KiyasVarligi.values) {
      final seri = seriler[v];
      if (seri == null || seri.isEmpty) continue;
      final h = kiyasla(
        basTRY: g.basTRY,
        basTs: g.basTs,
        sonTs: g.sonTs,
        akislar: g.akislar,
        fiyatSerisi: seri,
        kullaniciGetiriPct: kendi,
      );
      if (h != null) satirlar[v] = h;
    }
    return KiyasOzeti(girdi: g, satirlar: satirlar);
  }
}

/// Sıralı anahtarlar üzerinde ikili arama — akış başına seriyi yeniden
/// sıralamamak için bir kez kurulur.
class _FiyatBulucu {
  _FiyatBulucu(Map<int, double> seri)
      : _seri = {
          for (final e in seri.entries)
            if (e.value > 0 && e.value.isFinite) e.key: e.value,
        } {
    _anahtarlar = _seri.keys.toList()..sort();
  }

  final Map<int, double> _seri;
  late final List<int> _anahtarlar;

  double? at(int ts) {
    final k = _anahtarlar;
    if (k.isEmpty) return null;
    // Son anahtar <= ts.
    var lo = 0, hi = k.length - 1, idx = -1;
    while (lo <= hi) {
      final m = (lo + hi) >> 1;
      if (k[m] <= ts) {
        idx = m;
        lo = m + 1;
      } else {
        hi = m - 1;
      }
    }
    if (idx >= 0) {
      if (ts - k[idx] > KiyasService.geriTolerans.inMilliseconds) return null;
      return _seri[k[idx]];
    }
    if (k.first - ts > KiyasService.ileriTolerans.inMilliseconds) return null;
    return _seri[k.first];
  }
}
