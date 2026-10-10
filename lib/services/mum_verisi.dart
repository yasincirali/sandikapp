import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../demo/demo_modu.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/ohlc.dart';
import '../utils/mum_turetici.dart';
import 'crash_reporter.dart';
import 'history_service.dart'; // FiyatKaynagi'ni de yayımlar
import 'price_service.dart';
import 'supabase_service.dart';

/// Gerçek mum verisi — TradingView'deki gibi aralık seçilen mum grafiği
/// (yasin, 2026-10-10). Varlık ekranının Premium mum katmanı okur; özel
/// gösterge katmanı da (ayrı iş) aynı [OhlcBar] listesini okur.
///
/// ## Katmanlar
///   * **Kaynak kararı** `FiyatKaynagi.mumKaynagi` — burada sembol seçilmez
///     (sözleşme madde 1).
///   * **Saf dönüşümler** bu dosyanın üst-düzey fonksiyonları: ayrıştırma,
///     kur çevrimi, altın çarpanı, ölçek hizası, kapanıştan mum, pencere.
///     Hepsi test edilir (`test/mum_verisi_test.dart`).
///   * **Çekim** [MumVerisi] — ağ, önbellek, hata yutma (Crashlytics'e
///     non-fatal). Boş liste "mum yok" demektir; çağıran eski (kapanıştan
///     türetilen) mumlara düşer, ekran boş kalmaz.
///
/// ## Uydurma yok (madde 3)
/// Kuru bulunmayan bar düşer; dört fiyatından biri eksik bar düşer; fon ve
/// eurobond'a gün içi mum yazılmaz. Mum sayısı sınırı (bkz.
/// [gecerliAraliklar]) çizimi korur, veriyi kırpmaz: sığmayan aralık hiç
/// sunulmaz.

// ── Ayrıştırma ──────────────────────────────────────────────────────────────

/// Yahoo `v8/finance/chart` yanıtı → barlar. Dört fiyatından biri `null`
/// olan bar (Yahoo'nun seans arası boş satırları) atlanır.
List<OhlcBar> yahooOhlcCoz(Map<String, dynamic> body) {
  final result =
      (body['chart']?['result'] as List?)?.firstOrNull as Map<String, dynamic>?;
  if (result == null) return const [];
  final ts = (result['timestamp'] as List?) ?? const [];
  final q = ((result['indicators']?['quote'] as List?)?.firstOrNull
          as Map<String, dynamic>?) ??
      const {};
  List<Object?> l(String k) => (q[k] as List?) ?? const [];
  final o = l('open'), h = l('high'), lo = l('low'), c = l('close');
  final v = l('volume');
  final out = <OhlcBar>[];
  for (var i = 0; i < ts.length; i++) {
    double? d(List<Object?> x) =>
        i < x.length ? (x[i] as num?)?.toDouble() : null;
    final t = (ts[i] as num?)?.toInt();
    final bar = (t, d(o), d(h), d(lo), d(c));
    if (bar case (final t?, final ac?, final yu?, final du?, final ka?)) {
      final b = OhlcBar(
        t: t * 1000,
        acilis: ac,
        // Yahoo'nun yuvarlaması kimi barda yüksek < kapanış bırakıyor;
        // fitil gövdeyi her zaman kapsar.
        enYuksek: math.max(yu, math.max(ac, ka)),
        enDusuk: math.min(du, math.min(ac, ka)),
        kapanis: ka,
        hacim: d(v),
      );
      if (b.gecerli) out.add(b);
    }
  }
  out.sort((a, b) => a.t.compareTo(b.t));
  return out;
}

/// `kripto-seri` `mumlar` alanı (`[[ms, o, h, l, c, hacim?], …]`) → barlar.
List<OhlcBar> kriptoMumlariCoz(Object? rows) {
  if (rows is! List) return const [];
  final out = <OhlcBar>[];
  for (final r in rows) {
    if (r is! List || r.length < 5) continue;
    double? d(int i) => (r[i] as num?)?.toDouble();
    final t = (r[0] as num?)?.toInt();
    final o = d(1), h = d(2), l = d(3), c = d(4);
    if (t == null || o == null || h == null || l == null || c == null) {
      continue;
    }
    final b = OhlcBar(
      t: t,
      acilis: o,
      enYuksek: h,
      enDusuk: l,
      kapanis: c,
      hacim: r.length > 5 ? d(5) : null,
    );
    if (b.gecerli) out.add(b);
  }
  out.sort((a, b) => a.t.compareTo(b.t));
  return out;
}

