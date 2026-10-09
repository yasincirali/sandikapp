// Seçimlerinin getirisi — zaman ağırlıklı getiri (TWR), Yarış ve Zirve'nin
// ölçüsü (0095, 2026-10-01).
//
// ## Neden
// Yarış eskiden SİMÜLASYONDU: bugünkü sepet dönem başından beri tutulmuş
// sayılıyordu (`HistoryService.getPortfolioHistory(simulate: true)`). Ölçü
// kıyası ("Yarış Ölçüsü Kıyası", 2026-10-01) iki hatasını gösterdi: Y'yi
// satıp dipte X alan kullanıcı "hep X tutmuş" görünüyordu (kararı
// görünmüyordu) ve ay sonunda giren yeni kullanıcı bütün yılın getirisini
// alıyordu. Kullanıcı kararı R1: sıralama TWR — adı "Seçimlerinin
// getirisi"; kişinin kendi satırında ek bilgi olarak XIRR — "Paranın
// getirisi", Performans ile aynı sayı (`PeriodSummaryService`).
//
// ## Ne hesaplar
// Dönem günlere bölünür. Her gün, o günün BAŞINDAKİ miktarlar piyasa
// fiyatıyla değerlenir; günün getirisi `Σ q·p(gün sonu) / Σ q·p(gün başı)`;
// günler çarpılır. Paranın ne zaman, ne kadar eklendiği sonucu etkilemez —
// yalnız neyin tutulduğu. Kullanıcının girdiği alış FİYATI hiç kullanılmaz.
//
// ## Hile kuralları (sunucuyla aynı)
//   · Yarış anı ([yarisAni]): `addedDate` girişten ([Asset.createdAt]) 3
//     günden fazla gerideyse kayıt girildiği anda yapılmış sayılır — YALNIZ
//     anonim sıralamada ([SiralamaKapsami.anonim]: Zirve, genel). Ortaklar
//     arası Yarış'ta beyan edilen tarih geçerli (kullanıcı kararı
//     2026-10-01): herkes birbirini tanır, sahte kayıt yalnız arkadaşı
//     kandırır; buna karşılık geçmişini CSV/ekstreyle dürüstçe içe aktaran
//     kullanıcı 30 gün beklemeden sıralanır. Hile riski, kimliği bilinmeyen
//     portföyün herkesin önüne çıktığı anonim yüzeylerdedir.
//   · En az 30 gün ([asgariOlcumGun]; gerçek değer sunucudan, 0128) —
//     ilk varlığın EDİNME tarihinden (`addedDate`) sayılır, girişten değil
//     (kullanıcı kararı 2026-10-09). Getiri yine yarış anından ölçülür.
//   · Bugünkü portföyün %80'i fiyatlanamıyorsa sayı yok (uydurma yasağı).
//
// ## İki motor, tek kural
// Sunucu eşi `supabase/functions/leaderboard-snapshot/index.ts` ›
// `donemTwr` (Zirve ve genel havuz). Bu dosya Yarış'ta ortakları ve "Sen"
// satırını cihazda ölçer — ortağın lotları zaten burada ve canlı (2026-09-02
// kararı: snapshot beklemek bayat/eksik değer veriyordu). İki taraf AYNI
// senaryoyu geçer: `test/secim_getirisi_test.dart` ↔
// `supabase/tests/leaderboard_snapshot_test.ts`. Fiyat kaynağı farkı
// (istemci altını truncgil'den, sunucu GC=F'den) oranda sönümlenir.
import '../models/asset.dart';
import '../models/position.dart' show positionKey;
import 'history_service.dart';

/// `addedDate` girişten bu kadar gün gerideyse kayıt girildiği anda
/// yapılmış sayılır. Sunucu eşi `GERI_TARIH_PAYI_GUN`.
const int geriTarihPayiGun = 3;

/// Sıralamaya girmek için gereken en kısa süre (gün) — VARSAYILAN. Gerçek
/// değer sunucudaki `siralama_ayar` (0128, `siralama_asgari_olcum_gun`
/// RPC'si); okunamazsa bu. Sunucu eşi `ASGARI_OLCUM_GUN`. İlk varlığın
/// edinme tarihinden bugüne, dönemden bağımsız (2026-10-09; önce yarış
/// anından sayılıyordu, içe aktarılan geçmiş 30 gün bekliyordu).
const int asgariOlcumGun = 30;

/// Bugünkü değerin bu payı fiyatlanamıyorsa getiri yazılmaz. Sunucu eşi
/// `KAPSAMA_ESIGI`.
const double kapsamaEsigi = 0.8;

