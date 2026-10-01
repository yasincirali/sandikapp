import 'dart:math' as math;

import '../models/asset.dart';

/// Bir lot satırının portföyün GETİRİ hesabındaki nakit akışı (TRY):
/// portföye giren para +, portföyden çıkan para −.
///
/// **TEK KAYNAK** — dönem içi para ağırlıklı getiri (Özet, Grafik kartı,
/// tür dökümü, varlık ekranı, GÜNLÜK: ana sayfa, widget, Live Activity)
/// akışını buradan okur.
///
///   · alım → `+totalCostTRY` (komisyon dahil),
///   · satış → `−sellProceedsTRY` (maliyet değil ele geçen tutar),
///   · nakit temettü → `−dividendTRY`,
///   · silinen lot / mezar taşı → 0 (`isActive` ikisini de eler).
///
/// ## Neden temettü ÇIKIŞ (kullanıcı kararı 2026-10-01: "tek getiri dili,
/// XIRR her yerde")
/// Değer serisi yalnızca ELDEKİ varlıkları ölçer; nakit izlenmez. Temettü
/// ödendiğinde hisse fiyatı temettü kadar düşer ve bu düşüş seride vardır,
/// ama ödenen nakit seride YOKTUR — kullanıcının cebine (aracı kurumdaki
/// nakde) çıkmıştır. Satış gelirinde olduğu gibi: para portföyden çıktı.
/// Akışa girmediği sürece dönem getirisi temettüyü hiç saymıyordu ve
/// Derinlik'teki XIRR (`XirrService`, temettüyü cebe giren akış sayar) ile
/// çelişiyordu: emülatörde 1Y Özet %23,05 / XIRR %32,02, köprünün altında
/// da piyasa rakamının içinde OLMAYAN "Bunun nakit temettüsü ₺150.706"
/// yazıyordu. Eski not ("temettü piyasaTRY içinde erir") yanlıştı: fiyat
/// düşüşü seride, nakit değil.
///
/// Katkı (birikim disiplini: "bu ay ne kadar para koydum") ayrı bir
/// sorudur ve temettüyü saymaz — `PeriodSummaryService.flowOf`.
double getiriAkisi(Asset a) {
  if (!a.isActive) return 0;
  if (a.isBuy) return a.totalCostTRY;
  if (a.isSell) return -a.sellProceedsTRY;
  if (a.isDividend) return -a.dividendTRY;
  return 0;
}

/// Bir dönem içi nakit akışı: tutar (TRY, alım +, satış −) ve dönemde
/// KALDIĞI sürenin payı (`w`: dönem başında 1, dönem sonunda 0).
typedef DonemAkisi = ({double f, double w});

