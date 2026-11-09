import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

import '../services/para_agirlikli_getiri.dart';
import '../utils/tr_format.dart' show dayKey;
import 'asset.dart';

/// Varlığı ne zamandır tuttuğun ve o süredeki yıllık ortalama getirin
/// (Ar-Ge 7 Kas 20:30 #6, Premium).
///
/// ## Neden
/// Varlık ekranı pozisyonun alıştan bugüne getirisini toplam olarak yazar
/// ("+%180"); 3 yıldır tutulan fonda bunun yılda ne ettiği okunmuyordu.
/// Yüksek enflasyonda tek doğru karşılaştırma yıllık orandır.
@immutable
class EldeTutma {
  const EldeTutma(
      {required this.yil, required this.ay, required this.yillikPct});

  /// Tam yıl ve artan ay (2 yıl 3 ay → 2, 3).
  final int yil;
  final int ay;

  /// Yıllık ortalama getiri, yüzde (işaretli; −%12,3 de olabilir).
  final double yillikPct;

  @override
  bool operator ==(Object other) =>
      other is EldeTutma &&
      other.yil == yil &&
      other.ay == ay &&
      other.yillikPct == yillikPct;

  @override
  int get hashCode => Object.hash(yil, ay, yillikPct);
}

/// Pozisyonun [lotlar]'ından (ham defter ya da açık pozisyonun satırları)
/// elde tutma süresi ve yıllık ortalama getiri. Saf.
///
/// ## Hesap
/// Getiri TEK KAYNAKTAN: `paraAgirlikliGetiriPct` (Özet ve GÜNLÜK'ün para
/// ağırlıklı getirisi), akış `getiriAkisi` (alım +maliyet, satış −ele geçen,
/// temettü −net). Pencere bugünkü elde tutmanın ilk alış günü → [simdi].
/// İlk günün akışları "dönem başı değeri" olur; o zaman fonksiyon Dietz
/// yaklaşığı değil kesin IRR çözer (`bas > 0`). Dönem getirisi
/// `(1 + r)^(365,25 / gün) − 1` ile yıllıklandırılır: XIRR'ın aynısı.
///
/// ## Bugünkü elde tutma
/// Pozisyon bir kez tamamen satılıp sonra yeniden alındıysa süre YENİ
/// alıştan sayılır; eski turun akışları hesaba girmez. Yoksa "3 yıldır
/// tutuyorsun" bir yıl önce yeniden aldığın varlık için yanlış olurdu.
///
/// ## Satır yok (`null`) — uydurma sayı yok
///   · ilk alıştan 12 ay geçmedi: kısa sürede yıllıklandırma yanıltır
///     (bir ayda %5, "yıllık %80" olur);
///   · pozisyon kapalı (net miktar 0);
///   · maliyeti bilinmeyen alış var ya da bugünkü değer bilinmiyor;
///   · getiri çözülemedi (ortalama sermaye ≤ 0).
EldeTutma? eldeTutma({
  required List<Asset> lotlar,
  required double guncelDegerTRY,
  required DateTime simdi,
}) {
  if (!(guncelDegerTRY > 0) || !guncelDegerTRY.isFinite) return null;
  final hareketler = [
    for (final a in lotlar)
      if (a.isActive && (a.isBuy || a.isSell || a.isDividend)) a
  ]..sort((x, y) => x.addedDate.compareTo(y.addedDate));

  // Bugünkü elde tutmanın başı: net miktarın son kez sıfıra indiği
  // satıştan sonraki ilk hareket.
  var net = 0.0;
  var bas = 0;
  for (var i = 0; i < hareketler.length; i++) {
    final a = hareketler[i];
    if (a.isBuy) net += a.quantity;
    if (a.isSell) {
      net -= a.quantity;
      if (net <= _kirinti) {
        net = 0;
        bas = i + 1;
      }
    }
  }
  if (net <= _kirinti) return null;
  final tur = hareketler.sublist(bas);
  final ilkAlis = tur.where((a) => a.isBuy).firstOrNull;
  if (ilkAlis == null) return null;
  if (tur.any((a) => a.isBuy && a.maliyetBilinmiyor == true)) return null;

  final basGun = dayKey(ilkAlis.addedDate);
  final bugun = dayKey(simdi);
  // Takvim ayı farkı: gün henüz gelmediyse o ay dolmamış sayılır.
  var aylar = (bugun.year - basGun.year) * 12 + bugun.month - basGun.month;
  if (bugun.day < basGun.day) aylar -= 1;
  if (aylar < 12) return null;

  final toplam = simdi.difference(basGun).inMinutes / Duration.minutesPerDay;
  if (toplam <= 0) return null;
  var basDeger = 0.0;
  final akislar = <DonemAkisi>[];
  for (final a in tur) {
    final f = getiriAkisi(a);
    if (f == 0) continue;
    if (!dayKey(a.addedDate).isAfter(basGun)) {
      basDeger += f;
      continue;
    }
    final kalan =
        simdi.difference(a.addedDate).inMinutes / Duration.minutesPerDay;
    akislar.add((f: f, w: (kalan / toplam).clamp(0.0, 1.0)));
  }
  final donemPct = paraAgirlikliGetiriPct(
      bas: basDeger, son: guncelDegerTRY, akislar: akislar);
  if (donemPct == null || !donemPct.isFinite) return null;
  final carpan = 1 + donemPct / 100;
  if (carpan <= 0) return null;
  final yillik = (math.pow(carpan, 365.25 / toplam) - 1) * 100;
  if (!yillik.isFinite) return null;
  return EldeTutma(
      yil: aylar ~/ 12, ay: aylar % 12, yillikPct: yillik.toDouble());
}

/// Ondalık miktar artığı (0,1 + 0,2 − 0,3): bunun altı "kapalı".
const _kirinti = 1e-9;