const int _gunMs = 24 * 60 * 60 * 1000;

/// Hangi sıralama için ölçülüyor — kaydın TARİHİNE güven buna bağlı
/// (kullanıcı kararı 2026-10-01). Formül ikisinde de aynı (TWR).
enum SiralamaKapsami {
  /// Ortaklar arası Yarış: beyan edilen tarih geçerli; içe aktarılan geçmiş
  /// hemen sayılır.
  ortaklar,

  /// Zirve ve genel sıralama (anonim): geriye tarih kuralı — sunucunun
  /// `donemTwr`'ı ile birebir (sunucu yalnız anonim yüzeyleri yazar).
  anonim,
}

/// Satırın yarışta sayılan anı (epoch ms). Ortaklar kapsamında ya da giriş
/// anı yoksa (0095 öncesi kopya) tarih olduğu gibi.
int yarisAni(Asset a, SiralamaKapsami kapsam) {
  final eklenme = a.addedDate.millisecondsSinceEpoch;
  final giris = a.createdAt?.millisecondsSinceEpoch;
  if (giris == null || kapsam == SiralamaKapsami.ortaklar) return eklenme;
  return eklenme < giris - geriTarihPayiGun * _gunMs ? giris : eklenme;
}

/// Bir pozisyonun miktar geçmişi: fiyatlama şablonu (en yeni alım) +
/// zamana göre sıralı hareketler (alım +, satış −).
class PozisyonGecmisi {
  PozisyonGecmisi(this.anahtar, this.sablon);

  final String anahtar;
  Asset sablon;
  final List<({int an, double miktar})> hareketler = [];

  /// Pozisyonun ilk alımının EDİNME anı (`addedDate`, epoch ms) — asgari
  /// süre kapısı bununla sayılır (sunucu eşi `ilkEdinmeAni`).
  int? ilkEdinme;

  /// `an ≤ t` hareketlerin toplamı; en az 0.
  double miktarAninda(int tMs) {
    var q = 0.0;
    for (final h in hareketler) {
      if (h.an > tMs) break;
      q += h.miktar;
    }
    return q > 1e-7 ? q : 0;
  }
}

/// Defteri pozisyon geçmişlerine böler. Yalnız aktif alım/satım; silinmiş,
/// mezar taşı ve temettü satırı miktara girmez.
///
/// [lotlar] TEK KİŞİNİN defteri olmalı: `positionKey` sahip taşımaz, iki
/// kişinin aynı hissesi tek pozisyona düşerdi (bkz. `lotlarSahibeGore`).
List<PozisyonGecmisi> pozisyonGecmisleri(
    Iterable<Asset> lotlar, SiralamaKapsami kapsam) {
  final gruplar = <String, PozisyonGecmisi>{};
  final sablonTarihi = <String, int>{};
  for (final a in lotlar) {
    if (a.deletedAt != null || !(a.isBuy || a.isSell)) continue;
    final q = a.quantity;
    if (!q.isFinite || q <= 0) continue;
    final key = positionKey(a);
    final g = gruplar.putIfAbsent(key, () => PozisyonGecmisi(key, a));
    g.hareketler.add((an: yarisAni(a, kapsam), miktar: a.isSell ? -q : q));
    if (a.isBuy) {
      final t = a.addedDate.millisecondsSinceEpoch;
      final e = g.ilkEdinme;
      if (e == null || t < e) g.ilkEdinme = t;
      final onceki = sablonTarihi[key];
      if (onceki == null || t > onceki) {
        sablonTarihi[key] = t;
        g.sablon = a;
      }
    }
  }
  for (final g in gruplar.values) {
    g.hareketler.sort((a, b) => a.an.compareTo(b.an));
  }
  return gruplar.values.toList();
}

/// Defterdeki ilk varlığın edinme anı; alım yoksa `null`.
int? ilkEdinmeAni(List<PozisyonGecmisi> gecmis) {
  int? ilk;
  for (final p in gecmis) {
    final e = p.ilkEdinme;
    if (e != null && (ilk == null || e < ilk)) ilk = e;
  }
  return ilk;
}

/// Ölçüm anları: başlangıç, sonra bugünden geriye tam günler, en sonda
/// bugün. Sunucu eşi `olcumAnlari` — ızgara bugüne hizalı.
List<int> olcumAnlari(int basMs, int nowMs) {
  if (nowMs <= basMs) return const [];
  final anlar = <int>[basMs];
  for (var k = (nowMs - basMs) ~/ _gunMs; k >= 1; k--) {
    final t = nowMs - k * _gunMs;
    if (t > basMs) anlar.add(t);
  }
  anlar.add(nowMs);
  return anlar;
}