/// Dönemin PARA AĞIRLIKLI getirisi (yüzde) — dönem içi IRR. TEK hesap:
/// Özet (her dönem), Grafik kartının "piyasa etkisi" satırı ve GÜNLÜK
/// (ana sayfa, widget, Live Activity) buraya bakar.
///
/// ## Neden (2026-10-01, yasin: "best practice'lerle karşılaştır",
/// "bulgu çıkarsa tüm zaman aralıklarında uygulanmalı")
/// "Benim param enflasyonu yendi mi" sorusu yatırımcının KENDİ parasının
/// deneyimidir; GIPS/CFA pratiğinde bunun ölçüsü para ağırlıklı getiridir
/// (zaman ağırlıklı getiri yöneticiyi ölçer). Modified Dietz (ortalama
/// sermaye) bu getirinin doğrusal yaklaşığıdır; kısa dönemde ve küçük
/// akışta yeterli, uzun dönemde büyük akışta sapar. Ölçüldü: gerçek portföy
/// şeklinde 1Y %31,96 (Dietz) / %32,84 (kesin); dipte büyük alımda
/// %62,23 / %66,44 — %31,5 TÜFE'nin yanında hükmü çevirebilecek fark.
///
/// Denklem:  bas·(1+r) + Σ f_i·(1+r)^(w_i) = son
/// Dietz bunun `(1+r)^w ≈ 1 + w·r` doğrusallaştırması; aynı akışlar, aynı
/// ağırlıklar.
///
/// Kapılar (Dietz'den devralındı, sayı uydurulmaz):
///   · ortalama sermaye `bas + Σ f·w` pozitif değilse `null`,
///   · akış yoksa kesin `son/bas − 1` (yaklaşık değil),
///   · kök bulunamaz ya da işareti `son − bas − Σf` (₺ piyasa) ile
///     tutmazsa Dietz sonucu döner — yüzde ₺ satırıyla aynı yönü söyler
///     (TWR'nin reddedilme sebebi buydu).
double? paraAgirlikliGetiriPct({
  required double bas,
  required double son,
  required List<DonemAkisi> akislar,
}) {
  var sermaye = bas;
  var katki = 0.0;
  for (final a in akislar) {
    sermaye += a.f * a.w;
    katki += a.f;
  }
  if (sermaye <= 0) return null;
  final piyasa = son - bas - katki;
  final dietz = piyasa / sermaye * 100;
  if (akislar.isEmpty || piyasa == 0 || bas <= 0) return dietz;

  double fark(double r) {
    var v = bas * (1 + r);
    for (final a in akislar) {
      v += a.f * math.pow(1 + r, a.w);
    }
    return v - son;
  }

  // r = 0'da fark = −piyasa; kök piyasanın işaret tarafındadır.
  var lo = piyasa > 0 ? 0.0 : -0.999999;
  var hi = piyasa > 0 ? 1.0 : 0.0;
  if (piyasa > 0) {
    while (fark(hi) < 0 && hi < 1e6) {
      hi *= 2;
    }
  }
  final fLo = fark(lo);
  final fHi = fark(hi);
  if (!fLo.isFinite || !fHi.isFinite || fLo.sign == fHi.sign) return dietz;
  for (var i = 0; i < 200; i++) {
    final m = (lo + hi) / 2;
    if (fark(m).sign == fLo.sign) {
      lo = m;
    } else {
      hi = m;
    }
  }
  final r = (lo + hi) / 2 * 100;
  if (!r.isFinite || r.sign != piyasa.sign) return dietz;
  return r;
}

/// Bir ANIN TÜFE fiyat düzeyi — aylık endeksten okunur.
///
/// ## Kural: ay sonu çapaları arasında sabit aylık hız
/// Endeks tablosunun anahtarı ayın 1'idir ama değer o ayın ÖLÇÜMÜDÜR ve
/// uygulama onu AY SONU düzeyi sayar: TÜFE penceresi `ilkAy`'ın son günü
/// 00:00'ından `sonAy`'ın son günü 00:00'ına kurulur
/// (`InflationWindow.seriBaslangici` / `seriBitisi`). Aynı sözleşmeyle her
/// ayın son günü 00:00 bir ÇAPA'dır; iki çapa arasındaki an için düzey,
/// o ayın açıklanmış enflasyonunun ay içine SABİT HIZLA yayıldığı
/// varsayımıyla okunur:
///
///     I(t) = I(M−1) · (I(M) / I(M−1)) ^ ((t − çapa(M−1)) / (çapa(M) − çapa(M−1)))
///
/// Çapanın kendisinde tam olarak o ayın endeksi çıkar, yani pencere uçları
/// TÜFE penceresinin endeksleriyle birebir örtüşür.
///
/// **Neden basamak değil.** "Son ölçülmüş ay sonu" basamağı ay ortasında
/// eklenen paraya o ayın TAMAMININ enflasyonunu yüklüyordu (ay yarısında
/// girmiş ama ayın hepsini "yaşamış"). Ölçüldü: 1A'da 16'sında eklenen
/// ₺10.200 reel getiriyi +%0,20'den −%0,69'a çeviriyordu — tek aylık
/// pencerede kapalı formülden de kötü. Sabit hızla, enflasyon pencere
/// içinde düzgün dağıldığında reel getiri kapalı formülle `(1+n)/(1+e)−1`
/// BİREBİR aynıdır (cebirsel olarak; 1A her zaman bu durumda); fark
/// yalnızca aylar arası enflasyon eşit değilken doğar — K4'ün düzelttiği
/// şey tam olarak o: Ocak'ın yüksek enflasyonu Haziran'da eklenen paraya
/// yüklenmez.
///
/// Ay içi değer TÜİK'in açıkladığı bir sayı DEĞİLDİR ve ekrana yazılmaz;
/// yalnızca bir akışı fiyat düzeyine taşımak için ara hesaptır
/// (`InflationService.indexSeries` grafikte ara gün üretmez, o kural
/// görüntü içindir). Gereken iki aydan biri yoksa `null` — sayı uydurulmaz.
double? tufeDuzeyi(Map<DateTime, double> endeks, DateTime t) {
  DateTime capa(int y, int m) => DateTime(y, m + 1, 0);
  // t'yi içeren çapa aralığı: (çapa(M−1), çapa(M)].
  var y = t.year;
  var m = t.month;
  if (t.isAfter(capa(y, m))) {
    m += 1;
    if (m > 12) {
      m = 1;
      y += 1;
    }
  }
  final sonCapa = capa(y, m);
  final oncekiCapa = capa(y, m - 1);
  final iSon = endeks[DateTime(y, m, 1)];
  if (iSon == null || iSon <= 0) return null;
  if (!t.isBefore(sonCapa)) return iSon;
  final iOnce = endeks[DateTime(y, m - 1, 1)];
  if (iOnce == null || iOnce <= 0) return null;
  final pay = t.difference(oncekiCapa).inMilliseconds /
      sonCapa.difference(oncekiCapa).inMilliseconds;
  return iOnce * math.pow(iSon / iOnce, pay);
}

