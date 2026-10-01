import 'dart:math' as math;

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