/// Saf çekirdek — sunucunun `donemTwr`'ı ile birebir.
///
/// [birimFiyat]: pozisyonun `t` anındaki BİRİM TL fiyatı; serisi yoksa
/// `null`. [yedekBirimFiyat]: serisi olmayan pozisyonun bugünkü tahmini
/// birim TL değeri — yalnız kapsama kararı için (0 → bilinmiyor).
///
/// Sonuç [secimGetirisiSerisi]'nin SON noktasıdır: iki fonksiyon tek
/// döngüyü paylaşır (düello arenası lider şeridi, 2026-10-04) — şeridin
/// "bugün"ü sıralamadaki sayıdan ayrı bir hesap olamaz.
double? secimGetirisiPct({
  required List<PozisyonGecmisi> gecmis,
  required double? Function(PozisyonGecmisi p, int tMs) birimFiyat,
  required double Function(PozisyonGecmisi p) yedekBirimFiyat,
  required int nowMs,
  required int gun,
  int asgariGun = asgariOlcumGun,
}) =>
    secimGetirisiSerisi(
      gecmis: gecmis,
      birimFiyat: birimFiyat,
      yedekBirimFiyat: yedekBirimFiyat,
      nowMs: nowMs,
      gun: gun,
      asgariGun: asgariGun,
    )?.last.pct;

/// Seçimlerinin getirisinin GÜN GÜN birikimi: her ölçüm anında dönem
/// başından o ana kadarki TWR (%). Kapılar (asgari ölçüm, kapsama)
/// [secimGetirisiPct] ile aynı; geçemezse `null`.
///
/// Neden ayrı bir seri: Yarış'ın düello arenası (bayrak
/// `yaris_duello_arena`) dönemin her günü kimin önde olduğunu çizer. Sunucu
/// günlük TWR yazmıyor (snapshot yalnız dönem sonunu tutar); ama bu döngü
/// zaten her günün çarpanını hesaplıyor — ara toplamları atmak yerine
/// döndürür. Yeni hesap ya da yeni veri kaynağı değil.
///
/// Bir gün ölçülemezse (o gün fiyatlanan pozisyon yok) birikim değişmez ve
/// nokta önceki değerle tekrarlanır; ilk ölçülen günden önce nokta yok
/// (uydurma yok — şerit o günleri "bilinmiyor" çizer).
List<({int an, double pct})>? secimGetirisiSerisi({
  required List<PozisyonGecmisi> gecmis,
  required double? Function(PozisyonGecmisi p, int tMs) birimFiyat,
  required double Function(PozisyonGecmisi p) yedekBirimFiyat,
  required int nowMs,
  required int gun,
  int asgariGun = asgariOlcumGun,
}) {
  final edinme = ilkEdinmeAni(gecmis);
  if (edinme == null || nowMs - edinme < asgariGun * _gunMs) return null;
  // Ölçümün başladığı an: ilk alımın YARIŞ anı (geriye tarih kuralı).
  var ilk = -1;
  for (final p in gecmis) {
    for (final h in p.hareketler) {
      if (h.miktar > 0 && (ilk < 0 || h.an < ilk)) ilk = h.an;
    }
  }
  if (ilk < 0) return null;

  var deger = 0.0;
  var karanlik = 0.0;
  for (final p in gecmis) {
    final q = p.miktarAninda(nowMs);
    if (q <= 0) continue;
    final f = birimFiyat(p, nowMs);
    if (f == null) {
      karanlik += q * yedekBirimFiyat(p);
    } else {
      deger += q * f;
    }
  }
  if (deger <= 0 || deger < (deger + karanlik) * kapsamaEsigi) return null;

  final bas = nowMs - gun * _gunMs;
  final anlar = olcumAnlari(bas > ilk ? bas : ilk, nowMs);
  var carpim = 1.0;
  var olculdu = false;
  final noktalar = <({int an, double pct})>[];
  for (var i = 1; i < anlar.length; i++) {
    final a = anlar[i - 1];
    final b = anlar[i];
    var pay = 0.0;
    var payda = 0.0;
    for (final p in gecmis) {
      final q = p.miktarAninda(a);
      if (q <= 0) continue;
      final pa = birimFiyat(p, a);
      final pb = birimFiyat(p, b);
      if (pa == null || pb == null) continue;
      payda += q * pa;
      pay += q * pb;
    }
    if (payda <= 0) {
      if (olculdu) noktalar.add((an: b, pct: noktalar.last.pct));
      continue;
    }
    carpim *= pay / payda;
    olculdu = true;
    final roi = (carpim - 1) * 100;
    noktalar.add((
      an: b,
      pct: roi.isFinite ? roi.clamp(-100.0, 100000.0).toDouble() : double.nan,
    ));
  }
  if (!olculdu || !noktalar.last.pct.isFinite) return null;
  return noktalar;
}

