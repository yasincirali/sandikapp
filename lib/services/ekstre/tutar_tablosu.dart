import '../../utils/tr_katla.dart';
import 'ekstre_tablosu.dart';
import 'tablo_anlama.dart';

/// Yalnız TUTAR yazan fon listesi — SAF, ağ yok.
///
/// ## Neden (2026-10-15, DenizBank "Varlık Geçmişi Formu")
/// Bankanın aylık "Varlık Geçmişi" belgesi fonu adıyla ve yalnız TL
/// karşılığıyla yazar; adet ve birim fiyat yoktur:
///
/// ```
/// Yatırım Fonları                                         320.719,49 TRY
/// YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE---TRMYK9…   86.520,05 TRY
/// ```
///
/// Önceki sürüm bunu elle eşleme yedeğine düşürüyordu ("Adet ← Sütun 2",
/// "emin değiliz"); yapay zekâ da adet sütunu bulamıyordu çünkü yok
/// (yasin: "varlık tablosu bulamadı diyor"). Adet = tutar ÷ belge günündeki
/// birim fiyat. Fiyat UYDURULMAZ: o günün (ya da önceki 7 günün son) TEFAS
/// fiyatı alınamazsa satır eklenmez ve önizleme nedenini söyler.
///
/// Tanıma dar tutulur: iki dolu hücreli satır, ilk hücre fon adı ("fon"
/// kelimesi ya da sonda "---TR…" ISIN), ikinci hücre TL tutar. Ad yine
/// TEFAS unvanına TEK aday olarak eşleşmeli (`fonKoduBul`); eşleşmeyen ad
/// eklenmez.
class EkstreTutarFonu {
  const EkstreTutarFonu({required this.ad, required this.tutar});

  /// Belgedeki ad (ISIN ekiyle birlikte; anahtar `fonAdiAnahtari`).
  final String ad;

  /// TL karşılığı.
  final double tutar;
}

final _isin = RegExp(r'---\s*TR[A-Z0-9]{10}\s*$');
final _fonKelimesi = RegExp(r'\bfonu?\b');
final _tlTutar = RegExp(r'^[0-9.,]+\s*(try|tl)$');

/// Tablolardaki yalnız-tutarlı fon satırları (belge sırasıyla, tekil ad).
List<EkstreTutarFonu> tutarliFonlar(List<EkstreTablosu> tablolar) {
  final out = <EkstreTutarFonu>[];
  final gorulen = <String>{};
  for (final t in tablolar) {
    for (final satir in t.satirlar) {
      final dolu = [
        for (final h in satir)
          if (h.trim().isNotEmpty) h.trim(),
      ];
      if (dolu.length != 2) continue;
      final ad = dolu[0];
      final katli = trKatla(ad);
      if (katli.contains('toplam')) continue;
      if (!_isin.hasMatch(ad) && !_fonKelimesi.hasMatch(katli)) continue;
      // Grup başlığı ("Yatırım Fonları   320.719,49 TRY") ad değil.
      if (RegExp(r'^yatirim fonlari?$').hasMatch(katli)) continue;
      if (!_tlTutar.hasMatch(trKatla(dolu[1]))) continue;
      final tutar = sayiCoz(dolu[1]);
      if (tutar == null || tutar <= 0) continue;
      if (!gorulen.add(katli)) continue;
      out.add(EkstreTutarFonu(ad: ad, tutar: tutar));
    }
  }
  return out;
}

/// [seri] (zaman, fiyat; artan) içinden [gun]ün fiyatı: o gün ya da en çok
/// 7 gün öncesinin son fiyatı (hafta sonu, bayram). Yoksa `null`.
double? gunFiyati(List<(int, double)> seri, DateTime gun) {
  final gunSonu =
      DateTime(gun.year, gun.month, gun.day + 1).millisecondsSinceEpoch;
  final enEski =
      DateTime(gun.year, gun.month, gun.day - 7).millisecondsSinceEpoch;
  double? f;
  for (final (t, p) in seri) {
    if (t >= gunSonu) break;
    if (t >= enEski && p > 0) f = p;
  }
  return f;
}

/// Tutar ÷ fiyat → adet. Banka tutarı kuruşa yuvarlar; tam sayıya
/// yuvarlanmış adet tutarı kuruş içinde veriyorsa adet odur (TEFAS
/// yatırım fonu payı tam sayıdır). Değilse 4 ondalık (emeklilik fonu
/// payı kesirlidir).
double tutardanAdet(double tutar, double fiyat) {
  final q = tutar / fiyat;
  final tam = q.roundToDouble();
  final pay = tutar.abs() * 1e-6;
  if (tam > 0 && (tam * fiyat - tutar).abs() <= (pay > 0.02 ? pay : 0.02)) {
    return tam;
  }
  return (q * 10000).roundToDouble() / 10000;
}