/// Dönemin REEL para ağırlıklı getirisi (yüzde).
///
/// ## Neden (2026-10-01, K4)
/// Eski reel `(1+n)/(1+e) − 1` dönemin TOPLAM enflasyonunu her paraya,
/// portföyde kaldığı süreyle orantılı ve DÜZGÜN dağılmış sayıyordu:
/// Haziran'da eklenen ₺100.000, yılın enflasyonunun Ocak'ta yığıldığı bir
/// yılda da "ortalama" ayların enflasyonunu yaşamış oluyordu. Doğrusu, her
/// tutarı KENDİ tarihindeki fiyat düzeyine taşıyıp (`tufeDuzeyi`) aynı
/// para ağırlıklı denklemi çözmek:
///
///     bas·(1+r) + Σ f_i·k_i·(1+r)^(w_i) = son·k_son,   k = I_bas / I(t)
///
/// Ağırlıklar ([DonemAkisi.w]) nominal hesapla AYNI; değişen yalnızca
/// tutarların ölçeği. Akış yoksa `son/bas · I_bas/I_son − 1`, yani kapalı
/// formülle birebir. Akış varken de enflasyon pencerede düzgün dağıldıysa
/// birebir (cebir `tufeDuzeyi` notunda); ayrıştığı yer, aylık enflasyonun
/// eşit olmadığı uzun pencere — yıl başındaki yüksek ayları sonradan
/// eklenen para yaşamamıştır.
///
/// [akislar] her akışın tutarını, ağırlığını ve ANINI taşır; [basAn] /
/// [sonAn] dönem uçlarının fiyat düzeyi anları (Özet'te TÜFE penceresinin
/// uçları: nominal de o pencereye atfedilip puan farkıyla kıyaslanıyor). Herhangi bir an için endeks
/// yoksa `null` (uydurma sayı yasak — CLAUDE.md fiyat kaynağı (3)).
double? reelParaAgirlikliGetiriPct({
  required double bas,
  required double son,
  required DateTime basAn,
  required DateTime sonAn,
  required List<({double f, double w, DateTime an})> akislar,
  required Map<DateTime, double> endeks,
}) {
  final iBas = tufeDuzeyi(endeks, basAn);
  final iSon = tufeDuzeyi(endeks, sonAn);
  if (iBas == null || iSon == null) return null;
  final reelAkislar = <DonemAkisi>[];
  for (final a in akislar) {
    final i = tufeDuzeyi(endeks, a.an);
    if (i == null) return null;
    reelAkislar.add((f: a.f * iBas / i, w: a.w));
  }
  return paraAgirlikliGetiriPct(
    bas: bas,
    son: son * iBas / iSon,
    akislar: reelAkislar,
  );
}