// ── Dönüşümler ──────────────────────────────────────────────────────────────

/// USD barlarını TL'ye çevirir: her bar, KAPANIŞ anına (açılış + uzunluk)
/// eşit ya da öncesindeki en yeni kur noktasıyla çarpılır — o barın
/// kapanışında geçerli kur. Kur [toleransMs]'ten eskiyse bar DÜŞER
/// (sözleşme madde 3; hafta sonu boşluğunu atlatacak kadar geniş).
List<OhlcBar> kurlaCevir(
  List<OhlcBar> barlar,
  List<(int, double)> kur, {
  required MumAraligi aralik,
  int toleransMs = 4 * 24 * 60 * 60 * 1000,
}) {
  if (barlar.isEmpty || kur.isEmpty) return const [];
  final k = [
    for (final p in kur)
      if (p.$2.isFinite && p.$2 > 0) p,
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  if (k.isEmpty) return const [];
  final out = <OhlcBar>[];
  for (final b in barlar) {
    final kapanisAni = b.t + barUzunluguMs(b.t, aralik);
    // Son <= kapanisAni noktası (ikili arama).
    var lo = 0, hi = k.length - 1, bul = -1;
    while (lo <= hi) {
      final m = (lo + hi) >> 1;
      if (k[m].$1 <= kapanisAni) {
        bul = m;
        lo = m + 1;
      } else {
        hi = m - 1;
      }
    }
    if (bul < 0) continue;
    if (kapanisAni - k[bul].$1 > toleransMs + barUzunluguMs(b.t, aralik)) {
      continue;
    }
    out.add(b.carp(k[bul].$2));
  }
  return out;
}

/// Ons/TL barlarını ürün birimine taşır: gram22k (`gram22kFromXauTry`) ×
/// ürün çarpanı (çeyrek 1,75 …). Çizginin kullandığı AYNI iki adım.
List<OhlcBar> altinaCevir(List<OhlcBar> onsTl, double agirlik) {
  final k = PriceService.gram22kFromXauTry(1) * agirlik;
  return [for (final b in onsTl) b.carp(k)];
}

/// Canlı fiyata hiza (madde 2) ve son barın canlı fiyata sabitlenmesi.
///
///  1. [alt]/[ust] verilmişse (kaynak ekrandan farklı sağlayıcı: altın,
///     TL dövizi) bütün seri `canlı ÷ son kapanış` oranıyla taşınır — gram
///     serisinin `altinKalibrasyonu` ile aynı kural ve aynı bant. Oransal:
///     mumların şekli, yüzdeler, EMA değişmez; yalnız seviye.
///  2. Son bar hâlâ AÇIKSA (kapanış anı gelmemiş) kapanışı canlı fiyattır,
///     fitili de onu kapsar — TradingView'in oluşan mumu. Çizginin son
///     noktası da canlı fiyata sabitlenir (`_convertHistoryToSegments`);
///     başlık, çizgi ucu ve son mum aynı sayıyı söyler. Kapanmış bara
///     dokunulmaz: piyasa kapalıyken o bar tarihtir.
///
/// Canlı fiyat son kapanıştan %10'dan fazla saparsa (bayat ya da yanlış
/// kotasyon) sabitleme yapılmaz — tek sayı bütün mumu bozmasın.
List<OhlcBar> canliyaHizala(
  List<OhlcBar> barlar, {
  required double canli,
  required MumAraligi aralik,
  required DateTime simdi,
  double? alt,
  double? ust,
}) {
  if (barlar.isEmpty || !canli.isFinite || canli <= 0) return barlar;
  var out = barlar;
  if (alt != null && ust != null) {
    final k = olcekCarpani(
        seriSon: out.last.kapanis, canli: canli, alt: alt, ust: ust);
    if (k != 1.0) out = [for (final b in out) b.carp(k)];
  }
  final son = out.last;
  final acik =
      son.t + barUzunluguMs(son.t, aralik) > simdi.millisecondsSinceEpoch;
  final oran = canli / son.kapanis;
  if (!acik || oran < 0.90 || oran > 1.11) return out;
  return [
    ...out.take(out.length - 1),
    OhlcBar(
      t: son.t,
      acilis: son.acilis,
      enYuksek: math.max(son.enYuksek, canli),
      enDusuk: math.min(son.enDusuk, canli),
      kapanis: canli,
      hacim: son.hacim,
    ),
  ];
}

/// Günde tek fiyatı olan seriden (TEFAS NAV, eurobond kapanışı) mum.
///
/// Kova takvime hizalı (gün / Pazartesi / ayın 1'i, `kovaBaslangici`).
/// AÇILIŞ önceki kovanın kapanışıdır — fonun "açılış fiyatı" yoktur, ama
/// dün akşamki fiyattan bugünkü fiyata geçiş günün hareketidir. En
/// yüksek/en düşük, açılış dahil kovadaki fiyatların uçlarıdır. İlk kova
/// kendi ilk fiyatıyla açılır. Bu mumlar sağlayıcı OHLC'si DEĞİLDİR; ekran
/// bunu altyazıyla söyler.
List<OhlcBar> kapanislardanMumlar(
    List<(int, double)> kapanislar, MumAraligi aralik) {
  final sirali = [
    for (final p in kapanislar)
      if (p.$2.isFinite && p.$2 > 0) p,
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  if (sirali.isEmpty) return const [];
  final kovaMs = aralik.ms.toDouble();
  final out = <OhlcBar>[];
  int? kova;
  double? oncekiKapanis;
  late double ac, yu, du, ka;
  void kapat() {
    if (kova == null) return;
    out.add(
        OhlcBar(t: kova, acilis: ac, enYuksek: yu, enDusuk: du, kapanis: ka));
    oncekiKapanis = ka;
  }

  for (final (t, f) in sirali) {
    final bas = kovaBaslangici(DateTime.fromMillisecondsSinceEpoch(t), kovaMs)
        .millisecondsSinceEpoch;
    if (bas != kova) {
      kapat();
      kova = bas;
      ac = oncekiKapanis ?? f;
      yu = math.max(ac, f);
      du = math.min(ac, f);
    }
    if (f > yu) yu = f;
    if (f < du) du = f;
    ka = f;
  }
  kapat();
  return out;
}

/// Pencereye düşen barlar: barın bir kısmı bile [basMs, sonMs] içindeyse.
List<OhlcBar> pencereyeKirp(
    List<OhlcBar> barlar, int basMs, int sonMs, MumAraligi aralik) {
  return [
    for (final b in barlar)
      if (b.t + barUzunluguMs(b.t, aralik) > basMs && b.t <= sonMs) b,
  ];
}

/// Barları grafiğin X uzayına (dönem başından [birimMs] cinsinden) taşır:
/// çizim nesnesi [Mum]. Kova genişliği barın gerçek uzunluğu.
List<Mum> grafikMumlari(
  List<OhlcBar> barlar, {
  required MumAraligi aralik,
  required double baslangicMs,
  required double birimMs,
}) {
  return [
    for (final b in barlar)
      Mum(
        x: (b.t - baslangicMs) / birimMs,
        kovaMs: barUzunluguMs(b.t, aralik) / birimMs,
        acilis: b.acilis,
        enYuksek: b.enYuksek,
        enDusuk: b.enDusuk,
        kapanis: b.kapanis,
        noktaSayisi: 1,
      ),
  ];
}

// ── Aralık seçimi ───────────────────────────────────────────────────────────

/// Grafiğin taşıyabileceği en çok mum. Toplu çizimde (`mumCubuklariToplu`)
/// mum başına iki çubuk değil dört seri toplam çizilir; 1.500 mum (kriptoda
/// GÜNLÜK × 1 dk: 1.440) akıcı kalır. Üstü (1H × 1 dk = 10.080) hem
/// okunmaz hem ağır — o aralık o dönemde sunulmaz.
const int azamiMum = 1500;

/// En az mum: iki mum "grafik" değil.
const int asgariMum = 3;

/// Varsayılan aralık bu kadar muma en yakın olandır — TradingView'in ilk
/// açılışta ekrana sığdırdığı yoğunluk.
const int hedefMum = 80;

/// Varlığın işlem gördüğü süre — beklenen mum sayısı için. Gün içi
/// seans uzunluğu (dk) ve haftanın kaç günü.
({int gunDakika, int haftaGunu}) _seans(Asset a) {
  if (FiyatKaynagi.yediGun(a)) return (gunDakika: 1440, haftaGunu: 7);
  switch (a.type.fiyatlamaTuru) {
    case AssetType.hisse:
      // BIST ~10:00–18:00 (+ açılış/kapanış seansı), ABD 6,5 saat.
      final bist = a.ticker.trim().toUpperCase().endsWith('.IS') ||
          a.currency.trim().toUpperCase() == 'TRY';
      return (gunDakika: bist ? 480 : 390, haftaGunu: 5);
    case AssetType.fon:
    case AssetType.eurobond:
      return (gunDakika: 1, haftaGunu: 5);
    default:
      // Döviz, altın, emtia: hafta içi neredeyse 24 saat.
      return (gunDakika: 1380, haftaGunu: 5);
  }
}

/// [aralik] ile [spanDakika]'lık pencerede kaç mum çıkar (tahmin). Ağa
/// çıkmadan seçicinin hangi aralıkları sunacağına karar vermek için.
double beklenenMumSayisi(Asset a, MumAraligi aralik, double spanDakika) {
  if (!spanDakika.isFinite || spanDakika <= 0) return 0;
  final s = _seans(a);
  final gun = spanDakika / 1440;
  if (!aralik.gunIci) {
    final islemGunu = gun <= 1 ? 1.0 : gun * s.haftaGunu / 7;
    return islemGunu / (aralik.dakika / 1440);
  }
  final islemDakikasi = gun <= 1
      ? math.min(spanDakika, s.gunDakika.toDouble())
      : gun * s.haftaGunu / 7 * s.gunDakika;
  return islemDakikasi / aralik.dakika;
}

/// Bu varlıkta ve bu pencerede sunulacak aralıklar, küçükten büyüğe.
List<MumAraligi> gecerliAraliklar(Asset a, double spanDakika) {
  final k = FiyatKaynagi.mumKaynagi(a);
  return [
    for (final ar in k.araliklar)
      if (beklenenMumSayisi(a, ar, spanDakika) case final n
          when n >= asgariMum && n <= azamiMum)
        ar,
  ];
}

/// Seçimden çizilecek aralık: seçim geçerliyse o, değilse [hedefMum]'a
/// (logaritmik) en yakın geçerli aralık. Geçerli aralık yoksa null — çağıran
/// kapanıştan türetilen eski muma düşer.
MumAraligi? etkinAralik(Asset a, double spanDakika, MumAraligi? secim) {
  final gecerli = gecerliAraliklar(a, spanDakika);
  if (gecerli.isEmpty) return null;
  if (secim != null && gecerli.contains(secim)) return secim;
  MumAraligi? en;
  var fark = double.infinity;
  for (final ar in gecerli) {
    final n = beklenenMumSayisi(a, ar, spanDakika);
    final f = (math.log(n) - math.log(hedefMum)).abs();
    if (f < fark) {
      fark = f;
      en = ar;
    }
  }
  return en;
}

// ── Çekim ───────────────────────────────────────────────────────────────────

/// Mum çekimi — ağ, önbellek, hata yutma.
class MumVerisi {
  MumVerisi._();
  static final MumVerisi instance = MumVerisi._();

  final _onbellek = <String, ({DateTime zaman, Future<List<OhlcBar>> sonuc})>{};

  /// Önbellek ömrü: gün içi bir dakika (bar tazelenir), diğerleri on dakika.
  static Duration _omur(MumAraligi a) =>
      a.gunIci ? const Duration(minutes: 1) : const Duration(minutes: 10);

  @visibleForTesting
  void onbellegiTemizle() => _onbellek.clear();

  /// Test dikişi: ağ yerine sahte çekim (`HistoryService.seriCekici` gibi).
  /// Dönen barlar ham kabul edilir; hiza yine uygulanır.
  @visibleForTesting
  static Future<List<OhlcBar>> Function(
      Asset a, MumAraligi aralik, DateTime bas, DateTime son)? testCekici;

  /// [a]'nın [bas, son] penceresindeki [aralik] mumları, TL, canlı fiyata
  /// hizalı. Kaynak yoksa ya da çekim başarısızsa boş liste.
  Future<List<OhlcBar>> mumlar({
    required Asset a,
    required MumAraligi aralik,
    required DateTime bas,
    required DateTime son,
    required double canliBirim,
  }) {
    final kaynak = FiyatKaynagi.mumKaynagi(a);
    if (kaynak.tur == MumKaynakTuru.yok ||
        (DemoModu.aktif && testCekici == null)) {
      return Future.value(const []);
    }
    final simdi = DateTime.now();
    // Anahtar: kaynak + aralık + pencere (dakikaya yuvarlı). Canlı fiyat
    // anahtara girmez; hiza her okumada yeniden uygulanır.
    final anahtar = '${a.ticker}|${a.type.name}|${aralik.name}|'
        '${bas.millisecondsSinceEpoch ~/ 60000}|'
        '${son.millisecondsSinceEpoch ~/ 60000}';
    final eski = _onbellek[anahtar];
    final Future<List<OhlcBar>> ham;
    if (eski != null && simdi.difference(eski.zaman) < _omur(aralik)) {
      ham = eski.sonuc;
    } else {
      final cek = testCekici;
      ham = (cek != null
              ? cek(a, aralik, bas, son)
              : _cek(a, kaynak, aralik, bas, son))
          .catchError((Object e, StackTrace st) {
        CrashReporter.report(e, st, reason: 'mum_verisi_cekilemedi');
        return const <OhlcBar>[];
      });
      _onbellek[anahtar] = (zaman: simdi, sonuc: ham);
    }
    return ham.then((barlar) {
      if (barlar.isEmpty) _onbellek.remove(anahtar); // boş önbelleğe girmez
      return canliyaHizala(
        barlar,
        canli: canliBirim,
        aralik: aralik,
        simdi: DateTime.now(),
        alt: kaynak.olcekAlt,
        ust: kaynak.olcekUst,
      );
    });
  }

  Future<List<OhlcBar>> _cek(Asset a, MumKaynagi k, MumAraligi aralik,
      DateTime bas, DateTime son) async {
    final basMs = bas.millisecondsSinceEpoch;
    final sonMs = son.millisecondsSinceEpoch;
    switch (k.tur) {
      case MumKaynakTuru.yok:
        return const [];
      case MumKaynakTuru.kripto:
        final barlar = await SupabaseService.instance.kriptoMumlari(
          kod: k.sembol,
          aralik: aralik.kriptoAraligi,
          donem: kriptoDonemi(son.difference(bas)),
        );
        return pencereyeKirp(barlar, basMs, sonMs, aralik);
      case MumKaynakTuru.kapanis:
        // Çizginin AYNI motoru ve birim varlığı; pencere bir hafta önden
        // başlar ki ilk kovanın açılışı (önceki kapanış) bilinsin.
        final b = await HistoryService.instance
            .getPortfolioHistoryBreakdownAtResolution(
          assets: [FiyatKaynagi.birimVarlik(a)],
          from: bas.subtract(const Duration(days: 7)),
          to: son,
          tier: ResolutionTier.daily,
        );
        final mumlar = kapanislardanMumlar(
            [for (final e in b.total.entries) (e.key, e.value)], aralik);
        return pencereyeKirp(mumlar, basMs, sonMs, aralik);
      case MumKaynakTuru.yahoo:
        // Bir bar önden: pencerenin ilk barı tam gelsin.
        final p1 = bas.subtract(Duration(minutes: aralik.dakika));
        var usd = k.usdCevir;
        var barlar =
            await PriceService.instance.fetchOhlc(k.sembol, aralik, p1, son);
        if (barlar.isEmpty && k.yedekSembol != null) {
          // Altın merdiveni: spot yoksa vadeli (USD kote). Karışım yok.
          barlar = await PriceService.instance
              .fetchOhlc(k.yedekSembol!, aralik, p1, son);
          usd = true;
        }
        if (barlar.isEmpty) return const [];
        if (usd) {
          // Kur, barla aynı aralıkta: her barın kapanışındaki kur.
          final kur = await PriceService.instance
              .fetchOhlc(FiyatKaynagi.usdTry, aralik, p1, son);
          barlar = kurlaCevir(barlar, [for (final b in kur) (b.t, b.kapanis)],
              aralik: aralik);
        }
        if (k.altinAgirligi case final w?) barlar = altinaCevir(barlar, w);
        return pencereyeKirp(barlar, basMs, sonMs, aralik);
    }
  }

  /// Pencereyi kapsayan en dar `kripto-seri` dönemi (Yahoo `range` adları).
  @visibleForTesting
  static String kriptoDonemi(Duration pencere) {
    final g = pencere.inMinutes / 1440;
    if (g <= 1) return '1d';
    if (g <= 5) return '5d';
    if (g <= 31) return '1mo';
    if (g <= 92) return '3mo';
    if (g <= 183) return '6mo';
    if (g <= 366) return '1y';
    if (g <= 731) return '2y';
    if (g <= 1827) return '5y';
    return 'max';
  }
}