/// Sıralı seride `t` anındaki değer: `t`'den önceki son nokta; seri `t`'den
/// sonra başlıyorsa ilk nokta. Sunucu eşi `fiyatAninda`.
double? seriDegeriAninda(List<(int, double)> seri, int tMs) {
  if (seri.isEmpty) return null;
  if (seri.first.$1 > tMs) return seri.first.$2;
  var lo = 0, hi = seri.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (seri[mid].$1 <= tMs) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return seri[lo].$2;
}

/// Ağdan seri çekerek ölçen giriş noktası.
abstract final class SecimGetirisi {
  /// [lotlar] (tek kişinin defteri) için [gun] günlük seçimlerinin getirisi
  /// (%). Seri yoksa, ölçüm kısaysa ya da kapsama düşükse `null`.
  ///
  /// Fiyat: her pozisyonun BİRİM serisi (`FiyatKaynagi.birimVarlik` —
  /// varlık ekranıyla aynı kaynak, sözleşmenin 1. maddesi), GÜNLÜK
  /// çözünürlükte: sunucu da günlük seriyle ölçer; haftalık ızgara 1Y'de
  /// alım/satım gününü bir haftaya yuvarlardı.
  static Future<double?> donemPct(
    List<Asset> lotlar,
    int gun, {
    required SiralamaKapsami kapsam,
    DateTime? simdi,
    int asgariGun = asgariOlcumGun,
  }) async =>
      (await donemSerisi(lotlar, gun,
              kapsam: kapsam, simdi: simdi, asgariGun: asgariGun))
          ?.last
          .pct;

  /// [donemPct]'in gün gün birikimi ([secimGetirisiSerisi]) — aynı seri,
  /// aynı kapılar; son nokta [donemPct]'tir. İki kişiyi gün gün kıyaslarken
  /// ikisine AYNI [simdi] verilir ki ölçüm anları hizalansın.
  static Future<List<({int an, double pct})>?> donemSerisi(
    List<Asset> lotlar,
    int gun, {
    required SiralamaKapsami kapsam,
    DateTime? simdi,
    int asgariGun = asgariOlcumGun,
  }) async {
    final gecmis = pozisyonGecmisleri(lotlar, kapsam);
    if (gecmis.isEmpty) return null;
    final now = simdi ?? DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    // Ağa çıkmadan önce ucuz kapı: süre kısaysa seri çekmeye gerek yok.
    final edinme = ilkEdinmeAni(gecmis);
    if (edinme == null || nowMs - edinme < asgariGun * _gunMs) return null;

    final bd =
        await HistoryService.instance.getPortfolioHistoryBreakdownAtResolution(
      assets: [for (final p in gecmis) FiyatKaynagi.birimVarlik(p.sablon)],
      from: now.subtract(Duration(days: gun + 1)),
      to: now,
      tier: ResolutionTier.daily,
    );
    final seriler = <String, List<(int, double)>>{};
    for (final p in gecmis) {
      final s = bd.byPosition[p.anahtar];
      if (s == null || s.isEmpty) continue;
      final noktalar = [
        for (final e in s.entries)
          if (e.value.isFinite && e.value > 0) (e.key, e.value),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      if (noktalar.isNotEmpty) seriler[p.anahtar] = noktalar;
    }
    return secimGetirisiSerisi(
      gecmis: gecmis,
      birimFiyat: (p, t) {
        final s = seriler[p.anahtar];
        return s == null ? null : seriDegeriAninda(s, t);
      },
      // Sunucunun `yedekTryFiyati` kuralı: TRY'de son bilinen fiyat;
      // kur bilinmeyen döviz kotesinde 0 (kapsamayı iyimser yapmaz).
      yedekBirimFiyat: (p) =>
          p.sablon.currency.toUpperCase() == 'TRY' ? p.sablon.currentPrice : 0,
      nowMs: nowMs,
      gun: gun,
      asgariGun: asgariGun,
    );
  }
}
